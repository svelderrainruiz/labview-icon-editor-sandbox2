param(
    [string]$Repo = 'svelderrainruiz/labview-icon-editor',
    [string]$Ref = 'experimental/447-Sergio-Change-Number-1',
    [ValidateSet('2021')]
    [string]$LabVIEWVersion = '2021',
    [int]$PollSeconds = 2,
    [int]$TimeoutMinutes = 3,
    [int]$RunTimeoutMinutes = 10
)

$ErrorActionPreference = 'Stop'

function Assert-GhReady {
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        throw 'GitHub CLI (gh) not found in PATH.'
    }

    $null = & gh auth status 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw 'gh auth status failed. Please authenticate with GitHub.'
    }
}

function Start-DevModeRun {
    param(
        [string]$Mode
    )

    $args = @(
        'workflow', 'run', 'Toggle Development Mode',
        '--repo', $Repo,
        '--ref', $Ref,
        '-f', "mode=$Mode",
        '-f', "minimum_supported_lv_version=$LabVIEWVersion"
    )

    Write-Host ("Starting workflow: mode={0}" -f $Mode)
    & gh @args | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to dispatch workflow for mode=$Mode."
    }
}

function Get-LastCompletedRun {
    $runs = & gh run list `
        --repo $Repo `
        --workflow 'Toggle Development Mode' `
        --branch $Ref `
        --limit 10 `
        --json databaseId,createdAt,status,conclusion 2>$null | ConvertFrom-Json

    return $runs | Where-Object { $_.status -eq 'completed' } | Select-Object -First 1
}

function Get-RunModeFromJobs {
    param(
        [long]$RunId
    )

    $run = & gh run view --repo $Repo $RunId --json jobs 2>$null | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0 -or -not $run) {
        return $null
    }

    $jobName = $run.jobs | Select-Object -ExpandProperty name -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($jobName -match '^\s*Enable\b') { return 'enable' }
    if ($jobName -match '^\s*Disable\b') { return 'disable' }
    return $null
}

function Get-RunSummary {
    param(
        [long]$RunId
    )

    $run = & gh run view --repo $Repo $RunId --json status,conclusion 2>$null | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0 -or -not $run) {
        return $null
    }

    return $run
}

function Wait-ForRunCompletion {
    param(
        [long]$RunId,
        [string]$Mode
    )

    $deadline = (Get-Date).ToUniversalTime().AddMinutes($RunTimeoutMinutes)
    $lastStatus = $null

    do {
        $run = Get-RunSummary -RunId $RunId
        if (-not $run) {
            Start-Sleep -Seconds $PollSeconds
            continue
        }

        if ($run.status -ne $lastStatus) {
            Write-Host ("Run {0} status: {1}" -f $RunId, $run.status)
            $lastStatus = $run.status
        }

        if ($run.status -eq 'completed') {
            if ($run.conclusion -ne 'success') {
                Write-Host "Run failed; fetching logs..."
                & gh run view --repo $Repo $RunId --log
                throw "Workflow run failed for mode=$Mode (run id $RunId)."
            }
            return
        }

        Start-Sleep -Seconds $PollSeconds
    } while ((Get-Date).ToUniversalTime() -lt $deadline)

    throw "Timed out waiting for workflow run completion (mode=$Mode, run id $RunId)."
}

function Wait-ForActiveRunToFinish {
    $activeRun = & gh run list `
        --repo $Repo `
        --workflow 'Toggle Development Mode' `
        --branch $Ref `
        --status in_progress `
        --limit 1 `
        --json databaseId 2>$null | ConvertFrom-Json

    if (-not $activeRun -or -not $activeRun.databaseId) {
        $activeRun = & gh run list `
            --repo $Repo `
            --workflow 'Toggle Development Mode' `
            --branch $Ref `
            --status queued `
            --limit 1 `
            --json databaseId 2>$null | ConvertFrom-Json
    }

    if ($activeRun -and $activeRun.databaseId) {
        Write-Host "Active run detected ($($activeRun.databaseId)). Waiting for completion..."
        Wait-ForRunCompletion -RunId $activeRun.databaseId -Mode 'active'
    }
}

function Get-LatestRunAfterId {
    param(
        [long]$BaselineId
    )

    $runs = & gh run list `
        --repo $Repo `
        --workflow 'Toggle Development Mode' `
        --branch $Ref `
        --event workflow_dispatch `
        --limit 10 `
        --json databaseId,createdAt,status,conclusion 2>$null | ConvertFrom-Json

    $filtered = $runs | Where-Object { $_.databaseId -gt $BaselineId } | Sort-Object databaseId -Descending
    return $filtered | Select-Object -First 1
}

function Wait-ForRun {
    param(
        [long]$BaselineId,
        [string]$Mode
    )

    $deadline = (Get-Date).ToUniversalTime().AddMinutes($TimeoutMinutes)
    do {
        $run = Get-LatestRunAfterId -BaselineId $BaselineId
        if ($run) {
            $runMode = Get-RunModeFromJobs -RunId $run.databaseId
            if ($runMode -and $runMode -ne $Mode) {
                Write-Host ("Found run {0} for mode '{1}', waiting for mode '{2}'." -f $run.databaseId, $runMode, $Mode)
                Start-Sleep -Seconds $PollSeconds
                continue
            }

            Write-Host ("Workflow run found: {0}" -f $run.databaseId)
            if ($run.status -eq 'completed') {
                if ($run.conclusion -ne 'success') {
                    Write-Host "Run failed; fetching logs..."
                    & gh run view --repo $Repo $run.databaseId --log
                    throw "Workflow run failed for mode=$Mode (run id $($run.databaseId))."
                }
                return
            }

            Wait-ForRunCompletion -RunId $run.databaseId -Mode $Mode
            return
        }

        Write-Host "Waiting for workflow run (mode=$Mode)..."
        Start-Sleep -Seconds $PollSeconds
    } while ((Get-Date).ToUniversalTime() -lt $deadline)

    throw "Timed out waiting for workflow run (mode=$Mode)."
}

Assert-GhReady

Wait-ForActiveRunToFinish

$baselineId = (Get-LastCompletedRun | Select-Object -ExpandProperty databaseId) 2>$null
if (-not $baselineId) { $baselineId = 0 }
$baselineId = [long]$baselineId
Start-DevModeRun -Mode 'disable'
Wait-ForRun -BaselineId $baselineId -Mode 'disable'

$baselineId = (Get-LastCompletedRun | Select-Object -ExpandProperty databaseId) 2>$null
if (-not $baselineId) { $baselineId = 0 }
$baselineId = [long]$baselineId
Start-DevModeRun -Mode 'enable'
Wait-ForRun -BaselineId $baselineId -Mode 'enable'

