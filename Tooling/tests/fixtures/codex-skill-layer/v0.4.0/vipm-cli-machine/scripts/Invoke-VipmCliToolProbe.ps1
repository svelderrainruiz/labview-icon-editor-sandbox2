[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet('about', 'version', 'search', 'list', 'build', 'install', 'uninstall', 'all')]
    [string]$Tool = 'all',

    [Parameter()]
    [ValidateSet('probe', 'run')]
    [string]$Mode = 'probe',

    [Parameter()]
    [string]$LabVIEWVersion,

    [Parameter()]
    [ValidateSet('32', '64')]
    [string]$Bitness = $(if ($env:LVIE_VIPM_LABVIEW_BITNESS) { $env:LVIE_VIPM_LABVIEW_BITNESS } else { '64' }),

    [Parameter()]
    [switch]$AllowStateChange,

    [Parameter()]
    [string]$JsonOutputPath = $env:LVIE_VIPM_JSON_OUTPUT_PATH,

    [Parameter()]
    [int]$WaitTimeoutSeconds = $(if ($env:LVIE_VIPM_WAIT_TIMEOUT_SECONDS) { [int]$env:LVIE_VIPM_WAIT_TIMEOUT_SECONDS } else { 40 }),

    [Parameter()]
    [int]$WaitPollSeconds = $(if ($env:LVIE_VIPM_WAIT_POLL_SECONDS) { [int]$env:LVIE_VIPM_WAIT_POLL_SECONDS } else { 2 }),

    [Parameter()]
    [switch]$SkipProcessWait,

    [Parameter()]
    [int]$CommandTimeoutSeconds = $(if ($env:LVIE_VIPM_COMMAND_TIMEOUT_SECONDS) { [int]$env:LVIE_VIPM_COMMAND_TIMEOUT_SECONDS } else { 120 })
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-CommandAvailable {
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    return $null -ne (Get-Command -Name $Name -ErrorAction SilentlyContinue)
}

function Get-NormalizedLabVIEWYear {
    param(
        [Parameter(Mandatory)]
        [string]$Value
    )

    $trimmed = $Value.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed)) {
        throw 'LabVIEW version cannot be empty.'
    }

    if ($trimmed -match '^\d{4}$') {
        return $trimmed
    }

    if ($trimmed -match '^(\d{2})\.0$') {
        return "20$($Matches[1])"
    }

    throw "Unsupported LabVIEW version format '$Value'. Use YYYY or NN.0 (for example 2026 or 26.0)."
}

function Find-LvversionFile {
    param(
        [Parameter(Mandatory)]
        [string]$StartDirectory
    )

    $current = (Resolve-Path -LiteralPath $StartDirectory).Path
    while ($true) {
        $candidate = Join-Path -Path $current -ChildPath '.lvversion'
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }

        $parent = Split-Path -Path $current -Parent
        if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $current) {
            break
        }

        $current = $parent
    }

    return $null
}

function Resolve-LabVIEWVersion {
    param(
        [string]$ExplicitVersion
    )

    $source = $null
    $rawValue = $null
    $lvversionPath = $null

    if (-not [string]::IsNullOrWhiteSpace($ExplicitVersion)) {
        $source = 'parameter'
        $rawValue = $ExplicitVersion
    }
    elseif (-not [string]::IsNullOrWhiteSpace($env:LVIE_VIPM_LABVIEW_VERSION)) {
        $source = 'env:LVIE_VIPM_LABVIEW_VERSION'
        $rawValue = $env:LVIE_VIPM_LABVIEW_VERSION
    }
    else {
        $lvversionPath = Find-LvversionFile -StartDirectory (Get-Location).Path
        if ($lvversionPath) {
            $source = '.lvversion'
            $rawValue = (Get-Content -LiteralPath $lvversionPath -Raw).Trim()
        }
    }

    if ([string]::IsNullOrWhiteSpace($rawValue)) {
        throw 'Unable to resolve LabVIEW version. Provide -LabVIEWVersion, set LVIE_VIPM_LABVIEW_VERSION, or run from a tree containing .lvversion.'
    }

    return [pscustomobject]@{
        Year          = Get-NormalizedLabVIEWYear -Value $rawValue
        Source        = $source
        RawValue      = $rawValue
        LvversionPath = $lvversionPath
    }
}

