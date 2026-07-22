function Connect-HD365Graph {
    [CmdletBinding()]
    param(
        [ValidateSet('Read', 'Write')]
        [string]$Mode = 'Read',

        [string[]]$AdditionalScopes,

        # When set, connect with ONLY these scopes (+ User.Read) instead of the full catalog.
        # Strongly preferred to avoid repeated WAM consent prompts on bulk jobs.
        [string[]]$LeastScopes
    )

    $mg = Get-Module -ListAvailable -Name Microsoft.Graph.Authentication | Select-Object -First 1
    if (-not $mg) {
        throw "Microsoft.Graph.Authentication is not installed. Run: Install-Module Microsoft.Graph -Scope CurrentUser"
    }

    Import-Module Microsoft.Graph.Authentication -ErrorAction Stop

    $scopes = $null
    if ($LeastScopes -and $LeastScopes.Count -gt 0) {
        $scopes = @($LeastScopes + @('User.Read') | Select-Object -Unique)
        # For write mode, never silently drop needed write scopes from caller
    }
    elseif ($Mode -eq 'Write') {
        $scopes = Get-HD365WriteScopes
    }
    else {
        $scopes = Get-HD365ReadScopes
    }

    if ($AdditionalScopes) {
        $scopes = @($scopes + $AdditionalScopes | Select-Object -Unique)
    }

    # If already connected with a compatible mode and required scopes present, reuse.
    $context = Get-MgContext -ErrorAction SilentlyContinue
    if ($context) {
        $have = @($context.Scopes)
        $missing = @($scopes | Where-Object { $have -notcontains $_ })

        if ($missing.Count -eq 0 -and (
                ($Mode -eq 'Read' -and $script:HD365Session.GraphMode -in @('Read', 'Write')) -or
                ($Mode -eq 'Write' -and $script:HD365Session.GraphMode -eq 'Write')
            )) {
            $script:HD365Session.GraphConnected = $true
            return $context
        }

        # Need elevated/different scopes - reconnect once (not per operation)
        if ($Mode -eq 'Write' -or $missing.Count -gt 0) {
            Write-Host "Refreshing Microsoft Graph session for required scopes ($Mode)..." -ForegroundColor Yellow
            Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
            $context = $null
        }
    }

    $config = $script:HD365Config
    $connectParams = @{
        Scopes    = $scopes
        NoWelcome = $true
    }

    if ($config.graph.tenantId) {
        $connectParams['TenantId'] = $config.graph.tenantId
    }
    if ($config.graph.clientId) {
        $connectParams['ClientId'] = $config.graph.clientId
    }
    if ($config.graph.useDeviceCode) {
        $connectParams['UseDeviceCode'] = $true
    }

    Write-Host "Connecting to Microsoft Graph ($Mode) with $($scopes.Count) scope(s)..." -ForegroundColor Cyan
    Write-Host ("Scopes: " + ($scopes -join ', ')) -ForegroundColor DarkGray

    Connect-MgGraph @connectParams | Out-Null
    $context = Get-MgContext

    $script:HD365Session.GraphConnected = $true
    $script:HD365Session.GraphMode = $Mode

    Write-HD365Audit -EventType Auth -Data @{
        mode       = $Mode
        account    = $context.Account
        tenantId   = $context.TenantId
        scopeCount = @($context.Scopes).Count
        scopes     = @($context.Scopes)
        least      = [bool]$LeastScopes
    }

    Write-Host "Graph connected as $($context.Account) [$Mode]" -ForegroundColor Green
    return $context
}

function Connect-HD365Exchange {
    [CmdletBinding()]
    param()

    $exo = Get-Module -ListAvailable -Name ExchangeOnlineManagement | Select-Object -First 1
    if (-not $exo) {
        throw "ExchangeOnlineManagement is not installed. Run: Install-Module ExchangeOnlineManagement -Scope CurrentUser"
    }

    Import-Module ExchangeOnlineManagement -ErrorAction Stop

    if ($script:HD365Session.ExoConnected) {
        return
    }

    Write-Host "Connecting to Exchange Online..." -ForegroundColor Cyan
    $connectParams = @{ ShowBanner = $false }
    $tenantId = $script:HD365Config.graph.tenantId
    if ($tenantId) {
        # Delegated interactive: TenantId scopes the sign-in; Organization is for app-only / V2 param sets
        $connectParams['TenantId'] = $tenantId
    }
    Connect-ExchangeOnline @connectParams

    $script:HD365Session.ExoConnected = $true
    Write-HD365Audit -EventType Auth -Data @{ platform = 'ExchangeOnline' }
    Write-Host "Exchange Online connected." -ForegroundColor Green
}

function Ensure-HD365Platform {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Platform,

        [ValidateSet('Read', 'Write')]
        [string]$Mode = 'Read',

        [string[]]$LeastScopes
    )

    switch -Regex ($Platform) {
        'Graph|Microsoft Graph|Multi' {
            $connectParams = @{ Mode = $Mode }
            if ($LeastScopes -and $LeastScopes.Count -gt 0) {
                # Prefer task least-privilege scopes to avoid huge consent / repeated WAM prompts
                $connectParams['LeastScopes'] = @($LeastScopes)
            }
            # Keep Copilot Chat scopes on the same session so AI planning does not re-consent every phase
            if ($script:HD365Config -and [string]$script:HD365Config.ai.provider -eq 'CopilotChat') {
                $connectParams['AdditionalScopes'] = @(Get-HD365CopilotChatScopes)
            }
            Connect-HD365Graph @connectParams | Out-Null

            # Lazy-import common Graph submodules (bulk path uses Invoke-MgGraphRequest and may not need these)
            foreach ($m in @(
                    'Microsoft.Graph.Users',
                    'Microsoft.Graph.Groups',
                    'Microsoft.Graph.Identity.DirectoryManagement',
                    'Microsoft.Graph.Reports'
                )) {
                if (Get-Module -ListAvailable -Name $m) {
                    Import-Module $m -ErrorAction SilentlyContinue
                }
            }
        }
        'Exchange' {
            Connect-HD365Exchange
        }
        'Active Directory|AD|RSAT' {
            if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
                throw "ActiveDirectory RSAT module not available on this machine."
            }
            Import-Module ActiveDirectory -ErrorAction Stop
        }
        'Azure CLI' {
            $az = Get-Command az -ErrorAction SilentlyContinue
            if (-not $az) { throw "Azure CLI (az) not found on PATH." }
        }
    }
}
