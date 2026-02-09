#Requires -Version 7.0
<#
.SYNOPSIS
    Runs the DevMode.NoLabVIEW smoke suite.

.DESCRIPTION
    Executes the selected smoke depth with RUN_DEV_MODE_TESTS enabled, emits
    NUnit XML + text/json summaries under TestResults/devmode-no-labview-smoke,
    and enforces integration coverage guards.

.PARAMETER LabVIEWVersion
    LabVIEW version year (e.g., 2021) or numeric version (e.g., 21.0).

.PARAMETER LabVIEWBitness
    Bitness to run: 32, 64, both, all, or auto.

.PARAMETER DevModeNoLabVIEWSmokeDepth
    Smoke suite depth: minimal, balanced, or full.

.PARAMETER ConnectTimeoutMs
    Timeout propagated to smoke tests via LABVIEW_CONNECT_TIMEOUT_MS.

.PARAMETER ProcessTimeoutMs
    Timeout propagated to smoke tests via LABVIEW_PROCESS_TIMEOUT_MS.

.PARAMETER RepoRoot
    Optional repository root override.

.PARAMETER WorktreeRoot
    Optional override for worktree-root guardrails.

.PARAMETER SkipWorktreeRootCheck
    Skip enforcing that RepoRoot is under the configured worktree root.

.PARAMETER AutoWorktree
    Auto-create a short-path worktree and re-run from there when needed.

.PARAMETER RunId
    Optional run identifier used for artifact isolation.

.PARAMETER ArtifactRoot
    Optional override for the artifact output root.

.PARAMETER CleanRoom
    If set, purge known output folders before and after the run.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [AllowNull()]
    [AllowEmptyString()]
    [string]$LabVIEWVersion = '',

    [Parameter(Mandatory = $false)]
    [ValidateSet('32', '64', 'both', 'all', 'auto')]
    [string]$LabVIEWBitness = '64',

    [Parameter(Mandatory = $false)]
    [ValidateSet('minimal', 'balanced', 'full')]
    [string]$DevModeNoLabVIEWSmokeDepth = 'balanced',

    [Parameter(Mandatory = $false)]
    [ValidateRange(0, 600000)]
    [int]$ConnectTimeoutMs = 180000,

    [Parameter(Mandatory = $false)]
    [ValidateRange(0, 1200000)]
    [int]$ProcessTimeoutMs = 300000,

    [Parameter(Mandatory = $false)]
    [string]$RepoRoot,

    [Parameter(Mandatory = $false)]
    [string]$WorktreeRoot,

    [switch]$SkipWorktreeRootCheck,

    [switch]$AutoWorktree,

    [Parameter(Mandatory = $false)]
    [string]$RunId,

    [Parameter(Mandatory = $false)]
    [string]$ArtifactRoot,

    [switch]$CleanRoom
)

$ErrorActionPreference = 'Stop'

function Resolve-RepoRoot {
    param([string]$PathOverride)

    if ($PathOverride) {
        if (-not (Test-Path -Path $PathOverride)) {
            throw "RepoRoot does not exist: $PathOverride"
        }
        return (Resolve-Path -Path $PathOverride).Path
    }

    $scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $PSCommandPath }
    $git = Get-Command git -ErrorAction SilentlyContinue
    if ($git) {
        try {
            $gitRoot = git -C $scriptRoot rev-parse --show-toplevel 2>$null
            if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($gitRoot)) {
                return (Resolve-Path -Path $gitRoot.Trim()).Path
            }
        } catch {
            Write-Verbose ("git rev-parse failed: {0}" -f $_.Exception.Message)
        }
    }

    return (Resolve-Path -Path (Join-Path $scriptRoot '..')).Path
}

function Resolve-SmokeBitnessList {
    param([string]$Bitness)

    switch ($Bitness.ToLowerInvariant()) {
        '32' { return @('32') }
        '64' { return @('64') }
        'both' { return @('64', '32') }
        'all' { return @('64', '32') }
        'auto' { return @('64', '32') }
        default { return @('64') }
    }
}

