#Requires -Version 5.1
<#
.SYNOPSIS
    Install HD365 prerequisites and user settings scaffold.
#>
[CmdletBinding()]
param(
    [switch]$SkipGraph,
    [switch]$SkipExo,
    [switch]$SkipAiHint
)

$ErrorActionPreference = 'Stop'

Write-Host "Installing HD365 prerequisites..." -ForegroundColor Cyan

if (-not $SkipGraph) {
    if (-not (Get-Module -ListAvailable -Name Microsoft.Graph)) {
        Write-Host "Installing Microsoft.Graph (CurrentUser) - this can take several minutes..." -ForegroundColor Yellow
        Install-Module Microsoft.Graph -Scope CurrentUser -Force -AllowClobber
    }
    else {
        Write-Host "Microsoft.Graph already available." -ForegroundColor Green
    }
}

if (-not $SkipExo) {
    if (-not (Get-Module -ListAvailable -Name ExchangeOnlineManagement)) {
        Write-Host "Installing ExchangeOnlineManagement..." -ForegroundColor Yellow
        Install-Module ExchangeOnlineManagement -Scope CurrentUser -Force -AllowClobber
    }
    else {
        Write-Host "ExchangeOnlineManagement already available." -ForegroundColor Green
    }
}

$cfgDir = Join-Path $env:LOCALAPPDATA 'HD365'
$cfgPath = Join-Path $cfgDir 'settings.json'
$example = Join-Path $PSScriptRoot 'Config\settings.example.json'

if (-not (Test-Path -LiteralPath $cfgDir)) {
    New-Item -ItemType Directory -Path $cfgDir -Force | Out-Null
}

if (-not (Test-Path -LiteralPath $cfgPath)) {
    Copy-Item -LiteralPath $example -Destination $cfgPath
    Write-Host "Created settings: $cfgPath" -ForegroundColor Green
    Write-Host "Default AI provider: CopilotChat (requires M365 Copilot license)." -ForegroundColor Yellow
    Write-Host "Other providers available: AzureOpenAI, OpenAI, Anthropic, Gemini, Together, Mistral, Ollama (local)." -ForegroundColor Yellow
    Write-Host "Switch anytime with /ai in HD365." -ForegroundColor Yellow
}
else {
    Write-Host "Settings already exist: $cfgPath" -ForegroundColor Green
    Write-Host "Tip: type /ai in HD365 for an interactive provider status + switcher." -ForegroundColor DarkGray
}

$auditDir = Join-Path $cfgDir 'audit'
if (-not (Test-Path -LiteralPath $auditDir)) {
    New-Item -ItemType Directory -Path $auditDir -Force | Out-Null
}

# Optional: add this folder to PSModulePath for Import-Module HD365
$moduleParent = $PSScriptRoot
$userModulePath = [Environment]::GetEnvironmentVariable('PSModulePath', 'User')
if ($userModulePath -notlike "*$moduleParent*") {
    Write-Host ""
    Write-Host "To import by name from any session, either:" -ForegroundColor Cyan
    Write-Host "  Import-Module '$moduleParent\HD365.psd1'" -ForegroundColor White
    Write-Host "  or junction into Documents\PowerShell\Modules\HD365" -ForegroundColor White
}

if (-not $SkipAiHint) {
    Write-Host ""
    Write-Host "AI setup:" -ForegroundColor Cyan
    Write-Host "  CopilotChat (default): M365 Copilot license + Graph consent when HD365 connects" -ForegroundColor White
    Write-Host "  AzureOpenAI/OpenAI/Anthropic/Gemini/Together/Mistral: edit $cfgPath and set the matching API key env var" -ForegroundColor White
    Write-Host "  Ollama: install/run 'ollama serve' locally, no API key needed" -ForegroundColor White
    Write-Host "  In HD365 type /ai for an interactive status + switcher. allowOfflineFallback defaults to false." -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "Launch with:" -ForegroundColor Green
Write-Host "  & '$moduleParent\Start-HD365.ps1'" -ForegroundColor White
