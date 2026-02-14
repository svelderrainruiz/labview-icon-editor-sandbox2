#Requires -Version 7.0
<#
.SYNOPSIS
    Verifies that VIPC package versions are installed for a LabVIEW bitness.

.DESCRIPTION
    Uses VIPM CLI as the dependency authority:
      - expected set from "vipm list <vipc>"
      - installed set from "vipm list --installed"
    Comparison is by package_id + exact version.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$RepoRoot,

    [Parameter(Mandatory = $true)]
    [string]$VIPCPath,

    [Parameter(Mandatory = $true)]
    [ValidateSet('32', '64')]
    [string]$SupportedBitness,

    [Parameter(Mandatory = $false)]
    [AllowNull()]
    [AllowEmptyString()]
    [string]$LabVIEWVersion = '',

    [Parameter(Mandatory = $true)]
    [string]$OutputPath,

    [Parameter(Mandatory = $false)]
    [bool]$FailOnMismatch = $true
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Build-PackageVersionMap {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Packages
    )

    $map = @{}
    foreach ($pkg in $Packages) {
        if (-not $pkg) {
            continue
        }

        $id = [string]$pkg.package_id
        $version = [string]$pkg.version
        if ([string]::IsNullOrWhiteSpace($id) -or [string]::IsNullOrWhiteSpace($version)) {
            continue
        }

        if (-not $map.ContainsKey($id)) {
            $map[$id] = $version
        }
    }

    return $map
}

