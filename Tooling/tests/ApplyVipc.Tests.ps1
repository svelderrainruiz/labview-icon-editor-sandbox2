#Requires -Version 7.0
#Requires -Modules Pester

$ErrorActionPreference = 'Stop'

BeforeAll {
    $script:toolingRoot = Split-Path -Parent $PSScriptRoot
    $script:repoRoot = Split-Path -Parent $script:toolingRoot
    $script:applyScript = Join-Path $script:repoRoot '.github\actions\apply-vipc\ApplyVIPC.ps1'

    if (-not (Test-Path -Path $script:applyScript -PathType Leaf)) {
        throw "ApplyVIPC script not found: $script:applyScript"
    }
}

function script:New-ApplyVipmStub {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Directory
    )

    $stubPs1 = Join-Path $Directory 'vipm-apply-stub.ps1'
    $stubCmd = Join-Path $Directory 'vipm.cmd'

    @'
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)

$argLine = $Args -join ' '
if (-not [string]::IsNullOrWhiteSpace($env:VIPM_STUB_ARGS_LOG)) {
    Add-Content -Path $env:VIPM_STUB_ARGS_LOG -Value $argLine
}

$mode = [string]$env:VIPM_STUB_MODE
if ($mode -eq 'lock-once') {
    $markerPath = [string]$env:VIPM_STUB_LOCK_MARKER
    if (-not [string]::IsNullOrWhiteSpace($markerPath) -and -not (Test-Path -Path $markerPath -PathType Leaf)) {
        Set-Content -Path $markerPath -Value 'locked' -Encoding ascii
        [Console]::Error.WriteLine('Another VIPM operation is running')
        exit 1
    }
}

Write-Output 'VIPM stub install success'
exit 0
'@ | Set-Content -Path $stubPs1 -Encoding utf8

    @"
@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "$stubPs1" %*
exit /b %errorlevel%
"@ | Set-Content -Path $stubCmd -Encoding ascii

    return $stubCmd
}

function script:Invoke-ApplyVipcWithStub {
    param(
        [Parameter(Mandatory = $false)]
        [int]$VipmMaxAttempts = 3,

        [Parameter(Mandatory = $false)]
        [int]$VipmRetryDelaySeconds = 0
    )

    $previousNativePreference = $PSNativeCommandUseErrorActionPreference
    $PSNativeCommandUseErrorActionPreference = $false
    try {
        $null = & pwsh -NoProfile -File $script:applyScript `
            -LabVIEWVersion '26.0' `
            -SupportedBitness '64' `
            -RepoRoot $script:repoRoot `
            -VIPCPath '.github/actions/apply-vipc/runner_dependencies.vipc' `
            -AllowVipcTargetMismatch `
            -SkipWorktreeRootCheck `
            -VipmTimeoutSeconds 120 `
            -VipmMaxAttempts $VipmMaxAttempts `
            -VipmRetryDelaySeconds $VipmRetryDelaySeconds

        return $LASTEXITCODE
    }
    finally {
        $PSNativeCommandUseErrorActionPreference = $previousNativePreference
    }
}

Describe 'ApplyVIPC VIPM command contract' {
    BeforeEach {
        $script:stubDir = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -Path $script:stubDir -ItemType Directory -Force | Out-Null
        $script:argsLog = Join-Path $script:stubDir 'vipm-args.log'
        $script:lockMarker = Join-Path $script:stubDir 'lock.marker'
        $script:stubCmd = New-ApplyVipmStub -Directory $script:stubDir

        $env:LVIE_VIPM_CLI_PATH = $script:stubCmd
        $env:VIPM_STUB_ARGS_LOG = $script:argsLog
        $env:VIPM_STUB_LOCK_MARKER = $script:lockMarker
        $env:VIPM_STUB_MODE = ''
    }

    AfterEach {
        foreach ($name in @('LVIE_VIPM_CLI_PATH', 'VIPM_STUB_ARGS_LOG', 'VIPM_STUB_LOCK_MARKER', 'VIPM_STUB_MODE')) {
            Remove-Item -Path ("Env:{0}" -f $name) -ErrorAction SilentlyContinue
        }
    }

    It 'invokes vipm install with resolved year and bitness' {
        $exitCode = Invoke-ApplyVipcWithStub
        $exitCode | Should -Be 0

        $argLines = @(Get-Content -Path $script:argsLog)
        $argLines.Count | Should -BeGreaterOrEqual 1
        $argCombined = $argLines -join "`n"
        $argCombined | Should -Match '--labview-version\s+2026'
        $argCombined | Should -Match '--labview-bitness\s+64'
        $argCombined | Should -Match '--color-mode\s+never'
        $argCombined | Should -Match '\sinstall\s'
    }

    It 'retries on lock contention and succeeds on a later attempt' {
        $env:VIPM_STUB_MODE = 'lock-once'
        $exitCode = Invoke-ApplyVipcWithStub -VipmMaxAttempts 2 -VipmRetryDelaySeconds 0
        $exitCode | Should -Be 0

        $argLines = @(Get-Content -Path $script:argsLog)
        $argLines.Count | Should -BeGreaterOrEqual 2
    }
}
