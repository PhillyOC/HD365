function Get-HD365CopilotChatScopes {
    @(
        'Sites.Read.All'
        'Mail.Read'
        'People.Read.All'
        'OnlineMeetingTranscript.Read.All'
        'Chat.Read'
        'ChannelMessage.Read.All'
        'ExternalItem.Read.All'
        'User.Read'
    )
}

function Get-HD365CopilotGraphRoot {
    $root = 'https://graph.microsoft.com/beta'
    if ($script:HD365Config -and $script:HD365Config.ai.copilot -and $script:HD365Config.ai.copilot.graphRoot) {
        $root = [string]$script:HD365Config.ai.copilot.graphRoot.TrimEnd('/')
    }
    return $root
}

function Connect-HD365CopilotGraph {
    <#
    .SYNOPSIS
      Ensure Graph session has Copilot Chat API delegated scopes (may prompt once).
    #>
    [CmdletBinding()]
    param()

    $scopes = Get-HD365CopilotChatScopes
    $ctx = Get-MgContext -ErrorAction SilentlyContinue
    if ($ctx) {
        $have = @($ctx.Scopes)
        $missing = @($scopes | Where-Object { $have -notcontains $_ })
        if ($missing.Count -eq 0) { return $ctx }
    }

    Write-Host "Connecting Microsoft Graph for Copilot Chat API scopes (one-time consent may appear)..." -ForegroundColor Cyan
    Connect-HD365Graph -Mode Read -LeastScopes $scopes | Out-Null
    return (Get-MgContext)
}

function Get-HD365GraphErrorStatusCode {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Exception]$Exception)

    $msg = $Exception.Message
    if ($Exception.InnerException) { $msg = $msg + ' ' + $Exception.InnerException.Message }

    if ($msg -match '(?i)\b(401|403|404|429|500|502|503)\b') {
        return [int]$Matches[1]
    }
    if ($msg -match '(?i)Unauthorized') { return 401 }
    if ($msg -match '(?i)Forbidden') { return 403 }
    if ($msg -match '(?i)Not\s*Found') { return 404 }
    if ($msg -match '(?i)Internal\s*Server\s*Error') { return 500 }
    return $null
}

function New-HD365CopilotApiError {
    <#
    .SYNOPSIS
      Build a clear Copilot Chat API failure message (step + status + license note).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('create conversation', 'chat')]
        [string]$Step,

        [Parameter(Mandatory)]
        [System.Exception]$Exception
    )

    $status = Get-HD365GraphErrorStatusCode -Exception $Exception
    $statusText = if ($null -ne $status) { [string]$status } else { 'unknown' }
    $detail = $Exception.Message.Trim()

    $licenseHint = @(
        'Desktop/consumer Copilot is NOT this API.'
        'Graph /beta/copilot/conversations requires a Microsoft 365 Copilot add-on license on a work/school account.'
        'Home Graph sign-in can succeed while Chat API still fails (401/403/500).'
        'Retry on a work tenant account that has M365 Copilot assigned; run /ai to probe.'
    ) -join ' '

    return "Copilot Chat API failed at '$Step' (HTTP $statusText): $detail. $licenseHint"
}

function ConvertFrom-HD365CopilotChatResponse {
    <#
    .SYNOPSIS
      Extract assistant text from a copilotConversation chat response.
      Per Graph docs, messages[0] echoes the user prompt; messages[-1] is Copilot.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Response
    )

    if ($Response.messages) {
        $texts = @(
            @($Response.messages) |
                Where-Object { $_.text } |
                ForEach-Object { [string]$_.text }
        )
        if ($texts.Count -gt 0) {
            return $texts[-1].Trim()
        }
    }

    if ($Response.message -and $Response.message.text) {
        return ([string]$Response.message.text).Trim()
    }
    if ($Response.text) { return ([string]$Response.text).Trim() }
    if ($Response.answer) { return ([string]$Response.answer).Trim() }

    return $null
}

function Test-HD365CopilotChatApi {
    <#
    .SYNOPSIS
      Lightweight probe: POST /copilot/conversations only (no chat turn).
    #>
    [CmdletBinding()]
    param()

    $result = [ordered]@{
        Ok           = $false
        Step         = 'create conversation'
        StatusCode   = $null
        ConversationId = $null
        Message      = $null
        GraphAccount = $null
    }

    try {
        $ctx = Connect-HD365CopilotGraph
        $result.GraphAccount = if ($ctx) { $ctx.Account } else { $null }
        $root = Get-HD365CopilotGraphRoot
        $conv = Invoke-MgGraphRequest -Method POST -Uri "$root/copilot/conversations" -Body '{}' -ContentType 'application/json'
        if (-not $conv.id) {
            $result.Message = "Copilot Chat API failed at 'create conversation' (HTTP unknown): response had no id."
            return [pscustomobject]$result
        }
        $result.Ok = $true
        $result.ConversationId = [string]$conv.id
        $result.StatusCode = 201
        $result.Message = 'OK (conversation created)'
        if ($script:HD365Session) {
            $script:HD365Session.CopilotConversationId = $result.ConversationId
        }
        return [pscustomobject]$result
    }
    catch {
        $result.StatusCode = Get-HD365GraphErrorStatusCode -Exception $_.Exception
        $result.Message = New-HD365CopilotApiError -Step 'create conversation' -Exception $_.Exception
        return [pscustomobject]$result
    }
}

