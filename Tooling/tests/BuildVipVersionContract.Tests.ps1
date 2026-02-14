#Requires -Version 7.0
#Requires -Modules Pester

$ErrorActionPreference = 'Stop'

Describe 'Build VIP version contract' {
    BeforeAll {
        $script:toolingRoot = Split-Path -Parent $PSScriptRoot
        $script:repoRoot = Split-Path -Parent $script:toolingRoot
        $script:buildVipScriptPath = Join-Path $script:repoRoot '.github\actions\build-vip\build_vip.ps1'
        $script:workflowPath = Join-Path $script:repoRoot '.github\workflows\ci-composite.yml'

        if (-not (Test-Path -Path $script:buildVipScriptPath -PathType Leaf)) {
            throw "Build VIP script not found: $script:buildVipScriptPath"
        }
        if (-not (Test-Path -Path $script:workflowPath -PathType Leaf)) {
            throw "Workflow file not found: $script:workflowPath"
        }

        $script:buildVipContent = Get-Content -Path $script:buildVipScriptPath -Raw
        $script:workflowContent = Get-Content -Path $script:workflowPath -Raw
    }

    It 'requires both LabVIEWVersion and LabVIEWMinorRevision semantics in build_vip script' {
        $script:buildVipContent | Should -Match '\$LabVIEWVersion'
        $script:buildVipContent | Should -Match '\$LabVIEWMinorRevision'
        $script:buildVipContent | Should -Match "LabVIEWMinorRevision '.+' does not match \.lvversion minor"
        $script:buildVipContent | Should -Match '\$lvNumericVersion\s*=\s*"\$\(\$lvNumericMajor\)\.\$LabVIEWMinorRevision"'
    }

    It 'passes both year and minor revision in CI composite build-vip invocation' {
        $script:workflowContent | Should -Match '-LabVIEWVersion \$env:LABVIEW_VERSION_YEAR'
        $script:workflowContent | Should -Match '-LabVIEWMinorRevision \$env:LABVIEW_MINOR_REVISION'
    }
}
