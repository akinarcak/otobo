[CmdletBinding()]
param(
    [ValidateSet('Validate', 'Build', 'Up', 'Setup', 'Smoke', 'Logs', 'Down')]
    [string] $Action = 'Validate',

    [switch] $EnableSearch,

    [switch] $RemoveVolumes
)

$ErrorActionPreference = 'Stop'
$ComposeDirectory = $PSScriptRoot
$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$ComposeFile = Join-Path $ComposeDirectory 'compose.yml'
$EnvironmentFile = Join-Path $ComposeDirectory '.env'

function Assert-Command {
    param([Parameter(Mandatory)][string] $Name)

    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command '$Name' was not found."
    }
}

function Assert-Buildx {
    $BuildxVersion = & docker buildx version 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($BuildxVersion -join "`n"))) {
        throw 'Docker Buildx is required for image build or startup; the legacy builder cannot execute the CareOnCloud Dockerfile heredoc RUN blocks.'
    }
}

function Invoke-Compose {
    param([Parameter(ValueFromRemainingArguments)][string[]] $Arguments)

    $ProfileArguments = @()
    if ($EnableSearch) {
        $ProfileArguments = @('--profile', 'search')
    }
    & docker compose --project-directory $ComposeDirectory --env-file $EnvironmentFile -f $ComposeFile @ProfileArguments @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "docker compose failed with exit code $LASTEXITCODE."
    }
}

function Set-BuildMetadata {
    $env:CareOnCloud_GIT_BRANCH = (& git -C $RepositoryRoot branch --show-current).Trim()
    $env:CareOnCloud_GIT_COMMIT = (& git -C $RepositoryRoot rev-parse HEAD).Trim()
    $env:CareOnCloud_GIT_REPO = (& git -C $RepositoryRoot config --get remote.origin.url).Trim()
}

function Get-EnvironmentValue {
    param(
        [Parameter(Mandatory)][string] $Name,
        [string] $Default = ''
    )

    $Line = Get-Content $EnvironmentFile | Where-Object { $_ -match "^$([regex]::Escape($Name))=" } | Select-Object -First 1
    if (-not $Line) {
        return $Default
    }
    return $Line.Substring($Line.IndexOf('=') + 1)
}

function New-RandomSecret {
    param([int] $ByteCount = 24)

    $Bytes = New-Object byte[] $ByteCount
    $Generator = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $Generator.GetBytes($Bytes)
    }
    finally {
        $Generator.Dispose()
    }
    return [Convert]::ToBase64String($Bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

Assert-Command docker
if (-not (Test-Path $EnvironmentFile)) {
    throw "Missing $EnvironmentFile. Copy .env.example to .env and replace the example password."
}

Set-BuildMetadata
$BindAddress = Get-EnvironmentValue -Name 'CareOnCloud_BIND_ADDRESS' -Default '127.0.0.1'
if ($BindAddress -eq '0.0.0.0' -or $BindAddress -eq '::') {
    throw 'Refusing a public wildcard bind. Use localhost, a private interface, or a TLS reverse proxy.'
}

switch ($Action) {
    'Validate' {
        Invoke-Compose config --quiet
        Write-Host 'Compose configuration is valid.'
    }
    'Build' {
        Assert-Buildx
        Invoke-Compose build web
    }
    'Up' {
        Assert-Buildx
        Invoke-Compose up --detach --build
        $HttpPort = Get-EnvironmentValue -Name 'CareOnCloud_HTTP_PORT' -Default '8080'
        Write-Host "CareOnCloud ESM is starting at http://127.0.0.1:$HttpPort/"
    }
    'Setup' {
        $DatabasePassword = Get-EnvironmentValue -Name 'CareOnCloud_DB_ROOT_PASSWORD'
        if (-not $DatabasePassword) {
            throw 'CareOnCloud_DB_ROOT_PASSWORD is missing from .env.'
        }
        if ($DatabasePassword -eq 'replace-with-a-long-random-password' -or $DatabasePassword.Length -lt 16) {
            throw 'Choose a database root password with at least 16 characters.'
        }

        $HttpPort = Get-EnvironmentValue -Name 'CareOnCloud_HTTP_PORT' -Default '8080'
        $SetupArguments = @(
            'exec', '-T', 'web', 'bin/docker/quick_setup.pl',
            '--db-password', $DatabasePassword,
            '--http-type', 'http',
            '--http-port', $HttpPort,
            '--fqdn', 'localhost',
            '--add-admin-user'
        )
        if ($EnableSearch) {
            $SetupArguments += '--activate-elasticsearch'
        }
        Invoke-Compose @SetupArguments

        $AdminPassword = New-RandomSecret
        $RootPassword = New-RandomSecret
        Invoke-Compose exec -T web bin/careoncloud.Console.pl Admin::User::SetPassword admin $AdminPassword
        Invoke-Compose exec -T web bin/careoncloud.Console.pl Admin::User::SetPassword root@localhost $RootPassword

        $RuntimeDirectory = Join-Path $ComposeDirectory '.runtime'
        New-Item -ItemType Directory -Force -Path $RuntimeDirectory | Out-Null
        $CredentialFile = Join-Path $RuntimeDirectory 'admin-credentials.env'
        @(
            "URL=http://$BindAddress`:$HttpPort/careoncloud/index.pl",
            'USER=admin',
            "PASSWORD=$AdminPassword"
        ) | Set-Content -Encoding UTF8 $CredentialFile
        if (-not $IsWindows -and (Get-Command chmod -ErrorAction SilentlyContinue)) {
            & chmod 600 $CredentialFile
        }
        Write-Host "Admin credentials were written to $CredentialFile"
    }
    'Smoke' {
        Invoke-Compose ps
        $HttpPort = Get-EnvironmentValue -Name 'CareOnCloud_HTTP_PORT' -Default '8080'
        Invoke-RestMethod -Uri "http://127.0.0.1:$HttpPort/health" -TimeoutSec 10 | Out-Null
        Invoke-Compose exec -T web bin/careoncloud.Console.pl Maint::Config::Rebuild
        Write-Host 'HTTP health and CareOnCloud ESM console smoke checks passed.'
    }
    'Logs' {
        Invoke-Compose logs --follow --tail 200 web daemon
    }
    'Down' {
        $Arguments = @('down', '--remove-orphans')
        if ($RemoveVolumes) {
            $Arguments += '--volumes'
        }
        Invoke-Compose @Arguments
    }
}
