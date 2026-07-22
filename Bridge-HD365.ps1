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

# $PSScriptRoot is normally reliable, but Windows PowerShell 5.1 fails to populate it (leaves it
# empty) when this script is invoked via `-File` against an extended-length/verbatim path
# (`\\?\C:\...`) - which is exactly what Tauri's resource path resolution can hand back on
# Windows for the packaged desktop app. Fall back to deriving the script's own directory from
# $MyInvocation instead of trusting $PSScriptRoot alone, so the bridge never dies on a null
# Join-Path before it even gets a chance to report anything useful.
$scriptRoot = $PSScriptRoot
if ([string]::IsNullOrEmpty($scriptRoot)) {
    $scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
}
if ([string]::IsNullOrEmpty($scriptRoot)) {
    throw "Bridge-HD365.ps1 could not determine its own directory (both `$PSScriptRoot and `$MyInvocation.MyCommand.Path were empty)."
}

$modulePath = Join-Path $scriptRoot 'HD365.psd1'
Import-Module $modulePath -Force
Start-HD365Bridge -SettingsPath $SettingsPath
