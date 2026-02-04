#Requires -Version 7.0
<#
.SYNOPSIS
    Validates runner environment expectations and optionally fixes Git safe.directory.

.DESCRIPTION
    Ensures work roots exist, prints context, and sets scoped Git safe.directory
    to prevent "dubious ownership" errors when the runner service account differs
    from the checkout owner.

.PARAMETER WorkRoot
    Explicit runner work root. Defaults to LVIE_RUNNER_WORK_ROOT if set.

.PARAMETER WorktreeRoot
    Explicit worktree root. Defaults to LVIE_WORKTREE_ROOT if set.

.PARAMETER FixSafeDirectory
    Attempt to add a scoped safe.directory rule when missing.

.PARAMETER SafeDirectoryScope
    Target Git config scope for safe.directory. Defaults to System.
#>

[CmdletBinding()]
param(
    [string]$WorkRoot,
    [string]$WorktreeRoot,
    [switch]$FixSafeDirectory = $true,
    [ValidateSet('System', 'Global')]
    [string]$SafeDirectoryScope = 'System'
)

$ErrorActionPreference = 'Stop'

function Normalize-Path {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $Path }
    $full = [System.IO.Path]::GetFullPath($Path)
    if ($full.Length -gt 3 -and $full.EndsWith('\')) {
        $full = $full.TrimEnd('\')
    }
    return $full
}

$resolvedWorkRoot = if ($WorkRoot) { $WorkRoot } else { $env:LVIE_RUNNER_WORK_ROOT }
$resolvedWorktreeRoot = if ($WorktreeRoot) { $WorktreeRoot } else { $env:LVIE_WORKTREE_ROOT }
$resolvedWorkRoot = Normalize-Path -Path $resolvedWorkRoot
$resolvedWorktreeRoot = Normalize-Path -Path $resolvedWorktreeRoot

Write-Host ("Runner check: work_root={0}" -f ($resolvedWorkRoot ?? '<unset>'))
Write-Host ("Runner check: worktree_root={0}" -f ($resolvedWorktreeRoot ?? '<unset>'))

if ($resolvedWorkRoot -and -not (Test-Path -Path $resolvedWorkRoot)) {
    Write-Warning ("Runner work root does not exist: {0}" -f $resolvedWorkRoot)
}
if ($resolvedWorktreeRoot -and -not (Test-Path -Path $resolvedWorktreeRoot)) {
    Write-Warning ("Worktree root does not exist: {0}" -f $resolvedWorktreeRoot)
}

function Get-GitSafeDirectories {
    param([string]$Scope)
    $args = @('config')
    if ($Scope -eq 'System') { $args += '--system' }
    if ($Scope -eq 'Global') { $args += '--global' }
    $args += @('--get-all', 'safe.directory')
    try {
        & git @args 2>$null | Where-Object { $_ -and $_.Trim().Length -gt 0 }
    } catch {
        @()
    }
}

function Add-GitSafeDirectory {
    param([string]$Scope, [string]$PathPattern)
    $args = @('config')
    if ($Scope -eq 'System') { $args += '--system' }
    if ($Scope -eq 'Global') { $args += '--global' }
    $args += @('--add', 'safe.directory', $PathPattern)
    & git @args
}

if ($resolvedWorkRoot) {
    $safePattern = ($resolvedWorkRoot -replace '\\', '/') + '/*'
    $safeList = Get-GitSafeDirectories -Scope $SafeDirectoryScope
    $hasSafe = $false
    if ($safeList) {
        $hasSafe = $safeList | Where-Object { $_ -eq '*' -or $_ -eq $safePattern }
    }

    if (-not $hasSafe) {
        Write-Warning ("Git safe.directory missing for {0} (scope: {1})" -f $safePattern, $SafeDirectoryScope)
        if ($FixSafeDirectory) {
            try {
                Add-GitSafeDirectory -Scope $SafeDirectoryScope -PathPattern $safePattern
                Write-Host ("Added git safe.directory: {0} ({1})" -f $safePattern, $SafeDirectoryScope)
            } catch {
                Write-Warning ("Failed to add git safe.directory: {0}" -f $_.Exception.Message)
            }
        }
    } else {
        Write-Host ("Git safe.directory OK: {0} ({1})" -f $safePattern, $SafeDirectoryScope)
    }
}
