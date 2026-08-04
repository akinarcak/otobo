[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$OutputPath = Join-Path ([System.IO.Path]::GetTempPath()) "careoncloud-cpan-sbom-$PID.json"
try {
    & (Join-Path $PSScriptRoot 'Generate-CpanSbom.ps1') -OutputPath $OutputPath
    if ($null -ne $LASTEXITCODE -and $LASTEXITCODE -ne 0) { throw "SBOM generator failed with exit code $LASTEXITCODE." }
    $Bom = Get-Content -LiteralPath $OutputPath -Raw | ConvertFrom-Json
    if ($Bom.bomFormat -ne 'CycloneDX' -or $Bom.specVersion -ne '1.5') {
        throw 'Generated SBOM is not CycloneDX 1.5.'
    }
    if ($Bom.components.Count -lt 1) { throw 'Generated SBOM has no components.' }
    $SnapshotDistributionCount = @(Get-Content (Join-Path $RepositoryRoot 'cpanfile.docker.snapshot') | Where-Object {
        $_ -match '^  [A-Za-z0-9_]+(?:-[A-Za-z0-9_]+)*-[0-9][A-Za-z0-9._-]*$'
    }).Count
    if ($Bom.components.Count -ne $SnapshotDistributionCount) {
        throw "Generated SBOM component count $($Bom.components.Count) differs from snapshot distribution count $SnapshotDistributionCount."
    }
    foreach ($Component in $Bom.components) {
        if ($Component.type -ne 'library' -or !$Component.name -or !$Component.version -or $Component.purl -notmatch '^pkg:cpan/') {
            throw 'Generated SBOM contains an incomplete CPAN component.'
        }
    }
    Write-Output "CPAN CycloneDX SBOM contract passed with $($Bom.components.Count) components."
}
finally {
    Remove-Item -LiteralPath $OutputPath -Force -ErrorAction SilentlyContinue
}