try {
    $resolvedRepoRoot = (Resolve-Path -Path $RepoRoot).Path
    $resolvedVipcPath = Join-Path -Path $resolvedRepoRoot -ChildPath $VIPCPath
    if (-not (Test-Path -Path $resolvedVipcPath -PathType Leaf)) {
        throw "VIPC file not found at '$resolvedVipcPath'."
    }

    $versionHelper = Join-Path -Path $resolvedRepoRoot -ChildPath 'Tooling\support\LabVIEWVersion.ps1'
    if (-not (Test-Path -Path $versionHelper -PathType Leaf)) {
        throw "LabVIEW version helper not found at '$versionHelper'."
    }
    . $versionHelper

    $vipmHelper = Join-Path -Path $resolvedRepoRoot -ChildPath 'Tooling\support\VipmCli.ps1'
    if (-not (Test-Path -Path $vipmHelper -PathType Leaf)) {
        throw "VIPM CLI helper not found at '$vipmHelper'."
    }
    . $vipmHelper

    $lvInfo = Get-LabVIEWVersionInfo -VersionInput $LabVIEWVersion -RepoRoot $resolvedRepoRoot
    $vipmYear = ConvertTo-VipmLabVIEWYear -VersionInput $lvInfo

    $expectedArgs = @(
        '--labview-version', $vipmYear,
        '--labview-bitness', $SupportedBitness,
        'list', $resolvedVipcPath
    )
    $installedArgs = @(
        '--labview-version', $vipmYear,
        '--labview-bitness', $SupportedBitness,
        'list', '--installed'
    )

    $expectedResult = Invoke-VipmCliCommand -Arguments $expectedArgs
    if ($expectedResult.TimedOut) {
        throw ("VIPM expected-set command timed out after {0} attempt(s): {1}" -f $expectedResult.Attempts, $expectedResult.Command)
    }
    if ($expectedResult.ExitCode -ne 0) {
        throw ("VIPM expected-set command failed (exit {0}): {1}`nSTDERR: {2}" -f $expectedResult.ExitCode, $expectedResult.Command, $expectedResult.StdErr)
    }

    $installedResult = Invoke-VipmCliCommand -Arguments $installedArgs
    if ($installedResult.TimedOut) {
        throw ("VIPM installed-set command timed out after {0} attempt(s): {1}" -f $installedResult.Attempts, $installedResult.Command)
    }
    if ($installedResult.ExitCode -ne 0) {
        throw ("VIPM installed-set command failed (exit {0}): {1}`nSTDERR: {2}" -f $installedResult.ExitCode, $installedResult.Command, $installedResult.StdErr)
    }

    $expectedPackages = @(ConvertFrom-VipmListPackage -Text $expectedResult.StdOut)
    $installedPackages = @(ConvertFrom-VipmListPackage -Text $installedResult.StdOut)

    if ($expectedPackages.Count -eq 0) {
        throw "No expected packages were parsed from VIPM output for '$resolvedVipcPath'."
    }

    $expectedById = Build-PackageVersionMap -Packages $expectedPackages
    $installedById = Build-PackageVersionMap -Packages $installedPackages

    $missingExpected = New-Object 'System.Collections.Generic.List[string]'
    $versionMismatches = New-Object 'System.Collections.Generic.List[object]'
    foreach ($pkgId in ($expectedById.Keys | Sort-Object)) {
        if (-not $installedById.ContainsKey($pkgId)) {
            $missingExpected.Add($pkgId)
            continue
        }

        $expectedVersion = [string]$expectedById[$pkgId]
        $installedVersion = [string]$installedById[$pkgId]
        if ($expectedVersion -ne $installedVersion) {
            $versionMismatches.Add([pscustomobject]@{
                package_id        = $pkgId
                expected_version  = $expectedVersion
                installed_version = $installedVersion
            })
        }
    }

    $unexpectedInstalled = New-Object 'System.Collections.Generic.List[object]'
    foreach ($pkgId in ($installedById.Keys | Sort-Object)) {
        if ($expectedById.ContainsKey($pkgId)) {
            continue
        }

        $unexpectedInstalled.Add([pscustomobject]@{
            package_id = $pkgId
            version    = [string]$installedById[$pkgId]
        })
    }

    $missingExpectedArray = @($missingExpected.ToArray())
    $versionMismatchesArray = @($versionMismatches.ToArray())
    $unexpectedInstalledArray = @($unexpectedInstalled.ToArray())

    $status = if ($missingExpectedArray.Count -eq 0 -and $versionMismatchesArray.Count -eq 0) { 'pass' } else { 'fail' }

    $report = [ordered]@{
        generated_utc                 = (Get-Date).ToUniversalTime().ToString('o')
        repo_root                     = $resolvedRepoRoot
        vipc_path                     = $resolvedVipcPath
        vipc_sha256                   = (Get-FileHash -Path $resolvedVipcPath -Algorithm SHA256).Hash
        labview_version_raw           = $lvInfo.Raw
        labview_year                  = $lvInfo.Year
        labview_numeric               = $lvInfo.NumericVersion
        supported_bitness             = $SupportedBitness
        vipm_expected_command         = $expectedResult.Command
        vipm_installed_command        = $installedResult.Command
        expected_packages_normalized  = $expectedPackages
        installed_packages_normalized = $installedPackages
        missing_expected              = $missingExpectedArray
        version_mismatches            = $versionMismatchesArray
        unexpected_installed          = $unexpectedInstalledArray
        summary                       = [ordered]@{
            expected_count            = $expectedPackages.Count
            installed_count           = $installedPackages.Count
            missing_expected_count    = $missingExpectedArray.Count
            version_mismatch_count    = $versionMismatchesArray.Count
            unexpected_installed_count = $unexpectedInstalledArray.Count
            status                    = $status
        }
    }

    $outputDirectory = Split-Path -Parent $OutputPath
    if (-not [string]::IsNullOrWhiteSpace($outputDirectory) -and -not (Test-Path -Path $outputDirectory)) {
        New-Item -Path $outputDirectory -ItemType Directory -Force | Out-Null
    }
    $report | ConvertTo-Json -Depth 12 | Set-Content -Path $OutputPath -Encoding utf8

    Write-Host ("VIPC audit complete for LabVIEW {0} ({1}-bit)." -f $lvInfo.NumericVersion, $SupportedBitness)
    Write-Host ("Expected packages: {0}" -f $expectedPackages.Count)
    Write-Host ("Installed packages: {0}" -f $installedPackages.Count)
    Write-Host ("Missing expected: {0}" -f $missingExpectedArray.Count)
    Write-Host ("Version mismatches: {0}" -f $versionMismatchesArray.Count)
    Write-Host ("Unexpected installed (informational): {0}" -f $unexpectedInstalledArray.Count)
    Write-Host ("Report: {0}" -f (Resolve-Path -Path $OutputPath).Path)

    if ($status -eq 'fail' -and $FailOnMismatch) {
        throw "VIPC audit failed: missing expected packages or version mismatches detected."
    }

    $global:LASTEXITCODE = 0
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
