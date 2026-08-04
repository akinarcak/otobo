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
$Compose = Get-Content -Raw -LiteralPath (Join-Path $RepositoryRoot 'development/careoncloud/compose.yml')
$Layout = Get-Content -Raw -LiteralPath (Join-Path $RepositoryRoot 'Kernel/Output/HTML/Layout.pm')
$AgentInterface = Get-Content -Raw -LiteralPath (Join-Path $RepositoryRoot 'Kernel/System/Web/InterfaceAgent.pm')
$CustomerInterface = Get-Content -Raw -LiteralPath (Join-Path $RepositoryRoot 'Kernel/System/Web/InterfaceCustomer.pm')
$Ajax = Get-Content -Raw -LiteralPath (Join-Path $RepositoryRoot 'var/httpd/htdocs/js/Core.AJAX.js')

Assert-True ($FrameworkXML -match '<Item ValueType="String" ValueRegex="">careoncloud/</Item>') 'ScriptAlias is not careoncloud/.'
Assert-True ($FrameworkXML -match '<Item ValueType="String" ValueRegex="">/careoncloud-web/</Item>') 'Frontend::WebPath is not /careoncloud-web/.'
Assert-True ($DaemonXML -match 'SelectedID="careoncloud"') 'Daemon rotation type is not careoncloud.'
Assert-True ($PSGI -match "mount '/careoncloud' => \`$CareOnCloudApp") 'Canonical /careoncloud PSGI mount is missing.'
Assert-True ($PSGI -notmatch "mount '/otobo'") 'Legacy public PSGI mount must not be present.'

# The compatibility route that briefly existed on the test server was a PATH_INFO
# rewrite rather than a mount, so the assertion above would not have caught it.
# Forbid every spelling of a legacy /otobo entry point. Attribution lines are
# excluded: both the copyright URL and upstream issue links contain the old
# project path without being routes.
$PSGIRoutes = ($PSGI -split "`n" | Where-Object { $_ -notmatch 'github\.com' -and $_ -notmatch 'otobo\.io' }) -join "`n"
Assert-True ($PSGIRoutes -notmatch '/otobo') 'Legacy /otobo route must not be present in the PSGI application.'
Assert-True ($Compose -match 'careoncloud-app:/opt/careoncloud') 'CareOnCloud application volume mapping is missing.'
Assert-True ($Compose -match 'careoncloud-update:/opt/careoncloud_update') 'CareOnCloud update volume mapping is missing.'
Assert-True ($FrameworkXML -match '<Item ValueType="String" ValueRegex="">CareOnCloud ESM</Item>') 'ProductName is not CareOnCloud ESM.'
Assert-True ($FrameworkXML -match '<Item Key="HeaderText">CareOnCloud ESM \| Service Management</Item>') 'Dashboard header is not CareOnCloud branded.'
Assert-True ($FrameworkXML -match '<Item Key="Link">https://esm\.arcak\.net</Item>') 'Dashboard link is not CareOnCloud branded.'
Assert-True ($FrameworkXML -notmatch 'OTOBO 11\.1 \| Service Management') 'Legacy dashboard header remains.'
Assert-True ($FrameworkXML -notmatch 'https://otobo\.io/en/otobo-11-1/') 'Legacy dashboard link remains.'
Assert-True ($FrameworkXML -match 'CareOnCloud ESM Notifications') 'Notification sender is not CareOnCloud branded.'
Assert-True ($FrameworkXML -notmatch 'New OTOBO password') 'Legacy password notification subject remains.'
Assert-True ($FrameworkXML -notmatch 'Your Tickets\. Your OTOBO\.') 'Legacy customer login text remains.'
Assert-True ($FrameworkXML -notmatch 'Welcome %s, to your OTOBO\.') 'Legacy customer dashboard welcome text remains.'
Assert-True ($FrameworkXML -notmatch '<Item Key="Title" Translatable="1">OTOBO News</Item>') 'Legacy agent news title remains.'
Assert-True ($FrameworkXML -match '<Item Key="Title" Translatable="1">CareOnCloud ESM announcements</Item>') 'CareOnCloud agent news title is missing.'
Assert-True ($FrameworkXML -match '(?s)<Setting Name="DashboardBackend###0405-News".*?<Item Key="Default">0</Item>') 'Upstream agent news is not disabled by default.'
Assert-True ($Layout -match "X-CareOnCloud-Login") 'CareOnCloud login response header is missing.'
Assert-True ($Layout -notmatch "X-OTOBO-Login") 'Legacy login response header remains.'
Assert-True ($Layout -match "CareOnCloudBrowserHasCookie") 'CareOnCloud browser cookie is missing from Layout.'
Assert-True ($AgentInterface -match "CareOnCloudBrowserHasCookie") 'CareOnCloud browser cookie is missing from agent interface.'
Assert-True ($CustomerInterface -match "CareOnCloudBrowserHasCookie") 'CareOnCloud browser cookie is missing from customer interface.'
Assert-True ($Ajax -match "X-CareOnCloud-Login") 'CareOnCloud AJAX login header handling is missing.'

if ($Failures.Count) {
    $Failures | ForEach-Object { Write-Error $_ -ErrorAction Continue }
    throw "CareOnCloud brand contract failed with $($Failures.Count) error(s)."
}

Write-Output "CareOnCloud brand contract passed: $($RequiredPaths.Count) required paths, $($ForbiddenPaths.Count) forbidden paths and $($PackageFiles.Count) packages checked."
