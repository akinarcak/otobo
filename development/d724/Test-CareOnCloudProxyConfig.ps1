[CmdletBinding()]
param(
    [string] $ConfigurationPath
)

$ErrorActionPreference = 'Stop'
if (-not $ConfigurationPath) {
    $ConfigurationPath = Join-Path $PSScriptRoot '../../scripts/apache2-httpd-careoncloud-plack-proxy.include.conf'
}
$Configuration = Get-Content -Raw -LiteralPath $ConfigurationPath
$Required = @(
    'Alias /careoncloud-web/'
    'ProxyPass        "/careoncloud/"'
    'ProxyPassReverse "/careoncloud/"'
    'http://127.0.0.1:5000/careoncloud/'
)
foreach ($Pattern in $Required) {
    if ($Configuration -notlike "*$Pattern*") {
        throw "CareOnCloud proxy contract is missing: $Pattern"
    }
}
if ($Configuration -match '(?m)^\s*(Alias|ProxyPass|ProxyPassReverse)\s+"?/careoncloud/') {
    throw 'CareOnCloud proxy contract must not expose the legacy /careoncloud/ route.'
}
Write-Output 'CareOnCloud canonical proxy contract passed.'
