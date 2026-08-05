[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$UTF8 = [System.Text.UTF8Encoding]::new($false, $true)
$Failures = [System.Collections.Generic.List[string]]::new()
$MojibakePattern = '[' + [char]0x00C3 + [char]0x00C4 + [char]0x00C5 + [char]0x00C2 + ']'

function Read-UTF8Strict {
    param([string] $RelativePath)

    $Path = Join-Path $RepositoryRoot $RelativePath
    try {
        return $UTF8.GetString([System.IO.File]::ReadAllBytes($Path))
    }
    catch {
        throw "Invalid UTF-8 source: $RelativePath ($($_.Exception.Message))"
    }
}

function TranslationKeysGet {
    param([string] $Text)

    $Keys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($Match in [regex]::Matches($Text, '\{Translation\}->\{''([^'']+)''\}')) {
        [void] $Keys.Add($Match.Groups[1].Value)
    }
    foreach ($Match in [regex]::Matches($Text, '''([^'']+)''\s*=>')) {
        [void] $Keys.Add($Match.Groups[1].Value)
    }
    return ,$Keys
}

$Journeys = @(
    @{
        Name = 'customer-service-catalog'
        Template = 'packages/CareOnCloudCatalog/Kernel/Output/HTML/Templates/Standard/CustomerCareOnCloudCatalog.tt'
        Locale = 'packages/CareOnCloudCatalog/Kernel/Language/tr_CareOnCloudCatalog.pm'
    },
    @{
        Name = 'agent-operations-center'
        Template = 'packages/CareOnCloudReporting/Kernel/Output/HTML/Templates/Standard/AgentCareOnCloudOperations.tt'
        Locale = 'packages/CareOnCloudReporting/Kernel/Language/tr_CareOnCloudReporting.pm'
    }
)

foreach ($Journey in $Journeys) {
    $Template = Read-UTF8Strict $Journey.Template
    $Locale = Read-UTF8Strict $Journey.Locale
    if ($Template -match $MojibakePattern -or $Locale -match $MojibakePattern) {
        $Failures.Add("Mojibake marker found in $($Journey.Name).")
    }

    $TranslationKeys = TranslationKeysGet $Locale
    foreach ($Match in [regex]::Matches($Template, 'Translate\("([^"]+)"\)')) {
        $Key = $Match.Groups[1].Value
        if (-not $TranslationKeys.Contains($Key)) {
            $Failures.Add("Missing Turkish translation for '$Key' in $($Journey.Name).")
        }
    }
}

if ($Failures.Count) {
    $Failures | ForEach-Object { Write-Error $_ -ErrorAction Continue }
    throw "Critical language contract failed with $($Failures.Count) error(s)."
}

Write-Output "Critical language contract passed for $($Journeys.Count) customer/agent journeys."
