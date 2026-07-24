[CmdletBinding()]
param(
    [ValidateSet('Validate', 'Build', 'Up', 'Setup', 'Smoke', 'Logs', 'Down')]
    [string] $Action = 'Validate',

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

function Invoke-Compose {
    param([Parameter(ValueFromRemainingArguments)][string[]] $Arguments)

    & docker compose --project-directory $ComposeDirectory --env-file $EnvironmentFile -f $ComposeFile @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "docker compose failed with exit code $LASTEXITCODE."
    }
}

function Set-BuildMetadata {
    $env:D724_GIT_BRANCH = (& git -C $RepositoryRoot branch --show-current).Trim()
    $env:D724_GIT_COMMIT = (& git -C $RepositoryRoot rev-parse HEAD).Trim()
    $env:D724_GIT_REPO = (& git -C $RepositoryRoot config --get remote.origin.url).Trim()
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

Assert-Command docker
if (-not (Test-Path $EnvironmentFile)) {
    throw "Missing $EnvironmentFile. Copy .env.example to .env and replace the example password."
}

Set-BuildMetadata

switch ($Action) {
    'Validate' {
        Invoke-Compose config --quiet
        Write-Host 'Compose configuration is valid.'
    }
    'Build' {
        Invoke-Compose build web
    }
    'Up' {
        Invoke-Compose up --detach --build
        $HttpPort = Get-EnvironmentValue -Name 'D724_HTTP_PORT' -Default '8080'
        Write-Host "D724 ESM is starting at http://127.0.0.1:$HttpPort/"
    }
    'Setup' {
        $DatabasePassword = Get-EnvironmentValue -Name 'D724_DB_ROOT_PASSWORD'
        if (-not $DatabasePassword) {
            throw 'D724_DB_ROOT_PASSWORD is missing from .env.'
        }
        if ($DatabasePassword -eq 'replace-with-a-long-random-password' -or $DatabasePassword.Length -lt 16) {
            throw 'Choose a database root password with at least 16 characters.'
        }

        $HttpPort = Get-EnvironmentValue -Name 'D724_HTTP_PORT' -Default '8080'
        Invoke-Compose exec -T web bin/docker/quick_setup.pl `
            --db-password $DatabasePassword `
            --http-type http `
            --http-port $HttpPort `
            --fqdn localhost `
            --activate-elasticsearch `
            --add-admin-user
    }
    'Smoke' {
        Invoke-Compose ps
        $HttpPort = Get-EnvironmentValue -Name 'D724_HTTP_PORT' -Default '8080'
        Invoke-RestMethod -Uri "http://127.0.0.1:$HttpPort/health" -TimeoutSec 10 | Out-Null
        Invoke-Compose exec -T web bin/otobo.Console.pl Maint::Config::Rebuild
        Write-Host 'HTTP health and OTOBO console smoke checks passed.'
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
