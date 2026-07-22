function Get-HD365StandardDepartments {
    @(
        'HR'
        'Finance'
        'Accounting'
        'Executive'
        'Information Technology'
        'Operations'
        'Sales'
        'Marketing'
        'Legal'
        'Customer Support'
        'Facilities'
        'Security'
        'Research and Development'
        'Procurement'
        'Human Resources'
    ) | Select-Object -Unique
}

function Get-HD365UsStateNames {
    @(
        'Alabama', 'Alaska', 'Arizona', 'Arkansas', 'California', 'Colorado', 'Connecticut', 'Delaware',
        'Florida', 'Georgia', 'Hawaii', 'Idaho', 'Illinois', 'Indiana', 'Iowa', 'Kansas', 'Kentucky',
        'Louisiana', 'Maine', 'Maryland', 'Massachusetts', 'Michigan', 'Minnesota', 'Mississippi',
        'Missouri', 'Montana', 'Nebraska', 'Nevada', 'New Hampshire', 'New Jersey', 'New Mexico',
        'New York', 'North Carolina', 'North Dakota', 'Ohio', 'Oklahoma', 'Oregon', 'Pennsylvania',
        'Rhode Island', 'South Carolina', 'South Dakota', 'Tennessee', 'Texas', 'Utah', 'Vermont',
        'Virginia', 'Washington', 'West Virginia', 'Wisconsin', 'Wyoming', 'District of Columbia'
    )
}

function Test-HD365IsTopLevelOfficeGroup {
    <#
    .SYNOPSIS
      True only for top-level US state/DC groups named exactly "Ohio", "Kansas", etc.
      False for nested names like "Ohio - HR".
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]$DisplayName
    )

    process {
        if ([string]::IsNullOrWhiteSpace($DisplayName)) { return $false }
        # Nested dept groups always contain " - "
        if ($DisplayName -match '\s+-\s+') { return $false }
        foreach ($s in (Get-HD365UsStateNames)) {
            if ($s -ieq $DisplayName) { return $true }
        }
        return $false
    }
}

function Select-HD365TopLevelOfficeParents {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Groups
    )

    return @(
        $Groups |
            Where-Object { $_ -and $_.DisplayName -and (Test-HD365IsTopLevelOfficeGroup -DisplayName ([string]$_.DisplayName)) }
    )
}

function Get-HD365UsStateOfficeGroups {
    # Plain state names only (no "Office - " prefix): Ohio, Kansas, ...
    Get-HD365UsStateNames
}

function Get-HD365MailNickname {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DisplayName
    )

    $nick = ($DisplayName -replace '[^A-Za-z0-9]', '')
    if ([string]::IsNullOrWhiteSpace($nick)) { $nick = 'HD365Group' }
    if ($nick.Length -gt 64) { $nick = $nick.Substring(0, 64) }
    # Graph mailNickname must start with a letter/number
    if ($nick -notmatch '^[A-Za-z0-9]') { $nick = "G$nick" }
    return $nick
}

function Get-HD365UsStateAbbreviationMap {
    [ordered]@{
        'Alabama' = 'AL'; 'Alaska' = 'AK'; 'Arizona' = 'AZ'; 'Arkansas' = 'AR'; 'California' = 'CA'
        'Colorado' = 'CO'; 'Connecticut' = 'CT'; 'Delaware' = 'DE'; 'Florida' = 'FL'; 'Georgia' = 'GA'
        'Hawaii' = 'HI'; 'Idaho' = 'ID'; 'Illinois' = 'IL'; 'Indiana' = 'IN'; 'Iowa' = 'IA'
        'Kansas' = 'KS'; 'Kentucky' = 'KY'; 'Louisiana' = 'LA'; 'Maine' = 'ME'; 'Maryland' = 'MD'
        'Massachusetts' = 'MA'; 'Michigan' = 'MI'; 'Minnesota' = 'MN'; 'Mississippi' = 'MS'
        'Missouri' = 'MO'; 'Montana' = 'MT'; 'Nebraska' = 'NE'; 'Nevada' = 'NV'
        'New Hampshire' = 'NH'; 'New Jersey' = 'NJ'; 'New Mexico' = 'NM'; 'New York' = 'NY'
        'North Carolina' = 'NC'; 'North Dakota' = 'ND'; 'Ohio' = 'OH'; 'Oklahoma' = 'OK'
        'Oregon' = 'OR'; 'Pennsylvania' = 'PA'; 'Rhode Island' = 'RI'; 'South Carolina' = 'SC'
        'South Dakota' = 'SD'; 'Tennessee' = 'TN'; 'Texas' = 'TX'; 'Utah' = 'UT'; 'Vermont' = 'VT'
        'Virginia' = 'VA'; 'Washington' = 'WA'; 'West Virginia' = 'WV'; 'Wisconsin' = 'WI'
        'Wyoming' = 'WY'; 'District of Columbia' = 'DC'
    }
}

