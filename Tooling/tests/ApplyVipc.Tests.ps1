#Requires -Version 7.0
#Requires -Modules Pester

$ErrorActionPreference = 'Stop'

BeforeAll {
    $script:toolingRoot = Split-Path -Parent $PSScriptRoot
    $script:applyScriptPath = Join-Path $script:toolingRoot '..\.github\actions\apply-vipc\ApplyVIPC.ps1'
    $script:vipmHelperPath = Join-Path $script:toolingRoot 'support\VipmCli.ps1'

    if (-not (Test-Path -Path $script:applyScriptPath -PathType Leaf)) {
        throw "ApplyVIPC script not found: $script:applyScriptPath"
    }
    if (-not (Test-Path -Path $script:vipmHelperPath -PathType Leaf)) {
        throw "VIPM helper not found: $script:vipmHelperPath"
    }

    $script:applyScriptContent = Get-Content -Path $script:applyScriptPath -Raw
    . $script:vipmHelperPath
}

Describe 'ApplyVIPC command contract' {
    It 'uses VIPM CLI install with LabVIEW year and bitness parameters' {
        $script:applyScriptContent | Should -Match 'Invoke-VipmCliCommand'
        $script:applyScriptContent | Should -Match "'--labview-version'"
        $script:applyScriptContent | Should -Match "'--labview-bitness'"
        $script:applyScriptContent | Should -Match "'install'"
    }

    It 'supports temporary VIPC target mismatch override' {
        $script:applyScriptContent | Should -Match '\[switch\]\$AllowVipcTargetMismatch'
        $script:applyScriptContent | Should -Match '-AllowVipcTargetMismatch'
    }
}

Describe 'VIPM helper retry contract' {
    It 'normalizes LabVIEW numeric version to VIPM year format' {
        ConvertTo-VipmLabVIEWYear -VersionInput '26.0' | Should -Be '2026'
        ConvertTo-VipmLabVIEWYear -VersionInput '2026' | Should -Be '2026'
    }

    It 'retries lock contention and succeeds before max attempts on Windows' -Skip:($env:OS -ne 'Windows_NT') {
        $fakeDir = Join-Path $TestDrive 'fake-vipm-success'
        New-Item -Path $fakeDir -ItemType Directory -Force | Out-Null
        $vipmCmd = Join-Path $fakeDir 'vipm.cmd'
        @'
@echo off
setlocal EnableDelayedExpansion
set "COUNTER_FILE=%~dp0counter.txt"
if not exist "!COUNTER_FILE!" (
  > "!COUNTER_FILE!" echo 0
)
set /p COUNT=<"!COUNTER_FILE!"
set /a COUNT=COUNT+1
> "!COUNTER_FILE!" echo !COUNT!
if !COUNT! LSS 3 (
  echo Error: Operation 'global lock acquisition' timed out after 6s 1>&2
  exit /b 1
)
echo vipm 2026.1.0
exit /b 0
'@ | Set-Content -Path $vipmCmd -Encoding ascii

        $previousPath = $env:PATH
        try {
            $env:PATH = "$fakeDir;$previousPath"
            $result = Invoke-VipmCliCommand -Arguments @('version') -TimeoutSeconds 15 -MaxAttempts 3 -RetryDelaySeconds 0
            $result.ExitCode | Should -Be 0
            $result.Attempts | Should -Be 3
        }
        finally {
            $env:PATH = $previousPath
        }
    }

    It 'returns failure after max attempts during persistent lock contention on Windows' -Skip:($env:OS -ne 'Windows_NT') {
        $fakeDir = Join-Path $TestDrive 'fake-vipm-fail'
        New-Item -Path $fakeDir -ItemType Directory -Force | Out-Null
        $vipmCmd = Join-Path $fakeDir 'vipm.cmd'
        @'
@echo off
echo Error: Operation 'global lock acquisition' timed out after 6s 1>&2
exit /b 1
'@ | Set-Content -Path $vipmCmd -Encoding ascii

        $previousPath = $env:PATH
        try {
            $env:PATH = "$fakeDir;$previousPath"
            $result = Invoke-VipmCliCommand -Arguments @('version') -TimeoutSeconds 15 -MaxAttempts 2 -RetryDelaySeconds 0
            $result.ExitCode | Should -Not -Be 0
            $result.Attempts | Should -Be 2
            $result.LockContentionDetected | Should -BeTrue
        }
        finally {
            $env:PATH = $previousPath
        }
    }
}
