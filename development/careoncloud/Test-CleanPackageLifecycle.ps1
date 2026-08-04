[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$ComposeFile = Join-Path $PSScriptRoot 'compose.yml'
$Project = "careoncloud-package-lifecycle-$PID"
$EnvironmentFile = Join-Path ([System.IO.Path]::GetTempPath()) "$Project.env"
$Packages = @(
    'CareOnCloudFoundation', 'CareOnCloudTenantGuard', 'CareOnCloudAudit', 'CareOnCloudTenantDirectory',
    'CareOnCloudCatalog', 'CareOnCloudRequest', 'CareOnCloudTicketAudit', 'CareOnCloudProblem', 'CareOnCloudCMDB',
    'CareOnCloudChange', 'CareOnCloudCommitment', 'CareOnCloudWebhook', 'CareOnCloudAPI', 'CareOnCloudIdentity',
    'CareOnCloudSCIM', 'CareOnCloudReporting', 'CareOnCloudAssist', 'CareOnCloudObservability'
)
$GitCommit = (& git -C $RepositoryRoot rev-parse HEAD).Trim()
if ($GitCommit -notmatch '\A[0-9a-f]{40}\z') { throw "Could not resolve the source Git commit: $GitCommit" }

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

# The CareOnCloud Dockerfiles use Dockerfile frontend heredoc RUN blocks. The
# legacy builder silently accepts those blocks as empty input, producing a
# misleading later runtime failure (for example, missing local::lib). Fail
# before creating any candidate containers when the BuildKit frontend is not
# available on the runner.
$BuildxVersion = & docker buildx version 2>$null
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($BuildxVersion -join "`n"))) {
    throw 'Docker Buildx is required for clean package lifecycle acceptance; the legacy builder cannot execute the CareOnCloud Dockerfile heredoc RUN blocks.'
}

