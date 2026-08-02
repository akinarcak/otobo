[CmdletBinding()]
param(
    [switch] $RequireDocker
)

$ErrorActionPreference = 'Stop'
$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$RequiredFiles = @(
    'LICENSE',
    'SECURITY.md',
    'COPYING-Third-Party',
    'docs/esm/PRODUCT.md',
    'docs/esm/ARCHITECTURE.md',
    'docs/esm/ROADMAP.md',
    'docs/esm/GPL-COMMERCIAL.md',
    'docs/esm/security/TENANT-PATH-MATRIX.md',
    'docs/esm/branding/MIGRATION-SAFETY.md',
    'development/d724/compose.yml',
    'development/d724/.env.example',
    'development/d724/Test-CleanPackageLifecycle.ps1',
    'development/d724/Test-CareOnCloudBrand.ps1',
    'development/d724/Test-CriticalLanguage.ps1',
    'development/d724/Generate-CpanSbom.ps1',
    'development/d724/Test-CpanSbom.ps1',
    'development/d724/migrate-careoncloud-brand.sh',
    'development/d724/Accept-GenericInterfaceTicketUpdate.pl',
    'development/d724/Accept-SchedulerTicketPendingCheck.pl',
    'packages/D724Foundation/D724Foundation.sopm'
)

$MissingFiles = $RequiredFiles | Where-Object { -not (Test-Path (Join-Path $RepositoryRoot $_)) }
if ($MissingFiles) {
    throw "Required foundation files are missing: $($MissingFiles -join ', ')"
}

$LicensePolicyFiles = @(
    'README.md',
    'NOTICE',
    'docs/esm/GPL-COMMERCIAL.md'
)
foreach ($RelativePath in $LicensePolicyFiles) {
    $PolicyText = Get-Content (Join-Path $RepositoryRoot $RelativePath) -Raw
    if ($PolicyText -notmatch 'GPL-3\.0-only') {
        throw "License policy is not explicit in $RelativePath."
    }
    if ($PolicyText -match 'GPL-3\.0-or-later') {
        throw "License policy conflicts with GPL-3.0-only in $RelativePath."
    }
}

$SecurityPolicy = Get-Content (Join-Path $RepositoryRoot 'SECURITY.md') -Raw
$RequiredSecurityPolicyTerms = @(
    'github.com/akinarcak/otobo/security/advisories/new',
    'within three business days',
    'within seven calendar days',
    'CVE assignment',
    'Managed customers',
    'candidate builds',
    'not excluded because this repository is a fork'
)
foreach ($Term in $RequiredSecurityPolicyTerms) {
    if ($SecurityPolicy -notmatch [regex]::Escape($Term)) {
        throw "Security policy is missing required term: $Term"
    }
}
foreach ($ForbiddenTerm in @('security@otobo.org', 'forks of OTOBO', 'OTOBO Team Vulnerability Disclosure Policy')) {
    if ($SecurityPolicy -match [regex]::Escape($ForbiddenTerm)) {
        throw "Security policy retains upstream-only disclosure language: $ForbiddenTerm"
    }
}

$PackageSources = Get-ChildItem (Join-Path $RepositoryRoot 'packages') -Filter '*.sopm' -Recurse
if (-not $PackageSources) {
    throw 'No D724 package sources were found.'
}
foreach ($PackageSourceFile in $PackageSources) {
    $PackageDirectory = $PackageSourceFile.Directory.FullName
    [xml] $PackageSource = Get-Content $PackageSourceFile.FullName -Raw
    $PackageName = [string] $PackageSource.careoncloud_package.Name
    if ($PackageName -ne $PackageSourceFile.Directory.Name) {
        throw "Package name and directory differ: $PackageName"
    }
    if ([string] $PackageSource.careoncloud_package.License -ne 'GNU GENERAL PUBLIC LICENSE Version 3, 29 June 2007') {
        throw "$PackageName must declare the repository GPL-3.0-only package license."
    }
    foreach ($File in $PackageSource.careoncloud_package.Filelist.File) {
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
            [xml] $PackageXML = Get-Content $PackageFile -Raw
            if ($PackageXML.otobo_config -eq $null) {
                throw "$PackageName XML must use the framework otobo_config root: $($File.Location)"
            }
            if ([string] $PackageXML.otobo_config.init -notin @('Framework', 'Application', 'Config', 'Changes')) {
                throw "$PackageName XML has an invalid otobo_config init value: $($File.Location)"
            }
        }
    }
}

