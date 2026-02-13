<#
.SYNOPSIS
    Applies a .vipc file to a given LabVIEW version/bitness via VIPM CLI.

.EXAMPLE
    .\ApplyVIPC.ps1 -LabVIEWVersion "2026" -SupportedBitness "64" -RepoRoot "C:\repo" -VIPCPath ".github/actions/apply-vipc/runner_dependencies.vipc" -Verbose
#>

[CmdletBinding()]
Param (
    [AllowNull()]
    [AllowEmptyString()]
    [string]$LabVIEWVersion = '',

    [ValidateSet('32', '64')]
    [string]$SupportedBitness,

    [string]$RepoRoot,

    [string]$VIPCPath,

    [string]$WorktreeRoot,

    [switch]$SkipWorktreeRootCheck,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 7200)]
    [int]$VipmTimeoutSeconds = 600,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 10)]
    [int]$VipmMaxAttempts = 3,

    [Parameter(Mandatory = $false)]
    [ValidateRange(0, 600)]
    [int]$VipmRetryDelaySeconds = 5
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Verbose "Script Name: $($MyInvocation.MyCommand.Definition)"
Write-Verbose "Parameters provided:"
Write-Verbose " - LabVIEWVersion:            $LabVIEWVersion"
Write-Verbose " - SupportedBitness:          $SupportedBitness"
Write-Verbose " - RepoRoot:                  $RepoRoot"
Write-Verbose " - VIPCPath:                  $VIPCPath"
Write-Verbose " - VipmTimeoutSeconds:        $VipmTimeoutSeconds"
Write-Verbose " - VipmMaxAttempts:           $VipmMaxAttempts"
Write-Verbose " - VipmRetryDelaySeconds:     $VipmRetryDelaySeconds"

