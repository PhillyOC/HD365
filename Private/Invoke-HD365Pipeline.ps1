function ConvertTo-HD365DiscoveryText {
    [CmdletBinding()]
    param(
        [AllowNull()]
        $DiscoveryResult
    )

    if ($null -eq $DiscoveryResult) { return '(no discovery output)' }

    try {
        # Prefer compact JSON for AI / logging; fall back to Out-String
        $json = $DiscoveryResult | ConvertTo-Json -Depth 6 -Compress -ErrorAction Stop
        if ($json.Length -gt 120000) {
            return $json.Substring(0, 120000) + '...(truncated)'
        }
        return $json
    }
    catch {
        $text = ($DiscoveryResult | Out-String)
        if ($text.Length -gt 120000) { return $text.Substring(0, 120000) + '...(truncated)' }
        return $text
    }
}

function Show-HD365Discovery {
    [CmdletBinding()]
    param(
        [AllowNull()]
        $DiscoveryResult,

        [object]$Plan
    )

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor DarkCyan
    Write-Host " PHASE 1 - DISCOVERY (read-only, auto-ran)" -ForegroundColor DarkCyan
    Write-Host "============================================================" -ForegroundColor DarkCyan

    if ($Plan.solutionKind -eq 'CreateGroupAddAllUsers' -and $DiscoveryResult) {
        $existing = @($DiscoveryResult.ExistingGroups)
        $users = @($DiscoveryResult.Users)
        Write-Host ("Group name : {0}" -f $DiscoveryResult.GroupName) -ForegroundColor White
        if ($existing.Count -gt 0) {
            Write-Host "Existing   : FOUND" -ForegroundColor Yellow
            $existing | Select-Object DisplayName, Id, MailNickname | Format-Table -AutoSize | Out-String | Write-Host
        }
        else {
            Write-Host "Existing   : none (will create)" -ForegroundColor Green
        }
        Write-Host ("Users found: {0}" -f $users.Count) -ForegroundColor White
        $users | Select-Object -First 20 DisplayName, UserPrincipalName, Id | Format-Table -AutoSize | Out-String | Write-Host
        if ($users.Count -gt 20) {
            Write-Host ("... and {0} more" -f ($users.Count - 20)) -ForegroundColor DarkGray
        }
        return
    }

    if ($Plan.solutionKind -eq 'CreateNestedGroups' -and $DiscoveryResult) {
        $parents = @(Select-HD365TopLevelOfficeParents -Groups @($DiscoveryResult.Parents))
        $children = @($DiscoveryResult.ChildNames)
        if (-not $children -or $children.Count -eq 0) { $children = @($Plan.childNames) }
        $existing = @($DiscoveryResult.ExistingGroups)
        $planned = $parents.Count * $children.Count
        Write-Host ("Parents    : {0}  (plain state names: Ohio, Kansas, ...)" -f $parents.Count) -ForegroundColor White
        Write-Host ("Filter     : {0}" -f $DiscoveryResult.ParentFilter) -ForegroundColor DarkGray
        if ($DiscoveryResult.Note) {
            Write-Host ("Note       : {0}" -f $DiscoveryResult.Note) -ForegroundColor DarkGray
        }
        Write-Host ("Children   : {0}  => {1}" -f $children.Count, ($children -join ', ')) -ForegroundColor White
        Write-Host ("Matrix     : {0} nested groups planned" -f $planned) -ForegroundColor Cyan
        Write-Host ("Already exist: {0}" -f $existing.Count) -ForegroundColor Yellow
        $badParents = @($DiscoveryResult.Parents | Where-Object {
                $_ -and $_.DisplayName -and -not (Test-HD365IsTopLevelOfficeGroup -DisplayName ([string]$_.DisplayName))
            })
        if ($badParents.Count -gt 0) {
            Write-Host ("Ignored non-top-level parent candidates: {0}" -f $badParents.Count) -ForegroundColor Yellow
        }
        if ($parents.Count -gt 0) {
            Write-Host "Sample parents:" -ForegroundColor DarkGray
            $parents | Select-Object -First 5 DisplayName, Id | Format-Table -AutoSize | Out-String | Write-Host
            if ($parents.Count -gt 5) { Write-Host ("  ... and {0} more parents" -f ($parents.Count - 5)) -ForegroundColor DarkGray }
        }
        if ($existing.Count -gt 0) {
            Write-Host "Existing nested matches (sample):" -ForegroundColor Yellow
            $existing | Select-Object -First 10 DisplayName, Id | Format-Table -AutoSize | Out-String | Write-Host
        }
        return
    }

    if ($Plan.solutionKind -eq 'CreateManyGroups' -and $DiscoveryResult) {
        $requested = @($DiscoveryResult.Requested)
        if (-not $requested -or $requested.Count -eq 0) { $requested = @($Plan.groupNames) }
        $existing = @($DiscoveryResult.ExistingGroups)
        Write-Host ("Requested  : {0} group(s)" -f $requested.Count) -ForegroundColor White
        Write-Host ("Already exist: {0}" -f $existing.Count) -ForegroundColor Yellow
        Write-Host "Requested names:" -ForegroundColor White
        $requested | ForEach-Object { Write-Host "  - $_" }
        if ($existing.Count -gt 0) {
            Write-Host "Existing matches:" -ForegroundColor Yellow
            $existing | Select-Object DisplayName, Id, MailNickname | Format-Table -AutoSize | Out-String | Write-Host
        }
        return
    }

    if ($null -eq $DiscoveryResult) {
        Write-Host "(No pipeline output from discovery.)" -ForegroundColor DarkGray
        return
    }

    $DiscoveryResult | Format-Table -AutoSize | Out-String | Write-Host
}

