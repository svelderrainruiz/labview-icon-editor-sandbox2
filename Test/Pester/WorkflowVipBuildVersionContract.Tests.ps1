#Requires -Version 7.0
#Requires -Modules Pester

$ErrorActionPreference = 'Stop'

Describe 'Workflow VIP build version contract' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..\..')).Path
        $script:workflows = @(
            Join-Path $script:repoRoot '.github\workflows\ci-composite.yml'
            Join-Path $script:repoRoot '.github\workflows\ci.yml'
        )

        foreach ($workflowPath in $script:workflows) {
            if (-not (Test-Path -Path $workflowPath -PathType Leaf)) {
                throw "Workflow file not found: $workflowPath"
            }
        }
    }

    It 'passes both LABVIEW_VERSION_YEAR and LABVIEW_MINOR_REVISION into Build VI Package step' {
        foreach ($workflowPath in $script:workflows) {
            $content = Get-Content -Path $workflowPath -Raw
            $buildStepIndex = $content.IndexOf('name: Build VI Package (LV 64-bit)', [System.StringComparison]::Ordinal)
            $statusStepIndex = $content.IndexOf('name: Check VIP build status file', [System.StringComparison]::Ordinal)

            $buildStepIndex | Should -BeGreaterThan -1
            $statusStepIndex | Should -BeGreaterThan $buildStepIndex

            $buildStep = $content.Substring($buildStepIndex, $statusStepIndex - $buildStepIndex)
            $buildStep | Should -Match 'Invoke-VipBuild\.ps1'
            $buildStep | Should -Match '-LabVIEWVersion \$env:LABVIEW_VERSION_YEAR'
            $buildStep | Should -Match '-LabVIEWMinorRevision \$env:LABVIEW_MINOR_REVISION'
        }
    }
}
