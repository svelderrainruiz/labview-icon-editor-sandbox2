<#
.SYNOPSIS
    Iterates local dev-mode enable/disable runs for 64-bit coverage.

.DESCRIPTION
    Runs local dev-mode enable/disable cycles without GitHub Actions by invoking
    Set_Development_Mode.ps1 and RevertDevelopmentMode.ps1. The underlying
    scripts parse g-cli output for dev-mode error codes.

.PARAMETER MinimumSupportedLVVersion
    LabVIEW version used by g-cli (e.g., "2021").

.PARAMETER SupportedBitness
    LabVIEW bitness to target ("32" or "64"). Defaults to "64".

.PARAMETER Iterations
    Number of cycles to run.

.PARAMETER ModeSequence
    Order of modes to run per iteration (default: enable, disable).

.PARAMETER PauseSeconds
    Optional delay between mode runs.

.PARAMETER RelativePath
    Optional path to the repository root. If omitted, resolved relative to
    this script's location.

.EXAMPLE
    .\Tooling\DevModeIterate.ps1 -Iterations 3 -MinimumSupportedLVVersion 2021 -SupportedBitness 64
#>

param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('2020', '2021', '2022', '2023', '2024', '2025')]
    [string]$MinimumSupportedLVVersion = '2021',

    [Parameter(Mandatory = $false)]
    [ValidateSet('32', '64', IgnoreCase = $true)]
    [string]$SupportedBitness = '64',

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 1000)]
    [int]$Iterations = 1,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [ValidateSet('disable', 'enable', IgnoreCase = $true)]
    [string[]]$ModeSequence = @('enable', 'disable'),

    [Parameter(Mandatory = $false)]
    [ValidateRange(0, 3600)]
    [int]$PauseSeconds = 0,

    [Parameter(Mandatory = $false)]
    [string]$LogPath,

    [Parameter(Mandatory = $false)]
    [string]$RelativePath
)

$ErrorActionPreference = 'Stop'

function Resolve-RepoRoot {
    param(
        [string]$PathOverride
    )

    if ($PathOverride) {
        if (-not (Test-Path -Path $PathOverride)) {
            throw "RelativePath does not exist: $PathOverride"
        }
        return (Resolve-Path -Path $PathOverride).Path
    }

    return (Resolve-Path -Path (Join-Path $PSScriptRoot '..')).Path
}

$repoRoot = Resolve-RepoRoot -PathOverride $RelativePath
$logPathResolved = $LogPath
if ([string]::IsNullOrWhiteSpace($logPathResolved)) {
    $logDir = Join-Path -Path $repoRoot -ChildPath 'Tooling\logs'
    $null = New-Item -Path $logDir -ItemType Directory -Force
    $logPathResolved = Join-Path -Path $logDir -ChildPath ("dev-mode-iterate-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
} else {
    $logDir = Split-Path -Parent -Path $logPathResolved
    if (-not [string]::IsNullOrWhiteSpace($logDir)) {
        $null = New-Item -Path $logDir -ItemType Directory -Force
    }
}

$setScript = Join-Path -Path $repoRoot -ChildPath '.github\actions\set-development-mode\Set_Development_Mode.ps1'
$revertScript = Join-Path -Path $repoRoot -ChildPath '.github\actions\revert-development-mode\RevertDevelopmentMode.ps1'

if (-not (Test-Path -Path $setScript)) {
    throw "Set_Development_Mode.ps1 not found at $setScript"
}

if (-not (Test-Path -Path $revertScript)) {
    throw "RevertDevelopmentMode.ps1 not found at $revertScript"
}

$scriptArgs = @{
    MinimumSupportedLVVersion = $MinimumSupportedLVVersion
    SupportedBitness          = $SupportedBitness
    RelativePath              = $repoRoot
}

function Write-IterationLog {
    param(
        [string]$Message
    )

    $timestamp = Get-Date -Format o
    $line = "$timestamp $Message"
    $line | Out-File -FilePath $logPathResolved -Append -Encoding ascii
    Write-Host $line
}

Write-IterationLog ("start version={0} bitness={1} iterations={2} sequence={3} log={4}" -f `
    $MinimumSupportedLVVersion, $SupportedBitness, $Iterations, ($ModeSequence -join ','), $logPathResolved)

for ($iteration = 1; $iteration -le $Iterations; $iteration++) {
    foreach ($mode in $ModeSequence) {
        Write-IterationLog ("iteration={0} mode={1} event=start" -f $iteration, $mode)
        try {
            if ($mode -eq 'enable') {
                & $setScript @scriptArgs
            } else {
                & $revertScript @scriptArgs
            }

            if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne $null) {
                throw "Dev mode $mode failed with exit code $LASTEXITCODE."
            }
            $exitCodeValue = if ($LASTEXITCODE -eq $null) { 'null' } else { [string]$LASTEXITCODE }
            Write-IterationLog ("iteration={0} mode={1} event=finish exit_code={2}" -f $iteration, $mode, $exitCodeValue)
        } catch {
            Write-IterationLog ("iteration={0} mode={1} event=error message={2}" -f $iteration, $mode, $($_.Exception.Message))
            throw "Iteration $iteration failed while running mode '$mode': $($_.Exception.Message)"
        }

        if ($PauseSeconds -gt 0) {
            Start-Sleep -Seconds $PauseSeconds
        }
    }

    Write-IterationLog ("iteration={0} event=cycle_complete" -f $iteration)
}

Write-IterationLog ("completed iterations={0}" -f $Iterations)
