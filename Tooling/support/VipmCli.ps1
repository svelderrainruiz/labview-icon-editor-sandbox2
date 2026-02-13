#Requires -Version 7.0
<#
.SYNOPSIS
    Shared helpers for invoking and parsing VIPM CLI operations.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertTo-VipmLabVIEWYear {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$VersionInput
    )

    if ($null -eq $VersionInput) {
        throw "VersionInput cannot be null."
    }

    if ($VersionInput.PSObject -and $VersionInput.PSObject.Properties['Year']) {
        $yearValue = [string]$VersionInput.Year
        if ($yearValue -match '^\d{4}$') {
            return $yearValue
        }
    }

    $raw = [string]$VersionInput
    if ([string]::IsNullOrWhiteSpace($raw)) {
        throw "VersionInput is empty."
    }

    $trimmed = $raw.Trim()
    if ($trimmed -match '^\d{4}$') {
        return $trimmed
    }

    if ($trimmed -match '^(?<major>\d{2})$') {
        return ('20{0}' -f $Matches['major'])
    }

    if ($trimmed -match '^(?<major>\d{2})\.(?<minor>\d+)$') {
        return ('20{0}' -f $Matches['major'])
    }

    throw "Unsupported LabVIEW version format '$trimmed'. Expected YYYY, NN, or NN.n."
}

function Test-VipmLockContention {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [string]$StdOut,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [string]$StdErr
    )

    $combined = @($StdOut, $StdErr) -join [Environment]::NewLine
    if ([string]::IsNullOrWhiteSpace($combined)) {
        return $false
    }

    if ($combined -match 'Another VIPM operation is running') {
        return $true
    }

    if ($combined -match 'global lock acquisition') {
        return $true
    }

    if ($combined -match 'lock acquisition') {
        return $true
    }

    return $false
}

function Invoke-VipmCliCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 7200)]
        [int]$TimeoutSeconds = 180,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 10)]
        [int]$MaxAttempts = 3,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 600)]
        [int]$RetryDelaySeconds = 5,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [string]$WorkingDirectory
    )

    $vipmCommand = Get-Command -Name 'vipm' -ErrorAction SilentlyContinue
    if (-not $vipmCommand) {
        throw "Command 'vipm' was not found on PATH."
    }

    $finalArguments = @()
    if ($Arguments -notcontains '--color-mode') {
        $finalArguments += @('--color-mode', 'never')
    }
    $finalArguments += $Arguments

    $quotedArguments = foreach ($arg in $finalArguments) {
        if ($null -eq $arg) {
            '""'
            continue
        }

        $argText = [string]$arg
        if ($argText -match '[\s"]') {
            '"' + ($argText -replace '"', '\"') + '"'
        }
        else {
            $argText
        }
    }
    $argumentString = $quotedArguments -join ' '

    $attempt = 0
    $lastResult = $null
    while ($attempt -lt $MaxAttempts) {
        $attempt++
        $stdoutFile = [System.IO.Path]::GetTempFileName()
        $stderrFile = [System.IO.Path]::GetTempFileName()

        try {
            $startParams = @{
                FilePath               = $vipmCommand.Source
                ArgumentList           = $argumentString
                NoNewWindow            = $true
                PassThru               = $true
                RedirectStandardOutput = $stdoutFile
                RedirectStandardError  = $stderrFile
            }
            if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) {
                $startParams['WorkingDirectory'] = $WorkingDirectory
            }

            $process = Start-Process @startParams
            $completed = $process.WaitForExit($TimeoutSeconds * 1000)
            $timedOut = -not $completed
            if ($timedOut) {
                try {
                    $process.Kill()
                    $process.WaitForExit()
                }
                catch {
                    Write-Verbose ("Failed to kill timed out vipm process: {0}" -f $_.Exception.Message)
                }
            }

            $stdOut = (Get-Content -Path $stdoutFile -Raw -ErrorAction SilentlyContinue)
            $stdErr = (Get-Content -Path $stderrFile -Raw -ErrorAction SilentlyContinue)
            $exitCode = if ($timedOut) { 124 } else { $process.ExitCode }
            $isLockContention = (Test-VipmLockContention -StdOut $stdOut -StdErr $stdErr)

            $lastResult = [pscustomobject]@{
                ExitCode               = $exitCode
                StdOut                 = $stdOut
                StdErr                 = $stdErr
                TimedOut               = $timedOut
                Attempts               = $attempt
                MaxAttempts            = $MaxAttempts
                LockContentionDetected = $isLockContention
                Command                = ('vipm {0}' -f $argumentString)
            }

            if ($exitCode -eq 0) {
                return $lastResult
            }

            if (-not $isLockContention -or $attempt -ge $MaxAttempts) {
                return $lastResult
            }

            if ($RetryDelaySeconds -gt 0) {
                Start-Sleep -Seconds $RetryDelaySeconds
            }
        }
        finally {
            Remove-Item -Path $stdoutFile -ErrorAction SilentlyContinue
            Remove-Item -Path $stderrFile -ErrorAction SilentlyContinue
        }
    }

    return $lastResult
}

