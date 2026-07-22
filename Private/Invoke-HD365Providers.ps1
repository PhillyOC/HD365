function Get-HD365ProviderCatalog {
    <#
    .SYNOPSIS
      Catalog of AI providers available to this HD365 build.
      Work exports replace this file with a CopilotChat + AzureOpenAI-only version.
    #>
    [CmdletBinding()]
    param()

    @(
        [pscustomobject]@{
            Id             = 'CopilotChat'
            DisplayName    = 'Microsoft 365 Copilot Chat'
            Kind           = 'Copilot'
            NeedsKey       = $false
            NeedsEndpoint  = $false
            DefaultModel   = $null
            DefaultBaseUrl = 'https://graph.microsoft.com/beta'
            KeyEnvVar      = $null
            Notes          = 'Requires Microsoft 365 Copilot add-on license (work/school account).'
        }
        [pscustomobject]@{
            Id             = 'AzureOpenAI'
            DisplayName    = 'Azure OpenAI'
            Kind           = 'AzureOpenAI'
            NeedsKey       = $true
            NeedsEndpoint  = $true
            DefaultModel   = 'gpt-4o'
            DefaultBaseUrl = $null
            KeyEnvVar      = 'HD365_AZURE_OPENAI_KEY'
            Notes          = 'Set endpoint + deployment in settings.json ai.providers.AzureOpenAI.'
        }
        [pscustomobject]@{
            Id             = 'OpenAI'
            DisplayName    = 'OpenAI'
            Kind           = 'OpenAICompatible'
            NeedsKey       = $true
            NeedsEndpoint  = $false
            DefaultModel   = 'gpt-4o'
            DefaultBaseUrl = 'https://api.openai.com/v1'
            KeyEnvVar      = 'HD365_OPENAI_KEY'
            Notes          = ''
        }
        [pscustomobject]@{
            Id             = 'Anthropic'
            DisplayName    = 'Anthropic Claude'
            Kind           = 'Anthropic'
            NeedsKey       = $true
            NeedsEndpoint  = $false
            DefaultModel   = 'claude-sonnet-4-5'
            DefaultBaseUrl = 'https://api.anthropic.com/v1'
            KeyEnvVar      = 'HD365_ANTHROPIC_KEY'
            Notes          = ''
        }
        [pscustomobject]@{
            Id             = 'Gemini'
            DisplayName    = 'Google Gemini'
            Kind           = 'Gemini'
            NeedsKey       = $true
            NeedsEndpoint  = $false
            DefaultModel   = 'gemini-2.0-flash'
            DefaultBaseUrl = 'https://generativelanguage.googleapis.com/v1beta'
            KeyEnvVar      = 'HD365_GEMINI_KEY'
            Notes          = ''
        }
        [pscustomobject]@{
            Id             = 'Together'
            DisplayName    = 'Together AI'
            Kind           = 'OpenAICompatible'
            NeedsKey       = $true
            NeedsEndpoint  = $false
            DefaultModel   = 'meta-llama/Meta-Llama-3.1-70B-Instruct-Turbo'
            DefaultBaseUrl = 'https://api.together.xyz/v1'
            KeyEnvVar      = 'HD365_TOGETHER_KEY'
            Notes          = ''
        }
        [pscustomobject]@{
            Id             = 'Mistral'
            DisplayName    = 'Mistral AI'
            Kind           = 'OpenAICompatible'
            NeedsKey       = $true
            NeedsEndpoint  = $false
            DefaultModel   = 'mistral-large-latest'
            DefaultBaseUrl = 'https://api.mistral.ai/v1'
            KeyEnvVar      = 'HD365_MISTRAL_KEY'
            Notes          = ''
        }
        [pscustomobject]@{
            Id             = 'Ollama'
            DisplayName    = 'Ollama (local)'
            Kind           = 'Ollama'
            NeedsKey       = $false
            NeedsEndpoint  = $false
            DefaultModel   = 'llama3.2'
            DefaultBaseUrl = 'http://127.0.0.1:11434'
            KeyEnvVar      = $null
            Notes          = 'Requires Ollama running locally (ollama serve; ollama pull <model>).'
        }
    )
}

