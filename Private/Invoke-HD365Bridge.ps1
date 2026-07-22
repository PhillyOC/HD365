function Get-HD365BridgeParam {
    <#
    .SYNOPSIS
      Null/StrictMode-safe accessor for a field on the JSON-RPC 'params' object. Direct dot
      access (e.g. $Params.foo) throws under Set-StrictMode -Version Latest when $Params is a
      non-null object that simply lacks that property (e.g. client sent an empty {} params).
    #>
    [CmdletBinding()]
    param(
        [object]$Params,
        [Parameter(Mandatory)]
        [string]$Name,
        $Default = $null
    )

    if ($null -eq $Params) { return $Default }
    $prop = $Params.PSObject.Properties[$Name]
    if (-not $prop) { return $Default }
    if ($null -eq $prop.Value) { return $Default }
    return $prop.Value
}

function Invoke-HD365BridgeMethod {
    <#
    .SYNOPSIS
      Dispatch one JSON-RPC method call into the existing HD365 engine. Every engine call in
      here runs with streams 3/4/5/6 (Warning/Verbose/Debug/Information) redirected to $null by
      the caller (Start-HD365Bridge), so Write-Host narration inside the engine never corrupts
      the newline-delimited JSON protocol on stdout.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Method,

        [object]$Params
    )

    switch ($Method) {
        'ping' {
            return [ordered]@{
                pong         = $true
                bridgeVersion = $script:HD365BridgeVersion
                moduleVersion = $script:HD365ModuleVersion
                timestampUtc = (Get-Date).ToUniversalTime().ToString('o')
            }
        }

        'session.init' {
            # Only probe Get-MgContext if Microsoft.Graph.Authentication is already imported -
            # otherwise PowerShell's command-not-found autoload machinery scans every installed
            # module for a matching command, which can take 30s+ with the full Microsoft.Graph
            # module tree installed and would make every session.init call look "hung".
            $ctx = $null
            if (Get-Module -Name Microsoft.Graph.Authentication -ErrorAction SilentlyContinue) {
                try { $ctx = Get-MgContext -ErrorAction SilentlyContinue } catch {}
            }
            return [ordered]@{
                sessionId      = $script:HD365Session.Id
                phase          = $script:HD365Session.Phase
                operator       = $script:HD365Session.Operator
                machine        = $script:HD365Session.Machine
                graphConnected = [bool]$ctx
                graphAccount   = if ($ctx) { $ctx.Account } else { $null }
                graphMode      = [string]$script:HD365Session.GraphMode
                exoConnected   = [bool]$script:HD365Session.ExoConnected
                adAvailable    = [bool]$script:HD365Session.AdAvailable
                hasPending     = [bool]$script:HD365Session.PendingProposal
                configPath     = [string]$script:HD365ConfigPath
            }
        }

        'config.get' {
            return $script:HD365Config
        }

        'config.saveProvider' {
            $providerId = [string](Get-HD365BridgeParam -Params $Params -Name 'providerId')
            if (-not $providerId) { throw "Missing required param 'providerId'." }
            $catalogEntry = @(Get-HD365ProviderCatalog) | Where-Object { $_.Id -eq $providerId } | Select-Object -First 1
            if (-not $catalogEntry) { throw "Unknown provider '$providerId'." }
            if (-not $script:HD365Config.ai) {
                $script:HD365Config | Add-Member -NotePropertyName ai -NotePropertyValue ([pscustomobject]@{}) -Force
            }
            $script:HD365Config.ai | Add-Member -NotePropertyName provider -NotePropertyValue $catalogEntry.Id -Force
            Save-HD365Config | Out-Null
            return [ordered]@{ provider = $catalogEntry.Id }
        }

        'provider.catalog' {
            $activeProvider = [string]$script:HD365Config.ai.provider
            $rows = foreach ($p in @(Get-HD365ProviderCatalog)) {
                [ordered]@{
                    id            = $p.Id
                    displayName   = $p.DisplayName
                    kind          = $p.Kind
                    needsKey      = [bool]$p.NeedsKey
                    needsEndpoint = [bool]$p.NeedsEndpoint
                    keyEnvVar     = $p.KeyEnvVar
                    notes         = $p.Notes
                    configured    = (Test-HD365ProviderConfigured -Id $p.Id)
                    active        = ($p.Id -eq $activeProvider)
                }
            }
            return @($rows)
        }

        'ai.statusProbe' {
            return (Get-HD365AiStatusWithProbe)
        }

        'auth.connect' {
            $mode = [string](Get-HD365BridgeParam -Params $Params -Name 'mode' -Default 'Read')
            $ctx = Connect-HD365Graph -Mode $mode
            return [ordered]@{ account = $ctx.Account; tenantId = $ctx.TenantId; scopes = @($ctx.Scopes) }
        }

        'exo.connect' {
            Connect-HD365Exchange
            return [ordered]@{ connected = $true }
        }

        'pipeline.submit' {
            $message = [string](Get-HD365BridgeParam -Params $Params -Name 'message')
            if ([string]::IsNullOrWhiteSpace($message)) { throw "Missing required param 'message'." }
            $historyLimit = 8
            if ($script:HD365Config.session -and $script:HD365Config.session.historyLimit) {
                $historyLimit = [int]$script:HD365Config.session.historyLimit
            }
            $hist = @($script:HD365Session.History | Select-Object -Last ([Math]::Max(0, $historyLimit - 1)))
            $pending = Invoke-HD365Pipeline -UserMessage $message -History $hist

            $assistantCompact = ($pending.Proposal | ConvertTo-Json -Compress -Depth 6)
            $script:HD365Session.History.Add([pscustomobject]@{ user = $message; assistant = $assistantCompact })
            while ($script:HD365Session.History.Count -gt $historyLimit) {
                $script:HD365Session.History.RemoveAt(0)
            }

            return $pending
        }

        'run.preview' {
            return (Get-HD365RunPreview)
        }

        'run.execute' {
            $confirmPhrase = Get-HD365BridgeParam -Params $Params -Name 'confirmPhrase'
            return (Invoke-HD365ExecutePlan -ConfirmPhrase $confirmPhrase)
        }

        'run.cancel' {
            $script:HD365Session.PendingProposal = $null
            $script:HD365Session.Phase = 'Ready'
            Write-HD365Audit -EventType Cancel -Data @{ reason = 'user_cancel' }
            return [ordered]@{ cancelled = $true }
        }

        'audit.tail' {
            $last = [int](Get-HD365BridgeParam -Params $Params -Name 'last' -Default 50)
            $writesOnly = [bool](Get-HD365BridgeParam -Params $Params -Name 'writesOnly' -Default $false)
            return @(Get-HD365AuditLog -Last $last -WritesOnly:$writesOnly)
        }

        'shutdown' {
            $script:HD365BridgeShouldExit = $true
            return [ordered]@{ ok = $true }
        }

        default {
            throw "Unknown bridge method '$Method'."
        }
    }
}

