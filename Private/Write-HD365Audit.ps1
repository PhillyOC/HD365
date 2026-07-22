function Write-HD365Audit {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Proposal', 'Gather', 'ExecuteRead', 'ExecuteWrite', 'Auth', 'Error', 'Cancel', 'Session', 'Solution')]
        [string]$EventType,

        [hashtable]$Data = @{},

        [string]$ScriptText,

        [bool]$IsWrite = $false
    )

    $config = $script:HD365Config
    if (-not $config -or -not $config.audit.enabled) { return }

    $dir = $config.audit.directory
    if (-not $dir) { return }
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $day = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd')
    $file = Join-Path $dir "hd365-audit-$day.jsonl"

    $entry = [ordered]@{
        timestampUtc = (Get-Date).ToUniversalTime().ToString('o')
        sessionId    = $script:HD365Session.Id
        operator     = $script:HD365Session.Operator
        machine      = $script:HD365Session.Machine
        eventType    = $EventType
        phase        = $script:HD365Session.Phase
        isWrite      = $IsWrite
        graphMode    = $script:HD365Session.GraphMode
        scriptSha256 = $null
        scriptText   = $ScriptText
        data         = $Data
    }

    if ($ScriptText) {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($ScriptText)
        $hash = [System.Security.Cryptography.SHA256]::Create().ComputeHash($bytes)
        $entry.scriptSha256 = ([BitConverter]::ToString($hash) -replace '-', '').ToLowerInvariant()
    }

    $line = ($entry | ConvertTo-Json -Compress -Depth 8)
    Add-Content -LiteralPath $file -Value $line -Encoding UTF8

    if ($EventType -eq 'ExecuteWrite') {
        $writeFile = Join-Path $dir 'hd365-writes.jsonl'
        Add-Content -LiteralPath $writeFile -Value $line -Encoding UTF8
    }

    # Never leak path to the host pipeline / console
    return
}