function Get-HD365ProviderSettings {
    <#
    .SYNOPSIS
      Merge catalog defaults with settings.json ai.providers.<Id> overrides.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Id
    )

    $entry = @(Get-HD365ProviderCatalog) | Where-Object { $_.Id -eq $Id } | Select-Object -First 1
    if (-not $entry) {
        throw "Unknown AI provider '$Id'. Type /ai to see available providers."
    }

    $userCfg = $null
    if ($script:HD365Config -and $script:HD365Config.ai -and $script:HD365Config.ai.providers -and
        $script:HD365Config.ai.providers.PSObject.Properties[$Id]) {
        $userCfg = $script:HD365Config.ai.providers.$Id
    }

    $model = $entry.DefaultModel
    if ($userCfg -and $userCfg.PSObject.Properties['model'] -and $userCfg.model) { $model = [string]$userCfg.model }

    $baseUrl = $entry.DefaultBaseUrl
    if ($userCfg -and $userCfg.PSObject.Properties['baseUrl'] -and $userCfg.baseUrl) { $baseUrl = [string]$userCfg.baseUrl }
    if ($baseUrl) { $baseUrl = $baseUrl.TrimEnd('/') }

    $endpoint = $null
    if ($userCfg -and $userCfg.PSObject.Properties['endpoint'] -and $userCfg.endpoint) { $endpoint = [string]$userCfg.endpoint.TrimEnd('/') }

    $deployment = $null
    if ($userCfg -and $userCfg.PSObject.Properties['deployment'] -and $userCfg.deployment) { $deployment = [string]$userCfg.deployment }

    $apiVersion = '2024-10-21'
    if ($userCfg -and $userCfg.PSObject.Properties['apiVersion'] -and $userCfg.apiVersion) { $apiVersion = [string]$userCfg.apiVersion }

    $keyEnvVar = $entry.KeyEnvVar
    if ($userCfg -and $userCfg.PSObject.Properties['apiKeyEnvVar'] -and $userCfg.apiKeyEnvVar) { $keyEnvVar = [string]$userCfg.apiKeyEnvVar }

    [pscustomobject]@{
        Id            = $entry.Id
        DisplayName   = $entry.DisplayName
        Kind          = $entry.Kind
        NeedsKey      = $entry.NeedsKey
        NeedsEndpoint = $entry.NeedsEndpoint
        Notes         = $entry.Notes
        Model         = $model
        BaseUrl       = $baseUrl
        Endpoint      = $endpoint
        Deployment    = $deployment
        ApiVersion    = $apiVersion
        KeyEnvVar     = $keyEnvVar
    }
}

function Get-HD365ProviderApiKey {
    <#
    .SYNOPSIS
      Read a provider's API key from its configured environment variable.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Settings
    )

    $envVar = $Settings.KeyEnvVar
    if (-not $envVar) {
        throw "$($Settings.DisplayName) has no configured API key environment variable."
    }

    $key = [Environment]::GetEnvironmentVariable($envVar, 'Process')
    if (-not $key) { $key = [Environment]::GetEnvironmentVariable($envVar, 'User') }
    if (-not $key) { $key = [Environment]::GetEnvironmentVariable($envVar, 'Machine') }

    if (-not $key) {
        throw "$($Settings.DisplayName) API key not found. Set environment variable '$envVar'."
    }
    return $key
}

function Test-HD365ProviderConfigured {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Id
    )

    $settings = Get-HD365ProviderSettings -Id $Id

    switch ($settings.Kind) {
        'Copilot' { return $true }
        'Ollama'  { return [bool]$settings.BaseUrl }
        'AzureOpenAI' {
            if (-not $settings.Endpoint -or -not $settings.Deployment) { return $false }
            try { $null = Get-HD365ProviderApiKey -Settings $settings; return $true }
            catch { return $false }
        }
        default {
            try { $null = Get-HD365ProviderApiKey -Settings $settings; return $true }
            catch { return $false }
        }
    }
}

