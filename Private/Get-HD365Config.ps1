function Get-HD365Config {
    [CmdletBinding()]
    param(
        [string]$Path
    )

    if (-not $Path) {
        $userPath = Join-Path $env:LOCALAPPDATA 'HD365\settings.json'
        $examplePath = Join-Path $script:HD365Root 'Config\settings.example.json'
        if (Test-Path -LiteralPath $userPath) {
            $Path = $userPath
        }
        else {
            $Path = $examplePath
        }
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "HD365 settings not found at '$Path'. Copy Config\settings.example.json to %LOCALAPPDATA%\HD365\settings.json and edit it."
    }

    $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json

    if ($raw.audit.directory -match '%\w+%') {
        $raw.audit.directory = [Environment]::ExpandEnvironmentVariables($raw.audit.directory)
    }

    # Defaults for AI-first Copilot path
    if (-not $raw.ai) {
        $raw | Add-Member -NotePropertyName ai -NotePropertyValue ([pscustomobject]@{}) -Force
    }
    if (-not $raw.ai.provider) {
        $raw.ai | Add-Member -NotePropertyName provider -NotePropertyValue 'CopilotChat' -Force
    }
    if ($null -eq $raw.ai.PSObject.Properties['allowOfflineFallback'] -or $null -eq $raw.ai.allowOfflineFallback) {
        $raw.ai | Add-Member -NotePropertyName allowOfflineFallback -NotePropertyValue $false -Force
    }
    if (-not $raw.ai.copilot) {
        $raw.ai | Add-Member -NotePropertyName copilot -NotePropertyValue ([pscustomobject]@{
                graphRoot        = 'https://graph.microsoft.com/beta'
                timeZone         = 'America/New_York'
                requireJsonRetry = $true
            }) -Force
    }
    if (-not $raw.ai.PSObject.Properties['providers'] -or -not $raw.ai.providers) {
        $raw.ai | Add-Member -NotePropertyName providers -NotePropertyValue ([pscustomobject]@{}) -Force
    }

    # Migrate legacy flat AzureOpenAI/OpenAI fields (endpoint/deployment/apiVersion/apiKeyEnvVar/model
    # used to live directly under ai.*) into ai.providers.<ProviderId>.* so older settings.json files
    # keep working after the multi-provider refactor.
    $legacyProvider = [string]$raw.ai.provider
    $legacyFields = @('endpoint', 'deployment', 'apiVersion', 'apiKeyEnvVar', 'model')
    $hasLegacy = @($legacyFields | Where-Object { $raw.ai.PSObject.Properties[$_] -and $raw.ai.$_ }).Count -gt 0
    if ($hasLegacy -and $legacyProvider -in @('AzureOpenAI', 'OpenAI')) {
        if (-not $raw.ai.providers.PSObject.Properties[$legacyProvider]) {
            $raw.ai.providers | Add-Member -NotePropertyName $legacyProvider -NotePropertyValue ([pscustomobject]@{}) -Force
        }
        $target = $raw.ai.providers.$legacyProvider
        foreach ($field in $legacyFields) {
            if ($raw.ai.PSObject.Properties[$field] -and $raw.ai.$field) {
                if (-not $target.PSObject.Properties[$field]) {
                    $target | Add-Member -NotePropertyName $field -NotePropertyValue $raw.ai.$field -Force
                }
            }
        }
    }

    $script:HD365Config = $raw
    $script:HD365ConfigPath = $Path
    return $raw
}

function Save-HD365Config {
    <#
    .SYNOPSIS
      Persist the in-memory HD365 config (e.g. after /ai switches provider) to settings.json.
    #>
    [CmdletBinding()]
    param(
        [object]$Config,
        [string]$Path
    )

    if (-not $Config) { $Config = $script:HD365Config }
    if (-not $Config) { throw "No config loaded to save." }

    if (-not $Path) { $Path = $script:HD365ConfigPath }
    if (-not $Path) { throw "No settings path known. Run Get-HD365Config first." }

    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    ($Config | ConvertTo-Json -Depth 12) | Set-Content -LiteralPath $Path -Encoding UTF8
    return $Path
}