function ConvertTo-HD365DepartmentDisplayName {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name)

    $n = $Name.Trim().Trim('"').Trim("'")
    switch -Regex ($n.ToLowerInvariant()) {
        '^(hr|human resources)$' { return 'HR' }
        '^(it|information technology|info tech)$' { return 'Information Technology' }
        '^(r&d|research and development|research & development)$' { return 'Research and Development' }
        '^(exec|executive|executives)$' { return 'Executive' }
        '^(ops|operations)$' { return 'Operations' }
        '^(finance|financial)$' { return 'Finance' }
        '^(accounting|acct)$' { return 'Accounting' }
        '^(accounts?\s*payable|ap)$' { return 'Accounts Payable' }
        '^(accounts?\s*receivable|ar)$' { return 'Accounts Receivable' }
        '^(mgmt|management)$' { return 'Management' }
        '^(sales)$' { return 'Sales' }
        '^(marketing)$' { return 'Marketing' }
        '^(legal)$' { return 'Legal' }
        default {
            # Title-case words
            $textInfo = (Get-Culture).TextInfo
            return $textInfo.ToTitleCase($n.ToLowerInvariant())
        }
    }
}

function Get-HD365DepartmentCode {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$DisplayName)

    switch -Regex ($DisplayName.ToLowerInvariant()) {
        '^hr$' { return 'HR' }
        '^accounts payable$' { return 'AP' }
        '^accounts receivable$' { return 'AR' }
        '^information technology$' { return 'IT' }
        '^operations$' { return 'OPS' }
        '^finance$' { return 'FIN' }
        '^accounting$' { return 'ACCT' }
        '^management$' { return 'MGMT' }
        '^executive$' { return 'EXEC' }
        '^sales$' { return 'SALES' }
        '^marketing$' { return 'MKT' }
        '^legal$' { return 'LEGAL' }
        default {
            $parts = $DisplayName -split '\s+' | Where-Object { $_ }
            if ($parts.Count -eq 1) {
                $c = ($parts[0] -replace '[^A-Za-z0-9]', '').ToUpperInvariant()
                if ($c.Length -gt 6) { $c = $c.Substring(0, 6) }
                return $c
            }
            return (($parts | ForEach-Object { $_.Substring(0, 1) }) -join '').ToUpperInvariant()
        }
    }
}

function Get-HD365ParentStateAbbreviation {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ParentDisplayName)

    $map = Get-HD365UsStateAbbreviationMap
    $state = $ParentDisplayName.Trim()

    # Legacy "Office - Ohio" names still resolve
    if ($state -match '(?i)^Office\s*-\s*(.+)$') {
        $state = $Matches[1].Trim()
    }
    # Nested "Ohio - HR" -> use parent state segment
    elseif ($state -match '\s+-\s+') {
        $state = ([regex]::Split($state, '\s+-\s+'))[0].Trim()
    }

    foreach ($k in $map.Keys) {
        if ($k -ieq $state) { return [string]$map[$k] }
    }

    $nick = Get-HD365MailNickname -DisplayName $ParentDisplayName
    if ($nick.Length -gt 8) { return $nick.Substring(0, 8) }
    return $nick
}

function ConvertFrom-HD365NameListChunk {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ListChunk)

    $normalizedList = $ListChunk.Trim()
    $normalizedList = $normalizedList -replace '\s*,\s*and\s+', ','
    $normalizedList = $normalizedList -replace '\s+and\s+', ','
    $normalizedList = $normalizedList -replace '\s*,\s*', ','
    $parts = $normalizedList -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    $out = [System.Collections.Generic.List[string]]::new()
    $seen = @{}
    foreach ($p in $parts) {
        $clean = $p.Trim().Trim('"').Trim("'")
        $clean = $clean -replace '^(?i)(the|a|an)\s+', ''
        $clean = $clean -replace '^(?i)and\s+', ''
        if ($clean.Length -lt 2) { continue }
        $display = ConvertTo-HD365DepartmentDisplayName -Name $clean
        $key = $display.ToLowerInvariant()
        if (-not $seen.ContainsKey($key)) {
            $seen[$key] = $true
            $out.Add($display)
        }
    }
    return @($out)
}

