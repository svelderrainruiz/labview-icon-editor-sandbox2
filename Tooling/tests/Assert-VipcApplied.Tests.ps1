#Requires -Version 7.0
#Requires -Modules Pester

$ErrorActionPreference = 'Stop'

BeforeAll {
    $script:toolingRoot = Split-Path -Parent $PSScriptRoot
    $script:repoRoot = Split-Path -Parent $script:toolingRoot
    $script:assertScript = Join-Path $script:toolingRoot 'Assert-VipcApplied.ps1'
    $script:vipmHelper = Join-Path $script:toolingRoot 'support\VipmCli.ps1'

    if (-not (Test-Path -Path $script:assertScript -PathType Leaf)) {
        throw "Assert-VipcApplied script not found: $script:assertScript"
    }
    if (-not (Test-Path -Path $script:vipmHelper -PathType Leaf)) {
        throw "VIPM helper script not found: $script:vipmHelper"
    }

    . $script:vipmHelper
}

function script:New-VipmStub {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Directory
    )

    $stubPs1 = Join-Path $Directory 'vipm-stub.ps1'
    $stubCmd = Join-Path $Directory 'vipm.cmd'

    @'
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)

$argLine = $Args -join ' '
if (-not [string]::IsNullOrWhiteSpace($env:VIPM_STUB_ARGS_LOG)) {
    Add-Content -Path $env:VIPM_STUB_ARGS_LOG -Value $argLine
}

$installed = $argLine -match '(^|\s)--installed(\s|$)'
if ($installed) {
    $stdout = [string]$env:VIPM_STUB_INSTALLED_STDOUT
    $stderr = [string]$env:VIPM_STUB_INSTALLED_STDERR
    $exitCode = if ([string]::IsNullOrWhiteSpace($env:VIPM_STUB_INSTALLED_EXITCODE)) { 0 } else { [int]$env:VIPM_STUB_INSTALLED_EXITCODE }
} else {
    $stdout = [string]$env:VIPM_STUB_EXPECTED_STDOUT
    $stderr = [string]$env:VIPM_STUB_EXPECTED_STDERR
    $exitCode = if ([string]::IsNullOrWhiteSpace($env:VIPM_STUB_EXPECTED_EXITCODE)) { 0 } else { [int]$env:VIPM_STUB_EXPECTED_EXITCODE }
}

if (-not [string]::IsNullOrWhiteSpace($stdout)) {
    $stdout -split "\r?\n" | ForEach-Object { if (-not [string]::IsNullOrWhiteSpace($_)) { Write-Output $_ } }
}
if (-not [string]::IsNullOrWhiteSpace($stderr)) {
    $stderr -split "\r?\n" | ForEach-Object { if (-not [string]::IsNullOrWhiteSpace($_)) { [Console]::Error.WriteLine($_) } }
}

exit $exitCode
'@ | Set-Content -Path $stubPs1 -Encoding utf8

    @"
@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "$stubPs1" %*
exit /b %errorlevel%
"@ | Set-Content -Path $stubCmd -Encoding ascii

    return $stubCmd
}