function Invoke-HD365ProviderChat {
    <#
    .SYNOPSIS
      Send system+user text to the given provider and return assistant text.
      Every provider returns plain text; JSON parsing/retry happens in Invoke-HD365Ai.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProviderId,

        [Parameter(Mandatory)]
        [string]$System,

        [Parameter(Mandatory)]
        [string]$User,

        [double]$Temperature = 0.2,

        [int]$MaxTokens = 8192
    )

    $settings = Get-HD365ProviderSettings -Id $ProviderId

    switch ($settings.Kind) {
        'Copilot' {
            return Invoke-HD365CopilotChat -Message $User -SystemPreamble $System
        }

        'AzureOpenAI' {
            if (-not $settings.Endpoint -or -not $settings.Deployment) {
                throw "Azure OpenAI endpoint and deployment must be set in settings.json (ai.providers.AzureOpenAI)."
            }
            $apiKey = Get-HD365ProviderApiKey -Settings $settings
            $uri = "$($settings.Endpoint)/openai/deployments/$($settings.Deployment)/chat/completions?api-version=$($settings.ApiVersion)"
            $body = @{
                messages        = @(
                    @{ role = 'system'; content = $System }
                    @{ role = 'user'; content = $User }
                )
                temperature     = $Temperature
                max_tokens      = $MaxTokens
                response_format = @{ type = 'json_object' }
            } | ConvertTo-Json -Depth 10
            $headers = @{ 'api-key' = $apiKey; 'Content-Type' = 'application/json' }
            $resp = Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -Body $body -TimeoutSec 180
            return [string]$resp.choices[0].message.content
        }

        'OpenAICompatible' {
            if (-not $settings.BaseUrl) { throw "$($settings.DisplayName): base URL not configured." }
            if (-not $settings.Model) { throw "$($settings.DisplayName): model not configured." }
            $apiKey = Get-HD365ProviderApiKey -Settings $settings
            $uri = "$($settings.BaseUrl)/chat/completions"
            $headers = @{ Authorization = "Bearer $apiKey"; 'Content-Type' = 'application/json' }

            $bodyObj = [ordered]@{
                model       = $settings.Model
                messages    = @(
                    @{ role = 'system'; content = $System }
                    @{ role = 'user'; content = $User }
                )
                temperature = $Temperature
                max_tokens  = $MaxTokens
            }
            try {
                $bodyObj['response_format'] = @{ type = 'json_object' }
                $body = $bodyObj | ConvertTo-Json -Depth 10
                $resp = Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -Body $body -TimeoutSec 180
            }
            catch {
                # Some OpenAI-compatible providers reject response_format; retry without it.
                $bodyObj.Remove('response_format')
                $body = $bodyObj | ConvertTo-Json -Depth 10
                $resp = Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -Body $body -TimeoutSec 180
            }
            return [string]$resp.choices[0].message.content
        }

        'Anthropic' {
            if (-not $settings.BaseUrl) { throw "Anthropic: base URL not configured." }
            if (-not $settings.Model) { throw "Anthropic: model not configured." }
            $apiKey = Get-HD365ProviderApiKey -Settings $settings
            $uri = "$($settings.BaseUrl)/messages"
            $body = @{
                model       = $settings.Model
                system      = $System
                max_tokens  = $MaxTokens
                temperature = $Temperature
                messages    = @(
                    @{ role = 'user'; content = $User }
                )
            } | ConvertTo-Json -Depth 10
            $headers = @{
                'x-api-key'         = $apiKey
                'anthropic-version' = '2023-06-01'
                'Content-Type'      = 'application/json'
            }
            $resp = Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -Body $body -TimeoutSec 180
            $texts = @($resp.content | Where-Object { $_.type -eq 'text' } | ForEach-Object { [string]$_.text })
            return ($texts -join "`n")
        }

        'Gemini' {
            if (-not $settings.BaseUrl) { throw "Gemini: base URL not configured." }
            if (-not $settings.Model) { throw "Gemini: model not configured." }
            $apiKey = Get-HD365ProviderApiKey -Settings $settings
            $uri = "$($settings.BaseUrl)/models/$($settings.Model):generateContent?key=$apiKey"
            $body = @{
                systemInstruction = @{ parts = @(@{ text = $System }) }
                contents          = @(
                    @{ role = 'user'; parts = @(@{ text = $User }) }
                )
                generationConfig  = @{
                    temperature      = $Temperature
                    maxOutputTokens  = $MaxTokens
                    responseMimeType = 'application/json'
                }
            } | ConvertTo-Json -Depth 12
            $resp = Invoke-RestMethod -Method Post -Uri $uri -Body $body -ContentType 'application/json' -TimeoutSec 180
            $texts = @($resp.candidates[0].content.parts | Where-Object { $_.text } | ForEach-Object { [string]$_.text })
            return ($texts -join "`n")
        }

        'Ollama' {
            if (-not $settings.BaseUrl) { throw "Ollama: base URL not configured (default http://127.0.0.1:11434)." }
            if (-not $settings.Model) { throw "Ollama: model not configured." }
            $uri = "$($settings.BaseUrl)/api/chat"
            $body = @{
                model    = $settings.Model
                stream   = $false
                format   = 'json'
                messages = @(
                    @{ role = 'system'; content = $System }
                    @{ role = 'user'; content = $User }
                )
            } | ConvertTo-Json -Depth 10
            try {
                $resp = Invoke-RestMethod -Method Post -Uri $uri -Body $body -ContentType 'application/json' -TimeoutSec 180
            }
            catch {
                throw "Ollama request failed ($($_.Exception.Message)). Is 'ollama serve' running and is model '$($settings.Model)' pulled (ollama pull $($settings.Model))?"
            }
            return [string]$resp.message.content
        }

        default {
            throw "Unsupported AI provider kind '$($settings.Kind)' for '$ProviderId'."
        }
    }
}