function Show-HD365Solution {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Plan,

        [Parameter(Mandatory)]
        [string]$SolutionScript,

        [string]$SolutionSummary,

        [string]$ScriptPath,

        [int]$OperationCount = 0
    )

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host " PHASE 2 - SOLUTION (review / copy / run)" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Summary" -ForegroundColor White
    if ($SolutionSummary) { Write-Host "  $SolutionSummary" } else { Write-Host "  $($Plan.summary)" }
    Write-Host ""
    Write-Host "Platform : $($Plan.platform)" -ForegroundColor White
    Write-Host "Intent   : $($Plan.intent)   Write: $($Plan.isWrite)" -ForegroundColor White

    if ($Plan.modules) {
        Write-Host ("Modules  : " + (@($Plan.modules) -join ', '))
    }
    if ($Plan.leastScopes) {
        Write-Host "Least scopes / permissions:" -ForegroundColor White
        foreach ($s in @($Plan.leastScopes)) {
            Write-Host "  * $s" -ForegroundColor Green
        }
    }
    if ($Plan.rolesNeeded) {
        Write-Host "Roles (if required):" -ForegroundColor White
        foreach ($r in @($Plan.rolesNeeded)) {
            Write-Host "  * $r" -ForegroundColor Yellow
        }
    }
    if ($Plan.warnings) {
        Write-Host "Warnings:" -ForegroundColor Yellow
        foreach ($w in @($Plan.warnings)) {
            Write-Host "  ! $w" -ForegroundColor Yellow
        }
    }

    Write-Host ""
    Show-HD365ScriptPreview -ScriptText $SolutionScript -ScriptPath $ScriptPath -OperationCount $OperationCount

    if ($Plan.isWrite -or $Plan.intent -in @('write', 'mixed')) {
        Write-Host "+----------------------------------------------------------+" -ForegroundColor Red
        Write-Host "|  WRITE OPERATION - live tenant changes when you /run     |" -ForegroundColor Red
        Write-Host "|  Bulk jobs use Graph `$batch (one auth, progress meter)  |" -ForegroundColor Red
        Write-Host "+----------------------------------------------------------+" -ForegroundColor Red
        Write-Host ""
    }

    Write-Host "Next: /run to execute  |  /copy  |  /edit  |  refine in chat  |  /cancel" -ForegroundColor DarkYellow
    Write-Host ""
}

