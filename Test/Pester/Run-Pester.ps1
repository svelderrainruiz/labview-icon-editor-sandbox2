param(
    [AllowNull()]
    [AllowEmptyString()]
    [string]$LabVIEWVersion = '',

    [ValidateSet('32', '64', 'both', 'all', 'auto')]
    [string]$LabVIEWBitness = '64',

    [ValidateRange(0, 600000)]
    [int]$ConnectTimeoutMs = 120000,

    [ValidateRange(0, 1200000)]
    [int]$ProcessTimeoutMs = 300000,

    [switch]$RunDevModeTests,

    [switch]$CI,

    [Parameter(Mandatory = $false)]
    [string]$WorktreeRoot,

    [switch]$SkipWorktreeRootCheck
)

$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path -Path (Join-Path $PSScriptRoot '..\..')
$worktreeGuard = Join-Path $repoRoot 'Tooling\support\WorktreeGuard.ps1'
if (Test-Path -Path $worktreeGuard) {
    . $worktreeGuard
    $resolvedWorktreeRoot = Assert-RepoRootUnderWorktreeRoot -RepoRoot $repoRoot -WorktreeRoot $WorktreeRoot -Skip:$SkipWorktreeRootCheck -Context 'Run-Pester'
    Write-WorktreeContext -RepoRoot $repoRoot -WorktreeRoot $resolvedWorktreeRoot -Prefix 'Run-Pester'
    if ($resolvedWorktreeRoot) {
        $env:LVIE_WORKTREE_ROOT = $resolvedWorktreeRoot
    }
}
$versionHelper = Join-Path $repoRoot 'Tooling\support\LabVIEWVersion.ps1'
if (Test-Path -Path $versionHelper) {
    . $versionHelper
    $versionInfo = Get-LabVIEWVersionInfo -VersionInput $LabVIEWVersion -RepoRoot $repoRoot
    $LabVIEWVersion = $versionInfo.Year
    $env:LABVIEW_VERSION_RAW = $versionInfo.Raw
    $env:LABVIEW_VERSION_YEAR = $versionInfo.Year
    $env:LABVIEW_MINOR_REVISION = $versionInfo.MinorRevision.ToString()
    $env:LABVIEW_NUMERIC_VERSION = $versionInfo.NumericVersion
} elseif ([string]::IsNullOrWhiteSpace($LabVIEWVersion)) {
    $LabVIEWVersion = '2021'
}

$env:LABVIEW_VERSION = $LabVIEWVersion
$env:LABVIEW_BITNESS = $LabVIEWBitness
$env:LABVIEW_CONNECT_TIMEOUT_MS = $ConnectTimeoutMs.ToString()
$env:LABVIEW_PROCESS_TIMEOUT_MS = $ProcessTimeoutMs.ToString()
if ($PSBoundParameters.ContainsKey('RunDevModeTests')) {
    if ($RunDevModeTests) {
        $env:RUN_DEV_MODE_TESTS = '1'
    } else {
        Remove-Item Env:RUN_DEV_MODE_TESTS -ErrorAction SilentlyContinue
    }
}

$configuration = New-PesterConfiguration
$configuration.Run.Path = $PSScriptRoot
$configuration.Run.PassThru = $true
$configuration.Output.Verbosity = 'Detailed'

if ($CI) {
    $resultsDir = Join-Path $repoRoot 'TestResults'
    if (-not (Test-Path -Path $resultsDir)) {
        New-Item -Path $resultsDir -ItemType Directory | Out-Null
    }

    $configuration.TestResult.Enabled = $true
    $configuration.TestResult.OutputFormat = 'NUnitXml'
    $configuration.TestResult.OutputPath = (Join-Path $resultsDir ("pester-devmode-$LabVIEWVersion-$LabVIEWBitness.xml"))
}

$results = Invoke-Pester -Configuration $configuration
if ($results.FailedCount -gt 0) {
    exit 1
}
