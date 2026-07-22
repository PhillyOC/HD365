$ErrorActionPreference = 'Stop'
Get-ChildItem 'C:\HD365\Private\*.ps1' | ForEach-Object { . $_.FullName }

$states = @(Get-HD365UsStateOfficeGroups)
if ($states[0] -match '^Office') { throw 'state groups must not use Office - prefix' }
if ($states -notcontains 'Ohio') { throw 'missing Ohio' }
if ($states -notcontains 'Kansas') { throw 'missing Kansas' }

if (-not (Test-HD365IsTopLevelOfficeGroup -DisplayName 'Ohio')) { throw 'Ohio should be top' }
if (-not (Test-HD365IsTopLevelOfficeGroup -DisplayName 'New Hampshire')) { throw 'NH should be top' }
if (Test-HD365IsTopLevelOfficeGroup -DisplayName 'Ohio - HR') { throw 'Ohio - HR should not be top' }
if (Test-HD365IsTopLevelOfficeGroup -DisplayName 'Office - Ohio') { throw 'legacy Office - Ohio should not count as top now' }

if ((Get-HD365ParentStateAbbreviation -ParentDisplayName 'Ohio') -ne 'OH') { throw 'abbr OH' }
if ((Get-HD365ParentStateAbbreviation -ParentDisplayName 'Kansas') -ne 'KS') { throw 'abbr KS' }

$plan = New-HD365OfflineProposal -UserMessage 'create a group for every state in the US'
if ($plan.groupNames -match 'Office -') { throw 'create-every-state still using Office -' }
if ($plan.groupNames -notcontains 'Ohio') { throw 'Ohio missing from plan' }

$nestedPlan = New-HD365OfflineProposal -UserMessage 'within every state group, make groups for hr, finance, and operations'
if ($nestedPlan.discoveryScript -match "Office -") { throw 'nested discovery still references Office - prefix for parents' }

$groups = @(
    [pscustomobject]@{ Id = '1'; DisplayName = 'Ohio' }
    [pscustomobject]@{ Id = '2'; DisplayName = 'Ohio - HR' }
    [pscustomobject]@{ Id = '3'; DisplayName = 'Kansas' }
    [pscustomobject]@{ Id = '4'; DisplayName = 'Office - Alaska' }
)
$top = Select-HD365TopLevelOfficeParents -Groups $groups
if ($top.Count -ne 2) { throw "expected Ohio+Kansas, got $($top.Count)" }

$built = Build-HD365Solution -Plan $nestedPlan -DiscoveryResult ([pscustomobject]@{
        Parents = $groups
        ChildNames = $nestedPlan.childNames
        ExistingGroups = @([pscustomobject]@{ DisplayName = 'Ohio - HR'; Id = 'x' })
    }) -DiscoveryScript 'x'

if ($built.createCount -ne 5) { throw "expected 5 (2 states x 3 depts - 1 existing), got $($built.createCount)" }
if ($built.executionScript -notmatch "Name='Ohio'") { throw 'compact script missing Ohio' }
if ($built.executionScript -match 'Office -') { throw 'compact script still has Office -' }

Write-Host 'ALL_OK'
