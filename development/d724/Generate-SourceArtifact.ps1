[CmdletBinding()]
param(
    [string] $OutputDirectory = (Join-Path $PSScriptRoot '../../artifacts'),
    [string] $Ref = 'HEAD'
)

$ErrorActionPreference = 'Stop'
$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$Status = @(& git -C $RepositoryRoot status --short)
if ($Status) {
    throw 'A release source artifact requires a clean Git working tree.'
}

$Commit = (& git -C $RepositoryRoot rev-parse "$Ref^{commit}").Trim()
if ($Commit -notmatch '\A[0-9a-f]{40}\z') {
    throw "Could not resolve a commit for ref: $Ref"
}
$ShortCommit = $Commit.Substring(0, 12)
$ArchiveName = "careoncloud-esm-source-$ShortCommit.zip"
$ManifestName = "careoncloud-esm-source-$ShortCommit.manifest.json"
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$ArchivePath = Join-Path $OutputDirectory $ArchiveName
$ManifestPath = Join-Path $OutputDirectory $ManifestName

& git -C $RepositoryRoot archive --format=zip --prefix="careoncloud-esm-$ShortCommit/" --output=$ArchivePath $Commit
if ($LASTEXITCODE -ne 0) {
    throw "git archive failed with exit code $LASTEXITCODE."
}

$PackageVersions = @(
    Get-ChildItem (Join-Path $RepositoryRoot 'packages') -Recurse -Filter '*.sopm' |
        ForEach-Object {
            [xml] $Package = Get-Content $_.FullName -Raw
            [ordered]@{
                name = [string] $Package.careoncloud_package.Name
                version = [string] $Package.careoncloud_package.Version
            }
        } |
        Sort-Object name
)
$Manifest = [ordered]@{
    schema = 'careoncloud-esm-source-artifact/v1'
    git_commit = $Commit
    archive = [ordered]@{
        file = $ArchiveName
        sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $ArchivePath).Hash.ToLowerInvariant()
        format = 'zip'
    }
    packages = $PackageVersions
}
[System.IO.File]::WriteAllText(
    $ManifestPath,
    (($Manifest | ConvertTo-Json -Depth 8) + [Environment]::NewLine),
    [System.Text.UTF8Encoding]::new($false)
)
Write-Output "Generated source artifact and manifest for $Commit: $ArchivePath"