function Start-HD365Bridge {
    <#
    .SYNOPSIS
      JSON-RPC-over-stdio loop for the HD365 desktop app. Reads one newline-delimited JSON
      request per line from stdin ({id, method, params}), dispatches it into the existing
      HD365 engine, and writes one newline-delimited JSON response per line to stdout
      ({id, result} or {id, error}). Intended to be spawned as a long-lived child process by
      the Tauri Rust shell; never used by the console REPL.

    .PARAMETER SettingsPath
      Optional path to settings.json. Defaults to %LOCALAPPDATA%\HD365\settings.json or the
      bundled Config\settings.example.json, same as Start-HD365.
    #>
    [CmdletBinding()]
    param(
        [string]$SettingsPath
    )

    $script:HD365BridgeVersion = '1'
    $script:HD365ModuleVersion = (Get-Module HD365 -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Version)
    $script:HD365BridgeShouldExit = $false

    $null = Get-HD365Config -Path $SettingsPath
    $null = Initialize-HD365Session

    $stdin = [Console]::In

    while (-not $script:HD365BridgeShouldExit) {
        $line = $stdin.ReadLine()
        if ($null -eq $line) { break }   # EOF: parent closed the pipe (app exit) -> exit quietly
        if ([string]::IsNullOrWhiteSpace($line)) { continue }

        $id = $null
        try {
            $req = $line | ConvertFrom-Json -ErrorAction Stop
            $id = $req.id
            $method = [string]$req.method
            $params = $null
            if ($req.PSObject.Properties['params']) { $params = $req.params }

            $result = Invoke-HD365BridgeMethod -Method $method -Params $params 3>$null 4>$null 5>$null 6>$null
            $resp = [ordered]@{ id = $id; result = $result }
        }
        catch {
            $resp = [ordered]@{
                id    = $id
                error = [ordered]@{
                    message = $_.Exception.Message
                    type    = $_.Exception.GetType().Name
                }
            }
        }

        $json = $null
        try {
            $json = ($resp | ConvertTo-Json -Depth 20 -Compress)
        }
        catch {
            # Result failed to serialize (should be rare) - fall back to an error envelope that
            # will always serialize, rather than dropping/corrupting the response line.
            $json = ([ordered]@{ id = $id; error = [ordered]@{ message = "Response serialization failed: $($_.Exception.Message)" } } | ConvertTo-Json -Compress)
        }

        Write-Output $json
    }
}
