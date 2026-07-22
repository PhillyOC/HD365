function Get-HD365SystemPrompt {
    [CmdletBinding()]
    param()

    $path = Join-Path $script:HD365Root 'Config\system-prompt.txt'
    $base = Get-Content -LiteralPath $path -Raw -Encoding UTF8

    $catalog = Get-HD365ScopeCatalog
    $scopeNote = @"

Available Graph READ scopes for Gather phase:
$(($catalog.readScopes | ForEach-Object { "- $_" }) -join "`n")

Available Graph WRITE scopes (Execute phase only, after warning):
$(($catalog.writeScopes | ForEach-Object { "- $_" }) -join "`n")

Operator: $($script:HD365Session.Operator)
AD RSAT available: $($script:HD365Session.AdAvailable)
Current Graph mode: $($script:HD365Session.GraphMode)
AI provider: $($script:HD365Config.ai.provider)
"@

    return ($base + "`n" + $scopeNote)
}

function ConvertFrom-HD365AiJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Content
    )

    $text = $Content.Trim()
    if ($text -match '(?s)```(?:json)?\s*(.*?)\s*```') {
        $text = $Matches[1].Trim()
    }

    if ($text -notmatch '^\s*\{') {
        $start = $text.IndexOf('{')
        $end = $text.LastIndexOf('}')
        if ($start -ge 0 -and $end -gt $start) {
            $text = $text.Substring($start, $end - $start + 1)
        }
    }

    # Mild cleanup common in LLM output
    $text = $text -replace ',\s*}', '}' -replace ',\s*]', ']'

    try {
        return ($text | ConvertFrom-Json)
    }
    catch {
        throw "Failed to parse AI JSON: $($_.Exception.Message)`n--- content ---`n$($Content.Substring(0, [Math]::Min(1200, $Content.Length)))"
    }
}

function Test-HD365AiConfigured {
    [CmdletBinding()]
    param()

    $provider = [string]$script:HD365Config.ai.provider
    if (-not $provider) { $provider = 'CopilotChat' }

    try { return (Test-HD365ProviderConfigured -Id $provider) }
    catch { return $false }
}

function Invoke-HD365Ai {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$UserMessage,

        [object[]]$History,

        [ValidateSet('discovery', 'solution', 'auto')]
        [string]$PhaseHint = 'auto'
    )

    $config = $script:HD365Config
    $provider = [string]$config.ai.provider
    if (-not $provider) { $provider = 'CopilotChat' }

    $system = Get-HD365SystemPrompt
    $phaseLine = ""
    if ($PhaseHint -ne 'auto') {
        $phaseLine = "`nRequested phase: $PhaseHint. Set JSON field phase to '$PhaseHint'."
    }

    $historyBlock = ""
    if ($History) {
        $bits = foreach ($h in $History) {
            "USER: $($h.user)`nASSISTANT: $($h.assistant)"
        }
        $historyBlock = "`nPrior turns:`n" + ($bits -join "`n---`n")
    }

    $userPayload = $UserMessage + $phaseLine + $historyBlock

    $temperature = 0.2
    if ($null -ne $config.ai.temperature) { $temperature = [double]$config.ai.temperature }
    $maxTokens = 8192
    if ($null -ne $config.ai.maxTokens) { $maxTokens = [int]$config.ai.maxTokens }

    $preamble = @"
$system

IMPORTANT: Reply with ONE JSON object only that matches the schema in the system instructions. No markdown fences. No explanation outside JSON.
"@

    $content = Invoke-HD365ProviderChat -ProviderId $provider -System $preamble -User $userPayload -Temperature $temperature -MaxTokens $maxTokens

    try {
        return (ConvertFrom-HD365AiJson -Content $content)
    }
    catch {
        $retryAllowed = $true
        if ($provider -eq 'CopilotChat' -and $config.ai.copilot -and $config.ai.copilot.requireJsonRetry -eq $false) {
            $retryAllowed = $false
        }
        if (-not $retryAllowed) { throw }

        Write-Host "AI JSON parse failed; retrying with stricter instruction..." -ForegroundColor Yellow
        $retryMsg = @"
Your previous reply was not valid JSON for HD365. Return ONLY a valid JSON object for this request (no markdown, no prose):

$userPayload
"@
        $content = Invoke-HD365ProviderChat -ProviderId $provider -System $preamble -User $retryMsg -Temperature $temperature -MaxTokens $maxTokens
        return (ConvertFrom-HD365AiJson -Content $content)
    }
}

function Invoke-HD365AiSolution {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$UserMessage,

        [Parameter(Mandatory)]
        [object]$Plan,

        [Parameter(Mandatory)]
        [string]$DiscoveryResultsText
    )

    $prompt = @"
