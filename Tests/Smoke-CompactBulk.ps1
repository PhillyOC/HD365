$ErrorActionPreference = 'Stop'
$root = if ($PSScriptRoot) { Split-Path $PSScriptRoot -Parent } else { 'C:\HD365' }
Get-ChildItem (Join-Path $root 'Private\*.ps1') | ForEach-Object { . $_.FullName }

$msg = 'within every state group, make groups for accounts payable, hr, accounts receivable, management, operations, information technology, and finance'
$plan = New-HD365OfflineProposal -UserMessage $msg

$parents = 1..51 | ForEach-Object {
    [pscustomobject]@{
        Id = [guid]::NewGuid().ToString()
        DisplayName = "Office - State$_"
        MailNickname = "OfficeState$_"
    }
}
# Use real state names for first 2
$parents[0].DisplayName = 'Office - Alabama'
$parents[1].DisplayName = 'Office - Alaska'

$fake = [pscustomobject]@{
    Intent = 'CreateNestedGroups'
    ParentFilter = 'Office - *'
    ChildNames = $plan.childNames
    Parents = $parents
    ExistingGroups = @()
}

$built = Build-HD365Solution -Plan $plan -DiscoveryResult $fake -DiscoveryScript 'x'
if ($built.bulkKind -ne 'CreateNestedGroups') { throw 'missing bulkKind' }
if (-not $built.jobData) { throw 'missing jobData' }
if ($built.jobData.Parents.Count -ne 51) { throw 'parent count' }
if ($built.jobData.Departments.Count -ne 7) { throw 'dept count' }

$len = $built.executionScript.Length
Write-Host "Compact script length: $len"
if ($len -gt 25000) { throw "script still too large: $len" }
if ($built.executionScript -notmatch '\$parents=@\(') { throw 'missing parents array' }
if ($built.executionScript -match 'Office - Alabama - Accounts Payable') { throw 'should not expand every nested display name' }

$path = Save-HD365ScriptArtifact -ScriptText $built.executionScript -Prefix 'test'
if (-not (Test-Path $path)) { throw 'artifact missing' }
Write-Host "Artifact: $path"
Write-Host 'ALL_OK'