function Invoke-HD365CopilotChat {
    <#
    .SYNOPSIS
      Call Microsoft 365 Copilot Chat API (Graph beta) and return assistant text.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [string]$SystemPreamble
    )

    Connect-HD365CopilotGraph | Out-Null

    $root = Get-HD365CopilotGraphRoot

    $tz = 'America/New_York'
    if ($script:HD365Config -and $script:HD365Config.ai.copilot -and $script:HD365Config.ai.copilot.timeZone) {
        $tz = [string]$script:HD365Config.ai.copilot.timeZone
    }

    try {
        $conv = Invoke-MgGraphRequest -Method POST -Uri "$root/copilot/conversations" -Body '{}' -ContentType 'application/json'
    }
    catch {
        throw (New-HD365CopilotApiError -Step 'create conversation' -Exception $_.Exception)
    }

    $conversationId = $conv.id
    if (-not $conversationId) { throw "Copilot Chat: failed to create conversation (no id)." }

    if ($script:HD365Session) {
        $script:HD365Session.CopilotConversationId = $conversationId
    }

    $text = $Message
    if ($SystemPreamble) {
        $text = $SystemPreamble + "`n`n" + $Message
    }

    $bodyObj = @{
        message = @{
            text = $text
        }
        locationHint = @{
            timeZone = $tz
        }
    }
    $bodyJson = $bodyObj | ConvertTo-Json -Depth 6 -Compress

    Write-Host "Asking Microsoft 365 Copilot (Chat API)..." -ForegroundColor DarkGray
    try {
        $resp = Invoke-MgGraphRequest -Method POST -Uri "$root/copilot/conversations/$conversationId/chat" -Body $bodyJson -ContentType 'application/json'
    }
    catch {
        throw (New-HD365CopilotApiError -Step 'chat' -Exception $_.Exception)
    }

    $joined = ConvertFrom-HD365CopilotChatResponse -Response $resp
    if ([string]::IsNullOrWhiteSpace($joined)) {
        $raw = ($resp | ConvertTo-Json -Depth 8 -Compress)
        throw "Copilot Chat returned no text. Raw (truncated): $($raw.Substring(0, [Math]::Min(800, $raw.Length)))"
    }

    return $joined
}

function Show-HD365AiSetupHelp {
    [CmdletBinding()]
    param([string]$ErrorMessage)

    Write-Host ""
    Write-Host "AI planner required for this request." -ForegroundColor Yellow
    if ($ErrorMessage) {
        Write-Host "Detail: $ErrorMessage" -ForegroundColor DarkYellow
    }
    Write-Host ""
    Write-Host "Configured provider: $([string]$script:HD365Config.ai.provider)" -ForegroundColor Cyan
    Write-Host ""
    Write-Host 'Important:' -ForegroundColor White
    Write-Host '  Desktop/consumer Copilot app is NOT the Chat API HD365 uses.' -ForegroundColor Gray
    Write-Host '  Graph auth can succeed at home while Chat API still returns 401/403/500.' -ForegroundColor Gray
    Write-Host '  You need a work/school account with Microsoft 365 Copilot add-on license.' -ForegroundColor Gray
    Write-Host ''
    Write-Host 'CopilotChat (work tenant):' -ForegroundColor White
    Write-Host '  1. Sign in with the work account that has M365 Copilot assigned' -ForegroundColor Gray
    Write-Host '  2. In %LOCALAPPDATA%\HD365\settings.json set ai.provider to CopilotChat' -ForegroundColor Gray
    Write-Host '  3. Run /auth read and consent Copilot Chat Graph scopes' -ForegroundColor Gray
    Write-Host '  4. Type /ai - CopilotApi should be OK before long NL requests' -ForegroundColor Gray
    Write-Host ''
    Write-Host 'Other providers (agnostic line):' -ForegroundColor White
    Write-Host '  AzureOpenAI, OpenAI, Anthropic, Gemini, Together, Mistral - set an API key env var' -ForegroundColor Gray
    Write-Host '  Ollama - run locally (ollama serve), no API key needed' -ForegroundColor Gray
    Write-Host '  Type /ai to see the full list and switch interactively' -ForegroundColor Gray
    Write-Host ''
}
