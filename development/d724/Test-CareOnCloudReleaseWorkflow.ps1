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
    'docker/setup-buildx-action@v4'
    'docker/build-push-action@v7'
    'cache-from: type=gha,scope=careoncloud-web'
    'cache-to: type=gha,mode=max,scope=careoncloud-web'
    'anchore/sbom-action@'
    'name: Generate CycloneDX SBOM'
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

# Regression guard. A per-release DOCKER_TAG build-arg is consumed by the
# `carton install` layer of careoncloud.web.dockerfile and therefore invalidates
# the CPAN cache on every release build. Measured in run 30882609007: base layers
# 1/7..6/7 were CACHED while 7/7 reinstalled 213 CPAN distributions in 211.9s.
# The Dockerfile default `unspecified` already selects `carton install --deployment`,
# so passing the tag buys nothing. See docs/esm/NOTES-FOR-CODEX.md.
if ($Workflow -match 'DOCKER_TAG=') {
    throw 'CareOnCloud release workflow passes a DOCKER_TAG build-arg, which invalidates the cached CPAN layer on every build.'
}
Write-Output 'CareOnCloud release workflow contract passed.'
