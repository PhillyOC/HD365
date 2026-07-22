function ConvertTo-HD365OneLiner {
    <#
    .SYNOPSIS
      Collapse a PowerShell script to a single copy/paste-friendly line.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowEmptyString()]
        [string]$ScriptText
    )

    if ([string]::IsNullOrWhiteSpace($ScriptText)) { return '' }

    $lines = $ScriptText -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object {
        $_ -and ($_ -notmatch '^\s*#')
    }

    $joined = ($lines -join '; ').Trim()
    $joined = $joined -replace '\s*;\s*', '; '
    $joined = $joined -replace '\s+', ' '
    return $joined.Trim().TrimEnd(';')
}

function Format-HD365GuidList {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Ids
    )

    $quoted = $Ids | Where-Object { $_ } | ForEach-Object { "'$_'" }
    return (@($quoted) -join ',')
}
