#Requires -Version 5.1
<#
.SYNOPSIS
  Build portable HD365 zip from the repo (version from HD365.psd1).
#>
[CmdletBinding()]
param(
    [string]$RepoRoot,
    [string]$OutDir
)

$ErrorActionPreference = 'Stop'

if (-not $RepoRoot) {
    if ($PSScriptRoot) { $RepoRoot = Split-Path $PSScriptRoot -Parent }
    else { $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path }
}
if (-not $RepoRoot) { $RepoRoot = 'C:\HD365' }

$manifestPath = Join-Path $RepoRoot 'HD365.psd1'
if (-not (Test-Path -LiteralPath $manifestPath)) {
    throw "Manifest not found: $manifestPath"
}

$manifest = Import-PowerShellDataFile -Path $manifestPath
$version = [string]$manifest.ModuleVersion
if (-not $version) { throw 'ModuleVersion missing from HD365.psd1' }

if (-not $OutDir) {
    $OutDir = Join-Path $RepoRoot 'dist'
}
if (-not (Test-Path -LiteralPath $OutDir)) {
    New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
}

$stageName = "HD365-$version"
$stage = Join-Path $OutDir $stageName
if (Test-Path -LiteralPath $stage) {
    Remove-Item -LiteralPath $stage -Recurse -Force
}
New-Item -ItemType Directory -Path $stage -Force | Out-Null

$include = @(
    'HD365.psd1'
    'HD365.psm1'
    'Start-HD365.ps1'
    'Install-HD365.ps1'
    'README.md'
    'CHANGELOG.md'
    'VERSIONING.md'
    'SYNC.md'
    'LICENSE'
    'Public'
    'Private'
    'Config'
    'Tests'
)

foreach ($item in $include) {
    $src = Join-Path $RepoRoot $item
    if (-not (Test-Path -LiteralPath $src)) { continue }
    $dest = Join-Path $stage $item
    Copy-Item -LiteralPath $src -Destination $dest -Recurse -Force
}

$zipPath = Join-Path $OutDir ("HD365-{0}.zip" -f $version)
if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory($stage, $zipPath)

Write-Host "Built: $zipPath" -ForegroundColor Green
Write-Output $zipPath
