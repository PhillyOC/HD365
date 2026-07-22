$ErrorActionPreference = 'Stop'

$files = Get-ChildItem 'C:\HD365\Private\*.ps1', 'C:\HD365\Public\*.ps1'
foreach ($f in $files) {
    $errs = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$errs)
    if ($errs -and $errs.Count -gt 0) {
        throw ("PARSE_FAIL {0}: {1}" -f $f.Name, $errs[0].Message)
    }
}

Import-Module 'C:\HD365\HD365.psd1' -Force -ErrorAction Stop
$exported = @(Get-Command -Module HD365 | Select-Object -ExpandProperty Name | Sort-Object)
foreach ($need in @('Start-HD365', 'Get-HD365AuditLog', 'Connect-HD365')) {
    if ($exported -notcontains $need) { throw "missing export: $need" }
}

# Dot-source private surface for status (same as REPL internals)
Get-ChildItem 'C:\HD365\Private\*.ps1' | ForEach-Object { . $_.FullName }
$script:HD365Root = 'C:\HD365'
Initialize-HD365Session | Out-Null
$status = Get-HD365AiStatus
if ($status.Provider -ne 'CopilotChat') { throw "provider=$($status.Provider)" }
if (-not $status.Configured) { throw 'CopilotChat should report Configured=true' }
if ($status.AllowOfflineFallback -ne $false) { throw 'allowOfflineFallback should be false' }

Write-Host 'MODULE_LOAD_OK'
Write-Host ("Exports: " + ($exported -join ', '))
Write-Host ("Provider: " + $status.Provider)
Write-Host ("Settings: " + $status.SettingsPath)
