#Requires -Version 7.0
<#
.SYNOPSIS
    Enforces the LabVIEW version contract against .lvversion.

.DESCRIPTION
    Reads .lvversion from the repo and compares it with any declared or expected
    LabVIEW version inputs (parameters or environment variables). Throws when
    a mismatch is detected unless AllowMismatch is specified.

.PARAMETER RepoRoot
    Repository root that contains .lvversion.

.PARAMETER ExpectedVersion
    Optional expected version (year or numeric, e.g. 2021 or 21.0) to compare
    against .lvversion.

.PARAMETER AllowMismatch
    If set, mismatches are reported as warnings instead of errors.

.PARAMETER Context
    Optional context label used in messages.

.PARAMETER WriteSummary
    When set, write a summary entry to the GitHub Step Summary file.

.PARAMETER SummaryPath
    Optional override path for summary output (defaults to GITHUB_STEP_SUMMARY).

.PARAMETER EnforceProjectLvVersion
    When set, also validates lv_icon_editor.lvproj root LVVersion against
    .lvversion and enforces that the project parent path equals RepoRoot.

.PARAMETER ProjectPath
    Optional project path override used when EnforceProjectLvVersion is set.
    Falls back to LVIE_PROJECT_PATH, PROJECT_PATH, then <RepoRoot>\lv_icon_editor.lvproj.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$RepoRoot,

    [Parameter(Mandatory = $false)]
    [string]$ExpectedVersion,

    [switch]$AllowMismatch,

    [Parameter(Mandatory = $false)]
    [string]$Context,

    [switch]$WriteSummary,

    [Parameter(Mandatory = $false)]
    [string]$SummaryPath,

    [switch]$EnforceProjectLvVersion,

    [Parameter(Mandatory = $false)]
    [string]$ProjectPath
)

$ErrorActionPreference = 'Stop'

