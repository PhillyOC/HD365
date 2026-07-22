$ErrorActionPreference = 'Stop'
Import-Module 'C:\HD365\HD365.psd1' -Force
Write-Host ("Exported: " + ((Get-Command -Module HD365).Name -join ', '))

$script:HD365Root = 'C:\HD365'
Get-ChildItem 'C:\HD365\Private\*.ps1' | ForEach-Object { . $_.FullName }

# One-liner helper
$ol = ConvertTo-HD365OneLiner -ScriptText "Get-MgUser`n# comment`nGet-MgGroup"
if ($ol -match "`n") { throw 'one-liner still has newlines' }

# Offline plan: create group + add all users
$plan = New-HD365OfflineProposal -UserMessage 'create a group called "All Users" and add all users to it'
if ($plan.solutionKind -ne 'CreateGroupAddAllUsers') { throw "unexpected kind: $($plan.solutionKind)" }
if ($plan.discoveryScript -match "`n") { throw 'discovery has newlines' }
if ($plan.discoveryScript -match 'contoso') { throw 'discovery has placeholders' }
Write-Host "Discovery: $($plan.discoveryScript)"

# Fake discovery result -> solution must bake real GUIDs
$fake = [pscustomobject]@{
    Intent         = 'CreateGroupAddAllUsers'
    GroupName      = 'All Users'
    MailNickname   = 'AllUsers'
    ExistingGroups = @()
    Users          = @(
        [pscustomobject]@{ Id = '11111111-1111-1111-1111-111111111111'; DisplayName = 'A'; UserPrincipalName = 'a@test.com' }
        [pscustomobject]@{ Id = '22222222-2222-2222-2222-222222222222'; DisplayName = 'B'; UserPrincipalName = 'b@test.com' }
    )
}
$built = Build-HD365Solution -Plan $plan -DiscoveryResult $fake -DiscoveryScript $plan.discoveryScript
if ($built.executionScript -notmatch '11111111-1111-1111-1111-111111111111') { throw 'user id not baked in' }
if ($built.executionScript -match 'contoso') { throw 'solution has placeholders' }
if ($built.executionScript -match "`n") { throw 'solution has newlines' }
Write-Host "Solution: $($built.executionScript)"

# Existing group path
$fake2 = [pscustomobject]@{
    Intent         = 'CreateGroupAddAllUsers'
    GroupName      = 'All Users'
    MailNickname   = 'AllUsers'
    ExistingGroups = @([pscustomobject]@{ Id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'; DisplayName = 'All Users' })
    Users          = $fake.Users
}
$built2 = Build-HD365Solution -Plan $plan -DiscoveryResult $fake2 -DiscoveryScript $plan.discoveryScript
if ($built2.executionScript -notmatch 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa') { throw 'existing group id missing' }
if ($built2.executionScript -match 'New-MgGroup\s+-DisplayName') { throw 'should not create when exists' }

Write-Host 'ALL_OK'
