[CmdletBinding()]
param(
    [string] $OutputPath = (Join-Path $PSScriptRoot '../../artifacts/careoncloud-cpan-sbom.cdx.json')
)

$ErrorActionPreference = 'Stop'
$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$SnapshotPath = Join-Path $RepositoryRoot 'cpanfile.docker.snapshot'
$Snapshot = Get-Content -LiteralPath $SnapshotPath
$Distributions = foreach ($Line in $Snapshot) {
    if ($Line -match '^  ([A-Za-z0-9_]+(?:-[A-Za-z0-9_]+)*)-([0-9][A-Za-z0-9._-]*)$') {
        [pscustomobject]@{ Name = $Matches[1]; Version = $Matches[2] }
    }
}

if (-not $Distributions) {
    throw 'No CPAN distributions were found in cpanfile.docker.snapshot.'
}

$Components = foreach ($Distribution in $Distributions | Sort-Object Name, Version -Unique) {
    [ordered]@{
        type = 'library'
        name = $Distribution.Name
        version = $Distribution.Version
        purl = "pkg:cpan/$($Distribution.Name)@$($Distribution.Version)"
        properties = @(
            [ordered]@{ name = 'careoncloud:source-lock'; value = 'cpanfile.docker.snapshot' }
        )
    }
}

$Bom = [ordered]@{
    bomFormat = 'CycloneDX'
    specVersion = '1.5'
    serialNumber = 'urn:uuid:00000000-0000-0000-0000-000000000000'
    version = 1
    metadata = [ordered]@{
        component = [ordered]@{
            type = 'application'
            name = 'CareOnCloud ESM CPAN build dependencies'
            version = '11.1.x'
        }
        properties = @(
            [ordered]@{ name = 'careoncloud:scope'; value = 'CPAN distributions locked for careoncloud.web.dockerfile build' }
        )
    }
    components = @($Components)
}

$TargetDirectory = Split-Path -Parent $OutputPath
New-Item -ItemType Directory -Force -Path $TargetDirectory | Out-Null
[System.IO.File]::WriteAllText(
    (Resolve-Path $TargetDirectory).Path + [System.IO.Path]::DirectorySeparatorChar + (Split-Path -Leaf $OutputPath),
    (($Bom | ConvertTo-Json -Depth 12) + [Environment]::NewLine),
    [System.Text.UTF8Encoding]::new($false)
)

Write-Output "Generated CPAN CycloneDX SBOM with $($Components.Count) components: $OutputPath"
