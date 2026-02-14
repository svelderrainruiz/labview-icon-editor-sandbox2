#Requires -Version 7.0
<#
.SYNOPSIS
    Shared helpers for deterministic VIPM CLI invocation and parsing.

.DESCRIPTION
    Provides:
      - LabVIEW version normalization for VIPM CLI year arguments.
      - resilient VIPM process execution with timeout and lock-retry logic.
      - parsing helpers for "vipm list" package output.
#>

Set-StrictMode -Version Latest

function ConvertTo-VipmLabVIEWYear {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$VersionInput
    )

    if ($null -eq $VersionInput) {
        throw 'VersionInput cannot be null.'
    }

    if ($VersionInput -is [string]) {
        $raw = $VersionInput.Trim()
    } elseif ($VersionInput.PSObject.Properties.Name -contains 'Year') {
        $raw = [string]$VersionInput.Year
    } else {
        $raw = [string]$VersionInput
    }

    if ([string]::IsNullOrWhiteSpace($raw)) {
        throw 'VersionInput resolved to an empty value.'
    }

    if ($raw -match '^(?<year>20\d{2})$') {
        return $Matches['year']
    }

    if ($raw -match '^(?<major>\d{2})(?:\.(?<minor>\d+))?$') {
        $year = 2000 + [int]$Matches['major']
        return [string]$year
    }

    if ($raw -match '^(?<year>20\d{2})\.(?<minor>\d+)$') {
        return $Matches['year']
    }

    throw "Unable to normalize LabVIEW version '$raw' to VIPM year format."
}

function ConvertTo-VipmArgumentToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$Value
    )

    $text = if ($null -eq $Value) { '' } else { [string]$Value }
    if ($text -match '[\s"]') {
        return '"' + ($text -replace '"', '\"') + '"'
    }

    return $text
}

function Test-VipmLockContentionMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [string]$StdOut,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [string]$StdErr
    )

    $combined = "{0}`n{1}" -f ([string]$StdOut), ([string]$StdErr)
    foreach ($pattern in @(
        'Another VIPM operation is running',
        'global lock acquisition',
        'failed to acquire.*lock',
        'lock file'
    )) {
        if ($combined -match $pattern) {
            return $true
        }
    }

    return $false
}

function Invoke-VipmCliCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$Arguments,

        [Parameter(Mandatory = $false)]
        [ValidateRange(10, 7200)]
        [int]$TimeoutSeconds = 900,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 10)]
        [int]$MaxAttempts = 3,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 120)]
        [int]$RetryDelaySeconds = 5
    )

    $vipmCliPath = if ([string]::IsNullOrWhiteSpace($env:LVIE_VIPM_CLI_PATH)) { 'vipm' } else { $env:LVIE_VIPM_CLI_PATH }

    $effectiveArgs = @()
    if ($Arguments) {
        $effectiveArgs += $Arguments
    }

    if (-not ($effectiveArgs -contains '--color-mode')) {
        $effectiveArgs += @('--color-mode', 'never')
    }

    $argumentString = ($effectiveArgs | ForEach-Object { ConvertTo-VipmArgumentToken -Value $_ }) -join ' '
    $commandString = "{0} {1}" -f $vipmCliPath, $argumentString

    $last = $null
    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        $process = $null
        $timedOut = $false
        $stdOut = ''
        $stdErr = ''
        $exitCode = -1

        try {
            $startInfo = New-Object System.Diagnostics.ProcessStartInfo
            $startInfo.FileName = $vipmCliPath
            $startInfo.Arguments = $argumentString
            $startInfo.UseShellExecute = $false
            $startInfo.CreateNoWindow = $true
            $startInfo.RedirectStandardOutput = $true
            $startInfo.RedirectStandardError = $true

            $process = New-Object System.Diagnostics.Process
            $process.StartInfo = $startInfo
            $null = $process.Start()

            $waitSucceeded = $process.WaitForExit($TimeoutSeconds * 1000)
            if (-not $waitSucceeded) {
                $timedOut = $true
                try {
                    $process.Kill($true)
                } catch {
                    Write-Verbose ("Failed to kill timed-out VIPM process cleanly: {0}" -f $_.Exception.Message)
                }
                $process.WaitForExit()
            }

            $stdOut = $process.StandardOutput.ReadToEnd()
            $stdErr = $process.StandardError.ReadToEnd()
            $exitCode = if ($timedOut) { -1 } else { $process.ExitCode }
        }
        finally {
            if ($process) {
                $process.Dispose()
            }
        }

        $result = [pscustomobject]@{
            Command   = $commandString
            ExitCode  = $exitCode
            StdOut    = $stdOut
            StdErr    = $stdErr
            TimedOut  = $timedOut
            Attempts  = $attempt
        }
        $last = $result

        $lockContention = Test-VipmLockContentionMessage -StdOut $stdOut -StdErr $stdErr
        $shouldRetry = ($attempt -lt $MaxAttempts) -and (($timedOut -or $exitCode -ne 0) -and $lockContention)
        if ($shouldRetry) {
            if ($RetryDelaySeconds -gt 0) {
                Start-Sleep -Seconds $RetryDelaySeconds
            }
            continue
        }

        return $result
    }

    return $last
}

function ConvertFrom-VipmListPackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [string]$Text
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return @()
    }

    $packages = New-Object 'System.Collections.Generic.List[object]'
    $lines = $Text -split "\r?\n"
    foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        $match = [regex]::Match(
            $line,
            '^\s*(?<display>.+?)\s+\((?<id>[A-Za-z0-9_.-]+)\sv(?<version>[^)]+)\)\s*$'
        )
        if (-not $match.Success) {
            continue
        }

        $packages.Add([pscustomobject]@{
            display_name = $match.Groups['display'].Value.Trim()
            package_id   = $match.Groups['id'].Value.Trim()
            version      = $match.Groups['version'].Value.Trim()
        })
    }

    return @($packages | Sort-Object package_id, version -Unique)
}
