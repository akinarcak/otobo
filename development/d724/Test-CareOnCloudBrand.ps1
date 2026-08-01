[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$Failures = [System.Collections.Generic.List[string]]::new()

function Assert-True {
    param(
        [bool] $Condition,
        [string] $Message
    )

    if (-not $Condition) {
        $Failures.Add($Message)
    }
}

$RequiredPaths = @(
    'bin/careoncloud.Console.pl',
    'bin/careoncloud.Daemon.pl',
    'bin/careoncloud.SetPermissions.pl',
    'bin/psgi-bin/careoncloud.psgi',
    'careoncloud.web.dockerfile',
    'careoncloud.nginx.dockerfile',
    'scripts/database/careoncloud-schema.xml',
    'scripts/database/careoncloud-initial_insert.xml',
    'scripts/systemd/careoncloud-web.service',
    'scripts/systemd/careoncloud-daemon.service',
    'i18n/careoncloud',
    'var/logo-careoncloud.png',
    'var/httpd/htdocs/skins/Agent/default/img/careoncloud-logo.png',
    'var/httpd/htdocs/skins/Agent/default/img/careoncloud-signet.png',
    'var/httpd/htdocs/skins/Customer/default/img/careoncloud-logo.png',
    'var/httpd/htdocs/common/fonts/careoncloud.woff'
)

$ForbiddenPaths = @(
    'bin/otobo.Console.pl',
    'bin/otobo.Daemon.pl',
    'bin/otobo.SetPermissions.pl',
    'bin/psgi-bin/otobo.psgi',
    'otobo.web.dockerfile',
    'otobo.nginx.dockerfile',
    'scripts/database/otobo-schema.xml',
    'scripts/database/otobo-initial_insert.xml',
    'scripts/systemd/otobo-web.service',
    'scripts/systemd/otobo-daemon.service',
    'i18n/otobo',
    'var/logo-otobo.png',
    'var/httpd/htdocs/skins/Agent/default/img/otobo-signet.svg',
    'var/httpd/htdocs/skins/Customer/default/img/otobo_logo_simple_w.svg',
    'var/httpd/htdocs/common/fonts/otobo.woff'
)

foreach ($Path in $RequiredPaths) {
    Assert-True (Test-Path -LiteralPath (Join-Path $RepositoryRoot $Path)) "Required CareOnCloud path is missing: $Path"
}

foreach ($Path in $ForbiddenPaths) {
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $RepositoryRoot $Path))) "Legacy product path must not exist: $Path"
}

$PackageFiles = Get-ChildItem (Join-Path $RepositoryRoot 'packages') -Filter '*.sopm' -Recurse
foreach ($PackageFile in $PackageFiles) {
    [xml] $Package = Get-Content -Raw -LiteralPath $PackageFile.FullName
    Assert-True ($Package.DocumentElement.LocalName -eq 'careoncloud_package') "Invalid package root in $($PackageFile.Name)"

    foreach ($FileNode in $Package.DocumentElement.SelectNodes('./Filelist/File')) {
        $Location = $FileNode.GetAttribute('Location')
        Assert-True (Test-Path -LiteralPath (Join-Path $PackageFile.Directory.FullName $Location)) "Missing package file in $($PackageFile.Name): $Location"
    }
}

$FrameworkXML = Get-Content -Raw -LiteralPath (Join-Path $RepositoryRoot 'Kernel/Config/Files/XML/Framework.xml')
$DaemonXML = Get-Content -Raw -LiteralPath (Join-Path $RepositoryRoot 'Kernel/Config/Files/XML/Daemon.xml')
$PSGI = Get-Content -Raw -LiteralPath (Join-Path $RepositoryRoot 'bin/psgi-bin/careoncloud.psgi')
$Compose = Get-Content -Raw -LiteralPath (Join-Path $RepositoryRoot 'development/d724/compose.yml')

Assert-True ($FrameworkXML -match '<Item ValueType="String" ValueRegex="">careoncloud/</Item>') 'ScriptAlias is not careoncloud/.'
Assert-True ($FrameworkXML -match '<Item ValueType="String" ValueRegex="">/careoncloud-web/</Item>') 'Frontend::WebPath is not /careoncloud-web/.'
Assert-True ($DaemonXML -match 'SelectedID="careoncloud"') 'Daemon rotation type is not careoncloud.'
Assert-True ($PSGI -match "mount '/careoncloud' => \`$CareOnCloudApp") 'Canonical /careoncloud PSGI mount is missing.'
Assert-True ($PSGI -notmatch "mount '/otobo'") 'Legacy public PSGI mount must not be present.'
Assert-True ($Compose -match 'careoncloud-app:/opt/careoncloud') 'CareOnCloud application volume mapping is missing.'
Assert-True ($Compose -match 'careoncloud-update:/opt/careoncloud_update') 'CareOnCloud update volume mapping is missing.'

if ($Failures.Count) {
    $Failures | ForEach-Object { Write-Error $_ -ErrorAction Continue }
    throw "CareOnCloud brand contract failed with $($Failures.Count) error(s)."
}

Write-Output "CareOnCloud brand contract passed: $($RequiredPaths.Count) required paths, $($ForbiddenPaths.Count) forbidden paths and $($PackageFiles.Count) packages checked."
