$ErrorActionPreference = 'Stop'
Get-ChildItem 'C:\HD365\Private\*.ps1' | ForEach-Object { . $_.FullName }

$cases = @(
    'Create groups for HR, finance, accounting, executive, Information technology, and operations'
    'Create me an entire directory complete with groups for all the major departments in a company with office in every state'
    'Create me groups for HR, finance, accounting, executive, Information technology, and operations'
)

foreach ($c in $cases) {
    if (-not (Test-HD365IsCreateManyGroupsRequest -UserMessage $c)) { throw "Not detected as multi-create: $c" }
    $plan = New-HD365OfflineProposal -UserMessage $c
    if ($plan.solutionKind -ne 'CreateManyGroups') { throw "Bad kind $($plan.solutionKind) for: $c" }
    Write-Host ("---`n$c")
    Write-Host ("Count=$($plan.groupNames.Count) States=$($plan.includeStates) Defaults=$($plan.usedDefaults)")
    Write-Host (($plan.groupNames | Select-Object -First 8) -join ', ')
    if ($plan.groupNames -match 'major departments') { throw 'junk name slipped in' }
}

$plan = New-HD365OfflineProposal -UserMessage 'Create groups for HR, finance, accounting, executive, Information technology, and operations'
if ($plan.groupNames.Count -ne 6) { throw "expected 6 names, got $($plan.groupNames.Count)" }

$big = New-HD365OfflineProposal -UserMessage 'Create me an entire directory complete with groups for all the major departments in a company with office in every state'
if (-not $big.includeStates) { throw 'states not included' }
if ($big.groupNames.Count -lt 60) { throw "expected depts+states, got $($big.groupNames.Count)" }

$fake = [pscustomobject]@{
    Intent         = 'CreateManyGroups'
    Requested      = @('HR', 'Finance', 'Accounting')
    ExistingGroups = @([pscustomobject]@{ DisplayName = 'HR'; Id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'; MailNickname = 'HR' })
}
$built = Build-HD365Solution -Plan $plan -DiscoveryResult $fake -DiscoveryScript $plan.discoveryScript
if ($built.executionScript -notmatch "DisplayName='Finance'") { throw 'missing Finance create' }
if ($built.executionScript -match "DisplayName='HR'") { throw 'should skip existing HR' }
if ($built.executionScript -match "`n") { throw 'newlines in solution' }

Write-Host 'ALL_OK'
