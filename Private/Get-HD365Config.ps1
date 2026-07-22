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
                graphRoot         = 'https://graph.microsoft.com/beta'
                timeZone          = 'America/New_York'
                requireJsonRetry  = $true
            }) -Force
    }

    $script:HD365Config = $raw
    $script:HD365ConfigPath = $Path
    return $raw
}