function Wait-ForIdleProcess {
    param(
        [Parameter(Mandatory)]
        [string[]]$ProcessName,

        [Parameter(Mandatory)]
        [int]$TimeoutSeconds,

        [Parameter(Mandatory)]
        [int]$PollSeconds
    )

    if ($TimeoutSeconds -lt 1) {
        throw 'Wait timeout must be at least 1 second.'
    }

    if ($PollSeconds -lt 1) {
        throw 'Wait poll interval must be at least 1 second.'
    }

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $active = @()
        foreach ($name in $ProcessName) {
            $active += Get-Process -Name $name -ErrorAction SilentlyContinue
        }

        if (-not $active) {
            return
        }

        Start-Sleep -Seconds $PollSeconds
    }

    $names = $ProcessName -join ', '
    throw "Timed out waiting for processes to exit: $names"
}

function Invoke-VipmCommand {
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments,

        [Parameter(Mandatory)]
        [int]$TimeoutSeconds
    )

    $stdoutFile = [System.IO.Path]::GetTempFileName()
    $stderrFile = [System.IO.Path]::GetTempFileName()

    try {
        if ($TimeoutSeconds -lt 1) {
            throw 'Command timeout must be at least 1 second.'
        }

        $process = Start-Process -FilePath 'vipm' -ArgumentList $Arguments -NoNewWindow -PassThru -RedirectStandardOutput $stdoutFile -RedirectStandardError $stderrFile
        $completed = $process.WaitForExit($TimeoutSeconds * 1000)
        $timedOut = -not $completed

        if ($timedOut) {
            try {
                $process.Kill()
                $process.WaitForExit()
            }
            catch {
                Write-Verbose "Failed to terminate timed out vipm process: $($_.Exception.Message)"
            }
        }

        return [pscustomobject]@{
            ExitCode = if ($timedOut) { 124 } else { $process.ExitCode }
            StdOut   = (Get-Content -LiteralPath $stdoutFile -Raw)
            StdErr   = (Get-Content -LiteralPath $stderrFile -Raw)
            TimedOut = $timedOut
        }
    }
    finally {
        Remove-Item -LiteralPath $stdoutFile -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $stderrFile -ErrorAction SilentlyContinue
    }
}

function Get-ToolPlan {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('about', 'version', 'search', 'list', 'build', 'install', 'uninstall')]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$LabVIEWYear,

        [Parameter(Mandatory)]
        [ValidateSet('32', '64')]
        [string]$Arch
    )

    switch ($Name) {
        'about' {
            return [pscustomobject]@{
                Tool                 = $Name
                Arguments            = @('about')
                StateChanging        = $false
                ExpectFailureInProbe = $false
            }
        }
        'version' {
            return [pscustomobject]@{
                Tool                 = $Name
                Arguments            = @('version')
                StateChanging        = $false
                ExpectFailureInProbe = $false
            }
        }
        'search' {
            return [pscustomobject]@{
                Tool                 = $Name
                Arguments            = @('--labview-version', $LabVIEWYear, '--labview-bitness', $Arch, 'search', 'icon')
                StateChanging        = $false
                ExpectFailureInProbe = $false
            }
        }
        'list' {
            return [pscustomobject]@{
                Tool                 = $Name
                Arguments            = @('--labview-version', $LabVIEWYear, '--labview-bitness', $Arch, 'list', '--installed')
                StateChanging        = $false
                ExpectFailureInProbe = $false
            }
        }
        'build' {
            return [pscustomobject]@{
                Tool                 = $Name
                Arguments            = @('--labview-version', $LabVIEWYear, '--labview-bitness', $Arch, 'build', 'C:\__missing__\missing.vipb')
                StateChanging        = $true
                ExpectFailureInProbe = $true
            }
        }
        'install' {
            return [pscustomobject]@{
                Tool                 = $Name
                Arguments            = @('--labview-version', $LabVIEWYear, '--labview-bitness', $Arch, 'install', 'C:\__missing__\missing.vipc')
                StateChanging        = $true
                ExpectFailureInProbe = $true
            }
        }
        'uninstall' {
            return [pscustomobject]@{
                Tool                 = $Name
                Arguments            = @('--labview-version', $LabVIEWYear, '--labview-bitness', $Arch, 'uninstall', '__codex_probe_missing_pkg__')
                StateChanging        = $true
                ExpectFailureInProbe = $true
            }
        }
    }

    throw "Unsupported tool '$Name'."
}

