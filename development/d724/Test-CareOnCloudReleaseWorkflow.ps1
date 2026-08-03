[CmdletBinding()]
param(
    [string] $WorkflowPath
)

$ErrorActionPreference = 'Stop'
if (-not $WorkflowPath) {
    $WorkflowPath = Join-Path $PSScriptRoot '../../.github/workflows/careoncloud-release.yml'
}
$Workflow = Get-Content -Raw -LiteralPath $WorkflowPath
$Required = @(
    'name: CareOnCloud release image'
    "file: careoncloud.web.dockerfile"
    'target: careoncloud-web'
    'registry: ghcr.io'
    'docker/setup-buildx-action@v3'
    'cache-from: type=gha,scope=careoncloud-web'
    'cache-to: type=gha,mode=max,scope=careoncloud-web'
    'anchore/sbom-action@'
    'sigstore/cosign-installer@'
    'cosign sign --yes'
    'id-token: write'
)
foreach ($Pattern in $Required) {
    if ($Workflow -notlike "*$Pattern*") {
        throw "CareOnCloud release workflow is missing: $Pattern"
    }
}
if ($Workflow -match 'rotheross/otobo|otobo\.web\.dockerfile|target:\s*otobo') {
    throw 'CareOnCloud release workflow contains an upstream OTOBO image target.'
}
Write-Output 'CareOnCloud release workflow contract passed.'
