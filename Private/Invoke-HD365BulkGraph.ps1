function Invoke-MgHD365GraphRequest {
    <#
    .SYNOPSIS
      Thin wrapper around Invoke-MgGraphRequest using the existing session token (no re-auth).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('GET', 'POST', 'PATCH', 'PUT', 'DELETE')]
        [string]$Method,

        [Parameter(Mandatory)]
        [string]$Uri,

        [object]$Body,

        [hashtable]$Headers
    )

    $params = @{
        Method      = $Method
        Uri         = $Uri
        ErrorAction = 'Stop'
    }
    if ($PSBoundParameters.ContainsKey('Body')) {
        $params['Body'] = $Body
        $params['ContentType'] = 'application/json'
    }
    if ($Headers) { $params['Headers'] = $Headers }

    return Invoke-MgGraphRequest @params
}

function Invoke-HD365GraphBatch {
    <#
    .SYNOPSIS
      Execute Graph JSON batch requests (max 20 per round) with one auth context.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Requests
    )

    $results = [System.Collections.Generic.List[object]]::new()
    $chunks = [System.Collections.Generic.List[object[]]]::new()
    $buf = [System.Collections.Generic.List[object]]::new()

    foreach ($r in $Requests) {
        $buf.Add($r)
        if ($buf.Count -ge 20) {
            $chunks.Add(@($buf.ToArray()))
            $buf.Clear()
        }
    }
    if ($buf.Count -gt 0) { $chunks.Add(@($buf.ToArray())) }

    $round = 0
    foreach ($chunk in $chunks) {
        $round++
        $payload = @{ requests = @($chunk) }
        $resp = Invoke-MgHD365GraphRequest -Method POST -Uri 'https://graph.microsoft.com/v1.0/$batch' -Body $payload
        foreach ($item in @($resp.responses)) {
            $results.Add($item)
        }
        # Gentle pacing to reduce throttling / WAM weirdness
        Start-Sleep -Milliseconds 200
    }

    return @($results)
}

function Invoke-HD365BulkNestedGroups {
    <#
    .SYNOPSIS
      Create nested department groups under parents using Graph $batch (single session).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$JobData
    )

    $parents = @(Select-HD365TopLevelOfficeParents -Groups @($JobData.Parents))
    $depts = @($JobData.Departments)
    $existingSet = @{}
    if ($JobData.ExistingNames) {
        foreach ($n in @($JobData.ExistingNames)) {
            if ($n) { $existingSet[[string]$n.ToLowerInvariant()] = $true }
        }
    }

    $nest = $true
    if ($null -ne $JobData.NestMembership) { $nest = [bool]$JobData.NestMembership }

    # Build work items (skip existing names)
    $work = [System.Collections.Generic.List[object]]::new()
    $skipped = 0
    $usedNicks = @{}

    foreach ($p in $parents) {
        foreach ($d in $depts) {
            $display = "$($p.DisplayName) - $($d.Name)"
            if ($existingSet.ContainsKey($display.ToLowerInvariant())) {
                $skipped++
                continue
            }
            $nick = "$($p.Abbr)-$($d.Code)" -replace '[^A-Za-z0-9-]', ''
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
            $work.Add([pscustomobject]@{
                    ParentId     = [string]$p.Id
                    DisplayName  = $display
                    MailNickname = $nick
                })
        }
    }

    if ($work.Count -eq 0) {
        Write-Host "Nothing to create ($skipped already existed)." -ForegroundColor Yellow
        return [pscustomobject]@{ Created = 0; Skipped = $skipped; Failed = 0; Nested = 0 }
    }

    Write-Host ("Bulk create: {0} groups via Graph `$batch (20/req). Auth stays on existing write session." -f $work.Count) -ForegroundColor Cyan

    $created = [System.Collections.Generic.List[object]]::new()
    $failed = [System.Collections.Generic.List[object]]::new()
    $nestedOk = 0
    $total = $work.Count
    $done = 0

    # Process in waves of 20 creates, then membership refs
    for ($offset = 0; $offset -lt $work.Count; $offset += 20) {
        $slice = @($work | Select-Object -Skip $offset -First 20)
        $createReqs = for ($i = 0; $i -lt $slice.Count; $i++) {
            $item = $slice[$i]
            @{
                id      = "c$i"
                method  = 'POST'
                url     = '/groups'
                headers = @{ 'Content-Type' = 'application/json' }
                body    = @{
                    displayName     = $item.DisplayName
                    mailEnabled     = $false
                    mailNickname    = $item.MailNickname
                    securityEnabled = $true
                }
            }
        }

        $createResp = Invoke-HD365GraphBatch -Requests @($createReqs)
        $memberReqs = [System.Collections.Generic.List[object]]::new()

        foreach ($resp in $createResp) {
            $idx = [int](([string]$resp.id) -replace '^c', '')
            $item = $slice[$idx]
            $done++

            if ([int]$resp.status -ge 200 -and [int]$resp.status -lt 300) {
                $newId = [string]$resp.body.id
                $created.Add([pscustomobject]@{
                        DisplayName  = $item.DisplayName
                        Id           = $newId
                        ParentId     = $item.ParentId
                        MailNickname = $item.MailNickname
                    })
                if ($nest -and $newId) {
                    $memberReqs.Add(@{
                            id      = "m$idx"
                            method  = 'POST'
                            url     = "/groups/$($item.ParentId)/members/`$ref"
                            headers = @{ 'Content-Type' = 'application/json' }
                            body    = @{
                                '@odata.id' = "https://graph.microsoft.com/v1.0/directoryObjects/$newId"
                            }
                        })
                }
            }
            else {
                $err = $null
                if ($resp.body -and $resp.body.error) { $err = [string]$resp.body.error.message }
                if (-not $err) { $err = "HTTP $($resp.status)" }

                # Treat name/nickname conflicts as skipped (resume-safe after partial runs)
                if ($err -match 'already exists|Conflicting|another object with the same value') {
                    $skipped++
                }
                else {
                    $failed.Add([pscustomobject]@{ DisplayName = $item.DisplayName; Error = $err })
                }
            }
        }

        if ($memberReqs.Count -gt 0) {
            $memberResp = Invoke-HD365GraphBatch -Requests @($memberReqs)
            foreach ($mr in $memberResp) {
                if ([int]$mr.status -ge 200 -and [int]$mr.status -lt 300) { $nestedOk++ }
            }
        }

        $pct = [int](($done / [double]$total) * 100)
        Write-Host ("  Progress: {0}/{1} ({2}%)  created={3}  failed={4}" -f $done, $total, $pct, $created.Count, $failed.Count) -ForegroundColor DarkGray
    }

    Write-Host ("Done. Created={0}  Nested={1}  SkippedExisting={2}  Failed={3}" -f $created.Count, $nestedOk, $skipped, $failed.Count) -ForegroundColor Green
    if ($failed.Count -gt 0) {
        Write-Host "Failures (first 10):" -ForegroundColor Yellow
        $failed | Select-Object -First 10 | Format-Table -AutoSize | Out-String | Write-Host
    }

    return [pscustomobject]@{
        Created = $created.Count
        Nested  = $nestedOk
        Skipped = $skipped
        Failed  = $failed.Count
        Items   = @($created)
        Errors  = @($failed)
    }
}

