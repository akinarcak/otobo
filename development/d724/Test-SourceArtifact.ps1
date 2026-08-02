[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$OutputDirectory = Join-Path ([System.IO.Path]::GetTempPath()) "careoncloud-source-artifact-$PID"
try {
    & (Join-Path $PSScriptRoot 'Generate-SourceArtifact.ps1') -OutputDirectory $OutputDirectory
    if ($LASTEXITCODE -ne 0) { throw "Source artifact generator failed with exit code $LASTEXITCODE." }
    $ManifestFile = Get-ChildItem $OutputDirectory -Filter '*.manifest.json' | Select-Object -First 1
    if (!$ManifestFile) { throw 'Source artifact manifest was not generated.' }
    $Manifest = Get-Content $ManifestFile.FullName -Raw | ConvertFrom-Json
    $ExpectedCommit = (& git -C $RepositoryRoot rev-parse HEAD).Trim()
    if ($Manifest.schema -ne 'careoncloud-esm-source-artifact/v1' -or $Manifest.git_commit -ne $ExpectedCommit) {
        throw 'Source artifact manifest does not attest the current Git commit.'
    }
    $ArchivePath = Join-Path $OutputDirectory $Manifest.archive.file
    if (!(Test-Path $ArchivePath) -or (Get-FileHash -Algorithm SHA256 -LiteralPath $ArchivePath).Hash.ToLowerInvariant() -ne $Manifest.archive.sha256) {
        throw 'Source artifact archive hash does not match its manifest.'
    }
    if (@($Manifest.packages).Count -ne @(Get-ChildItem (Join-Path $RepositoryRoot 'packages') -Recurse -Filter '*.sopm').Count) {
        throw 'Source artifact manifest package inventory is incomplete.'
    }
    Write-Output "Source artifact contract passed for $($Manifest.git_commit)."
}
finally {
    Remove-Item -LiteralPath $OutputDirectory -Recurse -Force -ErrorAction SilentlyContinue
}
