function New-HD365CompactNestedScript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ParentsPs,

        [Parameter(Mandatory)]
        [string]$DeptsPs,

        [bool]$NestMembership = $true
    )

    # Readable multi-line source, then collapsed to one-liner for clipboard.
    # Idempotent: skips names that already exist (best-effort filter).
    $nestLine = ''
    if ($NestMembership) {
        $nestLine = 'New-MgGroupMember -GroupId $p.Id -DirectoryObjectId $g.Id -ErrorAction SilentlyContinue; '
    }

    $script = @"
`$parents=@($ParentsPs); `$depts=@($DeptsPs); foreach(`$p in `$parents){ foreach(`$d in `$depts){ `$name=(`$p.Name + ' - ' + `$d.Name); `$nick=(`$p.Abbr + '-' + `$d.Code); `$esc=(`$name -replace "'","''"); if(Get-MgGroup -Filter "displayName eq '`$esc'" -ErrorAction SilentlyContinue){ continue }; `$g=New-MgGroup -DisplayName `$name -MailEnabled:`$false -MailNickname `$nick -SecurityEnabled:`$true; ${nestLine}[pscustomobject]@{DisplayName=`$g.DisplayName; Id=`$g.Id; ParentId=`$p.Id; MailNickname=`$g.MailNickname} } }
"@

    return (ConvertTo-HD365OneLiner -ScriptText $script.Trim())
}