PHASE: solution
Original request: $UserMessage

Prior plan summary: $($Plan.summary)
Intent: $($Plan.intent)
Platform: $($Plan.platform)
isWrite: $($Plan.isWrite)
expectedCount: $($Plan.expectedCount)

DISCOVERY_RESULTS:
$DiscoveryResultsText

Return JSON with phase=solution. Prefer job.creates for large create matrices. executionScript must be a ONE-LINER (or empty if job.creates fully describes the work). Bake real names/IDs from DISCOVERY_RESULTS. Create missing parents then children in one job. No placeholders.
"@

    return (Invoke-HD365Ai -UserMessage $prompt -History @() -PhaseHint solution)
}

function Get-HD365AiStatus {
    [CmdletBinding()]
    param()

    $provider = [string]$script:HD365Config.ai.provider
    if (-not $provider) { $provider = 'CopilotChat' }

    $catalog = @(Get-HD365ProviderCatalog)
    $entry = $catalog | Where-Object { $_.Id -eq $provider } | Select-Object -First 1
    $displayName = if ($entry) { $entry.DisplayName } else { $provider }

    $configured = Test-HD365AiConfigured
    $ctx = $null
    try { $ctx = Get-MgContext -ErrorAction SilentlyContinue } catch {}

    $convId = $null
    if ($script:HD365Session -and $script:HD365Session.Contains('CopilotConversationId')) {
        $convId = $script:HD365Session.CopilotConversationId
    }

    $graphConnected = [bool]$ctx
    $copilotApi = 'n/a'
    $copilotApiDetail = $null
    if ($provider -eq 'CopilotChat') {
        if ($graphConnected) {
            $copilotApi = 'NotProbed'
            $copilotApiDetail = 'Run /ai to probe Chat API (create conversation).'
        }
        else {
            $copilotApi = 'NotProbed'
            $copilotApiDetail = 'Graph not connected. Run /auth read, then /ai again.'
        }
    }

    $tip = 'Use /ai to switch providers.'
    if ($provider -eq 'CopilotChat') {
        $tip = 'Desktop Copilot != Chat API. Needs work M365 Copilot add-on + Graph scopes. Use /ai to probe.'
    }
    elseif ($entry -and $entry.Kind -eq 'Ollama') {
        $tip = "Run 'ollama serve' locally and pull a model. Use /ai to switch providers."
    }
    elseif ($entry -and $entry.KeyEnvVar) {
        $tip = "Set env var $($entry.KeyEnvVar). Use /ai to switch providers."
    }

    [pscustomobject]@{
        Provider              = $provider
        ProviderName           = $displayName
        Configured            = $configured
        AllowOfflineFallback  = [bool]$script:HD365Config.ai.allowOfflineFallback
        GraphConnected        = $graphConnected
        GraphAccount          = if ($ctx) { $ctx.Account } else { $null }
        CopilotApi            = $copilotApi
        CopilotApiHttp        = $null
        CopilotApiDetail      = $copilotApiDetail
        CopilotConversationId = $convId
        SettingsPath          = $script:HD365ConfigPath
        CopilotGraphRoot      = if ($script:HD365Config.ai.copilot -and $script:HD365Config.ai.copilot.graphRoot) { $script:HD365Config.ai.copilot.graphRoot } else { 'https://graph.microsoft.com/beta' }
        Tip                   = $tip
    }
}

function Get-HD365AiStatusWithProbe {
    <#
    .SYNOPSIS
      AI status including a live Copilot conversation-create probe when provider is CopilotChat.
    #>
    [CmdletBinding()]
    param()

    $status = Get-HD365AiStatus
    if ([string]$status.Provider -ne 'CopilotChat') {
        return $status
    }

    if (-not $status.GraphConnected) {
        $status.CopilotApi = 'NotProbed'
        $status.CopilotApiDetail = 'Graph not connected. Run /auth read, then /ai again.'
        return $status
    }

    Write-Host "Probing Copilot Chat API (create conversation)..." -ForegroundColor DarkGray
    $probe = Test-HD365CopilotChatApi
    if ($probe.Ok) {
        $status.CopilotApi = 'OK'
        $status.CopilotApiHttp = $probe.StatusCode
        $status.CopilotApiDetail = $probe.Message
        $status.CopilotConversationId = $probe.ConversationId
        if ($probe.GraphAccount) { $status.GraphAccount = $probe.GraphAccount }
    }
    else {
        $code = $probe.StatusCode
        $status.CopilotApi = if ($null -ne $code) { "Failed ($code/license)" } else { 'Failed' }
        $status.CopilotApiHttp = $code
        $status.CopilotApiDetail = $probe.Message
    }

    return $status
}
