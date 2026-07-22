$ErrorActionPreference = 'Stop'
Get-ChildItem 'C:\HD365\Private\*.ps1' | ForEach-Object { . $_.FullName }

$msg = 'within every state group, make groups for accounts payable, hr, accounts receivable, management, operations, information technology, and finance'

if (-not (Test-HD365IsNestedGroupsRequest -UserMessage $msg)) { throw 'nested not detected' }
if (Test-HD365IsCreateManyGroupsRequest -UserMessage $msg) { throw 'should not be flat many-groups' }

$plan = New-HD365OfflineProposal -UserMessage $msg
if ($plan.solutionKind -ne 'CreateNestedGroups') { throw "kind=$($plan.solutionKind)" }
if ($plan.childNames.Count -ne 7) { throw "children=$($plan.childNames.Count): $($plan.childNames -join ',')" }
if ($plan.childNames -notcontains 'Accounts Payable') { throw 'AP missing' }
if ($plan.childNames -notcontains 'HR') { throw 'HR missing' }

$parents = @(
    [pscustomobject]@{ Id = '11111111-1111-1111-1111-111111111111'; DisplayName = 'Office - Alabama'; MailNickname = 'OfficeAlabama' }
    [pscustomobject]@{ Id = '22222222-2222-2222-2222-222222222222'; DisplayName = 'Office - Alaska'; MailNickname = 'OfficeAlaska' }
)
$fake = [pscustomobject]@{
    Intent         = 'CreateNestedGroups'
    ParentFilter   = 'Office - *'
    ChildNames     = $plan.childNames
    Parents        = $parents
    ExistingGroups = @(
        [pscustomobject]@{ Id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'; DisplayName = 'Office - Alabama - HR'; MailNickname = 'AL-HR' }
    )
}

$built = Build-HD365Solution -Plan $plan -DiscoveryResult $fake -DiscoveryScript $plan.discoveryScript
# 2 parents x 7 children - 1 existing = 13
if ($built.createCount -ne 13) { throw "createCount=$($built.createCount)" }
if ($built.executionScript -notmatch 'Office - Alabama - Accounts Payable') { throw 'missing nested AP name' }
if ($built.executionScript -match 'Office - Alabama - HR') { throw 'should skip existing AL-HR' }
if ($built.executionScript -notmatch 'New-MgGroupMember') { throw 'missing nest membership' }
if ($built.executionScript -match "`n") { throw 'newlines found' }

# /r alias pattern
if ('/r' -notmatch '^/(run|r)$') { throw '/r alias broken' }

Write-Host "Children: $($plan.childNames -join ', ')"
Write-Host "CreateCount: $($built.createCount)"
Write-Host 'ALL_OK'
