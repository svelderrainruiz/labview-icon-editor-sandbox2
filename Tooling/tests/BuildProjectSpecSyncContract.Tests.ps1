#Requires -Version 7.0
#Requires -Modules Pester

$ErrorActionPreference = 'Stop'

Describe 'BuildProjectSpec source sync contract' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..\..')).Path
        $script:buildProjectSpecPath = Join-Path $script:repoRoot '.github\actions\build-lvlibp\BuildProjectSpec.ps1'
        $script:ciWorkflowPath = Join-Path $script:repoRoot '.github\workflows\ci.yml'
        $script:ciCompositeWorkflowPath = Join-Path $script:repoRoot '.github\workflows\ci-composite.yml'
        $script:runCiCompositeLocalPath = Join-Path $script:repoRoot 'Tooling\Run-CICompositeLocal.ps1'
        if (-not (Test-Path -Path $script:buildProjectSpecPath -PathType Leaf)) {
            throw "BuildProjectSpec script not found: $script:buildProjectSpecPath"
        }
        if (-not (Test-Path -Path $script:ciWorkflowPath -PathType Leaf)) {
            throw "Workflow script not found: $script:ciWorkflowPath"
        }
        if (-not (Test-Path -Path $script:ciCompositeWorkflowPath -PathType Leaf)) {
            throw "Workflow script not found: $script:ciCompositeWorkflowPath"
        }
        if (-not (Test-Path -Path $script:runCiCompositeLocalPath -PathType Leaf)) {
            throw "Run-CICompositeLocal script not found: $script:runCiCompositeLocalPath"
        }

        $script:content = Get-Content -Path $script:buildProjectSpecPath -Raw
        $script:ciWorkflowContent = Get-Content -Path $script:ciWorkflowPath -Raw
        $script:ciCompositeWorkflowContent = Get-Content -Path $script:ciCompositeWorkflowPath -Raw
        $script:runCiCompositeLocalContent = Get-Content -Path $script:runCiCompositeLocalPath -Raw
    }

    It 'keeps workspace-to-install source sync opt-in' {
        $script:content | Should -Match '\[switch\]\$SyncIconEditorSourcesToInstall'
        $script:content | Should -Match 'if \(\$SyncIconEditorSourcesToInstall\.IsPresent\)'
        $script:content | Should -Match 'Skipping workspace-to-install Icon Editor source synchronization before build-spec execution\.'
        $script:content | Should -Not -Match 'Closing LabVIEW after MassCompile to clear in-memory VI state before build-spec execution\.'
        $script:content | Should -Match 'Invoke-CloseLabVIEWSafely -Version \$labviewVersionForClose -Bitness \$SupportedBitness'
    }

    It 'uses lvversion-normalized raw version for close-labview calls' {
        $script:content | Should -Match '\$labviewVersionForClose = \$versionInfo\.Raw'
        $script:content | Should -Not -Match 'Invoke-CloseLabVIEWSafely -Version \$labviewYear -Bitness \$SupportedBitness'
    }

    It 'enables workspace-to-install sync for CI BuildProjectSpec invocations' {
        $script:ciWorkflowContent | Should -Match '-SyncIconEditorSourcesToInstall'
        $script:ciCompositeWorkflowContent | Should -Match '-SyncIconEditorSourcesToInstall'
        $script:runCiCompositeLocalContent | Should -Match '-SyncIconEditorSourcesToInstall'
    }

    It 'normalizes symbolic resource and vilib URL aliases to repo-relative paths during build-spec execution' {
        $script:content | Should -Match '\$resourcePrefix = ''/<resource>/plugins/'''
        $script:content | Should -Match '\$resourceReplacement = ''\.\./resource/plugins/'''
        $script:content | Should -Match '\$vilibPrefix = ''/<vilib>/LabVIEW Icon API/'''
        $script:content | Should -Match '\$vilibReplacement = ''\.\./vi\.lib/LabVIEW Icon API/'''
        $script:content | Should -Match 'Normalized project URL aliases for build-spec execution'
    }
}
