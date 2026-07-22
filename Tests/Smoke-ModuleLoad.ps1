$ErrorActionPreference = 'Stop'
$root = if ($PSScriptRoot) { Split-Path $PSScriptRoot -Parent } else { 'C:\HD365' }

$files = Get-ChildItem (Join-Path $root 'Private\*.ps1'), (Join-Path $root 'Public\*.ps1')
foreach ($f in $files) {
    $errs = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$errs)
    if ($errs -and $errs.Count -gt 0) {
        throw ("PARSE_FAIL {0}: {1}" -f $f.Name, $errs[0].Message)
    }
}

Import-Module (Join-Path $root 'HD365.psd1') -Force -ErrorAction Stop
$exported = @(Get-Command -Module HD365 | Select-Object -ExpandProperty Name | Sort-Object)
foreach ($need in @('Start-HD365', 'Get-HD365AuditLog', 'Connect-HD365')) {
    if ($exported -notcontains $need) { throw "missing export: $need" }
}

# Dot-source private surface for status (same as REPL internals)
Get-ChildItem (Join-Path $root 'Private\*.ps1') | ForEach-Object { . $_.FullName }
$script:HD365Root = $root
Initialize-HD365Session | Out-Null
$status = Get-HD365AiStatus
if ($status.Provider -ne 'CopilotChat') { throw "provider=$($status.Provider)" }
if (-not $status.Configured) { throw 'CopilotChat should report Configured=true' }
if ($status.AllowOfflineFallback -ne $false) { throw 'allowOfflineFallback should be false' }

Write-Host 'MODULE_LOAD_OK'
Write-Host ("Exports: " + ($exported -join ', '))
Write-Host ("Provider: " + $status.Provider)
Write-Host ("Settings: " + $status.SettingsPath)
