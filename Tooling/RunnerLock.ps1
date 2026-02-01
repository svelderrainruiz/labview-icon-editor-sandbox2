#Requires -Version 7.0

[CmdletBinding()]
param(
    [ValidateSet('Acquire', 'Release')]
    [string]$Mode = 'Acquire',

    [ValidateRange(30, 86400)]
    [int]$TimeoutSeconds = 7200,

    [string]$LockRoot
)

$ErrorActionPreference = 'Stop'

function Resolve-LockRoot {
    param([string]$LockRootOverride)

    if (-not [string]::IsNullOrWhiteSpace($LockRootOverride)) {
        return $LockRootOverride
    }

    if (-not [string]::IsNullOrWhiteSpace($env:LVIE_WORKTREE_ROOT)) {
        return $env:LVIE_WORKTREE_ROOT
    }

    return 'C:\dev'
}

$root = Resolve-LockRoot -LockRootOverride $LockRoot
$locksDir = Join-Path $root 'locks'
$lockPath = Join-Path $locksDir 'labview-runner.lock'
$metadataPath = Join-Path $lockPath 'lock.json'

if ($Mode -eq 'Acquire') {
    New-Item -Path $locksDir -ItemType Directory -Force | Out-Null
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)

    while ($true) {
        try {
            New-Item -Path $lockPath -ItemType Directory -ErrorAction Stop | Out-Null

            $metadata = [pscustomobject]@{
                acquired_at = (Get-Date).ToString('o')
                machine     = $env:COMPUTERNAME
                pid         = $PID
                run_id      = $env:GITHUB_RUN_ID
                run_attempt = $env:GITHUB_RUN_ATTEMPT
                job         = $env:GITHUB_JOB
                workflow    = $env:GITHUB_WORKFLOW
                repository  = $env:GITHUB_REPOSITORY
            }

            $metadata | ConvertTo-Json | Set-Content -Path $metadataPath
            Write-Host "Acquired LabVIEW runner lock: $lockPath"
            break
        } catch {
            if ((Get-Date) -ge $deadline) {
                throw "Timed out waiting for LabVIEW runner lock at '$lockPath'. Remove the lock directory if it is stale."
            }

            Start-Sleep -Seconds 15
        }
    }
} else {
    if (Test-Path -Path $lockPath) {
        Remove-Item -Path $lockPath -Recurse -Force
        Write-Host "Released LabVIEW runner lock: $lockPath"
    } else {
        Write-Host "LabVIEW runner lock not present: $lockPath"
    }
}