function Test-IsStateChangingTool {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('about', 'version', 'search', 'list', 'build', 'install', 'uninstall')]
        [string]$Name
    )

    return $Name -in @('build', 'install', 'uninstall')
}

function Get-ResultClass {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('probe', 'run')]
        [string]$RunMode,

        [Parameter(Mandatory)]
        [int]$ExitCode,

        [Parameter(Mandatory)]
        [bool]$ExpectedFailure,

        [Parameter(Mandatory)]
        [bool]$TimedOut
    )

    if ($RunMode -eq 'probe') {
        if ($TimedOut) {
            return 'probe-fail'
        }

        if ($ExpectedFailure -and $ExitCode -ne 0) {
            return 'probe-expected-failure'
        }

        if ($ExpectedFailure -and $ExitCode -eq 0) {
            return 'probe-unexpected-success'
        }

        if ($ExitCode -eq 0) {
            return 'probe-pass'
        }

        return 'probe-fail'
    }

    if ($TimedOut) {
        return 'run-failure'
    }

    if ($ExitCode -eq 0) {
        return 'run-success'
    }

    return 'run-failure'
}

function Test-IsVipmLockAcquisitionFailure {
    param(
        [Parameter()]
        [AllowNull()]
        [string]$StdErr
    )

    if ([string]::IsNullOrWhiteSpace($StdErr)) {
        return $false
    }

    return $StdErr -match 'global lock acquisition' -or $StdErr -match 'Another VIPM operation is running'
}

$resolvedVersion = Resolve-LabVIEWVersion -ExplicitVersion $LabVIEWVersion

if (-not (Test-CommandAvailable -Name 'vipm')) {
    throw "Command 'vipm' was not found on PATH."
}

if (-not $SkipProcessWait.IsPresent) {
    Wait-ForIdleProcess -ProcessName @('vipm', 'labview') -TimeoutSeconds $WaitTimeoutSeconds -PollSeconds $WaitPollSeconds
}

$toolsToRun = if ($Tool -eq 'all') {
    @('about', 'version', 'search', 'list', 'build', 'install', 'uninstall')
}
else {
    @($Tool)
}

$stateChangingRequested = @($toolsToRun | Where-Object { Test-IsStateChangingTool -Name $_ })
if ($Mode -eq 'run' -and -not $AllowStateChange.IsPresent -and $stateChangingRequested.Count -gt 0) {
    throw "Run mode requested state-changing tool(s) without -AllowStateChange: $($stateChangingRequested -join ', ')."
}

