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

function Get-HD365RunPreview {
    <#
    .SYNOPSIS
      Pure (no console I/O, no Read-Host) inspection of the pending proposal: normalizes the
      one-liner, resolves write/read mode, connects the required platform (Graph/EXO/AD), and
      returns everything a caller (REPL or GUI bridge) needs to render a confirmation prompt.
    #>
    [CmdletBinding()]
    param()

    $pending = $script:HD365Session.PendingProposal
    if (-not $pending) {
        return [pscustomobject]@{ HasPending = $false }
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

    $previewPath = $null
    $opCount = 0
    if ($pending -is [System.Collections.IDictionary]) {
        if ($pending.Contains('ScriptPath')) { $previewPath = [string]$pending['ScriptPath'] }
        if ($pending.Contains('JobData') -and $pending['JobData'] -and $pending['JobData'].CreateCount) {
            $opCount = [int]$pending['JobData'].CreateCount
        }
    }

    $phrase = 'EXECUTE'
    if ($script:HD365Config.execution.confirmationPhrase) {
        $phrase = [string]$script:HD365Config.execution.confirmationPhrase
    }
    $requiresConfirmation = ($isWrite -and $script:HD365Config.execution.requireWriteConfirmation -ne $false)

    return [pscustomobject]@{
        HasPending           = $true
        IsWrite              = $isWrite
        ScriptText           = $scriptText
        ScriptPath           = $previewPath
        OperationCount       = $opCount
        RequiresConfirmation = $requiresConfirmation
        ConfirmationPhrase   = $phrase
        Summary              = [string]$proposal.summary
        Platform             = [string]$proposal.platform
    }
}

function Invoke-HD365ExecutePlan {
    <#
    .SYNOPSIS
      Pure (no Read-Host) execution of the pending proposal. Callers (REPL, GUI bridge) are
      responsible for obtaining confirmation *before* calling this when RequiresConfirmation
      was true on the matching Get-HD365RunPreview result, and must pass that phrase back here.
    #>
    [CmdletBinding()]
    param(
        [string]$ConfirmPhrase
    )

    $pending = $script:HD365Session.PendingProposal
    if (-not $pending) {
        throw "No pending proposal. Describe a task first."
    }

    $proposal = $pending.Proposal
    $scriptText = ConvertTo-HD365OneLiner -ScriptText ([string]$pending.ExecutionScript)
    $pending.ExecutionScript = $scriptText

    $isWrite = $false
    if ($proposal.isWrite -eq $true -or $proposal.intent -in @('write', 'mixed')) {
        $isWrite = $true
    }
    elseif ($pending -is [System.Collections.IDictionary] -and $pending.Contains('ForceWrite') -and $pending['ForceWrite']) {
        $isWrite = $true
    }
    if ($proposal.leastScopes -and (Test-HD365IsWriteScope -Scopes @($proposal.leastScopes))) {
        $isWrite = $true
    }

    $mode = if ($isWrite) { 'Write' } else { 'Read' }
    Ensure-HD365Platform -Platform ([string]$proposal.platform) -Mode $mode -LeastScopes @($proposal.leastScopes)

    if ($isWrite -and $script:HD365Config.execution.requireWriteConfirmation -ne $false) {
        $phrase = 'EXECUTE'
        if ($script:HD365Config.execution.confirmationPhrase) {
            $phrase = [string]$script:HD365Config.execution.confirmationPhrase
        }
        if (-not $ConfirmPhrase -or ($ConfirmPhrase.Trim() -ine $phrase)) {
            Write-HD365Audit -EventType Cancel -IsWrite:$true -ScriptText $scriptText -Data @{ reason = 'confirm_phrase_mismatch' }
            throw "Confirmation phrase did not match expected '$phrase'."
        }
    }

    $script:HD365Session.Phase = 'Execute'

    $output = $null
    $bulkKind = $null
    if ($pending -is [System.Collections.IDictionary] -and $pending.Contains('BulkKind')) {
        $bulkKind = [string]$pending['BulkKind']
    }

    try {
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
    }
    catch {
        $script:HD365Session.Phase = 'Solution'
        throw
    }

    $script:HD365Session.LastResult = $output
    $script:HD365Session.Phase = 'Ready'
    $script:HD365Session.PendingProposal = $null

    return [pscustomobject]@{
        Success  = $true
        BulkKind = $bulkKind
        Output   = $output
    }
}

function Invoke-HD365ApprovedRun {
    <#
    .SYNOPSIS
      REPL console wrapper: renders the write-warning box / typed-EXECUTE prompt around the
      pure Get-HD365RunPreview / Invoke-HD365ExecutePlan pair. Console behavior is unchanged;
      the GUI bridge calls those two functions directly instead of this wrapper.
    #>
    [CmdletBinding()]
    param()

    $preview = Get-HD365RunPreview
    if (-not $preview.HasPending) {
        Write-Host "No pending proposal. Describe a task first." -ForegroundColor Yellow
        return
    }

    $confirmPhrase = $null
    if ($preview.IsWrite) {
        Write-Host ""
        Write-Host "+----------------------------------------------------------+" -ForegroundColor Red
        Write-Host "|           WRITE EXECUTION WARNING                        |" -ForegroundColor Red
        Write-Host "|  This will make LIVE CHANGES in your Microsoft tenant.   |" -ForegroundColor Red
        Write-Host "|  An immutable audit record will be written locally.      |" -ForegroundColor Red
        Write-Host "+----------------------------------------------------------+" -ForegroundColor Red
        Write-Host ""

        Show-HD365ScriptPreview -ScriptText $preview.ScriptText -ScriptPath $preview.ScriptPath -OperationCount $preview.OperationCount -PreviewChars 500

        if ($preview.RequiresConfirmation) {
            if (-not (Get-HD365Confirmation -Prompt "Confirm WRITE execution." -Expected $preview.ConfirmationPhrase)) {
                Write-HD365Audit -EventType Cancel -IsWrite:$true -ScriptText $preview.ScriptText -Data @{ reason = 'user_declined_write' }
                Write-Host "Write execution cancelled." -ForegroundColor Yellow
                return
            }
            $confirmPhrase = $preview.ConfirmationPhrase
        }
    }

    try {
        $result = Invoke-HD365ExecutePlan -ConfirmPhrase $confirmPhrase
        $output = $result.Output

        Write-Host ""
        Write-Host "-- Result --" -ForegroundColor Green
        if ($null -eq $output) {
            Write-Host "(Command completed with no pipeline output.)" -ForegroundColor DarkGray
        }
        else {
            $output | Format-List | Out-String | Write-Host
        }

        Write-Host "Done. Refine with another message, /run again, or start a new request." -ForegroundColor DarkGray
    }
    catch {
        Write-Host "Execution failed: $($_.Exception.Message)" -ForegroundColor Red
    }
}
