#Requires -Version 5.1
<#
.SYNOPSIS
  Export a Copilot-only HD365 tree as a zip for carry to work Copilot Git.
  Strips OpenAI/Azure OpenAI provider paths and API-key setup.
#>
[CmdletBinding()]
param(
    [string]$RepoRoot,
    [string]$OutDir
)

$ErrorActionPreference = 'Stop'

if (-not $RepoRoot) {
    if ($PSScriptRoot) { $RepoRoot = Split-Path $PSScriptRoot -Parent }
    else { $RepoRoot = 'C:\HD365' }
}

$manifest = Import-PowerShellDataFile -Path (Join-Path $RepoRoot 'HD365.psd1')
$version = [string]$manifest.ModuleVersion
$stamp = Get-Date -Format 'yyyyMMdd'

if (-not $OutDir) { $OutDir = Join-Path $RepoRoot 'dist' }
if (-not (Test-Path -LiteralPath $OutDir)) {
    New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
}

$stageName = "HD365-work-$version-$stamp"
$stage = Join-Path $OutDir $stageName
if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
New-Item -ItemType Directory -Path $stage -Force | Out-Null

$include = @(
    'HD365.psd1', 'HD365.psm1', 'Start-HD365.ps1', 'Install-HD365.ps1',
    'README.md', 'CHANGELOG.md', 'VERSIONING.md', 'SYNC.md', 'LICENSE',
    'Public', 'Private', 'Config', 'Tests'
)
foreach ($item in $include) {
    $src = Join-Path $RepoRoot $item
    if (-not (Test-Path -LiteralPath $src)) { continue }
    Copy-Item -LiteralPath $src -Destination (Join-Path $stage $item) -Recurse -Force
}

