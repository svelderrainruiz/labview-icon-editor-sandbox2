#Requires -Version 7.0
<#
.SYNOPSIS
    Creates a short-path worktree for a CI job and exports REPO_ROOT/PROJECT_PATH.

.DESCRIPTION
    Centralizes CI worktree creation so workflows only need to pass a bitness and
    (optionally) a variant label. The script resolves the worktree root, creates
    a deterministic folder name, calls New-CIWorktree.ps1, and exports:
      - LVIE_WORKTREE_ROOT
      - REPO_ROOT
      - PROJECT_PATH

.PARAMETER Bitness
    LabVIEW bitness (32 or 64). Required.

.PARAMETER Variant
    Optional additional label included in the worktree folder name (e.g. 2021).

.PARAMETER Ref
    Git ref to check out. Defaults to GITHUB_SHA or HEAD.

.PARAMETER JobName
    Job name used to compute the job hash. Defaults to GITHUB_JOB.

.PARAMETER RunId
    Run ID. Defaults to GITHUB_RUN_ID.

.PARAMETER RunAttempt
    Run attempt. Defaults to GITHUB_RUN_ATTEMPT.

.PARAMETER ProjectFile
    Project file name to export as PROJECT_PATH. Defaults to lv_icon_editor.lvproj.

.PARAMETER WorktreeRoot
    Optional explicit worktree root. If omitted, LVIE_WORKTREE_ROOT or a
    runner-scoped default is used.

.PARAMETER RepoRoot
    Optional explicit repo root. If omitted, GITHUB_WORKSPACE or the script
    location is used.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('32', '64')]
    [string]$Bitness,

    [Parameter(Mandatory = $false)]
    [string]$Variant,

    [Parameter(Mandatory = $false)]
    [string]$Ref,

    [Parameter(Mandatory = $false)]
    [string]$JobName,

    [Parameter(Mandatory = $false)]
    [string]$RunId,

    [Parameter(Mandatory = $false)]
    [string]$RunAttempt,

    [Parameter(Mandatory = $false)]
    [string]$ProjectFile = 'lv_icon_editor.lvproj',

    [Parameter(Mandatory = $false)]
    [string]$WorktreeRoot,

    [Parameter(Mandatory = $false)]
    [string]$RepoRoot
)

$ErrorActionPreference = 'Stop'

function Resolve-RepoRoot {
    param([string]$BasePath)

    if (-not [string]::IsNullOrWhiteSpace($BasePath)) {
        return [System.IO.Path]::GetFullPath($BasePath)
    }

    if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_WORKSPACE)) {
        return [System.IO.Path]::GetFullPath($env:GITHUB_WORKSPACE)
    }

    return (Resolve-Path -Path (Join-Path $PSScriptRoot '..')).Path
}

$repoRoot = Resolve-RepoRoot -BasePath $RepoRoot

$jobName = $JobName
if ([string]::IsNullOrWhiteSpace($jobName)) {
    $jobName = $env:GITHUB_JOB
}
if ([string]::IsNullOrWhiteSpace($jobName)) {
    throw "JobName is required to compute the worktree name."
}

$runId = $RunId
if ([string]::IsNullOrWhiteSpace($runId)) {
    $runId = $env:GITHUB_RUN_ID
}
if ([string]::IsNullOrWhiteSpace($runId)) {
    $runId = 'local'
}

$runAttempt = $RunAttempt
if ([string]::IsNullOrWhiteSpace($runAttempt)) {
    $runAttempt = $env:GITHUB_RUN_ATTEMPT
}
if ([string]::IsNullOrWhiteSpace($runAttempt)) {
    $runAttempt = '1'
}

$ref = $Ref
if ([string]::IsNullOrWhiteSpace($ref)) {
    $ref = $env:GITHUB_SHA
}
if ([string]::IsNullOrWhiteSpace($ref)) {
    $ref = 'HEAD'
}

$root = $WorktreeRoot
$rootIsExplicit = $false
if ([string]::IsNullOrWhiteSpace($root)) {
    $root = $env:LVIE_WORKTREE_ROOT
}
if (-not [string]::IsNullOrWhiteSpace($root)) {
    $rootIsExplicit = $true
}

if ([string]::IsNullOrWhiteSpace($root)) {
    $rootBase = $env:RUNNER_WORKSPACE
    if ([string]::IsNullOrWhiteSpace($rootBase) -and -not [string]::IsNullOrWhiteSpace($env:GITHUB_WORKSPACE)) {
        $rootBase = Split-Path -Parent (Split-Path -Parent $env:GITHUB_WORKSPACE)
    }
    if ([string]::IsNullOrWhiteSpace($rootBase) -and -not [string]::IsNullOrWhiteSpace($env:GITHUB_WORKSPACE)) {
        $rootBase = Split-Path -Parent $env:GITHUB_WORKSPACE
    }
    if ([string]::IsNullOrWhiteSpace($rootBase)) {
        throw "Worktree root could not be resolved. Set LVIE_WORKTREE_ROOT or pass -WorktreeRoot."
    }
    $root = Join-Path $rootBase 'w'
}

$root = [System.IO.Path]::GetFullPath($root)
if (-not $rootIsExplicit) {
    New-Item -Path $root -ItemType Directory -Force | Out-Null
}

$hashBytes = [System.Text.Encoding]::UTF8.GetBytes($jobName)
$jobHash = [System.BitConverter]::ToString([System.Security.Cryptography.SHA1]::Create().ComputeHash($hashBytes)).Replace('-', '').Substring(0, 8)

$variantToken = if ([string]::IsNullOrWhiteSpace($Variant)) { $null } else { $Variant }
$name = if ($variantToken) {
    "ci-$jobHash-$variantToken-$Bitness-$runId-$runAttempt"
} else {
    "ci-$jobHash-$Bitness-$runId-$runAttempt"
}

$targetPath = Join-Path $root $name

$ensureScript = Join-Path $repoRoot 'Tooling/Ensure-WorktreeRoot.ps1'
if (-not (Test-Path -Path $ensureScript)) {
    throw "Ensure-WorktreeRoot.ps1 not found at $ensureScript"
}

$worktreeScript = Join-Path $repoRoot 'Tooling/New-CIWorktree.ps1'
if (-not (Test-Path -Path $worktreeScript)) {
    throw "New-CIWorktree.ps1 not found at $worktreeScript"
}

$worktree = & $worktreeScript -Ref $ref -Path $targetPath -WorktreeRoot $root
$projectPath = Join-Path $worktree $ProjectFile

if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_ENV)) {
    "LVIE_WORKTREE_ROOT=$root" | Out-File -FilePath $env:GITHUB_ENV -Append -Encoding ascii
    "REPO_ROOT=$worktree" | Out-File -FilePath $env:GITHUB_ENV -Append -Encoding ascii
    "PROJECT_PATH=$projectPath" | Out-File -FilePath $env:GITHUB_ENV -Append -Encoding ascii
}

Write-Host ("Worktree created: {0}" -f $worktree)
Write-Output $worktree