function ConvertFrom-VipmListPackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [string]$OutputText
    )

    if ([string]::IsNullOrWhiteSpace($OutputText)) {
        return @()
    }

    $lines = $OutputText -split "`r?`n"
    $parsed = New-Object 'System.Collections.Generic.List[object]'
    foreach ($line in $lines) {
        $match = [regex]::Match($line, '^\s*(?<display>.+?)\s+\((?<id>[^()\s]+)\s+v(?<version>[^()\s]+)\)\s*$')
        if (-not $match.Success) {
            continue
        }

        $parsed.Add([pscustomobject]@{
            display_name = $match.Groups['display'].Value.Trim()
            package_id   = $match.Groups['id'].Value.Trim()
            version      = $match.Groups['version'].Value.Trim()
        })
    }

    return @($parsed | Sort-Object -Property package_id, version -Unique)
}

function Compare-VipmPackageState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$ExpectedPackages,

        [Parameter(Mandatory = $true)]
        [object[]]$InstalledPackages
    )

    $expectedById = @{}
    foreach ($pkg in $ExpectedPackages) {
        if (-not $pkg.package_id) {
            continue
        }
        $expectedById[[string]$pkg.package_id] = [string]$pkg.version
    }

    $installedById = @{}
    foreach ($pkg in $InstalledPackages) {
        if (-not $pkg.package_id) {
            continue
        }
        $installedById[[string]$pkg.package_id] = [string]$pkg.version
    }

    $missingExpected = New-Object 'System.Collections.Generic.List[object]'
    $versionMismatches = New-Object 'System.Collections.Generic.List[object]'
    $unexpectedInstalled = New-Object 'System.Collections.Generic.List[object]'

    foreach ($expectedId in ($expectedById.Keys | Sort-Object)) {
        if (-not $installedById.ContainsKey($expectedId)) {
            $missingExpected.Add([pscustomobject]@{
                package_id        = $expectedId
                expected_version  = $expectedById[$expectedId]
            })
            continue
        }

        $expectedVersion = $expectedById[$expectedId]
        $installedVersion = $installedById[$expectedId]
        if ($expectedVersion -ne $installedVersion) {
            $versionMismatches.Add([pscustomobject]@{
                package_id        = $expectedId
                expected_version  = $expectedVersion
                installed_version = $installedVersion
            })
        }
    }

    foreach ($installedId in ($installedById.Keys | Sort-Object)) {
        if ($expectedById.ContainsKey($installedId)) {
            continue
        }

        $unexpectedInstalled.Add([pscustomobject]@{
            package_id        = $installedId
            installed_version = $installedById[$installedId]
        })
    }

    $missingExpectedArray = if ($missingExpected.Count -gt 0) { $missingExpected.ToArray() } else { @() }
    $versionMismatchesArray = if ($versionMismatches.Count -gt 0) { $versionMismatches.ToArray() } else { @() }
    $unexpectedInstalledArray = if ($unexpectedInstalled.Count -gt 0) { $unexpectedInstalled.ToArray() } else { @() }

    return [pscustomobject]@{
        missing_expected      = $missingExpectedArray
        version_mismatches    = $versionMismatchesArray
        unexpected_installed  = $unexpectedInstalledArray
        has_blocking_mismatch = [bool](($missingExpected.Count + $versionMismatches.Count) -gt 0)
    }
}
