function New-HD365OfflineProposal {
    <#
    .SYNOPSIS
      Offline (no AI) plan: discovery one-liner + intent metadata for solution builder.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$UserMessage
    )

    $msg = $UserMessage.Trim()
    $msgLower = $msg.ToLowerInvariant()

    # --- Create group + add all users ---
    if (
        ($msgLower -match 'create\s+(a\s+)?group') -and
        ($msgLower -match 'add\s+all\s+users' -or $msgLower -match 'add\s+every(one| user)')
    ) {
        $groupName = $null
        if ($msg -match 'called\s+"([^"]+)"') { $groupName = $Matches[1] }
        elseif ($msg -match "called\s+'([^']+)'") { $groupName = $Matches[1] }
        elseif ($msg -match 'named\s+"([^"]+)"') { $groupName = $Matches[1] }
        elseif ($msg -match 'group\s+(?:called|named)\s+(\S.+?)(?:\s+and\s+|\s*$)') {
            $groupName = $Matches[1].Trim().Trim('"').Trim("'")
        }
        if (-not $groupName) { $groupName = 'All Users' }

        $gnEsc = $groupName -replace "'", "''"
        $nick = ($groupName -replace '[^A-Za-z0-9]', '')
        if ([string]::IsNullOrWhiteSpace($nick)) { $nick = 'HD365Group' }
        if ($nick.Length -gt 64) { $nick = $nick.Substring(0, 64) }

        $discovery = @(
            "[pscustomobject]@{"
            "Intent='CreateGroupAddAllUsers';"
            "GroupName='$gnEsc';"
            "MailNickname='$nick';"
            "ExistingGroups=@(Get-MgGroup -Filter `"displayName eq '$gnEsc'`" -All -Property Id,DisplayName,MailNickname,MailEnabled,SecurityEnabled -ErrorAction SilentlyContinue);"
            "Users=@(Get-MgUser -All -Property Id,DisplayName,UserPrincipalName,UserType | Select-Object Id,DisplayName,UserPrincipalName,UserType)"
            "}"
        ) -join ' '

        return [pscustomobject]@{
            summary             = "Create security group '$groupName' (if missing) and add all tenant users as members."
            intent              = 'write'
            platform            = 'Microsoft Graph'
            modules             = @('Microsoft.Graph.Users', 'Microsoft.Graph.Groups')
            leastScopes         = @('User.Read.All', 'Group.Read.All', 'Group.ReadWrite.All', 'GroupMember.ReadWrite.All')
            rolesNeeded         = @('Groups Administrator (or equivalent)')
            phase               = 'discovery'
            discoveryScript     = (ConvertTo-HD365OneLiner -ScriptText $discovery)
            executionScript     = ''
            isWrite             = $true
            warnings            = @(
                'Solution embeds real user GUIDs from discovery.',
                'Write scopes are requested only when you /run.'
            )
            clarifyingQuestions = @()
            displayHints        = 'Discovery: existing group match + users'
            solutionKind        = 'CreateGroupAddAllUsers'
            groupName           = $groupName
            mailNickname        = $nick
            offline             = $true
        }
    }

    # --- Nested groups: within every parent, create child dept groups ---
    if (Test-HD365IsNestedGroupsRequest -UserMessage $msg) {
        $nested = Get-HD365NestedGroupPlan -UserMessage $msg
        $childQuoted = @($nested.ChildNames | ForEach-Object {
                $e = $_ -replace "'", "''"
                "'$e'"
            }) -join ','

        $stateList = @(Get-HD365UsStateNames | ForEach-Object {
                $e = $_ -replace "'", "''"
                "'$e'"
            }) -join ','

        $discovery = @(
            "`$stateNames=@($stateList);"
            "`$childNames=@($childQuoted);"
            "`$parents=@(Get-MgGroup -All -Property Id,DisplayName,MailNickname | Where-Object { `$n=`$_.DisplayName; (`$n -notmatch '\s+-\s+') -and (@(`$stateNames | Where-Object { `$_ -ieq `$n }).Count -gt 0) } | Select-Object Id,DisplayName,MailNickname);"
            "`$wanted=@(); foreach(`$p in `$parents){ foreach(`$c in `$childNames){ `$wanted += (`$p.DisplayName + ' - ' + `$c) } };"
            "`$existing=@(Get-MgGroup -All -Property Id,DisplayName,MailNickname | Where-Object { `$n=`$_.DisplayName; @(`$wanted | Where-Object { `$_ -ieq `$n }).Count -gt 0 } | Select-Object Id,DisplayName,MailNickname);"
            "[pscustomobject]@{ Intent='CreateNestedGroups'; ParentFilter='StateName'; ChildNames=`$childNames; Parents=`$parents; ExistingGroups=`$existing; ParentCount=`$parents.Count; ChildCount=`$childNames.Count; ExistingCount=`$existing.Count; PlannedCount=(`$parents.Count * `$childNames.Count); Note='Parents are plain state names only (Ohio, Kansas, ...). Nested State - Dept groups are never used as parents.' }"
        ) -join ' '

        return [pscustomobject]@{
            summary             = "Inside each state group (Ohio, Kansas, ...), create $($nested.ChildNames.Count) department group(s) named '<State> - <Dept>', and nest them as members of the state group."
            intent              = 'write'
            platform            = 'Microsoft Graph'
            modules             = @('Microsoft.Graph.Groups')
            leastScopes         = @('Group.Read.All', 'Group.ReadWrite.All', 'GroupMember.ReadWrite.All')
            rolesNeeded         = @('Groups Administrator (or equivalent)')
            phase               = 'discovery'
            discoveryScript     = (ConvertTo-HD365OneLiner -ScriptText $discovery)
            executionScript     = ''
            isWrite             = $true
            warnings            = @(
                'State groups are plain names (Ohio, Kansas) - no Office - prefix.'
                'Dept groups are named like Ohio - HR. Existing State - Dept names are never used as parents.'
                'Existing matching display names are skipped.'
                "This can create up to (state parents x $($nested.ChildNames.Count)) groups - review Phase 1 counts before /run."
                'Write scopes are requested only when you /run.'
            )
            clarifyingQuestions = @()
            displayHints        = 'Discovery: state parents + which State - Dept names already exist'
            solutionKind        = 'CreateNestedGroups'
            childNames          = @($nested.ChildNames)
            parentFilter        = [string]$nested.ParentFilter
            nestMembership      = [bool]$nested.NestMembership
            offline             = $true
        }
    }

    # --- Create many department / office groups ---
    if (Test-HD365IsCreateManyGroupsRequest -UserMessage $msg) {
        $namePlan = Get-HD365GroupNamesFromMessage -UserMessage $msg
        if ($namePlan.IsMultiCreate -and $namePlan.GroupNames.Count -gt 0) {
            $quotedNames = @($namePlan.GroupNames | ForEach-Object {
                    $e = $_ -replace "'", "''"
                    "'$e'"
                }) -join ','

            $discovery = @(
                "`$names=@($quotedNames);"
                "`$existing=@(Get-MgGroup -All -Property Id,DisplayName,MailNickname | Where-Object { `$d=`$_.DisplayName; @(`$names | Where-Object { `$_ -ieq `$d }).Count -gt 0 });"
                "[pscustomobject]@{ Intent='CreateManyGroups'; Requested=`$names; ExistingGroups=`$existing; ExistingCount=`$existing.Count; RequestedCount=`$names.Count }"
            ) -join ' '

            $warnings = @(
                'Creates security-enabled Microsoft 365 directory groups (not Teams).'
                'Existing groups with the same display name are skipped.'
                'Write scopes are requested only when you /run.'
            )
            if ($namePlan.UsedDefaults) {
                $warnings += 'Used the built-in major-department catalog (no explicit list parsed).'
            }
            if ($namePlan.IncludeStates) {
                $warnings += 'Included plain US state groups (Ohio, Kansas, ... + DC) - no Office - prefix.'
            }

            return [pscustomobject]@{
                summary             = "Create $($namePlan.GroupNames.Count) security group(s) from your directory request (skip names that already exist)."
                intent              = 'write'
                platform            = 'Microsoft Graph'
                modules             = @('Microsoft.Graph.Groups')
                leastScopes         = @('Group.Read.All', 'Group.ReadWrite.All')
                rolesNeeded         = @('Groups Administrator (or equivalent)')
                phase               = 'discovery'
                discoveryScript     = (ConvertTo-HD365OneLiner -ScriptText $discovery)
                executionScript     = ''
                isWrite             = $true
                warnings            = $warnings
                clarifyingQuestions = @()
                displayHints        = 'Discovery: requested vs already-existing group names'
                solutionKind        = 'CreateManyGroups'
                groupNames          = @($namePlan.GroupNames)
                includeStates       = [bool]$namePlan.IncludeStates
                usedDefaults        = [bool]$namePlan.UsedDefaults
                offline             = $true
            }
        }
    }

    # --- Add specific user to group ---
    if ($msgLower -match 'add\s+(\S+@\S+)\s+to\s+(.+)') {
        $upn = $Matches[1].Trim().Trim('"').Trim("'")
        $groupPart = $Matches[2].Trim().Trim('"').Trim("'") -replace '\s+group\s*$', ''
        $upnEsc = $upn -replace "'", "''"
        $gnEsc = $groupPart -replace "'", "''"

        $discovery = @(
            "[pscustomobject]@{"
            "Intent='AddUserToGroup';"
            "RequestedUpn='$upnEsc';"
            "RequestedGroup='$gnEsc';"
            "User=(Get-MgUser -UserId '$upnEsc' -Property Id,DisplayName,UserPrincipalName -ErrorAction SilentlyContinue | Select-Object Id,DisplayName,UserPrincipalName);"
            "Groups=@(Get-MgGroup -Filter `"displayName eq '$gnEsc'`" -All -Property Id,DisplayName -ErrorAction SilentlyContinue)"
            "}"
        ) -join ' '

        return [pscustomobject]@{
            summary             = "Add $upn to group '$groupPart'."
            intent              = 'write'
            platform            = 'Microsoft Graph'
            modules             = @('Microsoft.Graph.Users', 'Microsoft.Graph.Groups')
            leastScopes         = @('User.Read.All', 'Group.Read.All', 'GroupMember.ReadWrite.All')
            rolesNeeded         = @('Groups Administrator or group owner')
            phase               = 'discovery'
            discoveryScript     = (ConvertTo-HD365OneLiner -ScriptText $discovery)
            executionScript     = ''
            isWrite             = $true
            warnings            = @('Solution will embed resolved user and group GUIDs.')
            clarifyingQuestions = @()
            displayHints        = 'Confirm resolved user/group from discovery'
            solutionKind        = 'AddUserToGroup'
            offline             = $true
        }
    }

    # --- Named group / distro member counts ---
    if ($msgLower -match 'member' -and $msgLower -match '(distro|distribution|group|dl)') {
        $filterHint = 'Engineering'
        if ($msgLower -match 'engineering') { $filterHint = 'Engineering' }
        elseif ($msg -match '(?i)(?:of\s+the\s+|of\s+)([\w][\w\s-]{1,40}?)\s+(distro|distribution|group|dl)') {
            $filterHint = $Matches[1].Trim()
        }
        $fh = $filterHint -replace "'", "''"

        $discovery = "Get-MgGroup -All -Property Id,DisplayName,GroupTypes,MailEnabled,SecurityEnabled,Mail | Where-Object { `$_.DisplayName -like '*$fh*' } | ForEach-Object { [pscustomobject]@{ DisplayName=`$_.DisplayName; Id=`$_.Id; Mail=`$_.Mail; MailEnabled=`$_.MailEnabled; MemberCount=@(Get-MgGroupMember -GroupId `$_.Id -All -ErrorAction SilentlyContinue).Count } } | Sort-Object MemberCount -Descending"

        return [pscustomobject]@{
            summary             = "List groups matching '*$filterHint*' with member counts (read-only)."
            intent              = 'read'
            platform            = 'Microsoft Graph'
            modules             = @('Microsoft.Graph.Groups')
            leastScopes         = @('Group.Read.All', 'GroupMember.Read.All')
            rolesNeeded         = @()
            phase               = 'discovery'
            discoveryScript     = (ConvertTo-HD365OneLiner -ScriptText $discovery)
            executionScript     = ''
            isWrite             = $false
            warnings            = @('Classic distribution groups may require /exo if missing from Graph.')
            clarifyingQuestions = @()
            displayHints        = 'Table: DisplayName, MemberCount, Mail, Id'
            solutionKind        = 'ListGroupMemberCounts'
            filterHint          = $filterHint
            offline             = $true
        }
    }

    # --- Sign-in / audit ---
    if ($msgLower -match 'sign-?in|audit log') {
        $discovery = 'Get-MgAuditLogSignIn -Top 50 | Select-Object CreatedDateTime,UserPrincipalName,AppDisplayName,IpAddress,@{n=''Status'';e={$_.Status.ErrorCode}}'
        return [pscustomobject]@{
            summary             = 'Show recent sign-in logs (read-only).'
            intent              = 'read'
            platform            = 'Microsoft Graph'
            modules             = @('Microsoft.Graph.Reports')
            leastScopes         = @('AuditLog.Read.All')
            rolesNeeded         = @()
            phase               = 'discovery'
            discoveryScript     = (ConvertTo-HD365OneLiner -ScriptText $discovery)
            executionScript     = ''
            isWrite             = $false
            warnings            = @()
            clarifyingQuestions = @()
            displayHints        = 'Recent sign-ins table'
            solutionKind        = 'PassthroughRead'
            offline             = $true
        }
    }

    # --- Default: list users (safe read) ---
    $discovery = 'Get-MgUser -All -Property Id,DisplayName,UserPrincipalName,AccountEnabled | Select-Object Id,DisplayName,UserPrincipalName,AccountEnabled'
    return [pscustomobject]@{
        summary             = 'Offline intent not matched. Configure CopilotChat or OpenAI for full NL planning.'
        intent              = 'read'
        platform            = 'Microsoft Graph'
        modules             = @('Microsoft.Graph.Users')
        leastScopes         = @('User.Read.All')
        rolesNeeded         = @()
        phase               = 'discovery'
        discoveryScript     = (ConvertTo-HD365OneLiner -ScriptText $discovery)
        executionScript     = ''
        isWrite             = $false
        warnings            = @('Offline fallback is limited. Prefer ai.provider=CopilotChat with a Copilot license.')
        clarifyingQuestions = @()
        displayHints        = 'User directory listing'
        solutionKind        = 'PassthroughRead'
        offline             = $true
    }
}
