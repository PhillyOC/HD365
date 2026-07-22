#Requires -Version 5.1
<#
.SYNOPSIS
    Launcher for HelpDesk 365 AI (HD365).
#>
[CmdletBinding()]
param(
    [string]$SettingsPath
)

$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $PSScriptRoot 'HD365.psd1'
Import-Module $modulePath -Force
Start-HD365 -SettingsPath $SettingsPath
