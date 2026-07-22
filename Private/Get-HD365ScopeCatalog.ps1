function Get-HD365ScopeCatalog {
    [CmdletBinding()]
    param()

    $path = Join-Path $script:HD365Root 'Config\scopes.json'
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Scope catalog missing: $path"
    }

    if (-not $script:HD365ScopeCatalog) {
        $script:HD365ScopeCatalog = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    }

    return $script:HD365ScopeCatalog
}

function Get-HD365ReadScopes {
    [CmdletBinding()]
    param()
    return @( (Get-HD365ScopeCatalog).readScopes )
}

function Get-HD365WriteScopes {
    [CmdletBinding()]
    param()
    $catalog = Get-HD365ScopeCatalog
    return @($catalog.readScopes + $catalog.writeScopes | Select-Object -Unique)
}

function Test-HD365IsWriteScope {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Scopes
    )

    $write = @((Get-HD365ScopeCatalog).writeScopes)
    foreach ($s in $Scopes) {
        if ($write -contains $s) { return $true }
    }
    return $false
}
