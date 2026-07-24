[CmdletBinding()]
param(
    [switch] $RequireDocker
)

$ErrorActionPreference = 'Stop'
$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$RequiredFiles = @(
    'LICENSE',
    'COPYING-Third-Party',
    'docs/esm/PRODUCT.md',
    'docs/esm/ARCHITECTURE.md',
    'docs/esm/ROADMAP.md',
    'docs/esm/GPL-COMMERCIAL.md',
    'development/d724/compose.yml',
    'development/d724/.env.example',
    'packages/D724Foundation/D724Foundation.sopm'
)

$MissingFiles = $RequiredFiles | Where-Object { -not (Test-Path (Join-Path $RepositoryRoot $_)) }
if ($MissingFiles) {
    throw "Required foundation files are missing: $($MissingFiles -join ', ')"
}

$PackageSources = Get-ChildItem (Join-Path $RepositoryRoot 'packages') -Filter '*.sopm' -Recurse
if (-not $PackageSources) {
    throw 'No D724 package sources were found.'
}
foreach ($PackageSourceFile in $PackageSources) {
    $PackageDirectory = $PackageSourceFile.Directory.FullName
    [xml] $PackageSource = Get-Content $PackageSourceFile.FullName -Raw
    $PackageName = [string] $PackageSource.otobo_package.Name
    if ($PackageName -ne $PackageSourceFile.Directory.Name) {
        throw "Package name and directory differ: $PackageName"
    }
    if ($PackageSource.otobo_package.License -notmatch 'GENERAL PUBLIC LICENSE Version 3') {
        throw "$PackageName must declare GPL version 3."
    }
    foreach ($File in $PackageSource.otobo_package.Filelist.File) {
        $PackageFile = Join-Path $PackageDirectory $File.Location
        if (-not (Test-Path $PackageFile -PathType Leaf)) {
            throw "$PackageName file list entry is missing: $($File.Location)"
        }
        $RepositoryRelativePath = "packages/$PackageName/$($File.Location)"
        & git -C $RepositoryRoot ls-files --error-unmatch -- $RepositoryRelativePath 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "$PackageName file list entry is not tracked by Git: $RepositoryRelativePath"
        }
        if ($File.Location -match '\.xml$') {
            [xml] (Get-Content $PackageFile -Raw) | Out-Null
        }
    }
}

$ComposeText = Get-Content (Join-Path $PSScriptRoot 'compose.yml') -Raw
if ($ComposeText -notmatch '\$\{D724_BIND_ADDRESS:-127\.0\.0\.1\}') {
    throw 'Compose must default its HTTP bind address to localhost.'
}
$ForbiddenPatterns = @(
    '(?im)^\s*(?:MYSQL_ROOT_PASSWORD|D724_DB_ROOT_PASSWORD)\s*:\s*(?!\$\{)\S+',
    '(?i)password\s*[:=]\s*(?:admin|password|changeme|tes)\b',
    '(?i)ports:\s*\r?\n\s*-\s*["'']?(?:0\.0\.0\.0:)?(?:3306|9200):'
)
foreach ($Pattern in $ForbiddenPatterns) {
    if ($ComposeText -match $Pattern) {
        throw "Unsafe Compose configuration matched: $Pattern"
    }
}

if ($RequireDocker) {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        throw 'Docker is required for this validation mode.'
    }

    $TemporaryEnvironment = Join-Path ([System.IO.Path]::GetTempPath()) "d724-compose-$PID.env"
    try {
        @(
            'D724_DB_ROOT_PASSWORD=ci-validation-only-password',
            'D724_HTTP_PORT=8080'
        ) | Set-Content $TemporaryEnvironment

        & docker compose --project-directory $PSScriptRoot --env-file $TemporaryEnvironment -f (Join-Path $PSScriptRoot 'compose.yml') config --quiet
        if ($LASTEXITCODE -ne 0) {
            throw "docker compose config failed with exit code $LASTEXITCODE."
        }
    }
    finally {
        Remove-Item $TemporaryEnvironment -Force -ErrorAction SilentlyContinue
    }
}

Write-Host 'D724 ESM foundation checks passed.'
