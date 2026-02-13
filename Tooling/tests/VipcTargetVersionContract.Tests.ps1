#Requires -Version 7.0
#Requires -Modules Pester

$ErrorActionPreference = 'Stop'

Describe 'VIPC target version contract' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..\..')).Path
        $script:versionHelper = Join-Path $script:repoRoot 'Tooling\support\LabVIEWVersion.ps1'
        $script:vipcHelper = Join-Path $script:repoRoot 'Tooling\support\VipcConfig.ps1'
        $script:vipcPath = Join-Path $script:repoRoot '.github\actions\apply-vipc\runner_dependencies.vipc'

        if (-not (Test-Path -Path $script:versionHelper -PathType Leaf)) {
            throw "LabVIEW version helper not found: $script:versionHelper"
        }
        if (-not (Test-Path -Path $script:vipcHelper -PathType Leaf)) {
            throw "VIPC config helper not found: $script:vipcHelper"
        }
        if (-not (Test-Path -Path $script:vipcPath -PathType Leaf)) {
            throw "VIPC file not found: $script:vipcPath"
        }

        . $script:versionHelper
        . $script:vipcHelper

        $script:lvInfo = Get-LabVIEWVersionInfo -RepoRoot $script:repoRoot
        $script:vipcInfo = Get-VipcConfigInfo -VipcPath $script:vipcPath
    }

    It 'resolves .lvversion numeric contract value' {
        $script:lvInfo.NumericVersion | Should -Match '^\d+\.\d+$'
    }

    It 'matches VIPC target numeric version exactly to .lvversion' {
        $script:vipcInfo.TargetVersionNumeric | Should -Be $script:lvInfo.NumericVersion
    }
}
