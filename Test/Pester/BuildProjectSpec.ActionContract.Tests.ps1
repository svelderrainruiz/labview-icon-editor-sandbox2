#Requires -Version 7.0
#Requires -Modules Pester

$ErrorActionPreference = 'Stop'

Describe 'Build project-spec action contracts' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..\..')).Path
        $script:projectSpecActionPath = Join-Path $script:repoRoot '.github\actions\build-project-spec\action.yml'
        $script:packedCompatActionPath = Join-Path $script:repoRoot '.github\actions\build-lvlibp\action.yml'
        $script:projectSpecScriptPath = Join-Path $script:repoRoot '.github\actions\build-lvlibp\BuildProjectSpec.ps1'
        $script:packedShimScriptPath = Join-Path $script:repoRoot '.github\actions\build-lvlibp\Build_lvlibp.ps1'

        foreach ($path in @($script:projectSpecActionPath, $script:packedCompatActionPath, $script:projectSpecScriptPath, $script:packedShimScriptPath)) {
            if (-not (Test-Path -Path $path -PathType Leaf)) {
                throw "Required file not found: $path"
            }
        }

        $script:projectSpecActionContent = Get-Content -Path $script:projectSpecActionPath -Raw
        $script:packedCompatActionContent = Get-Content -Path $script:packedCompatActionPath -Raw
        $script:packedShimScriptContent = Get-Content -Path $script:packedShimScriptPath -Raw
    }

    It 'defines canonical build-project-spec action inputs for spec type routing' {
        $script:projectSpecActionContent | Should -Match 'name:\s*"Build Project Spec"'
        $script:projectSpecActionContent | Should -Match 'project_spec_type:'
        $script:projectSpecActionContent | Should -Match 'build_spec_name:'
        $script:projectSpecActionContent | Should -Match 'output_relative_path:'
        $script:projectSpecActionContent | Should -Match 'target_name:'
        $script:projectSpecActionContent | Should -Match 'BuildProjectSpec\.ps1'
    }

    It 'keeps build-lvlibp action as compatibility wrapper to packed-library shim script' {
        $script:packedCompatActionContent | Should -Match 'Compatibility wrapper'
        $script:packedCompatActionContent | Should -Match 'Build_lvlibp\.ps1'
        $script:packedCompatActionContent | Should -Match "-Context 'build-lvlibp'"
    }

    It 'keeps Build_lvlibp shim forwarding to BuildProjectSpec with deprecation warning' {
        $script:packedShimScriptContent | Should -Match 'deprecated'
        $script:packedShimScriptContent | Should -Match 'BuildProjectSpec\.ps1'
        $script:packedShimScriptContent | Should -Match "ProjectSpecType = 'PackedLibrary'"
    }
}