function Format-SmokeSummary {
    param(
        [string]$Bitness,
        [string]$Depth,
        [string[]]$SuitePaths,
        [object]$PesterResult,
        [object]$CoverageResult,
        [string]$XmlPath
    )

    $lines = @()
    $lines += "DevMode.NoLabVIEW Smoke Summary"
    $lines += "Bitness: $Bitness"
    $lines += "Depth: $Depth"
    $lines += "Suite:"
    foreach ($suitePath in $SuitePaths) {
        $lines += ("- {0}" -f $suitePath)
    }
    $lines += "Pester:"
    $lines += ("- TotalCount: {0}" -f $PesterResult.TotalCount)
    $lines += ("- PassedCount: {0}" -f $PesterResult.PassedCount)
    $lines += ("- FailedCount: {0}" -f $PesterResult.FailedCount)
    $lines += ("- SkippedCount: {0}" -f $PesterResult.SkippedCount)
    $lines += ("- InconclusiveCount: {0}" -f $PesterResult.InconclusiveCount)
    $lines += ("CoverageGuardPassed: {0}" -f $CoverageResult.Passed)
    $lines += ("NUnitXml: {0}" -f $XmlPath)
    if ($CoverageResult.Messages -and $CoverageResult.Messages.Count -gt 0) {
        $lines += "Coverage guard findings:"
        foreach ($message in $CoverageResult.Messages) {
            $lines += ("- {0}" -f $message)
        }
    }

    return ,$lines
}

