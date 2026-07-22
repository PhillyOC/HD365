#Requires -Version 5.1

Set-StrictMode -Version Latest

$script:HD365Root = $PSScriptRoot
$script:HD365Config = $null
$script:HD365ConfigPath = $null
$script:HD365Session = $null
$script:HD365ScopeCatalog = $null

$private = Get-ChildItem -Path (Join-Path $PSScriptRoot 'Private') -Filter '*.ps1' -ErrorAction SilentlyContinue
$public  = Get-ChildItem -Path (Join-Path $PSScriptRoot 'Public')  -Filter '*.ps1' -ErrorAction SilentlyContinue

foreach ($file in @($private + $public)) {
    . $file.FullName
}

Export-ModuleMember -Function @(
    'Start-HD365',
    'Get-HD365AuditLog',
    'Connect-HD365',
    'Start-HD365Bridge'
)
