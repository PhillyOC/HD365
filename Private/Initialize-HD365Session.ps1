function Initialize-HD365Session {
    [CmdletBinding()]
    param()

    # Reuse an already-loaded config (e.g. Start-HD365 -SettingsPath, or a test harness that
    # loaded a specific settings.json) instead of unconditionally re-running Get-HD365Config's
    # ambient %LOCALAPPDATA% detection, which would silently discard an explicit path.
    $config = $script:HD365Config
    if (-not $config) {
        $config = Get-HD365Config
    }

    $script:HD365Session = [ordered]@{
        Id              = [guid]::NewGuid().ToString('N')
        StartedAt       = (Get-Date).ToUniversalTime()
        Phase           = 'Ready'    # Ready | Discovery | Solution | Execute
        GraphConnected  = $false
        GraphMode       = 'None'     # None | Read | Write
        ExoConnected    = $false
        AdAvailable     = $false
        History         = [System.Collections.Generic.List[object]]::new()
        PendingProposal = $null
        LastResult      = $null
        Operator               = $env:USERNAME
        Machine                = $env:COMPUTERNAME
        ConfigPath             = $script:HD365ConfigPath
        CopilotConversationId  = $null
    }

    $auditDir = $config.audit.directory
    if ($config.audit.enabled -and $auditDir) {
        if (-not (Test-Path -LiteralPath $auditDir)) {
            New-Item -ItemType Directory -Path $auditDir -Force | Out-Null
        }
    }

    $adModule = Get-Module -ListAvailable -Name ActiveDirectory | Select-Object -First 1
    $script:HD365Session.AdAvailable = [bool]$adModule

    return $script:HD365Session
}
