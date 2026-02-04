#Requires -Version 7.0
<#
.SYNOPSIS
    Validates that the current runner is registered with expected labels.

.DESCRIPTION
    Queries the GitHub Actions API for the current runner name and verifies
    required labels are present. Intended for self-hosted runners.

.PARAMETER ExpectedLabel
    Primary label expected for this workflow run. Defaults to LVIE_EXPECTED_RUNNER_LABEL.

.PARAMETER ExpectedLabels
    Additional labels to require.

.PARAMETER CanonicalLabel
    Canonical label that must always be present. Defaults to self-hosted-windows-lv
    or LVIE_CANONICAL_RUNNER_LABEL when provided.

.PARAMETER RequireCanonicalLabel
    Force canonical label requirement (default: true).

.PARAMETER RequireLabel
    Fail if labels cannot be validated (default: true).

.PARAMETER Repo
    GitHub repository in owner/name format. Defaults to GITHUB_REPOSITORY.

.PARAMETER RunnerName
    Runner name to match. Defaults to RUNNER_NAME.

.PARAMETER Token
    GitHub token for API access. Defaults to GITHUB_TOKEN.
#>

[CmdletBinding()]
param(
    [string]$ExpectedLabel,
    [string[]]$ExpectedLabels,
    [string]$CanonicalLabel,
    [switch]$RequireCanonicalLabel,
    [switch]$RequireLabel,
    [string]$Repo,
    [string]$RunnerName,
    [string]$Token
)

$ErrorActionPreference = 'Stop'
$requireLabelEnabled = $RequireLabel.IsPresent -or -not $PSBoundParameters.ContainsKey('RequireLabel')
$requireCanonicalEnabled = $RequireCanonicalLabel.IsPresent -or -not $PSBoundParameters.ContainsKey('RequireCanonicalLabel')

function Test-Truthy {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    $normalized = $Value.Trim().ToLowerInvariant()
    return ($normalized -notin @('0', 'false', 'no'))
}

if (Test-Truthy -Value $env:LVIE_SKIP_RUNNER_LABEL_CHECK) {
    Write-Host 'Runner label check skipped (LVIE_SKIP_RUNNER_LABEL_CHECK=true).'
    return
}

if ([string]::IsNullOrWhiteSpace($ExpectedLabel)) {
    $ExpectedLabel = $env:LVIE_EXPECTED_RUNNER_LABEL
}
if ([string]::IsNullOrWhiteSpace($CanonicalLabel)) {
    $CanonicalLabel = $env:LVIE_CANONICAL_RUNNER_LABEL
}
if ([string]::IsNullOrWhiteSpace($CanonicalLabel)) {
    $CanonicalLabel = 'self-hosted-windows-lv'
}
if ([string]::IsNullOrWhiteSpace($Repo)) {
    $Repo = $env:GITHUB_REPOSITORY
}
if ([string]::IsNullOrWhiteSpace($RunnerName)) {
    $RunnerName = $env:RUNNER_NAME
}
if ([string]::IsNullOrWhiteSpace($Token)) {
    $Token = $env:GITHUB_TOKEN
}

$expected = @()
if ($ExpectedLabels) { $expected += $ExpectedLabels }
if ($ExpectedLabel) { $expected += $ExpectedLabel }
if ($requireCanonicalEnabled -and $CanonicalLabel) { $expected += $CanonicalLabel }
$expected = $expected | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -Unique

if (-not $expected -or $expected.Count -eq 0) {
    Write-Host 'Runner label check: no expected labels provided; skipping.'
    return
}

if ($env:GITHUB_ACTIONS -ne 'true') {
    $message = 'Runner label check: not running in GitHub Actions.'
    if ($requireLabelEnabled) {
        throw $message
    }
    Write-Warning $message
    return
}

if ([string]::IsNullOrWhiteSpace($Repo)) {
    $message = 'Runner label check: repository not available (GITHUB_REPOSITORY not set).'
    if ($requireLabelEnabled) { throw $message }
    Write-Warning $message
    return
}

if ([string]::IsNullOrWhiteSpace($RunnerName)) {
    $message = 'Runner label check: runner name not available (RUNNER_NAME not set).'
    if ($requireLabelEnabled) { throw $message }
    Write-Warning $message
    return
}

if ([string]::IsNullOrWhiteSpace($Token)) {
    $message = 'Runner label check: GitHub token not available (GITHUB_TOKEN not set).'
    if ($requireLabelEnabled) { throw $message }
    Write-Warning $message
    return
}

function Get-RunnerInfo {
    param(
        [string]$RepoName,
        [string]$RunnerName,
        [string]$TokenValue
    )

    $headers = @{
        Authorization = "token $TokenValue"
        Accept        = 'application/vnd.github+json'
        'User-Agent'  = 'LVIE-RunnerLabel'
    }

    $perPage = 100
    $page = 1
    do {
        $uri = "https://api.github.com/repos/$RepoName/actions/runners?per_page=$perPage&page=$page"
        try {
            $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers
        } catch {
            throw ("Runner label check: failed to query runner list: {0}" -f $_.Exception.Message)
        }

        if ($response -and $response.runners) {
            $match = $response.runners | Where-Object { $_.name -eq $RunnerName } | Select-Object -First 1
            if ($match) {
                return $match
            }
        }

        $count = if ($response -and $response.runners) { $response.runners.Count } else { 0 }
        $page += 1
    } while ($count -eq $perPage -and $page -le 10)

    return $null
}

$runnerInfo = Get-RunnerInfo -RepoName $Repo -RunnerName $RunnerName -TokenValue $Token
if (-not $runnerInfo) {
    $message = ("Runner label check: runner '{0}' not found in repo {1}." -f $RunnerName, $Repo)
    if ($requireLabelEnabled) { throw $message }
    Write-Warning $message
    return
}

$actualLabels = @()
if ($runnerInfo.labels) {
    $actualLabels = $runnerInfo.labels | ForEach-Object { $_.name }
}

$expectedNorm = $expected | ForEach-Object { $_.Trim().ToLowerInvariant() } | Select-Object -Unique
$actualNorm = $actualLabels | ForEach-Object { $_.Trim().ToLowerInvariant() } | Select-Object -Unique

$missing = @()
foreach ($label in $expectedNorm) {
    if (-not $actualNorm -or ($actualNorm -notcontains $label)) {
        $missing += $label
    }
}

Write-Host ("Runner label check: runner={0}" -f $RunnerName)
Write-Host ("Runner label check: expected={0}" -f ($expected -join ', '))
Write-Host ("Runner label check: actual={0}" -f ($actualLabels -join ', '))

if ($missing.Count -gt 0) {
    throw ("Runner label check failed: missing {0}." -f ($missing -join ', '))
}

Write-Host 'Runner label check: OK.'

