#Requires -Version 5.1
<#
.SYNOPSIS
  Build the HD365 desktop app (Tauri + React) installer(s).

.DESCRIPTION
  1. Reads the canonical version from HD365.psd1 and syncs it into app/package.json,
     app/src-tauri/Cargo.toml, and app/src-tauri/tauri.conf.json so the installer, exe metadata,
     and About screen all agree with the PowerShell module version.
  2. Stages a fresh copy of the PowerShell engine (HD365.psd1/psm1, Bridge-HD365.ps1, Private/,
     Public/, Config/) into app/src-tauri/engine/ - the resource directory tauri.conf.json's
     bundle.resources packages into the installer (see resolve_bridge_script in lib.rs, which
     resolves the live repo checkout in dev builds and this bundled engine/ dir in release
     builds).
  3. Runs `npm install` (only if node_modules is missing) and `npm run tauri build`.
  4. Copies the resulting NSIS/MSI installer(s) out of
     app/src-tauri/target/release/bundle/... into the repo's dist/ folder, alongside the
     console package's HD365-Setup-<version>.exe from Build-HD365Package.ps1, as
     HD365-Desktop-Setup-<version>.exe / .msi.

.PARAMETER RepoRoot
  Defaults to the parent of this script's directory (i.e. the repo root).

