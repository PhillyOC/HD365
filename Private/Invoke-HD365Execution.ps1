function Get-HD365Confirmation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Prompt,

        [string]$Expected = 'EXECUTE'
    )

    Write-Host $Prompt -ForegroundColor Yellow
    Write-Host "Type '$Expected' to continue, or anything else to cancel:" -ForegroundColor Yellow
    $answer = Read-Host
    return ($answer -and ($answer.Trim() -ieq $Expected))
}

function Invoke-HD365Script {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ScriptText,

        [switch]$IsWrite
    )

    if ([string]::IsNullOrWhiteSpace($ScriptText)) {
        throw "No script text to execute."
    }

    # Soft static guard: block obvious write cmdlets during gather-only runs
    $writePatterns = @(
        'Add-Mg', 'New-Mg', 'Update-Mg', 'Remove-Mg', 'Set-Mg',
        'Add-DistributionGroupMember', 'Remove-DistributionGroupMember',
        'Set-DistributionGroup', 'New-DistributionGroup', 'Remove-DistributionGroup',
        'Set-Mailbox', 'Add-MailboxPermission', 'Remove-MailboxPermission',
        'New-AD', 'Set-AD', 'Remove-AD', 'Add-AD',
        'az\s+\S+\s+(create|update|delete|set)\b'
    )

    if (-not $IsWrite) {
        foreach ($p in $writePatterns) {
            if ($ScriptText -match $p) {
                throw "Refusing to run potential WRITE command during read/gather execution. Use an approved write proposal and /run after confirmation. Matched: $p"
            }
        }
    }

    $temp = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "hd365-{0}.ps1" -f [guid]::NewGuid().ToString('N'))
    Set-Content -LiteralPath $temp -Value $ScriptText -Encoding UTF8

    try {
        Write-Host "Executing script..." -ForegroundColor Cyan
        $sw = [System.Diagnostics.Stopwatch]::StartNew()

        # Run in current session so Graph/EXO connections are available
        $result = & {
            $ErrorActionPreference = 'Stop'
            . $temp
        }

        $sw.Stop()

        Write-HD365Audit -EventType $(if ($IsWrite) { 'ExecuteWrite' } else { 'ExecuteRead' }) `
            -IsWrite:$IsWrite `
            -ScriptText $ScriptText `
            -Data @{
                durationMs = $sw.ElapsedMilliseconds
                success    = $true
            }

        return $result
    }
    catch {
        Write-HD365Audit -EventType Error -IsWrite:$IsWrite -ScriptText $ScriptText -Data @{
            error = $_.Exception.Message
        }
        throw
    }
    finally {
        Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-HD365ApprovedRun {
    [CmdletBinding()]
    param()

    $pending = $script:HD365Session.PendingProposal
    if (-not $pending) {
        Write-Host "No pending proposal. Describe a task first." -ForegroundColor Yellow
        return
    }
    $proposal = $pending.Proposal
    $scriptText = $pending.ExecutionScript
    if (-not $scriptText) { $scriptText = $proposal.executionScript }

    # One-liner enforcement for copy/paste consistency
    $scriptText = ConvertTo-HD365OneLiner -ScriptText $scriptText
    $pending.ExecutionScript = $scriptText

    $isWrite = $false
    if ($proposal.isWrite -eq $true -or $proposal.intent -in @('write', 'mixed')) {
        $isWrite = $true
    }
    elseif ($pending -is [System.Collections.IDictionary] -and $pending.Contains('ForceWrite') -and $pending['ForceWrite']) {
        $isWrite = $true
    }

    # Also treat leastScopes write catalog hits as write
    if ($proposal.leastScopes -and (Test-HD365IsWriteScope -Scopes @($proposal.leastScopes))) {
        $isWrite = $true
    }

    $mode = if ($isWrite) { 'Write' } else { 'Read' }
    Ensure-HD365Platform -Platform ([string]$proposal.platform) -Mode $mode -LeastScopes @($proposal.leastScopes)

    if ($isWrite) {
        Write-Host ""
        Write-Host "+----------------------------------------------------------+" -ForegroundColor Red
        Write-Host "|           WRITE EXECUTION WARNING                        |" -ForegroundColor Red
        Write-Host "|  This will make LIVE CHANGES in your Microsoft tenant.   |" -ForegroundColor Red
        Write-Host "|  An immutable audit record will be written locally.      |" -ForegroundColor Red
        Write-Host "+----------------------------------------------------------+" -ForegroundColor Red
        Write-Host ""

        $previewPath = $null
        $opCount = 0
        if ($pending -is [System.Collections.IDictionary]) {
            if ($pending.Contains('ScriptPath')) { $previewPath = [string]$pending['ScriptPath'] }
            if ($pending.Contains('JobData') -and $pending['JobData'] -and $pending['JobData'].CreateCount) {
                $opCount = [int]$pending['JobData'].CreateCount
            }
        }
        Show-HD365ScriptPreview -ScriptText $scriptText -ScriptPath $previewPath -OperationCount $opCount -PreviewChars 500

        $phrase = 'EXECUTE'
        if ($script:HD365Config.execution.confirmationPhrase) {
            $phrase = [string]$script:HD365Config.execution.confirmationPhrase
        }

        if ($script:HD365Config.execution.requireWriteConfirmation -ne $false) {
            if (-not (Get-HD365Confirmation -Prompt "Confirm WRITE execution." -Expected $phrase)) {
                Write-HD365Audit -EventType Cancel -IsWrite:$true -ScriptText $scriptText -Data @{ reason = 'user_declined_write' }
                Write-Host "Write execution cancelled." -ForegroundColor Yellow
                return
            }
        }

        $script:HD365Session.Phase = 'Execute'
    }
    else {
        $script:HD365Session.Phase = 'Execute'
    }

    try {
        $output = $null
        $bulkKind = $null
        if ($pending -is [System.Collections.IDictionary] -and $pending.Contains('BulkKind')) {
            $bulkKind = [string]$pending['BulkKind']
        }

        if ($bulkKind -eq 'AiJob' -and $pending['JobData']) {
            Write-Host "Executing AI bulk job (Graph `$batch, single session)..." -ForegroundColor Cyan
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $output = Invoke-HD365BulkAiJob -JobData $pending['JobData']
            $sw.Stop()
            Write-HD365Audit -EventType ExecuteWrite -IsWrite:$true -ScriptText $scriptText -Data @{
                durationMs = $sw.ElapsedMilliseconds
                success    = $true
                bulkKind   = $bulkKind
                created    = $output.Created
                failed     = $output.Failed
                nested     = $output.Nested
            }
        }
        elseif ($bulkKind -eq 'CreateNestedGroups' -and $pending['JobData']) {
            Write-Host "Executing bulk nested-group job (Graph `$batch, single session)..." -ForegroundColor Cyan
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $output = Invoke-HD365BulkNestedGroups -JobData $pending['JobData']
            $sw.Stop()
            Write-HD365Audit -EventType ExecuteWrite -IsWrite:$true -ScriptText $scriptText -Data @{
                durationMs = $sw.ElapsedMilliseconds
                success    = $true
                bulkKind   = $bulkKind
                created    = $output.Created
                failed     = $output.Failed
                nested     = $output.Nested
            }
        }
        else {
            $output = Invoke-HD365Script -ScriptText $scriptText -IsWrite:$isWrite
        }

        $script:HD365Session.LastResult = $output

        Write-Host ""
        Write-Host "-- Result --" -ForegroundColor Green
        if ($null -eq $output) {
            Write-Host "(Command completed with no pipeline output.)" -ForegroundColor DarkGray
        }
        else {
            $output | Format-List | Out-String | Write-Host
        }

        $script:HD365Session.Phase = 'Ready'
        Write-Host "Done. Refine with another message, /run again, or start a new request." -ForegroundColor DarkGray
    }
    catch {
        Write-Host "Execution failed: $($_.Exception.Message)" -ForegroundColor Red
        $script:HD365Session.Phase = 'Solution'
    }
}
