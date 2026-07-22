function Save-HD365ScriptArtifact {
    <#
    .SYNOPSIS
      Persist a solution script to disk for copy/run without flooding the console.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ScriptText,

        [string]$Prefix = 'solution'
    )

    $dir = Join-Path $env:LOCALAPPDATA 'HD365\scripts'
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss')
    $path = Join-Path $dir ("hd365-{0}-{1}.ps1" -f $Prefix, $stamp)
    Set-Content -LiteralPath $path -Value $ScriptText -Encoding UTF8
    return $path
}

function Show-HD365ScriptPreview {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ScriptText,

        [string]$ScriptPath,

        [int]$PreviewChars = 700,

        [int]$OperationCount = 0
    )

    $len = $ScriptText.Length
    Write-Host "-- Solution script (copy/paste ready) --" -ForegroundColor DarkCyan

    if ($len -le $PreviewChars) {
        Write-Host $ScriptText -ForegroundColor White
    }
    else {
        $preview = $ScriptText.Substring(0, $PreviewChars)
        Write-Host $preview -ForegroundColor White
        Write-Host ""
        Write-Host ("... truncated preview ({0:N0} chars total). Full script on disk:" -f $len) -ForegroundColor Yellow
        if ($ScriptPath) {
            Write-Host "  $ScriptPath" -ForegroundColor Green
        }
        Write-Host "  Use /copy to place the FULL script on the clipboard." -ForegroundColor DarkGray
    }

    if ($OperationCount -gt 0) {
        Write-Host ("Operations planned: {0}" -f $OperationCount) -ForegroundColor Cyan
    }
    Write-Host ""
}

function ConvertTo-HD365PsStringLiteral {
    param([string]$Value)
    if ($null -eq $Value) { return "''" }
    return ("'{0}'" -f ($Value -replace "'", "''"))
}

function ConvertTo-HD365CompactParentArray {
    param([object[]]$Parents)

    $parts = foreach ($p in $Parents) {
        $id = ConvertTo-HD365PsStringLiteral ([string]$p.Id)
        $display = if ($p.DisplayName) { [string]$p.DisplayName } elseif ($p.Name) { [string]$p.Name } else { '' }
        $name = ConvertTo-HD365PsStringLiteral $display
        $abbrVal = if ($p.Abbr) { [string]$p.Abbr } else { Get-HD365ParentStateAbbreviation -ParentDisplayName $display }
        $abbr = ConvertTo-HD365PsStringLiteral $abbrVal
        "[pscustomobject]@{Id=$id;Name=$name;Abbr=$abbr}"
    }
    return (@($parts) -join ',')
}

function ConvertTo-HD365CompactDeptArray {
    param([string[]]$ChildNames)

    $parts = foreach ($c in $ChildNames) {
        $name = ConvertTo-HD365PsStringLiteral $c
        $code = ConvertTo-HD365PsStringLiteral (Get-HD365DepartmentCode -DisplayName $c)
        "[pscustomobject]@{Name=$name;Code=$code}"
    }
    return (@($parts) -join ',')
}