function Resolve-RepoRoot {
    param([string]$Path)

    if (-not [string]::IsNullOrWhiteSpace($Path)) {
        return (Resolve-Path -Path $Path -ErrorAction Stop).Path
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

function Resolve-VersionInput {
    param([string]$Year, [string]$Minor)

    if ([string]::IsNullOrWhiteSpace($Year)) {
        if (-not [string]::IsNullOrWhiteSpace($Minor)) {
            throw "LabVIEW version year is required when a minor revision is provided."
        }
        return $null
    }

    if ([string]::IsNullOrWhiteSpace($Minor)) {
        return $Year
    }

    return "$Year.$Minor"
}

function Add-DeclaredVersion {
    param(
        [string]$Source,
        [string]$VersionInput
    )

    if ([string]::IsNullOrWhiteSpace($VersionInput)) {
        return $null
    }

    $info = Get-LabVIEWVersionInfo -VersionInput $VersionInput
    return [pscustomobject]@{
        Source        = $Source
        Raw           = $info.Raw
        Year          = $info.Year
        MinorRevision = [int]$info.MinorRevision
    }
}

function Resolve-SummaryPath {
    param([string]$OverridePath)

    if (-not [string]::IsNullOrWhiteSpace($OverridePath)) {
        return $OverridePath
    }

    return $env:GITHUB_STEP_SUMMARY
}

function ConvertTo-NormalizedPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    return ([System.IO.Path]::GetFullPath($Path)).TrimEnd('\', '/')
}

function Resolve-ProjectPathForContract {
    param(
        [string]$ProjectPathInput,
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot
    )

    $candidate = $null
    $source = $null
    if (-not [string]::IsNullOrWhiteSpace($ProjectPathInput)) {
        $candidate = $ProjectPathInput
        $source = 'parameter:ProjectPath'
    } elseif (-not [string]::IsNullOrWhiteSpace($env:LVIE_PROJECT_PATH)) {
        $candidate = $env:LVIE_PROJECT_PATH
        $source = '$env:LVIE_PROJECT_PATH'
    } elseif (-not [string]::IsNullOrWhiteSpace($env:PROJECT_PATH)) {
        $candidate = $env:PROJECT_PATH
        $source = '$env:PROJECT_PATH'
    } else {
        $candidate = 'lv_icon_editor.lvproj'
        $source = 'default:lv_icon_editor.lvproj'
    }

    $resolvedCandidate = if ([System.IO.Path]::IsPathRooted($candidate)) {
        $candidate
    } else {
        Join-Path -Path $RepoRoot -ChildPath $candidate
    }

    if (-not (Test-Path -Path $resolvedCandidate -PathType Leaf)) {
        throw ("Project version contract failed: project file was not found at '{0}' (source: {1})." -f $resolvedCandidate, $source)
    }

    return [pscustomobject]@{
        Path   = (Resolve-Path -Path $resolvedCandidate -ErrorAction Stop).Path
        Source = $source
    }
}

function Get-ProjectLvVersionInfo {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectFilePath
    )

    $rawXml = Get-Content -Path $ProjectFilePath -Raw -ErrorAction Stop
    try {
        [xml]$projectXml = $rawXml
    } catch {
        throw ("Project version contract failed: unable to parse project XML at '{0}'. {1}" -f $ProjectFilePath, $_.Exception.Message)
    }

    $projectNode = $projectXml.Project
    if (-not $projectNode -and $projectXml.DocumentElement) {
        $projectNode = $projectXml.DocumentElement
    }
    if (-not $projectNode -or $projectNode.Name -ne 'Project') {
        throw ("Project version contract failed: root Project node was not found in '{0}'." -f $ProjectFilePath)
    }

    $projectLvVersion = $projectNode.GetAttribute('LVVersion')
    if ([string]::IsNullOrWhiteSpace($projectLvVersion)) {
        throw ("Project version contract failed: root Project LVVersion attribute is missing in '{0}'." -f $ProjectFilePath)
    }
    if (-not ($projectLvVersion -match '^\d{8}$')) {
        throw ("Project version contract failed: LVVersion '{0}' in '{1}' is invalid. Expected 8 digits such as 21008000." -f $projectLvVersion, $ProjectFilePath)
    }

    $numericMajor = [int]$projectLvVersion.Substring(0, 2)
    $minorRevision = [int]$projectLvVersion.Substring(2, 2)
    $year = (2000 + $numericMajor).ToString()

    return [pscustomobject]@{
        Raw           = $projectLvVersion
        Year          = $year
        NumericMajor  = $numericMajor
        MinorRevision = $minorRevision
        NumericVersion = "$numericMajor.$minorRevision"
    }
}

function Write-VersionSummary {
    param(
        [string]$Path,
        [string]$ContextLabel,
        [string]$Status,
        [pscustomobject]$RepoInfo,
        [string[]]$Mismatches,
        [string]$Guidance,
        [string]$ProjectContractStatus,
        [string]$ProjectContractDetails
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return
    }

    $lines = @()
    $lines += "## LabVIEW Version Contract"
    if (-not [string]::IsNullOrWhiteSpace($ContextLabel)) {
        $lines += "- Context: $ContextLabel"
    }
    $lines += ("- .lvversion: {0} (year {1}, minor {2})" -f $RepoInfo.Raw, $RepoInfo.Year, $RepoInfo.MinorRevision)
    if (-not [string]::IsNullOrWhiteSpace($ProjectContractStatus)) {
        $lines += ("- Project contract: {0}" -f $ProjectContractStatus)
    }
    if (-not [string]::IsNullOrWhiteSpace($ProjectContractDetails)) {
        $lines += ("- Project details: {0}" -f $ProjectContractDetails)
    }
    $lines += ("- Status: {0}" -f $Status)
    if ($Mismatches -and $Mismatches.Count -gt 0) {
        $lines += ("- Mismatches: {0}" -f ($Mismatches -join '; '))
    }
    if (-not [string]::IsNullOrWhiteSpace($Guidance)) {
        $lines += ("- Guidance: {0}" -f $Guidance)
    }
    $lines += ""

    $lines | Out-File -FilePath $Path -Append -Encoding utf8
}

$repoRootResolved = Resolve-RepoRoot -Path $RepoRoot
$versionHelper = Join-Path $repoRootResolved 'Tooling/support/LabVIEWVersion.ps1'
if (-not (Test-Path -Path $versionHelper)) {
    throw "LabVIEW version helper not found at $versionHelper"
}

. $versionHelper

$repoInfo = Get-LabVIEWVersionInfo -RepoRoot $repoRootResolved
$repoYear = [string]$repoInfo.Year
$repoMinor = [int]$repoInfo.MinorRevision

$declared = @()

if (-not [string]::IsNullOrWhiteSpace($ExpectedVersion)) {
    $declared += Add-DeclaredVersion -Source 'expected' -VersionInput $ExpectedVersion
}

$requiredVersion = $env:LVIE_REQUIRED_LABVIEW_VERSION
if (-not [string]::IsNullOrWhiteSpace($requiredVersion)) {
    $declared += Add-DeclaredVersion -Source 'LVIE_REQUIRED_LABVIEW_VERSION' -VersionInput $requiredVersion
}

$requiredFromParts = Resolve-VersionInput -Year $env:LVIE_REQUIRED_LABVIEW_VERSION_YEAR -Minor $env:LVIE_REQUIRED_LABVIEW_MINOR_REVISION
if ($requiredFromParts) {
    $declared += Add-DeclaredVersion -Source 'LVIE_REQUIRED_LABVIEW_VERSION_YEAR/MINOR' -VersionInput $requiredFromParts
}

$envFromParts = Resolve-VersionInput -Year $env:LABVIEW_VERSION_YEAR -Minor $env:LABVIEW_MINOR_REVISION
if ($envFromParts) {
    $declared += Add-DeclaredVersion -Source 'LABVIEW_VERSION_YEAR/MINOR' -VersionInput $envFromParts
}

$declared = $declared | Where-Object { $_ }

$mismatches = @()
foreach ($entry in $declared) {
    if ($entry.Year -ne $repoYear -or $entry.MinorRevision -ne $repoMinor) {
        $mismatches += ("{0}={1} (year {2}, minor {3})" -f $entry.Source, $entry.Raw, $entry.Year, $entry.MinorRevision)
    }
}

$projectContractStatus = if ($EnforceProjectLvVersion) { 'enabled' } else { 'not-enforced' }
$projectContractDetails = $null
if ($EnforceProjectLvVersion) {
    $projectResolution = Resolve-ProjectPathForContract -ProjectPathInput $ProjectPath -RepoRoot $repoRootResolved
    $projectInfo = Get-ProjectLvVersionInfo -ProjectFilePath $projectResolution.Path

    $projectParent = ConvertTo-NormalizedPath -Path (Split-Path -Path $projectResolution.Path -Parent)
    $repoRootNormalized = ConvertTo-NormalizedPath -Path $repoRootResolved
    if (-not $projectParent.Equals($repoRootNormalized, [System.StringComparison]::OrdinalIgnoreCase)) {
        $mismatches += ("project parent '{0}' does not match RepoRoot '{1}' (source: {2})" -f $projectParent, $repoRootNormalized, $projectResolution.Source)
    }

    $repoNumericMajor = [int]$repoInfo.NumericMajor
    if ($projectInfo.NumericMajor -ne $repoNumericMajor -or $projectInfo.MinorRevision -ne $repoMinor) {
        $mismatches += ("project LVVersion={0} -> {1} (year {2}, minor {3}) does not match .lvversion {4} (year {5}, minor {6})" -f $projectInfo.Raw, $projectInfo.NumericVersion, $projectInfo.Year, $projectInfo.MinorRevision, $repoInfo.Raw, $repoYear, $repoMinor)
    }

    $projectContractStatus = 'ok'
    $projectContractDetails = ("path={0}; source={1}; LVVersion={2} -> {3} (year {4}, minor {5})" -f $projectResolution.Path, $projectResolution.Source, $projectInfo.Raw, $projectInfo.NumericVersion, $projectInfo.Year, $projectInfo.MinorRevision)
}

$contextLabel = if ([string]::IsNullOrWhiteSpace($Context)) { '' } else { " [$Context]" }
$baseMessage = "LabVIEW version contract${contextLabel}: .lvversion=$($repoInfo.Raw) (year $repoYear, minor $repoMinor)."
$guidance = "Update .lvversion or remove overrides (LVIE_REQUIRED_LABVIEW_VERSION*, LABVIEW_VERSION_YEAR/MINOR). For local runs, pass -AllowVersionMismatch to bypass."
if ($EnforceProjectLvVersion) {
    $guidance += " Ensure Project LVVersion matches .lvversion and that Split-Path -Parent PROJECT_PATH equals RepoRoot."
}
$summaryPath = $null
if ($WriteSummary) {
    $summaryPath = Resolve-SummaryPath -OverridePath $SummaryPath
    if ([string]::IsNullOrWhiteSpace($summaryPath)) {
        Write-Warning "WriteSummary requested, but no summary path was provided and GITHUB_STEP_SUMMARY is not set."
    }
}

if ($mismatches.Count -gt 0) {
    $details = "Mismatched declarations: {0}" -f ($mismatches -join '; ')
    $message = "$baseMessage $details $guidance"
    $summaryStatus = if ($AllowMismatch) { 'warning' } else { 'failed' }
    if ($EnforceProjectLvVersion) {
        $projectContractStatus = if ($AllowMismatch) { 'warning' } else { 'failed' }
    }
    if ($summaryPath) {
        Write-VersionSummary -Path $summaryPath -ContextLabel $Context -Status $summaryStatus -RepoInfo $repoInfo -Mismatches $mismatches -Guidance $guidance -ProjectContractStatus $projectContractStatus -ProjectContractDetails $projectContractDetails
    }
    if ($AllowMismatch) {
        Write-Warning $message
    } else {
        throw $message
    }
} else {
    if ($summaryPath) {
        Write-VersionSummary -Path $summaryPath -ContextLabel $Context -Status 'ok' -RepoInfo $repoInfo -Mismatches @() -Guidance $null -ProjectContractStatus $projectContractStatus -ProjectContractDetails $projectContractDetails
    }
    if ($EnforceProjectLvVersion -and -not [string]::IsNullOrWhiteSpace($projectContractDetails)) {
        Write-Host "$baseMessage Project contract OK. $projectContractDetails"
    } else {
        Write-Host "$baseMessage OK."
    }
}

Write-Output $repoInfo

