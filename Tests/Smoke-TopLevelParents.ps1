$ErrorActionPreference = 'Stop'
$root = if ($PSScriptRoot) { Split-Path $PSScriptRoot -Parent } else { 'C:\HD365' }
Get-ChildItem (Join-Path $root 'Private\*.ps1') | ForEach-Object { . $_.FullName }

if (-not (Test-HD365IsTopLevelOfficeGroup -DisplayName 'Office - Alabama')) { throw 'AL should be top' }
if (-not (Test-HD365IsTopLevelOfficeGroup -DisplayName 'Office - New Hampshire')) { throw 'NH should be top' }
if (-not (Test-HD365IsTopLevelOfficeGroup -DisplayName 'Office - District of Columbia')) { throw 'DC should be top' }
if (Test-HD365IsTopLevelOfficeGroup -DisplayName 'Office - District of Columbia - Accounts Payable') { throw 'nested should not be top' }
if (Test-HD365IsTopLevelOfficeGroup -DisplayName 'Office - District of Columbia - Accounts Payable - HR') { throw 'deep nested should not be top' }

$groups = @(
    [pscustomobject]@{ Id = '1'; DisplayName = 'Office - Alabama' }
    [pscustomobject]@{ Id = '2'; DisplayName = 'Office - Alabama - HR' }
    [pscustomobject]@{ Id = '3'; DisplayName = 'Office - Alabama - HR - Finance' }
    [pscustomobject]@{ Id = '4'; DisplayName = 'Office - Alaska' }
)
$top = Select-HD365TopLevelOfficeParents -Groups $groups
if ($top.Count -ne 2) { throw "expected 2 top parents, got $($top.Count)" }

$msg = 'within every state group, make groups for accounts payable, hr, and finance'
$plan = New-HD365OfflineProposal -UserMessage $msg
if ($plan.discoveryScript -notmatch 'parts.Count -eq 2') { throw 'discovery missing top-level guard' }

$fake = [pscustomobject]@{
    Intent = 'CreateNestedGroups'
    ChildNames = $plan.childNames
    Parents = $groups
    ExistingGroups = @()
}
$built = Build-HD365Solution -Plan $plan -DiscoveryResult $fake -DiscoveryScript 'x'
# Only AL + AK as parents => 2 x 3 = 6
if ($built.createCount -ne 6) { throw "createCount=$($built.createCount) expected 6" }
if ($built.executionScript -match 'Office - Alabama - HR -') { throw 'must not nest under child groups' }

Write-Host 'ALL_OK'
