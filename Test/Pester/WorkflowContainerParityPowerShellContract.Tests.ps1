#Requires -Version 7.0
#Requires -Modules Pester

$ErrorActionPreference = 'Stop'

Describe 'Workflow container parity PowerShell contract' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..\..')).Path
        $script:canonicalWorkflowPath = Join-Path $script:repoRoot '.github\workflows\labview-parity.yml'
        $script:wrapperWorkflowPath = Join-Path $script:repoRoot '.github\workflows\labview-container-parity.yml'
        $script:ciCompositeWorkflowPath = Join-Path $script:repoRoot '.github\workflows\ci-composite.yml'

        foreach ($path in @($script:canonicalWorkflowPath, $script:wrapperWorkflowPath, $script:ciCompositeWorkflowPath)) {
            if (-not (Test-Path -Path $path -PathType Leaf)) {
                throw "Required workflow file not found: $path"
            }
        }

        $script:canonicalContent = Get-Content -Path $script:canonicalWorkflowPath -Raw
        $script:wrapperContent = Get-Content -Path $script:wrapperWorkflowPath -Raw
        $script:ciCompositeContent = Get-Content -Path $script:ciCompositeWorkflowPath -Raw
    }

    It 'adds path-contract preflight before Windows parity run in labview-parity.yml' {
        $script:canonicalContent | Should -Match 'Validate path contract for Windows container shell'
        $script:canonicalContent | Should -Match 'pwsh -NoProfile -File "\$env:GITHUB_WORKSPACE\\Tooling\\Test-PathContract\.ps1" -WriteSummary'
        $script:canonicalContent | Should -Match 'Run parity lane via runner-cli \(windows-container\)'
        $script:canonicalContent | Should -Match '--mode windows-container'

        $preflightIndex = $script:canonicalContent.IndexOf('Validate path contract for Windows container shell')
        $runIndex = $script:canonicalContent.IndexOf('Run parity lane via runner-cli (windows-container)')
        $preflightIndex | Should -BeGreaterThan -1
        $runIndex | Should -BeGreaterThan -1
        $preflightIndex | Should -BeLessThan $runIndex
    }

    It 'gates Windows container parity on self-hosted parity success' {
        $script:canonicalContent | Should -Match 'parity-windows:\s*\r?\n\s+name:\s*Parity \(Windows Container\)\s*\r?\n\s+needs:\s*\[resolve-parity-context,\s*parity-self-hosted\]'
        $script:canonicalContent | Should -Match "needs\.parity-self-hosted\.result == 'success'"
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

    It 'keeps the legacy workflow as a forwarding wrapper to labview-parity.yml' {
        $script:wrapperContent | Should -Match 'name:\s*LabVIEW Container Parity \(Compatibility Wrapper\)'
        $script:wrapperContent | Should -Match 'uses:\s*\./\.github/workflows/labview-parity\.yml'
        $script:wrapperContent | Should -Match 'run_self_hosted:'
        $script:wrapperContent | Should -Match 'expected_sha:'
        $script:wrapperContent | Should -Match 'expected_sha:\s*\$\{\{ inputs\.expected_sha \}\}'
    }
}