function ConvertTo-HD365AiJobData {
    <#
    .SYNOPSIS
      Normalize AI solution.job into bulk JobData for Invoke-HD365BulkAiJob.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$AiSolution
    )

    $creates = @()
    if ($AiSolution.job -and $AiSolution.job.creates) {
        $creates = @($AiSolution.job.creates)
    }
    elseif ($AiSolution.creates) {
        $creates = @($AiSolution.creates)
    }

    if ($creates.Count -eq 0) { return $null }

    $nest = $true
    if ($AiSolution.job -and $null -ne $AiSolution.job.nestMembership) {
        $nest = [bool]$AiSolution.job.nestMembership
    }

    $rows = foreach ($c in $creates) {
        $dn = [string]$c.displayName
        if (-not $dn) { $dn = [string]$c.DisplayName }
        if (-not $dn) { continue }
        $nick = [string]$c.mailNickname
        if (-not $nick) { $nick = [string]$c.MailNickname }
        if (-not $nick) { $nick = Get-HD365MailNickname -DisplayName $dn }
        $parent = $null
        if ($c.parentDisplayName) { $parent = [string]$c.parentDisplayName }
        elseif ($c.ParentDisplayName) { $parent = [string]$c.ParentDisplayName }
        $parentId = $null
        if ($c.parentId) { $parentId = [string]$c.parentId }
        elseif ($c.ParentId) { $parentId = [string]$c.ParentId }

        [pscustomobject]@{
            DisplayName       = $dn
            MailNickname      = $nick
            ParentDisplayName = $parent
            ParentId          = $parentId
        }
    }

    return [pscustomobject]@{
        Creates        = @($rows)
        NestMembership = $nest
        CreateCount    = @($rows).Count
    }
}

