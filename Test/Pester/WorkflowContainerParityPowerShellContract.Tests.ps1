#Requires -Version 7.0
#Requires -Modules Pester

$ErrorActionPreference = 'Stop'

Describe 'Workflow container parity PowerShell contract' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..\..')).Path
        $script:containerParityWorkflowPath = Join-Path $script:repoRoot '.github\workflows\labview-container-parity.yml'
        $script:ciCompositeWorkflowPath = Join-Path $script:repoRoot '.github\workflows\ci-composite.yml'

        foreach ($path in @($script:containerParityWorkflowPath, $script:ciCompositeWorkflowPath)) {
            if (-not (Test-Path -Path $path -PathType Leaf)) {
                throw "Required workflow file not found: $path"
            }
        }

        $script:containerParityContent = Get-Content -Path $script:containerParityWorkflowPath -Raw
        $script:ciCompositeContent = Get-Content -Path $script:ciCompositeWorkflowPath -Raw
    }

    It 'adds path-contract preflight before Windows container parity run in labview-container-parity.yml' {
        $script:containerParityContent | Should -Match 'Validate path contract for Windows container shell'
        $script:containerParityContent | Should -Match 'pwsh -NoProfile -File "\$env:GITHUB_WORKSPACE\\Tooling\\Test-PathContract\.ps1" -WriteSummary'
        $script:containerParityContent | Should -Match 'powershell -NoProfile -ExecutionPolicy Bypass -File C:\\workspace\\Tooling\\container-parity\\runlabview-windows\.ps1'

        $preflightIndex = $script:containerParityContent.IndexOf('Validate path contract for Windows container shell')
        $runIndex = $script:containerParityContent.IndexOf('Run LabVIEWCLI parity script (Windows)')
        $preflightIndex | Should -BeGreaterThan -1
        $runIndex | Should -BeGreaterThan -1
        $preflightIndex | Should -BeLessThan $runIndex
    }

    It 'adds path-contract preflight before Windows container packed-library build in ci-composite.yml' {
        $script:ciCompositeContent | Should -Match 'Validate path contract for Windows container shell'
        $script:ciCompositeContent | Should -Match 'pwsh -NoProfile -File "\$env:GITHUB_WORKSPACE\\Tooling\\Test-PathContract\.ps1" -WriteSummary'
        $script:ciCompositeContent | Should -Match 'powershell -NoProfile -ExecutionPolicy Bypass -File C:\\workspace\\Tooling\\container-parity\\runlabview-windows\.ps1'

        $preflightIndex = $script:ciCompositeContent.IndexOf('Validate path contract for Windows container shell')
        $buildIndex = $script:ciCompositeContent.IndexOf('Build Windows packed library via LabVIEWCLI container parity script')
        $preflightIndex | Should -BeGreaterThan -1
        $buildIndex | Should -BeGreaterThan -1
        $preflightIndex | Should -BeLessThan $buildIndex
    }
}

