$ErrorActionPreference = 'Stop'
$root = if ($PSScriptRoot) { Split-Path $PSScriptRoot -Parent } else { 'C:\HD365' }

# Parse-check first, same discipline as the other smoke tests.
$errs = $null
[void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'Private\Invoke-HD365Bridge.ps1'), [ref]$null, [ref]$errs)
if ($errs -and $errs.Count -gt 0) { throw ("PARSE_FAIL Invoke-HD365Bridge.ps1: {0}" -f $errs[0].Message) }
[void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'Bridge-HD365.ps1'), [ref]$null, [ref]$errs)
if ($errs -and $errs.Count -gt 0) { throw ("PARSE_FAIL Bridge-HD365.ps1: {0}" -f $errs[0].Message) }

# Spawn the real bridge as a child process against the repo's example config, exactly like the
# Tauri Rust shell will, and drive it over stdin/stdout with newline-delimited JSON.
$settingsPath = Join-Path $root 'Config\settings.example.json'
$psi = [System.Diagnostics.ProcessStartInfo]::new()
$psi.FileName = 'powershell.exe'
$psi.Arguments = "-NoLogo -NoProfile -File `"$(Join-Path $root 'Bridge-HD365.ps1')`" -SettingsPath `"$settingsPath`""
$psi.RedirectStandardInput = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true

$proc = [System.Diagnostics.Process]::new()
$proc.StartInfo = $psi
[void]$proc.Start()

function Send-BridgeRequest {
    param([int]$Id, [string]$Method, [object]$Params)
    $req = [ordered]@{ id = $Id; method = $Method }
    if ($null -ne $Params) { $req['params'] = $Params }
    $line = ($req | ConvertTo-Json -Compress -Depth 10)
    $proc.StandardInput.WriteLine($line)
    $proc.StandardInput.Flush()

    # NOTE: StreamReader.Peek() on a redirected child process's stdout is not a reliable
    # non-blocking poll (it can block waiting on the underlying pipe). Use ReadLineAsync +
    # Task.Wait(timeout) instead, which is the robust way to bound a blocking pipe read.
    while ($true) {
        $respLine = $null
        while ($null -eq $respLine) {
            $task = $proc.StandardOutput.ReadLineAsync()
            if (-not $task.Wait(30000)) {
                throw "Timed out waiting for response to method '$Method'."
            }
            $respLine = $task.Result
            if ($null -eq $respLine) {
                throw "Bridge process closed stdout unexpectedly (exited: $($proc.HasExited), code: $(if ($proc.HasExited) { $proc.ExitCode } else { 'n/a' })). Stderr: $($proc.StandardError.ReadToEnd())"
            }
        }
        if ([string]::IsNullOrWhiteSpace($respLine)) { continue }
        return ($respLine | ConvertFrom-Json)
    }
}

try {
    $r1 = Send-BridgeRequest -Id 1 -Method 'ping'
    if (-not $r1.result.pong) { throw "ping did not return pong=true. Raw: $($r1 | ConvertTo-Json -Compress)" }
    Write-Host "BRIDGE_PING_OK bridgeVersion=$($r1.result.bridgeVersion)"

    $r2 = Send-BridgeRequest -Id 2 -Method 'session.init'
    if (-not $r2.result.sessionId) { throw "session.init did not return a sessionId. Raw: $($r2 | ConvertTo-Json -Compress)" }
    Write-Host "BRIDGE_SESSION_INIT_OK phase=$($r2.result.phase)"

    $r3 = Send-BridgeRequest -Id 3 -Method 'provider.catalog'
    $ids = @($r3.result | ForEach-Object { $_.id })
    foreach ($need in @('CopilotChat', 'AzureOpenAI', 'OpenAI', 'Anthropic', 'Gemini', 'Together', 'Mistral', 'Ollama')) {
        if ($ids -notcontains $need) { throw "provider.catalog missing '$need'. Got: $($ids -join ', ')" }
    }
    Write-Host "BRIDGE_PROVIDER_CATALOG_OK count=$($ids.Count)"

    $r4 = Send-BridgeRequest -Id 4 -Method 'run.preview'
    if ($r4.result.hasPending -ne $false) { throw "run.preview with no pending proposal should report hasPending=false. Raw: $($r4 | ConvertTo-Json -Compress)" }
    Write-Host "BRIDGE_RUN_PREVIEW_EMPTY_OK"

    $r5 = Send-BridgeRequest -Id 5 -Method 'audit.tail' -Params @{ last = 5 }
    if ($null -eq $r5.result) { throw "audit.tail returned null result. Raw: $($r5 | ConvertTo-Json -Compress)" }
    Write-Host "BRIDGE_AUDIT_TAIL_OK count=$(@($r5.result).Count)"

    $r5b = Send-BridgeRequest -Id 8 -Method 'session.prereqCheck'
    if ($null -eq $r5b.result.activeProviderId) { throw "session.prereqCheck did not return activeProviderId. Raw: $($r5b | ConvertTo-Json -Compress)" }
    Write-Host "BRIDGE_PREREQ_CHECK_OK provider=$($r5b.result.activeProviderId) graphModule=$($r5b.result.graphModuleInstalled)"

    $r6 = Send-BridgeRequest -Id 6 -Method 'no.such.method'
    if (-not $r6.error) { throw "Unknown method should return an error envelope. Raw: $($r6 | ConvertTo-Json -Compress)" }
    Write-Host "BRIDGE_UNKNOWN_METHOD_ERROR_OK"

    $r7 = Send-BridgeRequest -Id 7 -Method 'shutdown'
    if (-not $r7.result.ok) { throw "shutdown did not ack. Raw: $($r7 | ConvertTo-Json -Compress)" }

    if (-not $proc.WaitForExit(10000)) { throw "Bridge process did not exit after shutdown." }
    Write-Host "BRIDGE_SHUTDOWN_OK"

    Write-Host 'BRIDGE_SMOKE_OK'
}
finally {
    if (-not $proc.HasExited) { $proc.Kill() }
    $proc.Dispose()
}
