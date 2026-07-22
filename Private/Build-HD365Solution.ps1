function Build-HD365Solution {
    <#
    .SYNOPSIS
      Build a fully-formed one-liner solution script from discovery results + plan.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Plan,

        [Parameter(Mandatory)]
        [AllowNull()]
        $DiscoveryResult,

        [string]$DiscoveryScript
    )

    $kind = [string]$Plan.solutionKind
    if (-not $kind) { $kind = 'PassthroughRead' }

    switch ($kind) {
        'CreateGroupAddAllUsers' {
            $groupName = [string]$Plan.groupName
            $nick = [string]$Plan.mailNickname
            if (-not $groupName -and $DiscoveryResult -and $DiscoveryResult.GroupName) {
                $groupName = [string]$DiscoveryResult.GroupName
            }
            if (-not $nick -and $DiscoveryResult -and $DiscoveryResult.MailNickname) {
                $nick = [string]$DiscoveryResult.MailNickname
            }
            if (-not $groupName) { $groupName = 'All Users' }
            if (-not $nick) { $nick = ($groupName -replace '[^A-Za-z0-9]', ''); if (-not $nick) { $nick = 'AllUsers' } }

            $gnEsc = $groupName -replace "'", "''"
            $nickEsc = $nick -replace "'", "''"

            $users = @()
            if ($DiscoveryResult -and $DiscoveryResult.Users) {
                $users = @($DiscoveryResult.Users)
            }

            $ids = @(
                $users |
                    Where-Object { $_.Id } |
                    Select-Object -ExpandProperty Id -Unique
            )

            if ($ids.Count -eq 0) {
                throw "Discovery found 0 users. Cannot build add-all-users solution."
            }

            $idList = Format-HD365GuidList -Ids $ids

            $existingId = $null
            $existingName = $null
            if ($DiscoveryResult -and $DiscoveryResult.PSObject.Properties['ExistingGroups']) {
                foreach ($g in @($DiscoveryResult.ExistingGroups)) {
                    if ($null -ne $g -and $g.Id) {
                        $existingId = [string]$g.Id
                        $existingName = [string]$g.DisplayName
                        break
                    }
                }
            }

            if ($existingId) {
                $scriptText = "`$gid='$existingId'; @($idList) | ForEach-Object { New-MgGroupMember -GroupId `$gid -DirectoryObjectId `$_ -ErrorAction SilentlyContinue }; Get-MgGroup -GroupId `$gid | Select-Object DisplayName,Id; Write-Host ('Added/attempted membership for ' + @($idList).Count + ' users to existing group')"
                $summary = "Group '$groupName' already exists ($existingId). Solution adds $($ids.Count) discovered user(s)."
            }
            else {
                $scriptText = "`$g=New-MgGroup -DisplayName '$gnEsc' -MailEnabled:`$false -MailNickname '$nickEsc' -SecurityEnabled:`$true; @($idList) | ForEach-Object { New-MgGroupMember -GroupId `$g.Id -DirectoryObjectId `$_ }; `$g | Select-Object DisplayName,Id; Write-Host ('Created group and added ' + @($idList).Count + ' users')"
                $summary = "Create group '$groupName' and add $($ids.Count) discovered user GUID(s)."
            }

            return [pscustomobject]@{
                summary         = $summary
                executionScript = (ConvertTo-HD365OneLiner -ScriptText $scriptText)
                isWrite         = $true
                userCount       = $ids.Count
                groupName       = $groupName
                existingGroupId = $existingId
                existingName    = $existingName
                bakedUserIds    = $ids
            }
        }

        'CreateNestedGroups' {
            $parents = @()
            $children = @()
            $existing = @()

            if ($DiscoveryResult -and $DiscoveryResult.Parents) {
                $parents = @(Select-HD365TopLevelOfficeParents -Groups @($DiscoveryResult.Parents | Where-Object { $_ -and $_.Id }))
            }
            if ($Plan.childNames) {
                $children = @($Plan.childNames)
            }
            elseif ($DiscoveryResult -and $DiscoveryResult.ChildNames) {
                $children = @($DiscoveryResult.ChildNames)
            }
            if ($DiscoveryResult -and $DiscoveryResult.PSObject.Properties['ExistingGroups']) {
                $existing = @($DiscoveryResult.ExistingGroups | Where-Object { $_ })
            }

            if ($parents.Count -eq 0) {
                throw "No top-level US state groups found (expected names like Ohio, Kansas). Create them first (e.g. 'create a group for every state in the US')."
            }
            if ($children.Count -eq 0) {
                throw 'No child department names were provided for nested group creation.'
            }

            $existingSet = @{}
            foreach ($g in $existing) {
                if ($g.DisplayName) { $existingSet[$g.DisplayName.ToLowerInvariant()] = $true }
            }

            $jobs = [System.Collections.Generic.List[object]]::new()
            $skipped = 0
            $usedNicks = @{}

            foreach ($p in $parents) {
                $abbr = Get-HD365ParentStateAbbreviation -ParentDisplayName ([string]$p.DisplayName)
                foreach ($c in $children) {
                    $display = "$($p.DisplayName) - $c"
                    if ($existingSet.ContainsKey($display.ToLowerInvariant())) {
                        $skipped++
                        continue
                    }
                    $code = Get-HD365DepartmentCode -DisplayName $c
                    $nick = "$abbr-$code"
                    $nick = ($nick -replace '[^A-Za-z0-9-]', '')
                    if ($nick.Length -gt 64) { $nick = $nick.Substring(0, 64) }
                    $base = $nick
                    $i = 2
                    while ($usedNicks.ContainsKey($nick.ToLowerInvariant())) {
                        $suffix = "-$i"
                        $trim = [Math]::Max(1, 64 - $suffix.Length)
                        $nick = $base.Substring(0, [Math]::Min($base.Length, $trim)) + $suffix
                        $i++
                    }
                    $usedNicks[$nick.ToLowerInvariant()] = $true

                    $displayEsc = $display -replace "'", "''"
                    $nickEsc = $nick -replace "'", "''"
                    $jobs.Add([pscustomobject]@{
                            ParentId      = [string]$p.Id
                            DisplayName   = $displayEsc
                            MailNickname  = $nickEsc
                        })
                }
            }

            if ($jobs.Count -eq 0) {
                $scriptText = "Write-Host 'All nested groups already exist for $($parents.Count) parent(s) x $($children.Count) department(s).'"
                return [pscustomobject]@{
                    summary         = "All $($parents.Count * $children.Count) nested groups already exist."
                    executionScript = (ConvertTo-HD365OneLiner -ScriptText $scriptText)
                    isWrite         = $false
                    createCount     = 0
                    skipCount       = $skipped
                }
            }

            # Compact algorithm: parents + depts arrays (NOT one object per nested group)
            $parentRows = foreach ($p in $parents) {
                [pscustomobject]@{
                    Id          = [string]$p.Id
                    DisplayName = [string]$p.DisplayName
                    Abbr        = (Get-HD365ParentStateAbbreviation -ParentDisplayName ([string]$p.DisplayName))
                }
            }
            $deptRows = foreach ($c in $children) {
                [pscustomobject]@{
                    Name = $c
                    Code = (Get-HD365DepartmentCode -DisplayName $c)
                }
            }

            $parentsPs = ConvertTo-HD365CompactParentArray -Parents $parentRows
            $deptsPs = ConvertTo-HD365CompactDeptArray -ChildNames $children
            $nest = $true
            if ($null -ne $Plan.nestMembership) { $nest = [bool]$Plan.nestMembership }

            $scriptText = New-HD365CompactNestedScript -ParentsPs $parentsPs -DeptsPs $deptsPs -NestMembership:$nest

            $summary = "Create $($jobs.Count) nested group(s) under $($parents.Count) parent(s) via compact parent x dept loop"
            if ($skipped -gt 0) { $summary += "; skip $skipped existing" }
            if ($nest) { $summary += '; nest each child as member of its parent' }

            $jobData = [pscustomobject]@{
                Parents        = @($parentRows)
                Departments    = @($deptRows)
                ExistingNames  = @($existing | ForEach-Object { $_.DisplayName } | Where-Object { $_ })
                NestMembership = $nest
                CreateCount    = $jobs.Count
            }

            return [pscustomobject]@{
                summary         = $summary
                executionScript = $scriptText
                isWrite         = $true
                createCount     = $jobs.Count
                skipCount       = $skipped
                parentCount     = $parents.Count
                childCount      = $children.Count
                bulkKind        = 'CreateNestedGroups'
                jobData         = $jobData
            }
        }

        'CreateManyGroups' {
            $requested = @()
            if ($Plan.groupNames) { $requested = @($Plan.groupNames) }
            elseif ($DiscoveryResult -and $DiscoveryResult.Requested) { $requested = @($DiscoveryResult.Requested) }

            if ($requested.Count -eq 0) {
                throw 'No group names available to create.'
            }

            $existing = @()
            if ($DiscoveryResult -and $DiscoveryResult.PSObject.Properties['ExistingGroups']) {
                $existing = @($DiscoveryResult.ExistingGroups | Where-Object { $_ })
            }

            $existingMap = @{}
            foreach ($g in $existing) {
                if ($g.DisplayName) {
                    $existingMap[$g.DisplayName.ToLowerInvariant()] = $g
                }
            }

            $toCreate = [System.Collections.Generic.List[object]]::new()
            $skipped = [System.Collections.Generic.List[string]]::new()
            $usedNicks = @{}
            foreach ($g in $existing) {
                if ($g.MailNickname) { $usedNicks[$g.MailNickname.ToLowerInvariant()] = $true }
            }

            foreach ($name in $requested) {
                $key = $name.ToLowerInvariant()
                if ($existingMap.ContainsKey($key)) {
                    $skipped.Add($name)
                    continue
                }
                $nick = Get-HD365MailNickname -DisplayName $name
                $base = $nick
                $i = 2
                while ($usedNicks.ContainsKey($nick.ToLowerInvariant())) {
                    $suffix = "$i"
                    $trim = [Math]::Max(1, 64 - $suffix.Length)
                    $nick = $base.Substring(0, [Math]::Min($base.Length, $trim)) + $suffix
                    $i++
                }
                $usedNicks[$nick.ToLowerInvariant()] = $true
                $nameEsc = $name -replace "'", "''"
                $nickEsc = $nick -replace "'", "''"
                $toCreate.Add([pscustomobject]@{ DisplayName = $nameEsc; MailNickname = $nickEsc })
            }

            if ($toCreate.Count -eq 0) {
                $existingIds = @(
                    foreach ($name in $requested) {
                        $g = $existingMap[$name.ToLowerInvariant()]
                        if ($g) { "'$($g.Id)'" }
                    }
                ) -join ','
                $scriptText = "Write-Host 'All $($requested.Count) requested groups already exist.'; @($existingIds) | ForEach-Object { Get-MgGroup -GroupId `$_ -Property Id,DisplayName,MailNickname | Select-Object DisplayName,Id,MailNickname }"
                return [pscustomobject]@{
                    summary         = "All $($requested.Count) requested groups already exist. Solution lists them."
                    executionScript = (ConvertTo-HD365OneLiner -ScriptText $scriptText)
                    isWrite         = $false
                    createCount     = 0
                    skipCount       = $skipped.Count
                }
            }

            $objs = @(
                foreach ($item in $toCreate) {
                    "[pscustomobject]@{DisplayName='$($item.DisplayName)';MailNickname='$($item.MailNickname)'}"
                }
            ) -join ','

            $scriptText = "@($objs) | ForEach-Object { New-MgGroup -DisplayName `$_.DisplayName -MailEnabled:`$false -MailNickname `$_.MailNickname -SecurityEnabled:`$true } | Select-Object DisplayName,Id,MailNickname"
            $summary = "Create $($toCreate.Count) missing group(s)"
            if ($skipped.Count -gt 0) { $summary += "; skip $($skipped.Count) existing" }
            $summary += '.'

            return [pscustomobject]@{
                summary         = $summary
                executionScript = (ConvertTo-HD365OneLiner -ScriptText $scriptText)
                isWrite         = $true
                createCount     = $toCreate.Count
                skipCount       = $skipped.Count
                skippedNames    = @($skipped)
            }
        }

        'AddUserToGroup' {
            $user = $null
            $group = $null
            if ($DiscoveryResult) {
                $user = $DiscoveryResult.User
                $group = @($DiscoveryResult.Groups) | Select-Object -First 1
            }
            if (-not $user -or -not $user.Id) {
                $upn = if ($DiscoveryResult) { $DiscoveryResult.RequestedUpn } else { '?' }
                throw "Discovery could not resolve user '$upn'."
            }
            if (-not $group -or -not $group.Id) {
                $gn = if ($DiscoveryResult) { $DiscoveryResult.RequestedGroup } else { '?' }
                throw "Discovery could not resolve group '$gn'."
            }

            $scriptText = "New-MgGroupMember -GroupId '$($group.Id)' -DirectoryObjectId '$($user.Id)'; Get-MgGroupMember -GroupId '$($group.Id)' -All | Select-Object -ExpandProperty Id"
            return [pscustomobject]@{
                summary         = "Add $($user.UserPrincipalName) ($($user.Id)) to $($group.DisplayName) ($($group.Id))."
                executionScript = (ConvertTo-HD365OneLiner -ScriptText $scriptText)
                isWrite         = $true
                userId          = [string]$user.Id
                groupId         = [string]$group.Id
            }
        }

        'ListGroupMemberCounts' {
            # Bake discovered group IDs into a read one-liner for copy/paste
            $rows = @($DiscoveryResult)
            $ids = @($rows | Where-Object { $_.Id } | Select-Object -ExpandProperty Id)
            if ($ids.Count -gt 0) {
                $idList = Format-HD365GuidList -Ids $ids
                $scriptText = "@($idList) | ForEach-Object { `$g=Get-MgGroup -GroupId `$_ -Property Id,DisplayName,Mail; [pscustomobject]@{ DisplayName=`$g.DisplayName; Id=`$g.Id; Mail=`$g.Mail; MemberCount=@(Get-MgGroupMember -GroupId `$_ -All -ErrorAction SilentlyContinue).Count } }"
            }
            else {
                $scriptText = $DiscoveryScript
            }
            return [pscustomobject]@{
                summary         = "Read-only member-count one-liner for $($ids.Count) discovered group(s)."
                executionScript = (ConvertTo-HD365OneLiner -ScriptText $scriptText)
                isWrite         = $false
            }
        }

        'AiWrite' {
            $scriptText = [string]$Plan.executionScript
            if ([string]::IsNullOrWhiteSpace($scriptText)) {
                throw "AI write plan missing executionScript after discovery. Refine the request or check /ai for a configured provider."
            }
            if ($scriptText -match 'contoso\.com|user@|Exact Group Name|GroupName') {
                throw "Solution still contains placeholders. Discovery data was not applied."
            }
            return [pscustomobject]@{
                summary         = [string]$Plan.summary
                executionScript = (ConvertTo-HD365OneLiner -ScriptText $scriptText)
                isWrite         = $true
            }
        }

        default {
            # Read passthrough: solution is the discovery one-liner itself (already executed)
            $scriptText = $DiscoveryScript
            if ($Plan.executionScript) { $scriptText = [string]$Plan.executionScript }
            return [pscustomobject]@{
                summary         = [string]$Plan.summary
                executionScript = (ConvertTo-HD365OneLiner -ScriptText $scriptText)
                isWrite         = $false
            }
        }
    }
}