function Test-HD365IsNestedGroupsRequest {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$UserMessage)

    $m = $UserMessage.ToLowerInvariant()
    # within/inside/under/for each|every ... group(s), make/create groups for ...
    if ($m -match '(within|inside|under|across)\s+(every|each|all)\b') { return $true }
    if ($m -match '\b(for|in)\s+each\s+.+\bgroup') { return $true }
    if ($m -match '\b(every|each)\s+state\s+group\b') { return $true }
    if ($m -match '\bnested\b' -and $m -match '\bgroups?\b') { return $true }
    if ($m -match '\bsub-?groups?\b') { return $true }
    return $false
}

function Get-HD365NestedGroupPlan {
    <#
    .SYNOPSIS
      Plan parent x child group matrix, e.g. within every Office-* group create dept groups.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$UserMessage)

    $msg = $UserMessage.Trim()
    $msgLower = $msg.ToLowerInvariant()

    $childNames = @()
    $listChunk = $null
    if ($msg -match '(?i)(?:make|create|build|add|provision)\s+groups?\s+(?:for|like|:)\s+(.+)$') {
        $listChunk = $Matches[1].Trim()
    }
    elseif ($msg -match '(?i)groups?\s+(?:for|like|:)\s+(.+)$') {
        $listChunk = $Matches[1].Trim()
    }

    if ($listChunk) {
        $childNames = @(ConvertFrom-HD365NameListChunk -ListChunk $listChunk)
    }

    if ($childNames.Count -eq 0) {
        $childNames = @(
            'Accounts Payable'
            'HR'
            'Accounts Receivable'
            'Management'
            'Operations'
            'Information Technology'
            'Finance'
        )
    }

    # Parents = plain US state group names (Ohio, Kansas, ...). Never nested "State - Dept".
    $parentFilter = 'StateName'
    $parentScope = 'top-level US state groups named exactly like Ohio, Kansas, etc.'
    if ($msgLower -match 'state' -or $msgLower -match 'within') {
        $parentFilter = 'StateName'
        $parentScope = 'every top-level US state group (Ohio, Kansas, ...)'
    }

    return [pscustomobject]@{
        ChildNames     = $childNames
        ParentFilter   = $parentFilter
        ParentScope    = $parentScope
        NestMembership = $true
        EstimatedMax   = ($childNames.Count * 51) # informational
        UseStateParents = $true
    }
}

