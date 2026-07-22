$ErrorActionPreference = 'Stop'
$root = if ($PSScriptRoot) { Split-Path $PSScriptRoot -Parent } else { 'C:\HD365' }

Get-ChildItem (Join-Path $root 'Private\*.ps1') | ForEach-Object { . $_.FullName }
$script:HD365Root = $root
$script:HD365Config = Get-Content (Join-Path $root 'Config\settings.example.json') -Raw | ConvertFrom-Json
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

# OpenAI-compatible (OpenAI/Together/Mistral) response shape: choices[0].message.content
$fakeOpenAiResp = [pscustomobject]@{
    choices = @(
        [pscustomobject]@{ message = [pscustomobject]@{ content = '{"summary":"from-openai-compatible","phase":"discovery","discoveryScript":"Get-MgUser -Top 1","executionScript":"","isWrite":false}' } }
    )
}
$openAiContent = [string]$fakeOpenAiResp.choices[0].message.content
$j3 = ConvertFrom-HD365AiJson -Content $openAiContent
if ($j3.summary -ne 'from-openai-compatible') { throw 'openai-compatible json path failed' }

# Anthropic response shape: content[] blocks with type=text
$fakeAnthropicResp = [pscustomobject]@{
    content = @(
        [pscustomobject]@{ type = 'text'; text = '{"summary":"from-anthropic","phase":"discovery","discoveryScript":"Get-MgUser -Top 1","executionScript":"","isWrite":false}' }
    )
}
$anthropicTexts = @($fakeAnthropicResp.content | Where-Object { $_.type -eq 'text' } | ForEach-Object { [string]$_.text })
$j4 = ConvertFrom-HD365AiJson -Content ($anthropicTexts -join "`n")
if ($j4.summary -ne 'from-anthropic') { throw 'anthropic json path failed' }

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

$exampleCfg = Get-HD365Config -Path (Join-Path $root 'Config\settings.example.json')
if ([string]$exampleCfg.ai.provider -ne 'CopilotChat') {
    throw 'default provider should be CopilotChat'
}

# --- Provider catalog: all 8 providers present ---
$catalog = @(Get-HD365ProviderCatalog)
$expectedIds = @('CopilotChat', 'AzureOpenAI', 'OpenAI', 'Anthropic', 'Gemini', 'Together', 'Mistral', 'Ollama')
foreach ($id in $expectedIds) {
    if (@($catalog | Where-Object { $_.Id -eq $id }).Count -ne 1) { throw "catalog missing provider: $id" }
}
if ($catalog.Count -ne $expectedIds.Count) { throw "catalog has unexpected extra entries: $($catalog.Count)" }

# --- Ollama: configured via baseUrl only, no key needed ---
if (-not (Test-HD365ProviderConfigured -Id 'Ollama')) { throw 'Ollama should be configured via default baseUrl only' }

# --- OpenAI: unconfigured when API key env var is not set ---
$script:HD365Config.ai.providers.OpenAI.apiKeyEnvVar = 'HD365_TEST_NOT_SET_KEY_9f3a'
if (Test-HD365ProviderConfigured -Id 'OpenAI') { throw 'OpenAI should be unconfigured without an API key' }

# --- Legacy flat settings.json migration into ai.providers.<Id> ---
$savedConfig = $script:HD365Config
$savedConfigPath = $script:HD365ConfigPath
try {
    $legacyPath = Join-Path $env:TEMP ("hd365-legacy-{0}.json" -f [guid]::NewGuid().ToString('N'))
    $legacyJson = @'
{
  "ai": {
    "provider": "AzureOpenAI",
    "endpoint": "https://legacy.openai.azure.com/",
    "deployment": "legacy-deploy",
    "apiVersion": "2023-05-15",
    "apiKeyEnvVar": "HD365_LEGACY_KEY",
    "temperature": 0.3,
    "maxTokens": 4096
  },
  "graph": { "tenantId": "", "clientId": "", "useDeviceCode": false, "preferInteractive": true },
  "execution": { "requireWriteConfirmation": true, "confirmationPhrase": "EXECUTE", "allowClipboardCopy": true, "timeoutSeconds": 600 },
  "audit": { "enabled": true, "directory": "%TEMP%\\hd365-legacy-audit", "retainDays": 30 },
  "session": { "historySize": 50, "defaultPhase": "Ready" }
}
'@
    Set-Content -LiteralPath $legacyPath -Value $legacyJson -Encoding UTF8
    $legacyCfg = Get-HD365Config -Path $legacyPath
    if ($legacyCfg.ai.providers.AzureOpenAI.endpoint -ne 'https://legacy.openai.azure.com/') { throw 'migration: endpoint missing' }
    if ($legacyCfg.ai.providers.AzureOpenAI.deployment -ne 'legacy-deploy') { throw 'migration: deployment missing' }
    if ($legacyCfg.ai.providers.AzureOpenAI.apiVersion -ne '2023-05-15') { throw 'migration: apiVersion missing' }
    if ($legacyCfg.ai.providers.AzureOpenAI.apiKeyEnvVar -ne 'HD365_LEGACY_KEY') { throw 'migration: apiKeyEnvVar missing' }
    Remove-Item -LiteralPath $legacyPath -Force -ErrorAction SilentlyContinue
}
finally {
    $script:HD365Config = $savedConfig
    $script:HD365ConfigPath = $savedConfigPath
}

# Pipeline placeholder path must parse (no smart dashes)
$null = [System.Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $root 'Private\Invoke-HD365Pipeline.ps1'),
    [ref]$null,
    [ref]$null
)
$errs = $null
[void][System.Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $root 'Private\Invoke-HD365Pipeline.ps1'),
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
if ([string]$status.ProviderName -notmatch 'Copilot') { throw 'ProviderName should reflect catalog display name' }

Write-Host 'ALL_OK'
