#Requires -Version 7.0
#Requires -Modules Pester

$ErrorActionPreference = 'Stop'

Describe 'BuildProjectSpec source sync contract' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..\..')).Path
        $script:buildProjectSpecPath = Join-Path $script:repoRoot '.github\actions\build-lvlibp\BuildProjectSpec.ps1'
        if (-not (Test-Path -Path $script:buildProjectSpecPath -PathType Leaf)) {
            throw "BuildProjectSpec script not found: $script:buildProjectSpecPath"
        }

        $script:content = Get-Content -Path $script:buildProjectSpecPath -Raw
    }

    It 'keeps workspace-to-install source sync opt-in' {
        $script:content | Should -Match '\[switch\]\$SyncIconEditorSourcesToInstall'
        $script:content | Should -Match 'if \(\$SyncIconEditorSourcesToInstall\.IsPresent\)'
        $script:content | Should -Match 'Skipping workspace-to-install Icon Editor source synchronization before build-spec execution\.'
    }
}