function Get-HD365GroupNamesFromMessage {
    <#
    .SYNOPSIS
      Extract requested security-group display names from natural language.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$UserMessage
    )

    $msg = $UserMessage.Trim()
    $msgLower = $msg.ToLowerInvariant()
    $names = [System.Collections.Generic.List[string]]::new()
    $includeStates = $false
    $usedDefaults = $false

    if ($msgLower -match 'every state|all (?:\d+\s+)?states|office in every state|offices in every state|each state') {
        $includeStates = $true
    }

    # Explicit list after for/like/: e.g. "groups for HR, finance, and operations"
    $listChunk = $null
    if ($msg -match '(?i)(?:groups?|departments?)\s+(?:for|like|:)\s+(.+)$') {
        $listChunk = $Matches[1].Trim()
    }
    elseif ($msg -match '(?i)(?:create|make|build|provision)\s+(?:me\s+)?(?:an?\s+)?(?:entire\s+)?(?:directory|org(?:anization)?|ou)\b') {
        # directory/org scaffold with no explicit list -> defaults
        $listChunk = $null
    }
    elseif ($msg -match '(?i)(?:create|make|build|provision)\s+(?:me\s+)?groups?\s+(.+)$') {
        $listChunk = $Matches[1].Trim()
        $listChunk = $listChunk -replace '^(?i)for\s+', ''
        $listChunk = $listChunk -replace '^(?i)called\s+', ''
    }

    $forceDefaults = $false
    if ($listChunk) {
        if ($listChunk -match '(?i)major departments?' -or $listChunk -match '(?i)^all the major' -or $listChunk -match '(?i)normal company') {
            $forceDefaults = $true
        }
        else {
            # Drop trailing scaffolding phrases
            $listChunk = $listChunk -replace '(?i)\s+that a normal company.*$', ''
            $listChunk = $listChunk -replace '(?i)\s+in a company.*$', ''
            $listChunk = $listChunk -replace '(?i)\s+with office.*$', ''

            # Normalize list separators, then split (avoid ", and X" leaving "and X")
            $normalizedList = $listChunk
            $normalizedList = $normalizedList -replace '\s*,\s*and\s+', ','
            $normalizedList = $normalizedList -replace '\s+and\s+', ','
            $normalizedList = $normalizedList -replace '\s*,\s*', ','
            $parts = $normalizedList -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
            foreach ($p in $parts) {
                $clean = $p.Trim().Trim('"').Trim("'")
                $clean = $clean -replace '^(?i)(the|a|an)\s+', ''
                $clean = $clean -replace '^(?i)and\s+', ''
                # Skip junk fragments
                if ($clean -match '(?i)major departments?') { $forceDefaults = $true; continue }
                if ($clean -match '^(?i)(major|normal|company|department|departments|group|groups|all|entire|directory|office|offices|every state|all states)$') { continue }
                if ($clean.Length -lt 2) { continue }
                if ($clean.Length -gt 64) { continue }
                if ($clean -match '\s+(in|with|for|that|company|office)') { continue }
                $names.Add($clean)
            }
        }
    }

    # "major departments" / directory scaffold with no usable explicit list
    if (($names.Count -eq 0 -or $forceDefaults) -and (
            $forceDefaults -or
            $msgLower -match 'major departments?' -or
            $msgLower -match 'entire directory' -or
            $msgLower -match 'normal company' -or
            ($msgLower -match 'departments?' -and $msgLower -match 'creat' -and $names.Count -eq 0)
        )) {
        $names.Clear()
        foreach ($d in (Get-HD365StandardDepartments)) {
            # Prefer HR over duplicate Human Resources in default set for cleaner tenant
            if ($d -eq 'Human Resources') { continue }
            $names.Add($d)
        }
        $usedDefaults = $true
    }

    # Normalize common aliases
    $normalized = [System.Collections.Generic.List[string]]::new()
    $seen = @{}
    foreach ($n in $names) {
        $display = $n
        switch -Regex ($n.ToLowerInvariant()) {
            '^(hr|human resources)$' { $display = 'HR'; break }
            '^(it|information technology|info tech)$' { $display = 'Information Technology'; break }
            '^(r&d|research and development|research & development)$' { $display = 'Research and Development'; break }
            '^(exec|executive|executives)$' { $display = 'Executive'; break }
            '^(ops|operations)$' { $display = 'Operations'; break }
            '^(finance|financial)$' { $display = 'Finance'; break }
            '^(accounting|acct)$' { $display = 'Accounting'; break }
        }
        $key = $display.ToLowerInvariant()
        if (-not $seen.ContainsKey($key)) {
            $seen[$key] = $true
            $normalized.Add($display)
        }
    }

    if ($includeStates) {
        foreach ($og in (Get-HD365UsStateOfficeGroups)) {
            $key = $og.ToLowerInvariant()
            if (-not $seen.ContainsKey($key)) {
                $seen[$key] = $true
                $normalized.Add($og)
            }
        }
    }

    return [pscustomobject]@{
        GroupNames     = @($normalized)
        IncludeStates  = $includeStates
        UsedDefaults   = $usedDefaults
        IsMultiCreate  = ($normalized.Count -gt 0)
    }
}

function Test-HD365IsCreateManyGroupsRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$UserMessage
    )

    $m = $UserMessage.ToLowerInvariant()

    # Nested matrix requests are handled separately
    if (Test-HD365IsNestedGroupsRequest -UserMessage $UserMessage) { return $false }

    # Single group + add all users handled elsewhere
    if ($m -match 'add\s+all\s+users') { return $false }

    $createVerb = $m -match '\b(create|make|build|provision|scaffold|set up|setup)\b'
    if (-not $createVerb) { return $false }

    $groupish = $m -match '\bgroups?\b' -or $m -match '\bdepartments?\b' -or $m -match '\bdirectory\b' -or $m -match '\boffice(s)?\b'
    if (-not $groupish) { return $false }

    # Multi-target signals
    if ($m -match ',' -or $m -match '\band\b' -or $m -match 'major departments' -or $m -match 'every state' -or $m -match 'entire directory') {
        return $true
    }

    # "create groups for X" even without comma if plural groups
    if ($m -match '\bgroups\b') { return $true }

    return $false
}