try {
    Write-Verbose "Attempting to resolve RepoRoot..."
    $ResolvedRepoRoot = (Resolve-Path -Path $RepoRoot -ErrorAction Stop).Path
    Write-Verbose "ResolvedRepoRoot: $ResolvedRepoRoot"

    $versionHelper = Join-Path -Path $ResolvedRepoRoot -ChildPath 'Tooling\support\LabVIEWVersion.ps1'
    if (-not (Test-Path -Path $versionHelper)) {
        throw "LabVIEW version helper not found at $versionHelper"
    }
    . $versionHelper

    if ([string]::IsNullOrWhiteSpace($LabVIEWVersion)) {
        $lvInfoFallback = Get-LabVIEWVersionInfo -VersionInput $LabVIEWVersion -RepoRoot $ResolvedRepoRoot
        $LabVIEWVersion = $lvInfoFallback.Raw
        if ($PSBoundParameters -ne $null) {
            $PSBoundParameters['LabVIEWVersion'] = $LabVIEWVersion
        }
        Write-Warning "LabVIEWVersion was not provided; defaulting to .lvversion ($LabVIEWVersion)."
    }
    else {
        $repoInfo = Get-LabVIEWVersionInfo -RepoRoot $ResolvedRepoRoot
        $inputInfo = Get-LabVIEWVersionInfo -VersionInput $LabVIEWVersion -RepoRoot $ResolvedRepoRoot
        if ($repoInfo.Year -ne $inputInfo.Year -or $repoInfo.MinorRevision -ne $inputInfo.MinorRevision) {
            throw "LabVIEWVersion '$($inputInfo.Raw)' does not match .lvversion '$($repoInfo.Raw)'."
        }
    }

    $preflightScript = Join-Path -Path $ResolvedRepoRoot -ChildPath 'Tooling\Invoke-Preflight.ps1'
    if (Test-Path -Path $preflightScript) {
        try {
            . $preflightScript
            $scriptArgs = Convert-BoundParametersToArgumentList -BoundParameters $PSBoundParameters
            $relativeScript = if ($PSCommandPath) { Get-RepoRelativePath -RepoRoot $ResolvedRepoRoot -Path $PSCommandPath } else { $null }
            $preflight = Invoke-Preflight `
                -RepoRoot $ResolvedRepoRoot `
                -WorktreeRoot $WorktreeRoot `
                -LabVIEWVersion $LabVIEWVersion `
                -LabVIEWBitness $SupportedBitness `
                -SkipWorktreeRootCheck:$SkipWorktreeRootCheck `
                -AutoWorktree:$false `
                -ScriptPath $relativeScript `
                -ScriptArguments $scriptArgs
            if ($preflight.Reinvoked) {
                return
            }
            $ResolvedRepoRoot = $preflight.RepoRoot
        }
        catch {
            if ($env:GITHUB_ACTIONS -eq 'true') {
                throw
            }

            Write-Warning ("Preflight failed outside GitHub Actions; continuing. Details: {0}" -f $_.Exception.Message)
        }
    }

    $ResolvedVIPCPath = Join-Path -Path $ResolvedRepoRoot -ChildPath $VIPCPath -ErrorAction Stop
    Write-Verbose "ResolvedVIPCPath: $ResolvedVIPCPath"

    if (-not (Test-Path -Path $ResolvedVIPCPath -PathType Leaf)) {
        throw "The .vipc file does not exist at '$ResolvedVIPCPath'."
    }

    $vipcConfigHelper = Join-Path -Path $ResolvedRepoRoot -ChildPath 'Tooling\support\VipcConfig.ps1'
    if (-not (Test-Path -Path $vipcConfigHelper)) {
        throw "VIPC config helper not found at $vipcConfigHelper"
    }
    . $vipcConfigHelper

    $vipmHelper = Join-Path -Path $ResolvedRepoRoot -ChildPath 'Tooling\support\VipmCli.ps1'
    if (-not (Test-Path -Path $vipmHelper)) {
        throw "VIPM helper not found at $vipmHelper"
    }
    . $vipmHelper

    $lvInfo = Get-LabVIEWVersionInfo -VersionInput $LabVIEWVersion -RepoRoot $ResolvedRepoRoot
    $targetLvYear = ConvertTo-VipmLabVIEWYear -VersionInput $lvInfo
    $vipmVersionLabel = if ($SupportedBitness -eq '64') {
        "$($lvInfo.NumericVersion) (64-bit)"
    }
    else {
        $lvInfo.NumericVersion
    }

    $vipcConfig = Get-VipcConfigInfo -VipcPath $ResolvedVIPCPath
    Write-Verbose ("VIPC target name: {0}" -f $vipcConfig.TargetName)
    Write-Verbose ("VIPC target version (raw): {0}" -f $vipcConfig.TargetVersionRaw)
    Write-Verbose ("VIPC target version (numeric): {0}" -f $vipcConfig.TargetVersionNumeric)
    Write-Verbose ("VIPC package count: {0}" -f $vipcConfig.PackageCount)

    if ($vipcConfig.TargetVersionNumeric -ne $lvInfo.NumericVersion) {
        Write-Warning ("VIPC target version mismatch detected. Requested LabVIEW numeric version: {0}. VIPC target version: {1} (raw: {2}). Continuing with VIPM CLI apply; enforce installed dependency versions with Assert-VipcApplied." -f $lvInfo.NumericVersion, $vipcConfig.TargetVersionNumeric, $vipcConfig.TargetVersionRaw)
    }

    $vipmArgs = @(
        '--labview-version', $targetLvYear,
        '--labview-bitness', $SupportedBitness,
        'install', $ResolvedVIPCPath
    )

    Write-Output "Applying dependencies via VIPM CLI for LabVIEW $vipmVersionLabel..."

    $result = Invoke-VipmCliCommand `
        -Arguments $vipmArgs `
        -TimeoutSeconds $VipmTimeoutSeconds `
        -MaxAttempts $VipmMaxAttempts `
        -RetryDelaySeconds $VipmRetryDelaySeconds

    Write-Output ("Executing: {0}" -f $result.Command)

    if (-not [string]::IsNullOrWhiteSpace($result.StdOut)) {
        $result.StdOut -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { Write-Host $_ }
    }

    if (-not [string]::IsNullOrWhiteSpace($result.StdErr)) {
        $result.StdErr -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { Write-Warning $_ }
    }

    if ($result.ExitCode -ne 0) {
        throw "vipm install failed with exit code $($result.ExitCode) after $($result.Attempts) attempt(s)."
    }

    if (Get-Command g-cli -ErrorAction SilentlyContinue) {
        try {
            Write-Output ("Closing LabVIEW {0} ({1}-bit) after VIPC apply..." -f $targetLvYear, $SupportedBitness)
            & g-cli --lv-ver $targetLvYear --arch $SupportedBitness QuitLabVIEW | Out-Null
        }
        catch {
            Write-Warning ("Failed to close LabVIEW {0} ({1}-bit): {2}" -f $targetLvYear, $SupportedBitness, $_.Exception.Message)
        }
    }

    $global:LASTEXITCODE = 0
    Write-Host "Successfully applied dependencies to LabVIEW: $vipmVersionLabel"
}
catch {
    Write-Error "An error occurred while applying the .vipc dependencies. Details: $($_.Exception.Message)"
    exit 1
}
