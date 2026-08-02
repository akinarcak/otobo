[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$ComposeFile = Join-Path $PSScriptRoot 'compose.yml'
$Project = "d724-package-lifecycle-$PID"
$EnvironmentFile = Join-Path ([System.IO.Path]::GetTempPath()) "$Project.env"
$Packages = @('D724Foundation', 'D724TenantGuard', 'D724TenantDirectory', 'D724Audit', 'D724TicketAudit', 'D724Problem')

function New-RandomSecret {
    $Bytes = New-Object byte[] 24
    $Generator = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $Generator.GetBytes($Bytes) } finally { $Generator.Dispose() }
    return [Convert]::ToBase64String($Bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

function Invoke-Compose {
    param([Parameter(Mandatory)][string[]] $ComposeArguments)
    & docker compose --project-directory $PSScriptRoot --env-file $EnvironmentFile -f $ComposeFile -p $Project @ComposeArguments
    if ($LASTEXITCODE -ne 0) { throw "docker compose failed with exit code $LASTEXITCODE." }
}

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw 'Docker is required for clean package lifecycle acceptance.'
}

$DatabasePassword = New-RandomSecret
$GenericInterfacePassword = New-RandomSecret
@(
    "D724_DB_ROOT_PASSWORD=$DatabasePassword",
    'D724_BIND_ADDRESS=127.0.0.1',
    'D724_HTTP_PORT=18080'
) | Set-Content -Encoding utf8 $EnvironmentFile

try {
    Invoke-Compose -ComposeArguments @('up', '--detach', '--build', 'db', 'redis', 'web')
    $WebContainer = "$Project-web-1"
    $Ready = $false
    for ($Attempt = 1; $Attempt -le 60; $Attempt++) {
        $Health = (& docker inspect --format '{{.State.Health.Status}}' $WebContainer 2>$null).Trim()
        if ($Health -eq 'healthy') { $Ready = $true; break }
        Start-Sleep -Seconds 2
    }
    if (-not $Ready) { throw 'Clean lifecycle web container did not become healthy.' }

    $QuickSetupOutput = Invoke-Compose -ComposeArguments @(
        'exec', '-T', 'web', 'bin/docker/quick_setup.pl',
        '--db-password', $DatabasePassword,
        '--http-type', 'http', '--http-port', '18080',
        '--fqdn', 'localhost', '--add-admin-user'
    )
    Invoke-Compose -ComposeArguments @('exec', '-T', 'web', 'sh', '-lc', 'mkdir -p /tmp/d724-pkgs /tmp/d724-package-out')
    & docker cp (Join-Path $PSScriptRoot 'Accept-GenericInterfaceTicketUpdate.pl') ($WebContainer + ':/tmp/Accept-GenericInterfaceTicketUpdate.pl')
    if ($LASTEXITCODE -ne 0) { throw 'Could not copy Generic Interface acceptance script into the clean lifecycle container.' }
    & docker cp (Join-Path $PSScriptRoot 'Accept-SchedulerTicketPendingCheck.pl') ($WebContainer + ':/tmp/Accept-SchedulerTicketPendingCheck.pl')
    if ($LASTEXITCODE -ne 0) { throw 'Could not copy scheduler acceptance script into the clean lifecycle container.' }
    foreach ($Package in $Packages) {
        $Source = Join-Path $RepositoryRoot "packages/$Package"
        if (-not (Test-Path $Source -PathType Container)) { throw "Package source is missing: $Package" }
        & docker cp $Source ($WebContainer + ':/tmp/d724-pkgs/')
        if ($LASTEXITCODE -ne 0) { throw "Could not copy $Package into the clean lifecycle container." }
    }

    $LifecycleCommand = @'
set -euo pipefail
build_install() {
    package="$1"
    sopm="/tmp/d724-pkgs/$package/$package.sopm"
    bin/careoncloud.Console.pl Dev::Package::Build --module-directory "/tmp/d724-pkgs/$package" "$sopm" /tmp/d724-package-out
    opm=$(find /tmp/d724-package-out -maxdepth 1 -name "$package-*.opm" -print -quit)
    test -n "$opm"
    bin/careoncloud.Console.pl Admin::Package::Install --force "$opm"
}
build_install D724Foundation
build_install D724TenantGuard
build_install D724TenantDirectory
build_install D724Audit
build_install D724TicketAudit
build_install D724Problem
deployment=$(bin/careoncloud.Console.pl Admin::Package::List --show-deployment-info)
printf '%s\n' "$deployment"
! printf '%s\n' "$deployment" | grep -q 'Not OK'
printf '%s\n' "$deployment" | grep -c 'Pck. Status: OK' | grep -qx 6
'@
    Invoke-Compose -ComposeArguments @('exec', '-T', 'web', 'sh', '-lc', $LifecycleCommand)
    Invoke-Compose -ComposeArguments @('restart', 'web')
    $Ready = $false
    for ($Attempt = 1; $Attempt -le 60; $Attempt++) {
        $Health = (& docker inspect --format '{{.State.Health.Status}}' $WebContainer 2>$null).Trim()
        if ($Health -eq 'healthy') { $Ready = $true; break }
        Start-Sleep -Seconds 2
    }
    if (-not $Ready) { throw 'Clean lifecycle web container did not become healthy after package activation.' }

    $AcceptanceCommand = @'
set -euo pipefail
bin/careoncloud.Console.pl Admin::User::SetPassword admin "$D724_GI_ACCEPTANCE_PASSWORD" >/dev/null
D724_GI_ACCEPTANCE_PASSWORD="$D724_GI_ACCEPTANCE_PASSWORD" perl -I. -IKernel/cpan-lib -ICustom /tmp/Accept-GenericInterfaceTicketUpdate.pl
perl -I. -IKernel/cpan-lib -ICustom /tmp/Accept-SchedulerTicketPendingCheck.pl
bin/careoncloud.Console.pl Dev::UnitTest::Run --package D724Problem
opm=$(find /tmp/d724-package-out -maxdepth 1 -name 'D724Problem-*.opm' -print -quit)
bin/careoncloud.Console.pl Admin::Package::Uninstall "$opm"
if bin/careoncloud.Console.pl Admin::Config::Read --setting-name D724::Problem::Enabled; then
    echo 'D724::Problem::Enabled remained after uninstall.' >&2
    exit 41
fi
bin/careoncloud.Console.pl Admin::Package::Install --force "$opm"
bin/careoncloud.Console.pl Dev::UnitTest::Run --package D724Problem
'@
    Invoke-Compose -ComposeArguments @('exec', '-T', '-e', "D724_GI_ACCEPTANCE_PASSWORD=$GenericInterfacePassword", 'web', 'sh', '-lc', $AcceptanceCommand)
    Write-Host 'Clean D724Problem package lifecycle acceptance passed.'
}
finally {
    if (Test-Path $EnvironmentFile) {
        Invoke-Compose -ComposeArguments @('down', '--volumes', '--remove-orphans')
        Remove-Item $EnvironmentFile -Force -ErrorAction SilentlyContinue
    }
}
