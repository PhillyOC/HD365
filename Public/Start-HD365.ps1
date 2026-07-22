function Start-HD365 {
    <#
    .SYNOPSIS
        Launch the HelpDesk 365 AI interactive console.

    .DESCRIPTION
        Natural-language M365 helpdesk assistant. Uses AI to propose least-privilege
        PowerShell (Graph / EXO / AD / Azure CLI), gathers with READ scopes only,
        and executes writes only after explicit approval + confirmation.

    .PARAMETER SettingsPath
        Optional path to settings.json. Defaults to %LOCALAPPDATA%\HD365\settings.json
        or the bundled Config\settings.example.json.

    .EXAMPLE
        Start-HD365
    #>
    [CmdletBinding()]
    param(
        [string]$SettingsPath
    )

    $null = Get-HD365Config -Path $SettingsPath
    $null = Initialize-HD365Session
    Start-HD365Repl
}

function Get-HD365AuditLog {
    <#
    .SYNOPSIS
        Read HD365 local audit JSONL records.
    #>
    [CmdletBinding()]
    param(
        [int]$Last = 50,
        [switch]$WritesOnly,
        [string]$AuditDirectory
    )

    if (-not $script:HD365Config) {
        $null = Get-HD365Config
    }

    $dir = $AuditDirectory
    if (-not $dir) { $dir = $script:HD365Config.audit.directory }

    if ($WritesOnly) {
        $path = Join-Path $dir 'hd365-writes.jsonl'
        if (-not (Test-Path -LiteralPath $path)) { return @() }
        $lines = Get-Content -LiteralPath $path -Encoding UTF8
    }
    else {
        $files = Get-ChildItem -LiteralPath $dir -Filter 'hd365-audit-*.jsonl' -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending
        if (-not $files) { return @() }
        $lines = Get-Content -LiteralPath $files[0].FullName -Encoding UTF8
    }

    $records = foreach ($line in $lines) {
        if ($line) { $line | ConvertFrom-Json }
    }
    $records | Select-Object -Last $Last
}

function Connect-HD365 {
    <#
    .SYNOPSIS
        Connect Microsoft Graph for HD365 with Read or Write mode.
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('Read', 'Write')]
        [string]$Mode = 'Read'
    )

    if (-not $script:HD365Config) { $null = Get-HD365Config }
    if (-not $script:HD365Session) { $null = Initialize-HD365Session }
    Connect-HD365Graph -Mode $Mode
}