Write-Host "Validated $($PackageSources.Count) D724 package manifests and file lists."

$CleanLifecycleScript = Get-Content (Join-Path $PSScriptRoot 'Test-CleanPackageLifecycle.ps1') -Raw
foreach ($RequiredRuntimeContract in @(
    '/opt/careoncloud/bin/psgi-bin/careoncloud.psgi',
    '/opt/careoncloud_install/careoncloud_next/bin/psgi-bin/careoncloud.psgi',
    "grep -F 'careoncloud.psgi' /opt/careoncloud_install/entrypoint.sh",
    'D724_GIT_COMMIT=$GitCommit',
    'D724_EXPECTED_GIT_COMMIT=$GitCommit'
)) {
    if ($CleanLifecycleScript -notmatch [regex]::Escape($RequiredRuntimeContract)) {
        throw "Clean package lifecycle is missing the CareOnCloud image runtime contract: $RequiredRuntimeContract"
    }
}

$TicketAuditWrapper = Get-Content (Join-Path $RepositoryRoot 'packages/D724TicketAudit/Kernel/System/Ticket/D724AuditCustom.pm') -Raw
$TicketAuditService = Get-Content (Join-Path $RepositoryRoot 'packages/D724TicketAudit/Kernel/System/D724/TicketAudit.pm') -Raw
$TicketAuditRegression = Get-Content (Join-Path $RepositoryRoot 'packages/D724TicketAudit/scripts/test/D724/TicketAudit.t') -Raw
foreach ($RequiredTicketCreateAtomicityContract in @(
    'Kernel::GenericInterface::Operation::Ticket::TicketCreate::Run',
    'GenericInterfaceTicketCreateRun',
    'GENERIC_INTERFACE_TICKET_CREATE_FAILED',
    'failed Generic Interface create leaves no ticket row'
)) {
    $Present = $TicketAuditWrapper -match [regex]::Escape($RequiredTicketCreateAtomicityContract) `
        -or $TicketAuditService -match [regex]::Escape($RequiredTicketCreateAtomicityContract) `
        -or $TicketAuditRegression -match [regex]::Escape($RequiredTicketCreateAtomicityContract)
    if (!$Present) {
        throw "TicketAudit is missing the Generic Interface TicketCreate atomicity contract: $RequiredTicketCreateAtomicityContract"
    }
}

$GenericInterfaceAcceptance = Get-Content (Join-Path $PSScriptRoot 'Accept-GenericInterfaceTicketUpdate.pl') -Raw
foreach ($RequiredTicketCreateAcceptanceContract in @(
    "Type => 'Ticket::TicketCreate'",
    "Route => '/TicketCreate'",
    'HTTP TicketCreate scope is invalid',
    'HTTP TicketCreate audit event missing',
    'HTTP TicketCreate audit chain verification failed'
)) {
    if ($GenericInterfaceAcceptance -notmatch [regex]::Escape($RequiredTicketCreateAcceptanceContract)) {
        throw "Generic Interface TicketCreate acceptance is missing required contract: $RequiredTicketCreateAcceptanceContract"
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

$PublicIssueTemplates = Get-ChildItem (Join-Path $RepositoryRoot '.github/ISSUE_TEMPLATE') -File -ErrorAction Stop
foreach ($Template in $PublicIssueTemplates) {
    $TemplateText = Get-Content $Template.FullName -Raw
    if ($TemplateText -match '(?i)\boto(?:bo|rs)\b') {
        throw "Public issue template retains an upstream product brand: $($Template.Name)"
    }
}

$SecretScanRoots = @('packages', 'development/d724', 'docs/esm', '.github') |
    ForEach-Object { Join-Path $RepositoryRoot $_ } |
    Where-Object { Test-Path $_ }
$SecretPatterns = @(
    '(?m)-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----',
    '(?i)\bAKIA[0-9A-Z]{16}\b',
    '(?i)\bgh[pousr]_[A-Za-z0-9_]{20,}\b'
)
foreach ($Root in $SecretScanRoots) {
    foreach ($Candidate in Get-ChildItem $Root -Recurse -File) {
        $CandidateText = Get-Content $Candidate.FullName -Raw -ErrorAction Stop
        foreach ($Pattern in $SecretPatterns) {
            if ($CandidateText -match $Pattern) {
                throw "Potential committed secret material in $($Candidate.FullName)"
            }
        }
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
