$ErrorActionPreference = 'Stop'
Get-ChildItem 'C:\HD365\Private\*.ps1' | ForEach-Object { . $_.FullName }
$script:HD365Root = 'C:\HD365'
$script:HD365Config = Get-Content 'C:\HD365\Config\settings.example.json' -Raw | ConvertFrom-Json
$script:HD365Config.ai.allowOfflineFallback = $false

# JSON extract from fenced markdown
$fenced = @'
Here you go:
```json
{"summary":"ok","isWrite":true,"job":{"nestMembership":true,"creates":[{"displayName":"Ohio","mailNickname":"Ohio"}]}}
```
'@
$j = ConvertFrom-HD365AiJson -Content $fenced
if ($j.summary -ne 'ok') { throw 'json extract failed' }

# Copilot chat response: last message is the assistant (first echoes user)
$fakeChat = [pscustomobject]@{
    messages = @(
        [pscustomobject]@{ text = 'user prompt' }
        [pscustomobject]@{ text = '{"summary":"from-copilot","phase":"discovery","discoveryScript":"Get-MgGroup -Top 1","executionScript":"","isWrite":false}' }
    )
}
$assistant = ConvertFrom-HD365CopilotChatResponse -Response $fakeChat
if ($assistant -notmatch 'from-copilot') { throw 'copilot last-message extract failed' }
$j2 = ConvertFrom-HD365AiJson -Content $assistant
if ($j2.summary -ne 'from-copilot') { throw 'copilot json path failed' }

$fakeAi = [pscustomobject]@{
    summary = 'test'
    isWrite = $true
    job     = [pscustomobject]@{
        nestMembership = $true
        creates        = @(
            [pscustomobject]@{ displayName = 'Ohio'; mailNickname = 'Ohio'; parentDisplayName = $null }
            [pscustomobject]@{ displayName = 'Ohio - Accounts Payable'; mailNickname = 'OH-AP'; parentDisplayName = 'Ohio' }
            [pscustomobject]@{ displayName = 'Kansas'; mailNickname = 'Kansas' }
        )
    }
}
$job = ConvertTo-HD365AiJobData -AiSolution $fakeAi
if ($job.CreateCount -ne 3) { throw "createCount=$($job.CreateCount)" }
if ($job.Creates[1].ParentDisplayName -ne 'Ohio') { throw 'parent missing' }

if ([string](Get-HD365Config -Path 'C:\HD365\Config\settings.example.json').ai.provider -ne 'CopilotChat') {
    throw 'default provider should be CopilotChat'
}

# Pipeline placeholder path must parse (no smart dashes)
$null = [System.Management.Automation.Language.Parser]::ParseFile(
    'C:\HD365\Private\Invoke-HD365Pipeline.ps1',
    [ref]$null,
    [ref]$null
)
$errs = $null
[void][System.Management.Automation.Language.Parser]::ParseFile(
    'C:\HD365\Private\Invoke-HD365Pipeline.ps1',
    [ref]$null,
    [ref]$errs
)
if ($errs -and $errs.Count -gt 0) { throw ("pipeline parse: " + $errs[0].Message) }

# Copilot error wrapping (step + status + license note)
$ex500 = [System.Exception]::new('Response status code does not indicate success: InternalServerError (Internal Server Error).')
$msg = New-HD365CopilotApiError -Step 'create conversation' -Exception $ex500
if ($msg -notmatch "create conversation") { throw 'error missing step' }
if ($msg -notmatch '500') { throw 'error missing status' }
if ($msg -notmatch 'Desktop/consumer Copilot') { throw 'error missing license hint' }
if ((Get-HD365GraphErrorStatusCode -Exception $ex500) -ne 500) { throw 'status parse failed' }

$script:HD365Session = [ordered]@{ CopilotConversationId = $null }
$status = Get-HD365AiStatus
if ($status.GraphConnected -ne $false -and $null -eq $status.GraphAccount) {
    # ok either way depending on ambient Graph session
}
if ($status.CopilotApi -ne 'NotProbed' -and $status.CopilotApi -ne 'n/a') {
    if ([string]$status.Provider -eq 'CopilotChat' -and $status.CopilotApi -ne 'NotProbed') {
        throw "expected NotProbed without live probe, got $($status.CopilotApi)"
    }
}
if ($status.Tip -notmatch 'Desktop Copilot') { throw 'tip should mention desktop vs Chat API' }

Write-Host 'ALL_OK'
