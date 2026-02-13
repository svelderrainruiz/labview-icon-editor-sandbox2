#Requires -Version 7.0
<#
.SYNOPSIS
    Verifies that VIPC package versions are installed for a LabVIEW bitness.

.DESCRIPTION
    Uses VIPM CLI as the source of truth for both expected package versions
    from a .vipc file and installed package versions for a target LabVIEW
    version/bitness. Produces a JSON audit report and optionally fails on
    blocking mismatches.
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
    [bool]$FailOnMismatch = $true,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 7200)]
    [int]$VipmTimeoutSeconds = 180,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 10)]
    [int]$VipmMaxAttempts = 3,

    [Parameter(Mandatory = $false)]
    [ValidateRange(0, 600)]
    [int]$VipmRetryDelaySeconds = 5
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-FirstVipmErrorLine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [string]$StdOut,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [string]$StdErr
    )

    $combined = @($StdErr, $StdOut) -join [Environment]::NewLine
    if ([string]::IsNullOrWhiteSpace($combined)) {
        return $null
    }

    return (($combined -split "`r?`n") | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1)
}

try {
    $resolvedRepoRoot = (Resolve-Path -Path $RepoRoot -ErrorAction Stop).Path
    $resolvedVipcPath = Join-Path -Path $resolvedRepoRoot -ChildPath $VIPCPath
    if (-not (Test-Path -Path $resolvedVipcPath -PathType Leaf)) {
        throw "VIPC file not found at '$resolvedVipcPath'."
    }

    $versionHelper = Join-Path -Path $resolvedRepoRoot -ChildPath 'Tooling\support\LabVIEWVersion.ps1'
    if (-not (Test-Path -Path $versionHelper -PathType Leaf)) {
        throw "LabVIEW version helper not found at '$versionHelper'."
    }

    $vipmHelper = Join-Path -Path $resolvedRepoRoot -ChildPath 'Tooling\support\VipmCli.ps1'
    if (-not (Test-Path -Path $vipmHelper -PathType Leaf)) {
        throw "VIPM helper not found at '$vipmHelper'."
    }

    . $versionHelper
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

    $expectedResult = Invoke-VipmCliCommand `
        -Arguments $expectedArgs `
        -TimeoutSeconds $VipmTimeoutSeconds `
        -MaxAttempts $VipmMaxAttempts `
        -RetryDelaySeconds $VipmRetryDelaySeconds

    if ($expectedResult.ExitCode -ne 0) {
        $errorLine = Get-FirstVipmErrorLine -StdOut $expectedResult.StdOut -StdErr $expectedResult.StdErr
        $message = "VIPM expected package query failed with exit code $($expectedResult.ExitCode)."
        if ($errorLine) {
            $message = "$message $errorLine"
        }
        throw $message
    }

    $installedResult = Invoke-VipmCliCommand `
        -Arguments $installedArgs `
        -TimeoutSeconds $VipmTimeoutSeconds `
        -MaxAttempts $VipmMaxAttempts `
        -RetryDelaySeconds $VipmRetryDelaySeconds

    if ($installedResult.ExitCode -ne 0) {
        $errorLine = Get-FirstVipmErrorLine -StdOut $installedResult.StdOut -StdErr $installedResult.StdErr
        $message = "VIPM installed package query failed with exit code $($installedResult.ExitCode)."
        if ($errorLine) {
            $message = "$message $errorLine"
        }
        throw $message
    }

    $expectedPackages = @(ConvertFrom-VipmListPackage -OutputText (@($expectedResult.StdOut, $expectedResult.StdErr) -join [Environment]::NewLine))
    if ($expectedPackages.Count -eq 0) {
        throw "No expected package entries were discovered in '$resolvedVipcPath' via VIPM CLI."
    }

    $installedPackages = @(ConvertFrom-VipmListPackage -OutputText (@($installedResult.StdOut, $installedResult.StdErr) -join [Environment]::NewLine))
    $comparison = Compare-VipmPackageState -ExpectedPackages $expectedPackages -InstalledPackages $installedPackages

    $summary = [ordered]@{
        expected_count           = $expectedPackages.Count
        installed_count          = $installedPackages.Count
        missing_expected_count   = @($comparison.missing_expected).Count
        version_mismatch_count   = @($comparison.version_mismatches).Count
        unexpected_count         = @($comparison.unexpected_installed).Count
        status                   = if ($comparison.has_blocking_mismatch) { 'fail' } else { 'pass' }
    }

    $report = [ordered]@{
        generated_utc               = (Get-Date).ToUniversalTime().ToString('o')
        repo_root                   = $resolvedRepoRoot
        vipc_path                   = $resolvedVipcPath
        vipc_sha256                 = (Get-FileHash -Path $resolvedVipcPath -Algorithm SHA256).Hash
        labview_version_raw         = $lvInfo.Raw
        labview_year                = $lvInfo.Year
        labview_numeric             = $lvInfo.NumericVersion
        supported_bitness           = $SupportedBitness
        vipm_expected_command       = $expectedResult.Command
        vipm_installed_command      = $installedResult.Command
        vipm_expected_attempts      = $expectedResult.Attempts
        vipm_installed_attempts     = $installedResult.Attempts
        expected_packages_normalized = $expectedPackages
        installed_packages_normalized = $installedPackages
        missing_expected            = @($comparison.missing_expected)
        version_mismatches          = @($comparison.version_mismatches)
        unexpected_installed        = @($comparison.unexpected_installed)
        summary                     = $summary
    }

    $outputDirectory = Split-Path -Parent $OutputPath
    if (-not [string]::IsNullOrWhiteSpace($outputDirectory) -and -not (Test-Path -Path $outputDirectory)) {
        New-Item -Path $outputDirectory -ItemType Directory -Force | Out-Null
    }

    $report | ConvertTo-Json -Depth 12 | Set-Content -Path $OutputPath -Encoding utf8

    Write-Host ("VIPC audit complete for LabVIEW {0} ({1}-bit)." -f $lvInfo.NumericVersion, $SupportedBitness)
    Write-Host ("Expected packages: {0}" -f $expectedPackages.Count)
    Write-Host ("Installed packages: {0}" -f $installedPackages.Count)
    Write-Host ("Missing expected: {0}" -f @($comparison.missing_expected).Count)
    Write-Host ("Version mismatches: {0}" -f @($comparison.version_mismatches).Count)
    Write-Host ("Report: {0}" -f (Resolve-Path -Path $OutputPath).Path)

    if ($comparison.has_blocking_mismatch) {
        Write-Warning "VIPC audit detected blocking mismatches:"
        foreach ($entry in @($comparison.missing_expected)) {
            Write-Warning ("  Missing expected: {0}@{1}" -f $entry.package_id, $entry.expected_version)
        }
        foreach ($entry in @($comparison.version_mismatches)) {
            Write-Warning ("  Version mismatch: {0} expected={1} installed={2}" -f $entry.package_id, $entry.expected_version, $entry.installed_version)
        }

        if ($FailOnMismatch) {
            throw "VIPC audit failed: missing expected packages or version mismatches."
        }
    }

    if (@($comparison.unexpected_installed).Count -gt 0) {
        Write-Warning "Unexpected installed packages found (informational only):"
        foreach ($entry in @($comparison.unexpected_installed)) {
            Write-Warning ("  Unexpected installed: {0}@{1}" -f $entry.package_id, $entry.installed_version)
        }
    }

    $global:LASTEXITCODE = 0
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
