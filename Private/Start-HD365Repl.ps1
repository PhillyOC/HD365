function Start-HD365Repl {
    [CmdletBinding()]
    param()

    Show-HD365Banner
    [void](Write-HD365Audit -EventType Session -Data @{ action = 'start' })

    $historyLimit = 50
    if ($script:HD365Config.session.historySize) {
        $historyLimit = [int]$script:HD365Config.session.historySize
    }

    while ($true) {
        $phase = $script:HD365Session.Phase
        if (-not $phase) { $phase = 'Ready' }
        $promptColor = switch ($phase) {
            'Discovery' { 'DarkCyan' }
            'Solution'  { 'Yellow' }
            'Execute'   { 'Red' }
            default     { 'Cyan' }
        }

        Write-Host -NoNewline "HD365:$phase> " -ForegroundColor $promptColor
        $line = Read-Host
        if ($null -eq $line) { continue }
        $line = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($line)) { continue }

        if ($line -match '^/(quit|exit)$') {
            Write-HD365Audit -EventType Session -Data @{ action = 'quit' }
            Write-Host "Goodbye." -ForegroundColor DarkGray
            break
        }

        if ($line -match '^/help$') { Show-HD365Help; continue }

        if ($line -match '^/ai(\s+(?<name>\S+))?$') {
            $target = $Matches['name']
            $catalog = @(Get-HD365ProviderCatalog)

            if ($target) {
                $match = $catalog | Where-Object { $_.Id -ieq $target } | Select-Object -First 1
                if (-not $match) {
                    Write-Host "Unknown provider '$target'. Type /ai to see the list." -ForegroundColor Red
                    continue
                }
                $script:HD365Config.ai.provider = $match.Id
                try { Save-HD365Config | Out-Null } catch { Write-Host "Warning: could not save settings.json: $($_.Exception.Message)" -ForegroundColor Yellow }
                Write-Host "AI provider set to $($match.DisplayName) ($($match.Id))." -ForegroundColor Green
            }

            $aiStatus = Get-HD365AiStatusWithProbe
            $aiStatus | Format-List | Out-String | Write-Host

            Write-Host "Available AI providers:" -ForegroundColor Cyan
            $menu = @{}
            $i = 1
            foreach ($p in $catalog) {
                $ready = Test-HD365ProviderConfigured -Id $p.Id
                $mark = if ($ready) { '[ready]      ' } else { '[needs setup]' }
                $active = if ($p.Id -eq [string]$aiStatus.Provider) { '  <- active' } else { '' }
                Write-Host ("  {0}. {1,-12} {2}  {3}{4}" -f $i, $p.Id, $mark, $p.DisplayName, $active)
                $menu[[string]$i] = $p.Id
                $i++
            }
            Write-Host ""

            if (-not (Test-HD365AiConfigured)) {
                Show-HD365AiSetupHelp
            }
            elseif ([string]$aiStatus.Provider -eq 'CopilotChat' -and [string]$aiStatus.CopilotApi -notmatch '^OK') {
                Show-HD365AiSetupHelp -ErrorMessage ([string]$aiStatus.CopilotApiDetail)
            }

            if (-not $target) {
                Write-Host "Switch: type a number or name (e.g. /ai Ollama), or press Enter to keep current." -ForegroundColor DarkYellow
                Write-Host -NoNewline "Provider> " -ForegroundColor Cyan
                $choice = Read-Host
                if (-not [string]::IsNullOrWhiteSpace($choice)) {
                    $choice = $choice.Trim()
                    $newId = $null
                    if ($menu.ContainsKey($choice)) { $newId = $menu[$choice] }
                    else {
                        $m2 = $catalog | Where-Object { $_.Id -ieq $choice } | Select-Object -First 1
                        if ($m2) { $newId = $m2.Id }
                    }
                    if (-not $newId) {
                        Write-Host "Not recognized; provider unchanged." -ForegroundColor Yellow
                    }
                    else {
                        $script:HD365Config.ai.provider = $newId
                        try { Save-HD365Config | Out-Null } catch { Write-Host "Warning: could not save settings.json: $($_.Exception.Message)" -ForegroundColor Yellow }
                        Write-Host "AI provider set to $newId." -ForegroundColor Green
                        if (-not (Test-HD365AiConfigured)) { Show-HD365AiSetupHelp }
                    }
                }
            }
            continue
        }

        if ($line -match '^/status$') {
            $ctx = $null
            try { $ctx = Get-MgContext -ErrorAction SilentlyContinue } catch {}
            [pscustomobject]@{
                SessionId      = $script:HD365Session.Id
                Phase          = $script:HD365Session.Phase
                GraphMode      = $script:HD365Session.GraphMode
                GraphAccount   = if ($ctx) { $ctx.Account } else { $null }
                ExoConnected   = $script:HD365Session.ExoConnected
                AdAvailable    = $script:HD365Session.AdAvailable
                HasSolution    = [bool]$script:HD365Session.PendingProposal
                ConfigPath     = $script:HD365ConfigPath
                AuditDirectory = $script:HD365Config.audit.directory
            } | Format-List | Out-String | Write-Host
            continue
        }

        if ($line -match '^/auth(\s+(?<mode>read|write))?$') {
            $mode = if ($Matches['mode']) { (Get-Culture).TextInfo.ToTitleCase($Matches['mode']) } else { 'Read' }
            try { Connect-HD365Graph -Mode $mode | Out-Null } catch { Write-Host $_.Exception.Message -ForegroundColor Red }
            continue
        }

        if ($line -match '^/exo$') {
            try { Connect-HD365Exchange } catch { Write-Host $_.Exception.Message -ForegroundColor Red }
            continue
        }

        if ($line -match '^/cancel$') {
            $script:HD365Session.PendingProposal = $null
            $script:HD365Session.Phase = 'Ready'
            Write-HD365Audit -EventType Cancel -Data @{ reason = 'user_cancel' }
            Write-Host "Pending solution cleared." -ForegroundColor DarkGray
            continue
        }

        if ($line -match '^/copy$') {
            $p = $script:HD365Session.PendingProposal
            if (-not $p) { Write-Host "Nothing to copy." -ForegroundColor Yellow; continue }
            $text = $null
            if ($p.ScriptPath -and (Test-Path -LiteralPath $p.ScriptPath)) {
                $text = Get-Content -LiteralPath $p.ScriptPath -Raw -Encoding UTF8
            }
            if (-not $text) {
                $text = ConvertTo-HD365OneLiner -ScriptText ([string]$p.ExecutionScript)
            }
            try {
                Set-Clipboard -Value $text.Trim()
                Write-Host ("Solution script copied to clipboard ({0:N0} chars)." -f $text.Length) -ForegroundColor Green
                if ($p.ScriptPath) { Write-Host "File: $($p.ScriptPath)" -ForegroundColor DarkGray }
            }
            catch {
                Write-Host "Clipboard unavailable. Script file:" -ForegroundColor Yellow
                if ($p.ScriptPath) { Write-Host $p.ScriptPath } else { Write-Host $text }
            }
            continue
        }

        if ($line -match '^/edit$') {
            $p = $script:HD365Session.PendingProposal
            if (-not $p) { Write-Host "No solution to edit." -ForegroundColor Yellow; continue }
            $text = ConvertTo-HD365OneLiner -ScriptText ([string]$p.ExecutionScript)
            $temp = Join-Path $env:TEMP ("hd365-edit-{0}.ps1" -f [guid]::NewGuid().ToString('N'))
            Set-Content -LiteralPath $temp -Value $text -Encoding UTF8
            Write-Host "Opening editor. Keep as one line if possible. Save and close..." -ForegroundColor Cyan
            Start-Process -FilePath notepad.exe -ArgumentList $temp -Wait
            $newText = ConvertTo-HD365OneLiner -ScriptText (Get-Content -LiteralPath $temp -Raw -Encoding UTF8)
            $p.ExecutionScript = $newText
            Write-Host "Solution updated:" -ForegroundColor Green
            Write-Host $p.ExecutionScript -ForegroundColor White
            continue
        }

        if ($line -match '^/approve$') {
            Write-Host "No separate approve step - the on-screen solution is the review. Type /run to execute." -ForegroundColor DarkYellow
            continue
        }

        if ($line -match '^/(run|r)$') {
            Invoke-HD365ApprovedRun
            continue
        }

        if ($line -match '^/audit(\s+(?<n>\d+))?$') {
            $n = 20
            if ($Matches['n']) { $n = [int]$Matches['n'] }
            $dir = $script:HD365Config.audit.directory
            $files = Get-ChildItem -LiteralPath $dir -Filter 'hd365-audit-*.jsonl' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
            if (-not $files) { Write-Host "No audit files yet in $dir" -ForegroundColor Yellow; continue }
            $lines = Get-Content -LiteralPath $files[0].FullName -Encoding UTF8 -ErrorAction SilentlyContinue
            $lines | Select-Object -Last $n | ForEach-Object {
                try {
                    $o = $_ | ConvertFrom-Json
                    '{0}  {1,-14}  write={2}  {3}' -f $o.timestampUtc, $o.eventType, $o.isWrite, ($(if ($o.data.summary) { $o.data.summary } elseif ($o.data.action) { $o.data.action } else { $o.scriptSha256 }))
                }
                catch { $_ }
            }
            Write-Host ""
            Write-Host "Write trail: $(Join-Path $dir 'hd365-writes.jsonl')" -ForegroundColor DarkGray
            continue
        }

        # Natural language -> automatic discovery + solution
        try {
            $hist = @($script:HD365Session.History | Select-Object -Last ([Math]::Max(0, $historyLimit - 1)))
            $pending = Invoke-HD365Pipeline -UserMessage $line -History $hist

            $assistantCompact = ($pending.Proposal | ConvertTo-Json -Compress -Depth 6)
            $script:HD365Session.History.Add([pscustomobject]@{ user = $line; assistant = $assistantCompact })
            while ($script:HD365Session.History.Count -gt $historyLimit) {
                $script:HD365Session.History.RemoveAt(0)
            }
        }
        catch {
            Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
            Write-HD365Audit -EventType Error -Data @{ error = $_.Exception.Message; user = $line }
            $script:HD365Session.Phase = 'Ready'
        }
    }
}