function script:Invoke-AssertVipcWithStub {
    param(
        [Parameter(Mandatory = $true)]
        [string]$OutputPath,

        [Parameter(Mandatory = $false)]
        [bool]$FailOnMismatch = $true
    )

    $previousNativePreference = $PSNativeCommandUseErrorActionPreference
    $PSNativeCommandUseErrorActionPreference = $false
    try {
        $null = & pwsh -NoProfile -File $script:assertScript `
            -RepoRoot $script:repoRoot `
            -VIPCPath '.github/actions/apply-vipc/runner_dependencies.vipc' `
            -SupportedBitness 64 `
            -OutputPath $OutputPath `
            -FailOnMismatch:$FailOnMismatch
        $exitCode = $LASTEXITCODE
    }
    finally {
        $PSNativeCommandUseErrorActionPreference = $previousNativePreference
    }
    return [pscustomobject]@{
        ExitCode   = $exitCode
        OutputPath = $OutputPath
    }
}

Describe 'Parse-VipmListPackages' {
    It 'parses package_id and version tuples from vipm list output' {
        $text = @'
Found 2 packages:
  LUnit (astemes_lib_lunit v1.12.5.6)
  VIPM API (jki_lib_vipm_api v2020.0.3.80)
Listing installed packages
'@
        $parsed = @(ConvertFrom-VipmListPackage -Text $text)
        $parsed.Count | Should -Be 2
        $parsed[0].package_id | Should -Be 'astemes_lib_lunit'
        $parsed[0].version | Should -Be '1.12.5.6'
        $parsed[1].package_id | Should -Be 'jki_lib_vipm_api'
        $parsed[1].version | Should -Be '2020.0.3.80'
    }
}

Describe 'Assert-VipcApplied script behavior' {
    BeforeEach {
        $script:stubDir = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -Path $script:stubDir -ItemType Directory -Force | Out-Null
        $script:stubCmd = New-VipmStub -Directory $script:stubDir
        $script:outputPath = Join-Path $script:stubDir 'vipc-audit.json'
        $script:argsLog = Join-Path $script:stubDir 'vipm-args.log'

        $env:LVIE_VIPM_CLI_PATH = $script:stubCmd
        $env:VIPM_STUB_ARGS_LOG = $script:argsLog
        $env:VIPM_STUB_EXPECTED_EXITCODE = '0'
        $env:VIPM_STUB_INSTALLED_EXITCODE = '0'
        $env:VIPM_STUB_EXPECTED_STDERR = ''
        $env:VIPM_STUB_INSTALLED_STDERR = ''
    }

    AfterEach {
        foreach ($name in @(
            'LVIE_VIPM_CLI_PATH',
            'VIPM_STUB_ARGS_LOG',
            'VIPM_STUB_EXPECTED_STDOUT',
            'VIPM_STUB_INSTALLED_STDOUT',
            'VIPM_STUB_EXPECTED_EXITCODE',
            'VIPM_STUB_INSTALLED_EXITCODE',
            'VIPM_STUB_EXPECTED_STDERR',
            'VIPM_STUB_INSTALLED_STDERR'
        )) {
            Remove-Item -Path ("Env:{0}" -f $name) -ErrorAction SilentlyContinue
        }
    }

    It 'fails when expected package is missing from installed set' {
        $env:VIPM_STUB_EXPECTED_STDOUT = @'
Found 2 packages:
  LUnit (astemes_lib_lunit v1.12.5.6)
  VIPM API (jki_lib_vipm_api v2020.0.3.80)
'@
        $env:VIPM_STUB_INSTALLED_STDOUT = @'
Found 1 packages:
  LUnit (astemes_lib_lunit v1.12.5.6)
'@

        $result = Invoke-AssertVipcWithStub -OutputPath $script:outputPath -FailOnMismatch $true
        $result.ExitCode | Should -Be 1
    }

    It 'fails when installed version mismatches expected version' {
        $env:VIPM_STUB_EXPECTED_STDOUT = @'
Found 1 packages:
  LUnit (astemes_lib_lunit v1.12.5.6)
'@
        $env:VIPM_STUB_INSTALLED_STDOUT = @'
Found 1 packages:
  LUnit (astemes_lib_lunit v1.12.5.5)
'@

        $result = Invoke-AssertVipcWithStub -OutputPath $script:outputPath -FailOnMismatch $true
        $result.ExitCode | Should -Be 1
    }

    It 'passes and reports unexpected installed packages as informational only' {
        $env:VIPM_STUB_EXPECTED_STDOUT = @'
Found 1 packages:
  LUnit (astemes_lib_lunit v1.12.5.6)
'@
        $env:VIPM_STUB_INSTALLED_STDOUT = @'
Found 2 packages:
  LUnit (astemes_lib_lunit v1.12.5.6)
  VIPM API (jki_lib_vipm_api v2020.0.3.80)
'@

        $result = Invoke-AssertVipcWithStub -OutputPath $script:outputPath -FailOnMismatch $true
        $result.ExitCode | Should -Be 0

        $report = Get-Content -Raw -Path $script:outputPath | ConvertFrom-Json
        $report.summary.status | Should -Be 'pass'
        @($report.unexpected_installed).Count | Should -Be 1
        $report.unexpected_installed[0].package_id | Should -Be 'jki_lib_vipm_api'
    }
}