$records = @()
foreach ($toolName in $toolsToRun) {
    $plan = Get-ToolPlan -Name $toolName -LabVIEWYear $resolvedVersion.Year -Arch $Bitness

    if ($Mode -eq 'run' -and $plan.StateChanging -and -not $AllowStateChange.IsPresent) {
        throw "Tool '$toolName' is state-changing. Re-run with -AllowStateChange."
    }

    $execution = Invoke-VipmCommand -Arguments $plan.Arguments -TimeoutSeconds $CommandTimeoutSeconds
    $resultClass = Get-ResultClass -RunMode $Mode -ExitCode $execution.ExitCode -ExpectedFailure $plan.ExpectFailureInProbe -TimedOut $execution.TimedOut
    if ($Mode -eq 'probe' -and -not $plan.ExpectFailureInProbe -and -not $execution.TimedOut -and $execution.ExitCode -ne 0 -and (Test-IsVipmLockAcquisitionFailure -StdErr $execution.StdErr)) {
        $resultClass = 'probe-expected-failure'
    }
    $commandText = 'vipm ' + ($plan.Arguments -join ' ')

    $failureMessage = ''
    if ($execution.TimedOut) {
        $failureMessage = "vipm command timed out after $CommandTimeoutSeconds second(s)."
    }
    elseif ($execution.ExitCode -ne 0) {
        $candidate = @($execution.StdErr, $execution.StdOut) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1
        if ($candidate) {
            $failureMessage = ($candidate -split "`r?`n" | Select-Object -First 1).Trim()
        }
        else {
            $failureMessage = "vipm exited with code $($execution.ExitCode)."
        }
    }

    $stdoutPreview = if ([string]::IsNullOrWhiteSpace($execution.StdOut)) { $null } else { (($execution.StdOut -split "`r?`n") | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1) }
    $stderrPreview = if ([string]::IsNullOrWhiteSpace($execution.StdErr)) { $null } else { (($execution.StdErr -split "`r?`n") | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1) }

    $record = [pscustomobject]@{
        timestamp_utc        = (Get-Date).ToUniversalTime().ToString('o')
        tool                 = $toolName
        mode                 = $Mode
        resolved_labview_year = $resolvedVersion.Year
        resolved_bitness     = $Bitness
        command              = $commandText
        exit_code            = $execution.ExitCode
        result_class         = $resultClass
        stdout_preview       = $stdoutPreview
        stderr_preview       = $stderrPreview
        timed_out            = $execution.TimedOut
        state_change_allowed = $AllowStateChange.IsPresent
        failure_message      = $failureMessage
    }

    $records += $record
    Write-Host "[$resultClass] $toolName (exit $($execution.ExitCode))"
}

if ([string]::IsNullOrWhiteSpace($JsonOutputPath)) {
    $JsonOutputPath = Join-Path -Path (Get-Location).Path -ChildPath 'TestResults\agent-logs\vipm-cli-machine.latest.json'
}

$jsonDirectory = Split-Path -Path $JsonOutputPath -Parent
if (-not (Test-Path -LiteralPath $jsonDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $jsonDirectory -Force | Out-Null
}

$payload = [pscustomobject]@{
    generated_utc            = (Get-Date).ToUniversalTime().ToString('o')
    command_timeout_seconds  = $CommandTimeoutSeconds
    selected_tool            = $Tool
    mode                     = $Mode
    resolved_labview_year    = $resolvedVersion.Year
    resolved_labview_source  = $resolvedVersion.Source
    resolved_lvversion_path  = $resolvedVersion.LvversionPath
    resolved_labview_raw     = $resolvedVersion.RawValue
    resolved_bitness         = $Bitness
    state_changing_requested = $stateChangingRequested
    run_count                = @($records).Count
    failure_count            = @($records | Where-Object { $_.exit_code -ne 0 }).Count
    runs                     = $records
}

$payload | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $JsonOutputPath -Encoding UTF8
Write-Host "Wrote JSON results to $JsonOutputPath"

if ($Mode -eq 'probe') {
    $unexpected = @($records | Where-Object { $_.result_class -in @('probe-fail', 'probe-unexpected-success') })
    if ($unexpected.Count -gt 0) {
        throw "Probe encountered unexpected outcomes for tool(s): $($unexpected.tool -join ', ')."
    }
}
else {
    $runFailures = @($records | Where-Object { $_.result_class -eq 'run-failure' })
    if ($runFailures.Count -gt 0) {
        throw "Run mode failed for tool(s): $($runFailures.tool -join ', ')."
    }
}