$repoRoot = Resolve-RepoRoot -PathOverride $RepoRoot
$preflightScript = Join-Path $repoRoot 'Tooling\Invoke-Preflight.ps1'
$preflight = $null
if (Test-Path -Path $preflightScript) {
    . $preflightScript
    $scriptArgs = Convert-BoundParametersToArgumentList -BoundParameters $PSBoundParameters
    $relativeScript = if ($PSCommandPath) { Get-RepoRelativePath -RepoRoot $repoRoot -Path $PSCommandPath } else { $null }
    $preflight = Invoke-Preflight `
        -RepoRoot $repoRoot `
        -WorktreeRoot $WorktreeRoot `
        -LabVIEWVersion $LabVIEWVersion `
        -LabVIEWBitness $LabVIEWBitness `
        -SkipWorktreeRootCheck:$SkipWorktreeRootCheck `
        -AutoWorktree:$AutoWorktree `
        -ScriptPath $relativeScript `
        -ScriptArguments $scriptArgs `
        -RunId $RunId `
        -ArtifactRoot $ArtifactRoot `
        -CleanRoom:$CleanRoom
    if ($preflight.Reinvoked) {
        return
    }
    $repoRoot = $preflight.RepoRoot
}

$versionHelper = Join-Path $repoRoot 'Tooling\support\LabVIEWVersion.ps1'
if (-not (Test-Path -Path $versionHelper)) {
    throw "LabVIEW version helper not found at $versionHelper"
}

$smokeHelper = Join-Path $repoRoot 'Tooling\support\DevModeNoLabVIEWSmoke.ps1'
if (-not (Test-Path -Path $smokeHelper)) {
    throw "Smoke helper not found at $smokeHelper"
}

. $versionHelper
. $smokeHelper

$versionInfo = Get-LabVIEWVersionInfo -VersionInput $LabVIEWVersion -RepoRoot $repoRoot
$LabVIEWVersion = $versionInfo.Year
if ([string]::IsNullOrWhiteSpace($LabVIEWVersion)) {
    throw "LabVIEW version could not be resolved. Check .lvversion."
}

Assert-DevModeNoLabVIEWProjectFileClean -RepoRoot $repoRoot -ProjectRelativePath 'lv_icon_editor.lvproj'

$suite = Get-DevModeNoLabVIEWSmokeSuite -Depth $DevModeNoLabVIEWSmokeDepth
$suiteTests = @($suite.Tests)
if (-not $suiteTests -or $suiteTests.Count -eq 0) {
    throw "DevMode.NoLabVIEW smoke suite '$DevModeNoLabVIEWSmokeDepth' is empty."
}

$suitePaths = @()
foreach ($test in $suiteTests) {
    $fullPath = [System.IO.Path]::GetFullPath((Join-Path $repoRoot $test.Path))
    if (-not (Test-Path -Path $fullPath -PathType Leaf)) {
        throw "Smoke test file not found: $fullPath"
    }
    $suitePaths += $fullPath
}

$resultsRoot = Join-Path $repoRoot 'TestResults\devmode-no-labview-smoke'
New-Item -Path $resultsRoot -ItemType Directory -Force | Out-Null

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$bitnesses = Resolve-SmokeBitnessList -Bitness $LabVIEWBitness
$failures = New-Object System.Collections.Generic.List[string]
$runSummaries = @()

$savedEnv = @{
    RUN_DEV_MODE_TESTS       = $env:RUN_DEV_MODE_TESTS
    LABVIEW_VERSION          = $env:LABVIEW_VERSION
    LABVIEW_VERSION_YEAR     = $env:LABVIEW_VERSION_YEAR
    LABVIEW_BITNESS          = $env:LABVIEW_BITNESS
    LABVIEW_CONNECT_TIMEOUT_MS = $env:LABVIEW_CONNECT_TIMEOUT_MS
    LABVIEW_PROCESS_TIMEOUT_MS = $env:LABVIEW_PROCESS_TIMEOUT_MS
    LVIE_SKIP_WORKTREE_ROOT_CHECK = $env:LVIE_SKIP_WORKTREE_ROOT_CHECK
    LVIE_SKIP_DEVMODE_PROCESS_CHECK = $env:LVIE_SKIP_DEVMODE_PROCESS_CHECK
}

try {
    $env:RUN_DEV_MODE_TESTS = '1'
    $env:LABVIEW_VERSION = $LabVIEWVersion
    $env:LABVIEW_VERSION_YEAR = $LabVIEWVersion
    $env:LABVIEW_CONNECT_TIMEOUT_MS = $ConnectTimeoutMs.ToString()
    $env:LABVIEW_PROCESS_TIMEOUT_MS = $ProcessTimeoutMs.ToString()
    $env:LVIE_SKIP_DEVMODE_PROCESS_CHECK = '1'
    Write-Host 'DevMode process check bypass enabled for smoke run.'
    if ($SkipWorktreeRootCheck) {
        $env:LVIE_SKIP_WORKTREE_ROOT_CHECK = '1'
    }

    foreach ($bitness in $bitnesses) {
        Write-Host ("Running DevMode.NoLabVIEW smoke ({0}-bit, depth={1})..." -f $bitness, $DevModeNoLabVIEWSmokeDepth)
        $env:LABVIEW_BITNESS = $bitness

        $xmlPath = Join-Path $resultsRoot ("pester-devmode-no-labview-smoke-{0}-{1}-bit-{2}.xml" -f $LabVIEWVersion, $bitness, $timestamp)
        $summaryPath = Join-Path $resultsRoot ("summary-{0}-bit-{1}.txt" -f $bitness, $timestamp)

        $configuration = New-PesterConfiguration
        $configuration.Run.Path = @($suitePaths)
        $configuration.Run.PassThru = $true
        $configuration.Output.Verbosity = 'Detailed'
        $configuration.TestResult.Enabled = $true
        $configuration.TestResult.OutputFormat = 'NUnitXml'
        $configuration.TestResult.OutputPath = $xmlPath

        $result = Invoke-Pester -Configuration $configuration
        $coverage = Test-DevModeNoLabVIEWSmokeCoverage -PesterResult $result -Suite $suite
        $summaryLines = Format-SmokeSummary -Bitness $bitness -Depth $DevModeNoLabVIEWSmokeDepth -SuitePaths $suitePaths -PesterResult $result -CoverageResult $coverage -XmlPath $xmlPath
        Set-Content -Path $summaryPath -Value $summaryLines -Encoding ascii

        $runSummary = [pscustomobject]@{
            Bitness        = $bitness
            Depth          = $DevModeNoLabVIEWSmokeDepth
            TotalCount     = $result.TotalCount
            PassedCount    = $result.PassedCount
            FailedCount    = $result.FailedCount
            SkippedCount   = $result.SkippedCount
            CoveragePassed = $coverage.Passed
            CoverageMessages = @($coverage.Messages)
            XmlPath        = $xmlPath
            SummaryPath    = $summaryPath
        }
        $runSummaries += $runSummary

        if ($result.FailedCount -gt 0) {
            $failures.Add(("Smoke tests failed for {0}-bit (failed={1})." -f $bitness, $result.FailedCount))
        }
        if (-not $coverage.Passed) {
            foreach ($message in $coverage.Messages) {
                $failures.Add(("{0}-bit coverage guard: {1}" -f $bitness, $message))
            }
        }
    }
}
finally {
    foreach ($key in $savedEnv.Keys) {
        $value = $savedEnv[$key]
        if ($null -eq $value) {
            Remove-Item ("Env:{0}" -f $key) -ErrorAction SilentlyContinue
        } else {
            Set-Item ("Env:{0}" -f $key) -Value $value
        }
    }

    if ($preflight -and $preflight.CleanRoomAfter) {
        Invoke-PreflightCleanup -RepoRoot $preflight.RepoRoot -Phase 'after'
    }
}

$summaryJsonPath = Join-Path $resultsRoot ("summary-{0}.json" -f $timestamp)
$summaryTextPath = Join-Path $resultsRoot ("summary-{0}.txt" -f $timestamp)
$summaryPayload = [pscustomobject]@{
    TimestampUtc = (Get-Date).ToUniversalTime().ToString('o')
    LabVIEWVersion = $LabVIEWVersion
    LabVIEWBitness = $LabVIEWBitness
    Depth = $DevModeNoLabVIEWSmokeDepth
    Results = @($runSummaries)
    Failures = @($failures)
}

$summaryPayload | ConvertTo-Json -Depth 8 | Set-Content -Path $summaryJsonPath -Encoding utf8
$summaryText = @(
    "DevMode.NoLabVIEW smoke gate",
    "LabVIEWVersion: $LabVIEWVersion",
    "BitnessInput: $LabVIEWBitness",
    "Depth: $DevModeNoLabVIEWSmokeDepth",
    "ResultCount: $($runSummaries.Count)",
    "FailureCount: $($failures.Count)",
    "SummaryJson: $summaryJsonPath"
)
Set-Content -Path $summaryTextPath -Value $summaryText -Encoding ascii

if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_STEP_SUMMARY)) {
    $summaryLines = @()
    $summaryLines += '### DevMode.NoLabVIEW Smoke'
    $summaryLines += ''
    $summaryLines += "- Version: $LabVIEWVersion"
    $summaryLines += "- Depth: $DevModeNoLabVIEWSmokeDepth"
    $summaryLines += "- Result count: $($runSummaries.Count)"
    $summaryLines += "- Failures: $($failures.Count)"
    foreach ($entry in $runSummaries) {
        $summaryLines += "- $($entry.Bitness)-bit: total=$($entry.TotalCount), failed=$($entry.FailedCount), skipped=$($entry.SkippedCount), coverage=$($entry.CoveragePassed)"
    }
    if ($failures.Count -gt 0) {
        $summaryLines += ''
        $summaryLines += 'Failures:'
        foreach ($failure in $failures) {
            $summaryLines += "- $failure"
        }
    }
    Add-Content -Path $env:GITHUB_STEP_SUMMARY -Value ($summaryLines -join [Environment]::NewLine)
}

if ($failures.Count -gt 0) {
    $joinedFailures = ($failures | Select-Object -Unique) -join '; '
    throw "DevMode.NoLabVIEW smoke gate failed. $joinedFailures"
}

Write-Host ("DevMode.NoLabVIEW smoke gate passed (depth={0}, bitness={1})." -f $DevModeNoLabVIEWSmokeDepth, ($bitnesses -join ','))
Write-Host ("Smoke artifacts: {0}" -f $resultsRoot)