function Invoke-HD365Pipeline {
    <#
    .SYNOPSIS
      Automatic two-phase flow: discovery (read) -> solution one-liner with real data.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$UserMessage,

        [object[]]$History
    )

    Write-Host "Planning with AI ($([string]$script:HD365Config.ai.provider))..." -ForegroundColor DarkGray

    $plan = $null
    $usedAi = $false
    $allowOffline = [bool]$script:HD365Config.ai.allowOfflineFallback

    try {
        $plan = Invoke-HD365Ai -UserMessage $UserMessage -History $History -PhaseHint discovery
        $usedAi = $true
        if (-not $plan.platform) {
            $plan | Add-Member -NotePropertyName platform -NotePropertyValue 'Microsoft Graph' -Force
        }
        if (-not $plan.solutionKind) {
            $kind = if ($plan.isWrite -or $plan.intent -in @('write', 'mixed')) { 'AiJob' } else { 'PassthroughRead' }
            $plan | Add-Member -NotePropertyName solutionKind -NotePropertyValue $kind -Force
        }
    }
    catch {
        if (-not $allowOffline) {
            Show-HD365AiSetupHelp -ErrorMessage $_.Exception.Message
            throw "AI planner required. Offline fallback is disabled (ai.allowOfflineFallback=false)."
        }
        Write-Host "AI unavailable ($($_.Exception.Message)). Offline fallback enabled..." -ForegroundColor Yellow
        $plan = New-HD365OfflineProposal -UserMessage $UserMessage
    }

    $discoveryScript = ConvertTo-HD365OneLiner -ScriptText ([string]$plan.discoveryScript)
    if ([string]::IsNullOrWhiteSpace($discoveryScript)) {
        throw "Planner did not return a discoveryScript."
    }

    # ---- PHASE 1: auto discovery (read-only, no review) ----
    $script:HD365Session.Phase = 'Discovery'
    Write-Host "Phase 1: running read-only discovery..." -ForegroundColor Cyan
    if ($discoveryScript.Length -gt 500) {
        Write-Host ($discoveryScript.Substring(0, 500) + '... (truncated)') -ForegroundColor DarkGray
    }
    else {
        Write-Host $discoveryScript -ForegroundColor DarkGray
    }

    Ensure-HD365Platform -Platform ([string]$plan.platform) -Mode Read -LeastScopes @($plan.leastScopes)
    $discoveryResult = Invoke-HD365Script -ScriptText $discoveryScript -IsWrite:$false
    $script:HD365Session.LastResult = $discoveryResult

    Write-HD365Audit -EventType Gather -ScriptText $discoveryScript -Data @{
        user    = $UserMessage
        summary = [string]$plan.summary
        offline = [bool]$plan.offline
    }

    Show-HD365Discovery -DiscoveryResult $discoveryResult -Plan $plan

    # ---- PHASE 2: build solution with real data ----
    $script:HD365Session.Phase = 'Solution'
    Write-Host "Phase 2: building solution one-liner from discovery data..." -ForegroundColor Cyan

    $solutionScript = $null
    $solutionSummary = $null
    $bulkKind = $null
    $jobData = $null
    $opCount = 0

    if ($usedAi) {
        $discoText = ConvertTo-HD365DiscoveryText -DiscoveryResult $discoveryResult
        try {
            $aiSolution = Invoke-HD365AiSolution -UserMessage $UserMessage -Plan $plan -DiscoveryResultsText $discoText
            $solutionSummary = [string]$aiSolution.summary
            if ($aiSolution.leastScopes) { $plan.leastScopes = @($aiSolution.leastScopes) }
            if ($null -ne $aiSolution.isWrite) { $plan.isWrite = [bool]$aiSolution.isWrite }
            if ($aiSolution.warnings) { $plan.warnings = @($aiSolution.warnings) }
            if ($aiSolution.expectedCount) {
                $plan | Add-Member -NotePropertyName expectedCount -NotePropertyValue $aiSolution.expectedCount -Force
            }

            $jobData = ConvertTo-HD365AiJobData -AiSolution $aiSolution
            if ($jobData -and $jobData.CreateCount -gt 0) {
                $bulkKind = 'AiJob'
                $opCount = [int]$jobData.CreateCount
                $plan.isWrite = $true
                $solutionScript = [string]$aiSolution.executionScript
                if ([string]::IsNullOrWhiteSpace($solutionScript)) {
                    $msg = 'Write-Host ("Bulk job ready: ' + $opCount + ' groups. Use /run to execute."); "' + $opCount + ' creates planned"'
                    $solutionScript = ConvertTo-HD365OneLiner -ScriptText $msg
                }
                else {
                    $solutionScript = ConvertTo-HD365OneLiner -ScriptText $solutionScript
                }
            }
            else {
                $solutionScript = ConvertTo-HD365OneLiner -ScriptText ([string]$aiSolution.executionScript)
            }
        }
        catch {
            Write-Host "AI solution pass failed ($($_.Exception.Message))." -ForegroundColor Red
            if (-not $allowOffline) { throw }
            Write-Host "Falling back to local builder (offline)..." -ForegroundColor Yellow
        }
    }

    if ([string]::IsNullOrWhiteSpace($solutionScript)) {
        $built = Build-HD365Solution -Plan $plan -DiscoveryResult $discoveryResult -DiscoveryScript $discoveryScript
        $solutionScript = [string]$built.executionScript
        $solutionSummary = [string]$built.summary
        if ($null -ne $built.isWrite) { $plan.isWrite = [bool]$built.isWrite }
        if ($built.PSObject.Properties['bulkKind']) { $bulkKind = [string]$built.bulkKind }
        if ($built.PSObject.Properties['jobData']) { $jobData = $built.jobData }
        if ($built.PSObject.Properties['createCount']) { $opCount = [int]$built.createCount }
    }

    if ([string]::IsNullOrWhiteSpace($solutionScript) -and -not ($jobData -and $jobData.CreateCount -gt 0)) {
        throw "Failed to build a solution script from discovery results."
    }
    if ([string]::IsNullOrWhiteSpace($solutionScript) -and $jobData) {
        $solutionScript = ConvertTo-HD365OneLiner -ScriptText ("Write-Host 'Bulk job: {0} creates via /run'" -f $jobData.CreateCount)
    }

    # Guard: solution must be one line
    $solutionScript = ConvertTo-HD365OneLiner -ScriptText $solutionScript

    $plan.executionScript = $solutionScript
    $plan.phase = 'solution'

    $scriptPath = Save-HD365ScriptArtifact -ScriptText $solutionScript -Prefix 'solution'
    if (-not $opCount) { $opCount = 0 }

    Show-HD365Solution -Plan $plan -SolutionScript $solutionScript -SolutionSummary $solutionSummary -ScriptPath $scriptPath -OperationCount $opCount

    Write-HD365Audit -EventType Solution -IsWrite:([bool]$plan.isWrite) -ScriptText $solutionScript -Data @{
        user       = $UserMessage
        summary    = $solutionSummary
        offline    = [bool]$plan.offline
        scriptPath = $scriptPath
        bulkKind   = $bulkKind
        opCount    = $opCount
    }

    $script:HD365Session.PendingProposal = [ordered]@{
        Proposal         = $plan
        ExecutionScript  = $solutionScript
        ScriptPath       = $scriptPath
        DiscoveryScript  = $discoveryScript
        DiscoveryResult  = $discoveryResult
        SolutionSummary  = $solutionSummary
        BulkKind         = $bulkKind
        JobData          = $jobData
        Approved         = $true   # review = on-screen solution; /run executes
        UserMessage      = $UserMessage
        CreatedAt        = (Get-Date).ToUniversalTime()
    }

    return $script:HD365Session.PendingProposal
}