.PARAMETER SkipInstall
  Skip `npm install` even if node_modules is missing (assumes it's already been run).
#>
[CmdletBinding()]
param(
    [string]$RepoRoot,
    [switch]$SkipInstall
)

$ErrorActionPreference = 'Stop'

if (-not $RepoRoot) {
    if ($PSScriptRoot) { $RepoRoot = Split-Path $PSScriptRoot -Parent }
    else { $RepoRoot = 'C:\HD365' }
}

$appDir = Join-Path $RepoRoot 'app'
$tauriDir = Join-Path $appDir 'src-tauri'
$engineDir = Join-Path $tauriDir 'engine'

# ---------------------------------------------------------------------------
# 1. Version sync (single source of truth: HD365.psd1)
# ---------------------------------------------------------------------------
$manifestPath = Join-Path $RepoRoot 'HD365.psd1'
if (-not (Test-Path -LiteralPath $manifestPath)) { throw "Manifest not found: $manifestPath" }
$manifest = Import-PowerShellDataFile -Path $manifestPath
$version = [string]$manifest.ModuleVersion
if (-not $version) { throw 'ModuleVersion missing from HD365.psd1' }
Write-Host "HD365 version: $version" -ForegroundColor Cyan

# NOTE: deliberately regex-patch the "version" field in place rather than round-tripping through
# ConvertFrom-Json/ConvertTo-Json - PowerShell's JSON serializer reformats/reorders/re-escapes
# the whole file (and, on Windows PowerShell 5.1, `-Encoding utf8` adds a BOM that breaks
# downstream Node/JSON tooling like vite's PostCSS config loader). A targeted regex replace
# keeps every other byte of these hand-authored files untouched.
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
function Set-FileNoBom {
    param([string]$Path, [string]$Content)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

$packageJsonPath = Join-Path $appDir 'package.json'
$packageJsonRaw = Get-Content -LiteralPath $packageJsonPath -Raw
$packageJsonRaw = $packageJsonRaw -replace '(?m)^(\s*"version":\s*)"[^"]*"', "`${1}`"$version`""
Set-FileNoBom -Path $packageJsonPath -Content $packageJsonRaw

$cargoTomlPath = Join-Path $tauriDir 'Cargo.toml'
$cargoTomlRaw = Get-Content -LiteralPath $cargoTomlPath -Raw
$cargoTomlRaw = $cargoTomlRaw -replace '(?m)^version = "[^"]*"', "version = `"$version`""
Set-FileNoBom -Path $cargoTomlPath -Content $cargoTomlRaw

$tauriConfPath = Join-Path $tauriDir 'tauri.conf.json'
$tauriConfRaw = Get-Content -LiteralPath $tauriConfPath -Raw
$tauriConfRaw = $tauriConfRaw -replace '(?m)^(\s*"version":\s*)"[^"]*"', "`${1}`"$version`""
Set-FileNoBom -Path $tauriConfPath -Content $tauriConfRaw

Write-Host "Synced version $version into app/package.json, Cargo.toml, tauri.conf.json" -ForegroundColor DarkGray

# ---------------------------------------------------------------------------
# 2. Stage the PowerShell engine as a bundle resource
# ---------------------------------------------------------------------------
if (Test-Path -LiteralPath $engineDir) {
    Remove-Item -LiteralPath $engineDir -Recurse -Force
}
New-Item -ItemType Directory -Path $engineDir -Force | Out-Null

$engineItems = @('HD365.psd1', 'HD365.psm1', 'Bridge-HD365.ps1', 'Private', 'Public', 'Config')
foreach ($item in $engineItems) {
    $src = Join-Path $RepoRoot $item
    if (-not (Test-Path -LiteralPath $src)) { throw "Engine source item not found: $src" }
    Copy-Item -LiteralPath $src -Destination (Join-Path $engineDir $item) -Recurse -Force
}
# Restore the committed .gitkeep placeholder (see app/src-tauri/.gitignore) so `git status`
# never reports it as deleted - it must always exist for tauri-build's resource path check to
# pass on a clean checkout, even before this script has ever staged real engine content.
New-Item -ItemType File -Path (Join-Path $engineDir '.gitkeep') -Force | Out-Null
Write-Host "Staged engine/ with: $($engineItems -join ', ')" -ForegroundColor DarkGray

# ---------------------------------------------------------------------------
# 3. npm install (if needed) + tauri build
# ---------------------------------------------------------------------------
Push-Location $appDir
try {
    $nodeModules = Join-Path $appDir 'node_modules'
    if (-not $SkipInstall -and -not (Test-Path -LiteralPath $nodeModules)) {
        Write-Host 'Running npm install...' -ForegroundColor Cyan
        npm install
        if ($LASTEXITCODE -ne 0) { throw "npm install failed with exit code $LASTEXITCODE" }
    }

    Write-Host 'Running npm run tauri build...' -ForegroundColor Cyan
    npm run tauri build
    if ($LASTEXITCODE -ne 0) { throw "npm run tauri build failed with exit code $LASTEXITCODE" }
}
finally {
    Pop-Location
}

# ---------------------------------------------------------------------------
# 4. Collect installer artifacts into dist/
# ---------------------------------------------------------------------------
$outDir = Join-Path $RepoRoot 'dist'
if (-not (Test-Path -LiteralPath $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }

# Ask cargo for the *effective* target directory rather than assuming the default
# app/src-tauri/target - it can be redirected (CARGO_TARGET_DIR env var, .cargo/config.toml,
# sandboxed dev environments, etc.) and hardcoding it silently produces "no artifact found".
$cargoManifest = Join-Path $tauriDir 'Cargo.toml'
$metadataJson = cargo metadata --no-deps --format-version 1 --manifest-path $cargoManifest 2>$null
if ($LASTEXITCODE -ne 0 -or -not $metadataJson) { throw 'cargo metadata failed while locating the build output directory.' }
$targetDirectory = ($metadataJson | ConvertFrom-Json).target_directory
$bundleDir = Join-Path $targetDirectory 'release\bundle'
Write-Host "Bundle output dir: $bundleDir" -ForegroundColor DarkGray

$produced = @()

$nsisExe = Get-ChildItem -Path (Join-Path $bundleDir 'nsis') -Filter '*.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
if ($nsisExe) {
    $dest = Join-Path $outDir "HD365-Desktop-Setup-$version.exe"
    Copy-Item -LiteralPath $nsisExe.FullName -Destination $dest -Force
    $produced += $dest
}

$msi = Get-ChildItem -Path (Join-Path $bundleDir 'msi') -Filter '*.msi' -ErrorAction SilentlyContinue | Select-Object -First 1
if ($msi) {
    $dest = Join-Path $outDir "HD365-Desktop-$version.msi"
    Copy-Item -LiteralPath $msi.FullName -Destination $dest -Force
    $produced += $dest
}

if ($produced.Count -eq 0) {
    throw "tauri build finished but no NSIS/MSI artifact was found under $bundleDir"
}

foreach ($p in $produced) { Write-Host "Built: $p" -ForegroundColor Green }
Write-Output $produced
