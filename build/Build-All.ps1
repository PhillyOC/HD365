#Requires -Version 5.1
<#
.SYNOPSIS
  Local helper: build zip; compile .exe if Inno Setup is installed.
#>
[CmdletBinding()]
param(
    [string]$RepoRoot,
    [switch]$SkipExe
)

$ErrorActionPreference = 'Stop'
if (-not $RepoRoot) {
    if ($PSScriptRoot) { $RepoRoot = Split-Path $PSScriptRoot -Parent }
    else { $RepoRoot = 'C:\HD365' }
}
$zip = & (Join-Path $PSScriptRoot 'Build-HD365Package.ps1') -RepoRoot $RepoRoot

$manifest = Import-PowerShellDataFile -Path (Join-Path $RepoRoot 'HD365.psd1')
$version = [string]$manifest.ModuleVersion

if ($SkipExe) {
    Write-Host "SkipExe set; zip only: $zip"
    return
}

$isccCandidates = @(
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
    "${env:ProgramFiles}\Inno Setup 6\ISCC.exe"
)
$iscc = $isccCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $iscc) {
    Write-Host "Inno Setup not found locally. Zip is ready: $zip" -ForegroundColor Yellow
    Write-Host "CI release workflow builds the .exe on tag push. Or: choco install innosetup" -ForegroundColor DarkGray
    return
}

& $iscc "/DMyAppVersion=$version" (Join-Path $PSScriptRoot 'HD365.iss')
$exe = Join-Path $RepoRoot ("dist\HD365-Setup-{0}.exe" -f $version)
if (Test-Path -LiteralPath $exe) {
    Write-Host "Built: $exe" -ForegroundColor Green
}
else {
    throw "ISCC finished but exe not found: $exe"
}
