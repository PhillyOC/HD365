$ErrorActionPreference = 'Stop'
try {
    Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
}
catch {
    Write-Host 'Microsoft.Graph.Authentication missing. Run .\Install-HD365.ps1 first.' -ForegroundColor Yellow
    exit 2
}
$root = if ($PSScriptRoot) { Split-Path $PSScriptRoot -Parent } else { 'C:\HD365' }
Get-ChildItem (Join-Path $root 'Private\*.ps1') | ForEach-Object { . $_.FullName }
$script:HD365Root = $root
Initialize-HD365Session | Out-Null

$ctx = Get-MgContext -ErrorAction SilentlyContinue
if (-not $ctx) {
    Write-Host 'GRAPH_NOT_CONNECTED - run HD365 /auth read first, then re-run this probe.' -ForegroundColor Yellow
    exit 2
}

Write-Host ("Graph account: " + $ctx.Account) -ForegroundColor Cyan
Write-Host ("Scopes: " + @($ctx.Scopes).Count) -ForegroundColor DarkGray

$prompt = @'
Return ONLY this JSON object and nothing else:
{"summary":"copilot-probe","intent":"read","platform":"Microsoft Graph","modules":["Microsoft.Graph.Groups"],"leastScopes":["Group.Read.All"],"rolesNeeded":[],"phase":"discovery","discoveryScript":"Get-MgGroup -Top 1 -Property Id,DisplayName | Select-Object Id,DisplayName","executionScript":"","isWrite":false,"warnings":[],"clarifyingQuestions":[],"displayHints":"","expectedCount":null,"job":null}
'@

try {
    $text = Invoke-HD365CopilotChat -Message $prompt -SystemPreamble 'You are a JSON API. Reply with one JSON object only.'
    Write-Host '--- Copilot text (truncated) ---' -ForegroundColor DarkGray
    Write-Host $text.Substring(0, [Math]::Min(500, $text.Length))
    $obj = ConvertFrom-HD365AiJson -Content $text
    if ($obj.summary -ne 'copilot-probe' -and -not $obj.discoveryScript) {
        throw "Unexpected JSON keys: $(( $obj.PSObject.Properties.Name ) -join ',')"
    }
    Write-Host 'COPILOT_PROBE_OK' -ForegroundColor Green
    Write-Host ("summary=" + $obj.summary)
    exit 0
}
catch {
    Write-Host ('COPILOT_PROBE_FAIL: ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
