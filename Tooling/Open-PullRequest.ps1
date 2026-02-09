#Requires -Version 7.0
<##
.SYNOPSIS
    Opens a GitHub pull request for the current branch.

.DESCRIPTION
    Uses GitKraken CLI (gk) for git operations and GitHub CLI (gh) to open a PR.
    Defaults to base branch 'develop' and the current branch as the head.

.PARAMETER RepoRoot
    Optional repository root override.

.PARAMETER BaseBranch
    Base branch to target (default: develop).

.PARAMETER HeadBranch
    Head branch to use (default: current branch).

.PARAMETER Title
    Optional PR title. If omitted, uses gh --fill.

.PARAMETER Body
    Optional PR body. If omitted, uses gh --fill.

.PARAMETER Draft
    Create the PR as a draft.

.PARAMETER RequireCleanWorktree
    Fail if the working tree has uncommitted changes.

.PARAMETER OpenInBrowser
    Open the created pull request in the default browser.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$RepoRoot,

    [Parameter(Mandatory = $false)]
    [string]$BaseBranch = 'develop',

    [Parameter(Mandatory = $false)]
    [string]$HeadBranch,

    [Parameter(Mandatory = $false)]
    [string]$Title,

    [Parameter(Mandatory = $false)]
    [string]$Body,

    [switch]$Draft,

    [switch]$RequireCleanWorktree,

    [switch]$OpenInBrowser
)

$ErrorActionPreference = 'Stop'

$gitKrakenScript = Join-Path $PSScriptRoot 'support\GitKrakenCli.ps1'
if (-not (Test-Path -Path $gitKrakenScript)) {
    throw "GitKraken CLI helper not found at $gitKrakenScript"
}
. $gitKrakenScript
Enable-GitKrakenGitShim -Require | Out-Null

function Resolve-RepoRoot {
    param([string]$PathOverride)

    if (-not [string]::IsNullOrWhiteSpace($PathOverride)) {
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

function Confirm-GhReady {
    $null = & gh --version 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "GitHub CLI (gh) not found or not authenticated. Run 'gh auth login'."
    }
}

function Test-CleanWorktree {
    param([string]$RepoRootResolved)

    $status = & git -C $RepoRootResolved status --porcelain 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "git status failed: $status"
    }
    return [string]::IsNullOrWhiteSpace(($status | Out-String).Trim())
}

$repoRootResolved = Resolve-RepoRoot -PathOverride $RepoRoot
Confirm-GhReady

if ([string]::IsNullOrWhiteSpace($HeadBranch)) {
    $HeadBranch = (git -C $repoRootResolved rev-parse --abbrev-ref HEAD).Trim()
}

if ($HeadBranch -eq $BaseBranch) {
    throw "Head branch '$HeadBranch' matches base branch '$BaseBranch'. Check out a feature branch before opening a PR."
}

if ($RequireCleanWorktree.IsPresent) {
    $isClean = Test-CleanWorktree -RepoRootResolved $repoRootResolved
    if (-not $isClean) {
        throw 'Working tree has uncommitted changes. Commit or stash before opening a PR.'
    }
}

$ghArgs = @('pr', 'create', '--base', $BaseBranch, '--head', $HeadBranch)
if ($Draft.IsPresent) {
    $ghArgs += '--draft'
}

if ([string]::IsNullOrWhiteSpace($Title) -and [string]::IsNullOrWhiteSpace($Body)) {
    $ghArgs += '--fill'
} else {
    if (-not [string]::IsNullOrWhiteSpace($Title)) {
        $ghArgs += @('--title', $Title)
    }
    if (-not [string]::IsNullOrWhiteSpace($Body)) {
        $ghArgs += @('--body', $Body)
    }
}

Push-Location -Path $repoRootResolved
try {
    & gh @ghArgs
    if ($LASTEXITCODE -ne 0) {
        throw "gh pr create failed with exit code $LASTEXITCODE."
    }

    if ($OpenInBrowser.IsPresent) {
        & gh pr view --web
        if ($LASTEXITCODE -ne 0) {
            throw "gh pr view --web failed with exit code $LASTEXITCODE."
        }
    }
} finally {
    Pop-Location
}