$DatabasePassword = New-RandomSecret
$GenericInterfacePassword = New-RandomSecret
@(
    "CareOnCloud_DB_ROOT_PASSWORD=$DatabasePassword",
    'CareOnCloud_BIND_ADDRESS=127.0.0.1',
    'CareOnCloud_HTTP_PORT=18080',
    "CareOnCloud_GIT_COMMIT=$GitCommit"
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

    $RuntimeContract = @'
set -eu
test -f /opt/careoncloud/bin/psgi-bin/careoncloud.psgi
test -f /opt/careoncloud_install/careoncloud_next/bin/psgi-bin/careoncloud.psgi
grep -F 'careoncloud.psgi' /opt/careoncloud_install/entrypoint.sh >/dev/null
test "$(tr -d '\r\n' < /opt/careoncloud_install/careoncloud_next/git-commit.txt)" = "$CareOnCloud_EXPECTED_GIT_COMMIT"
'@
    Invoke-Compose -ComposeArguments @('exec', '-T', '-e', "CareOnCloud_EXPECTED_GIT_COMMIT=$GitCommit", 'web', 'sh', '-lc', $RuntimeContract)

    $QuickSetupOutput = Invoke-Compose -ComposeArguments @(
        'exec', '-T', 'web', 'bin/docker/quick_setup.pl',
        '--db-password', $DatabasePassword,
        '--http-type', 'http', '--http-port', '18080',
        '--fqdn', 'localhost', '--add-admin-user'
    )
    Invoke-Compose -ComposeArguments @('exec', '-T', 'web', 'sh', '-lc', 'mkdir -p /tmp/careoncloud-pkgs /tmp/careoncloud-package-out')
    & docker cp (Join-Path $PSScriptRoot 'Accept-GenericInterfaceTicketUpdate.pl') ($WebContainer + ':/tmp/Accept-GenericInterfaceTicketUpdate.pl')
    if ($LASTEXITCODE -ne 0) { throw 'Could not copy Generic Interface acceptance script into the clean lifecycle container.' }
    & docker cp (Join-Path $PSScriptRoot 'Clean-QuickSetupTicket.pl') ($WebContainer + ':/tmp/Clean-QuickSetupTicket.pl')
    if ($LASTEXITCODE -ne 0) { throw 'Could not copy quick-setup fixture cleanup script into the clean lifecycle container.' }
    & docker cp (Join-Path $PSScriptRoot 'Accept-SchedulerTicketPendingCheck.pl') ($WebContainer + ':/tmp/Accept-SchedulerTicketPendingCheck.pl')
    if ($LASTEXITCODE -ne 0) { throw 'Could not copy scheduler acceptance script into the clean lifecycle container.' }
    & docker cp (Join-Path $PSScriptRoot 'Accept-GenericAgentTenantScope.pl') ($WebContainer + ':/tmp/Accept-GenericAgentTenantScope.pl')
    if ($LASTEXITCODE -ne 0) { throw 'Could not copy GenericAgent acceptance script into the clean lifecycle container.' }
    foreach ($Package in $Packages) {
        $Source = Join-Path $RepositoryRoot "packages/$Package"
        if (-not (Test-Path $Source -PathType Container)) { throw "Package source is missing: $Package" }
        & docker cp $Source ($WebContainer + ':/tmp/careoncloud-pkgs/')
        if ($LASTEXITCODE -ne 0) { throw "Could not copy $Package into the clean lifecycle container." }
    }

$LifecycleCommand = @'
set -euo pipefail
perl -I. -IKernel/cpan-lib -ICustom /tmp/Clean-QuickSetupTicket.pl
build_install() {
    package="$1"
    sopm="/tmp/careoncloud-pkgs/$package/$package.sopm"
    bin/careoncloud.Console.pl Dev::Package::Build --module-directory "/tmp/careoncloud-pkgs/$package" "$sopm" /tmp/careoncloud-package-out
    opm=$(find /tmp/careoncloud-package-out -maxdepth 1 -name "$package-*.opm" -print -quit)
    test -n "$opm"
    bin/careoncloud.Console.pl Admin::Package::Install --force "$opm"
}
build_install CareOnCloudFoundation
build_install CareOnCloudTenantGuard
build_install CareOnCloudAudit
build_install CareOnCloudTenantDirectory
build_install CareOnCloudCatalog
build_install CareOnCloudRequest
build_install CareOnCloudTicketAudit
build_install CareOnCloudProblem
build_install CareOnCloudCMDB
build_install CareOnCloudChange
build_install CareOnCloudCommitment
build_install CareOnCloudWebhook
build_install CareOnCloudAPI
build_install CareOnCloudIdentity
build_install CareOnCloudSCIM
build_install CareOnCloudReporting
build_install CareOnCloudAssist
build_install CareOnCloudObservability
deployment=$(bin/careoncloud.Console.pl Admin::Package::List --show-deployment-info)
printf '%s\n' "$deployment"
! printf '%s\n' "$deployment" | grep -q 'Not OK'
printf '%s\n' "$deployment" | grep -c 'Pck. Status: OK' | grep -qx 18
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
bin/careoncloud.Console.pl Admin::User::SetPassword admin "$CareOnCloud_GI_ACCEPTANCE_PASSWORD" >/dev/null
CareOnCloud_GI_ACCEPTANCE_PASSWORD="$CareOnCloud_GI_ACCEPTANCE_PASSWORD" perl -I. -IKernel/cpan-lib -ICustom /tmp/Accept-GenericInterfaceTicketUpdate.pl
perl -I. -IKernel/cpan-lib -ICustom /tmp/Accept-SchedulerTicketPendingCheck.pl
perl -I. -IKernel/cpan-lib -ICustom /tmp/Accept-GenericAgentTenantScope.pl
for package in \
    CareOnCloudFoundation CareOnCloudTenantGuard CareOnCloudAudit CareOnCloudTenantDirectory CareOnCloudCatalog \
    CareOnCloudRequest CareOnCloudTicketAudit CareOnCloudCMDB CareOnCloudChange CareOnCloudCommitment CareOnCloudWebhook \
    CareOnCloudAPI CareOnCloudIdentity CareOnCloudSCIM CareOnCloudReporting CareOnCloudAssist CareOnCloudObservability
do
    bin/careoncloud.Console.pl Dev::UnitTest::Run --package "$package"
done
bin/careoncloud.Console.pl Dev::UnitTest::Run --package CareOnCloudProblem
opm=$(find /tmp/careoncloud-package-out -maxdepth 1 -name 'CareOnCloudProblem-*.opm' -print -quit)
bin/careoncloud.Console.pl Admin::Package::Uninstall "$opm"
if bin/careoncloud.Console.pl Admin::Config::Read --setting-name CareOnCloud::Problem::Enabled; then
    echo 'CareOnCloud::Problem::Enabled remained after uninstall.' >&2
    exit 41
fi
bin/careoncloud.Console.pl Admin::Package::Install --force "$opm"
bin/careoncloud.Console.pl Dev::UnitTest::Run --package CareOnCloudProblem
'@
    Invoke-Compose -ComposeArguments @('exec', '-T', '-e', "CareOnCloud_GI_ACCEPTANCE_PASSWORD=$GenericInterfacePassword", 'web', 'sh', '-lc', $AcceptanceCommand)
    Write-Host 'Clean CareOnCloud package lifecycle acceptance passed.'
}
finally {
    if (Test-Path $EnvironmentFile) {
        Invoke-Compose -ComposeArguments @('down', '--volumes', '--remove-orphans')
        Remove-Item $EnvironmentFile -Force -ErrorAction SilentlyContinue
    }
}
