function Show-HD365Banner {
    [CmdletBinding()]
    param()

    $banner = @'
 _   _ ____ _____  __   ____
| | | |  _ \___ / / /_ | ___|
| |_| | | | ||_ \| '_ \|___ \
|  _  | |_| |__) | (_) |___) |
|_| |_|____/____/ \___/|____/

HelpDesk 365 AI  -  Graph-first M365 admin assistant
'@

    Write-Host $banner -ForegroundColor Cyan
    Write-Host "Session : $($script:HD365Session.Id)" -ForegroundColor DarkGray
    Write-Host "Phase   : $($script:HD365Session.Phase)  |  Graph: $($script:HD365Session.GraphMode)  |  Operator: $($script:HD365Session.Operator)" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "Flow: ask -> AI discovery (read) -> AI solution -> /run" -ForegroundColor DarkYellow
    Write-Host ("AI      : {0}" -f $script:HD365Config.ai.provider) -ForegroundColor DarkGray
    Write-Host "Commands: /help  /ai  /status  /auth [read|write]  /exo  /run (/r)  /edit  /copy  /cancel  /audit  /quit" -ForegroundColor DarkYellow
    Write-Host ""
}

function Show-HD365Help {
    [CmdletBinding()]
    param()

    @"

HD365 AI-first two-phase flow
  1. DISCOVERY  - AI plans read-only script; host auto-runs it
  2. SOLUTION   - AI returns one-liner and/or bulk job with real data
  3. /run       - execute (writes require typing EXECUTE)

AI provider (settings.json ai.provider):
  CopilotChat (default) | AzureOpenAI | OpenAI
  Type /ai for status. Complex NL requires AI (offline fallback off by default).

Examples
  Create groups for every US state and AP/AR under each (150 total)
  Create groups for every Mexican state with Finance and HR children
  Show members of engineering distribution lists

Slash commands
  /help              Show this help
  /ai                AI provider / Copilot status
  /status            Session / auth status
  /auth read|write   Connect Microsoft Graph
  /exo               Connect Exchange Online
  /run or /r         Execute current solution (live)
  /edit              Edit solution in notepad
  /copy              Copy full solution script to clipboard
  /cancel            Discard current solution
  /audit [n]         Show last n audit events
  /quit              Exit HD365

"@ | Write-Host
}

# Kept for compatibility; pipeline uses Show-HD365Solution instead
function Show-HD365Proposal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Proposal
    )

    $script = [string]$Proposal.executionScript
    if (-not $script) { $script = [string]$Proposal.discoveryScript }
    Show-HD365Solution -Plan $Proposal -SolutionScript (ConvertTo-HD365OneLiner -ScriptText $script) -SolutionSummary ([string]$Proposal.summary)
}