# --- Copilot-only trim: settings ---
$settingsPath = Join-Path $stage 'Config\settings.example.json'
$settings = Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
$settings.ai.provider = 'CopilotChat'
$settings.ai.allowOfflineFallback = $false
# Remove consumer API fields if present
foreach ($prop in @('endpoint', 'deployment', 'apiVersion', 'apiKeyEnvVar', 'model', 'temperature', 'maxTokens')) {
    if ($settings.ai.PSObject.Properties[$prop]) {
        $settings.ai.PSObject.Properties.Remove($prop)
    }
}
($settings | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $settingsPath -Encoding UTF8

# --- Copilot-only trim: Invoke-HD365Ai.ps1 ---
$aiPath = Join-Path $stage 'Private\Invoke-HD365Ai.ps1'
$aiText = Get-Content -LiteralPath $aiPath -Raw -Encoding UTF8

# Force provider to CopilotChat only in Test-HD365AiConfigured / Invoke-HD365Ai switch
$workAiHeader = @'
# WORK EXPORT: CopilotChat only. Non-Copilot providers removed by Export-HD365Work.ps1.

'@
# Replace Get-HD365AiApiKey body to throw clearly if somehow called
$aiText = $aiText -replace '(?s)function Get-HD365AiApiKey \{.*?^\}', @'
function Get-HD365AiApiKey {
    [CmdletBinding()]
    param()
    throw "This HD365 build is CopilotChat-only. OpenAI/Azure OpenAI keys are not supported."
}
'@

# Collapse Test-HD365AiConfigured to Copilot-only
$aiText = $aiText -replace '(?s)function Test-HD365AiConfigured \{.*?^\}', @'
function Test-HD365AiConfigured {
    [CmdletBinding()]
    param()
    $provider = [string]$script:HD365Config.ai.provider
    if (-not $provider) { $provider = 'CopilotChat' }
    return ($provider -eq 'CopilotChat')
}
'@

# Collapse Invoke-HD365Ai switch to CopilotChat only (remove AzureOpenAI/OpenAI arms)
$aiText = $aiText -replace "(?s)switch \(\`$provider\) \{.*?default \{[^}]+\}\s*\}", @'
switch ($provider) {
        'CopilotChat' {
            $preamble = @"
$system

IMPORTANT: Reply with ONE JSON object only that matches the schema in the system instructions. No markdown fences. No explanation outside JSON.
"@
            $content = Invoke-HD365CopilotChat -Message $userPayload -SystemPreamble $preamble

            try {
                return (ConvertFrom-HD365AiJson -Content $content)
            }
            catch {
                if ($config.ai.copilot.requireJsonRetry -eq $false) { throw }
                Write-Host "Copilot JSON parse failed; retrying with stricter instruction..." -ForegroundColor Yellow
                $retryMsg = @"
Your previous reply was not valid JSON for HD365. Return ONLY a valid JSON object for this request (no markdown, no prose):

$userPayload
"@
                $content = Invoke-HD365CopilotChat -Message $retryMsg -SystemPreamble $preamble
                return (ConvertFrom-HD365AiJson -Content $content)
            }
        }
        default {
            throw "This HD365 build is CopilotChat-only. Unsupported provider '$provider'."
        }
    }
'@

Set-Content -LiteralPath $aiPath -Value ($workAiHeader + $aiText) -Encoding UTF8

# --- Copilot-only README ---
$workReadme = @'
# HD365 (enterprise / Copilot Chat)

Graph-first PowerShell assistant for Microsoft 365 helpdesk work.
This build uses **Microsoft 365 Copilot Chat API only** (Graph beta).

## Requirements

- Work/school account with a **Microsoft 365 Copilot add-on** license
- Microsoft Graph PowerShell SDK
- PowerShell 5.1+

## Quick start

```powershell
.\Install-HD365.ps1
.\Start-HD365.ps1
```

Then: `/auth read` -> `/ai` (expect `CopilotApi = OK`) -> natural-language requests.

Writes require typing `EXECUTE`. Audit logs: `%LOCALAPPDATA%\HD365\audit\`.

## Notes

- Desktop/consumer Copilot is not this API.
- Do not configure OpenAI/Azure OpenAI in this build.
- See SYNC.md for the ethical firewall between lines.
'@
Set-Content -LiteralPath (Join-Path $stage 'README.md') -Value $workReadme -Encoding UTF8

# Soften Install AI hints
$installPath = Join-Path $stage 'Install-HD365.ps1'
if (Test-Path -LiteralPath $installPath) {
    $inst = Get-Content -LiteralPath $installPath -Raw -Encoding UTF8
    $inst = $inst -replace 'AzureOpenAI/OpenAI[^\r\n]*', 'This build is CopilotChat-only (M365 Copilot license required).'
    $inst = $inst -replace 'Or set ai\.provider to AzureOpenAI/OpenAI when Compliance allows\.', 'CopilotChat only in this build.'
    Set-Content -LiteralPath $installPath -Value $inst -Encoding UTF8
}

# Soften Show-HD365AiSetupHelp OpenAI section
$copilotPath = Join-Path $stage 'Private\Invoke-HD365Copilot.ps1'
if (Test-Path -LiteralPath $copilotPath) {
    $c = Get-Content -LiteralPath $copilotPath -Raw -Encoding UTF8
    $c = $c -replace "(?s)Write-Host 'OpenAI / Azure OpenAI \(if Compliance allows\):'.*?Write-Host ''", @"
Write-Host 'This build is CopilotChat-only.' -ForegroundColor White
    Write-Host '  OpenAI / Azure OpenAI are not available here.' -ForegroundColor Gray
    Write-Host ''
"@
    Set-Content -LiteralPath $copilotPath -Value $c -Encoding UTF8
}

$zipPath = Join-Path $OutDir ("HD365-work-{0}-{1}.zip" -f $version, $stamp)
if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory($stage, $zipPath)

Write-Host "Work export: $zipPath" -ForegroundColor Green
Write-Host "Carry this zip to the work laptop; push to Copilot Git from there." -ForegroundColor Cyan
Write-Output $zipPath
