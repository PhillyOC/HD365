#Requires -Version 5.1
<#
.SYNOPSIS
    JSON-RPC stdio bridge launcher for the HD365 desktop app (Tauri).

.DESCRIPTION
    Spawned as a long-lived child process by the desktop app's Rust shell. Speaks
    newline-delimited JSON over stdin/stdout - never intended to be run interactively by a
    human. For the console experience, use Start-HD365.ps1 instead.
#>
[CmdletBinding()]
param(
    [string]$SettingsPath
)

$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $PSScriptRoot 'HD365.psd1'
Import-Module $modulePath -Force
Start-HD365Bridge -SettingsPath $SettingsPath