function Invoke-HD365BulkAiJob {
    <#
    .SYNOPSIS
      Generic bulk group create (+ optional nest) from AI job JSON. Parents first, then children.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$JobData
    )

    $items = @($JobData.Creates)
    if ($items.Count -eq 0) {
        Write-Host "AI job has no creates." -ForegroundColor Yellow
        return [pscustomobject]@{ Created = 0; Nested = 0; Skipped = 0; Failed = 0 }
    }

    $nest = $true
    if ($null -ne $JobData.NestMembership) { $nest = [bool]$JobData.NestMembership }

    # Wave order: no parent first, then with parent
    $roots = @($items | Where-Object { -not $_.ParentDisplayName -and -not $_.ParentId })
    $children = @($items | Where-Object { $_.ParentDisplayName -or $_.ParentId })
    $ordered = @($roots + $children)

    Write-Host ("Bulk AI job: {0} groups via Graph `$batch (parents first)." -f $ordered.Count) -ForegroundColor Cyan

    $nameToId = @{}
    $created = [System.Collections.Generic.List[object]]::new()
    $failed = [System.Collections.Generic.List[object]]::new()
    $skipped = 0
    $nestedOk = 0
    $done = 0
    $total = $ordered.Count

    for ($offset = 0; $offset -lt $ordered.Count; $offset += 20) {
        $slice = @($ordered | Select-Object -Skip $offset -First 20)
        $createReqs = for ($i = 0; $i -lt $slice.Count; $i++) {
            $item = $slice[$i]
            @{
                id      = "c$i"
                method  = 'POST'
                url     = '/groups'
                headers = @{ 'Content-Type' = 'application/json' }
                body    = @{
                    displayName     = $item.DisplayName
                    mailEnabled     = $false
                    mailNickname    = $item.MailNickname
                    securityEnabled = $true
                }
            }
        }

        $createResp = Invoke-HD365GraphBatch -Requests @($createReqs)
        $memberReqs = [System.Collections.Generic.List[object]]::new()

        foreach ($resp in $createResp) {
            $idx = [int](([string]$resp.id) -replace '^c', '')
            $item = $slice[$idx]
            $done++
            $status = [int]$resp.status

            if ($status -ge 200 -and $status -lt 300) {
                $newId = [string]$resp.body.id
                $nameToId[$item.DisplayName.ToLowerInvariant()] = $newId
                $created.Add([pscustomobject]@{
                        DisplayName  = $item.DisplayName
                        Id           = $newId
                        MailNickname = $item.MailNickname
                        ParentId     = $item.ParentId
                    })

                $parentId = $item.ParentId
                if (-not $parentId -and $item.ParentDisplayName) {
                    $pkey = $item.ParentDisplayName.ToLowerInvariant()
                    if ($nameToId.ContainsKey($pkey)) {
                        $parentId = $nameToId[$pkey]
                    }
                    else {
                        # Resolve existing parent in tenant
                        try {
                            $esc = $item.ParentDisplayName -replace "'", "''"
                            $pg = Get-MgGroup -Filter "displayName eq '$esc'" -ErrorAction SilentlyContinue | Select-Object -First 1
                            if ($pg) {
                                $parentId = $pg.Id
                                $nameToId[$pkey] = $parentId
                            }
                        }
                        catch {}
                    }
                }

                if ($nest -and $parentId -and $newId) {
                    $memberReqs.Add(@{
                            id      = "m$idx"
                            method  = 'POST'
                            url     = "/groups/$parentId/members/`$ref"
                            headers = @{ 'Content-Type' = 'application/json' }
                            body    = @{
                                '@odata.id' = "https://graph.microsoft.com/v1.0/directoryObjects/$newId"
                            }
                        })
                }
            }
            else {
                $err = $null
                if ($resp.body -and $resp.body.error) { $err = [string]$resp.body.error.message }
                if (-not $err) { $err = "HTTP $status" }
                if ($err -match 'already exists|Conflicting|another object with the same value') {
                    $skipped++
                    # Cache existing id if possible for nesting children
                    try {
                        $esc = $item.DisplayName -replace "'", "''"
                        $eg = Get-MgGroup -Filter "displayName eq '$esc'" -ErrorAction SilentlyContinue | Select-Object -First 1
                        if ($eg) { $nameToId[$item.DisplayName.ToLowerInvariant()] = $eg.Id }
                    }
                    catch {}
                }
                else {
                    $failed.Add([pscustomobject]@{ DisplayName = $item.DisplayName; Error = $err })
                }
            }
        }

        if ($memberReqs.Count -gt 0) {
            $memberResp = Invoke-HD365GraphBatch -Requests @($memberReqs)
            foreach ($mr in $memberResp) {
                if ([int]$mr.status -ge 200 -and [int]$mr.status -lt 300) { $nestedOk++ }
            }
        }

        $pct = [int](($done / [double]$total) * 100)
        Write-Host ("  Progress: {0}/{1} ({2}%)  created={3}  skipped={4}  failed={5}" -f $done, $total, $pct, $created.Count, $skipped, $failed.Count) -ForegroundColor DarkGray
    }

    Write-Host ("Done. Created={0}  Nested={1}  Skipped={2}  Failed={3}" -f $created.Count, $nestedOk, $skipped, $failed.Count) -ForegroundColor Green
    if ($failed.Count -gt 0) {
        $failed | Select-Object -First 15 | Format-Table -AutoSize | Out-String | Write-Host
    }

    return [pscustomobject]@{
        Created = $created.Count
        Nested  = $nestedOk
        Skipped = $skipped
        Failed  = $failed.Count
        Items   = @($created)
        Errors  = @($failed)
    }
}
