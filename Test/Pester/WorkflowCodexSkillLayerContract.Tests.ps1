#Requires -Version 7.0
#Requires -Modules Pester

$ErrorActionPreference = 'Stop'

Describe 'Workflow Codex skill layer asset contract' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..\..')).Path
        $script:ciCompositePath = Join-Path $script:repoRoot '.github\workflows\ci-composite.yml'
        $script:ciPath = Join-Path $script:repoRoot '.github\workflows\ci.yml'

        foreach ($path in @($script:ciCompositePath, $script:ciPath)) {
            if (-not (Test-Path -Path $path -PathType Leaf)) {
                throw "Required file not found: $path"
            }
        }

        $script:ciCompositeContent = Get-Content -Path $script:ciCompositePath -Raw
        $script:ciContent = Get-Content -Path $script:ciPath -Raw
    }

    It 'defines and uploads codex-skill-layer in ci-composite' {
        $script:ciCompositeContent | Should -Match 'codex-skill-layer-asset:'
        $script:ciCompositeContent | Should -Match 'artifact_name=codex-skill-layer'
        $script:ciCompositeContent | Should -Match "requiredAssets = @\('vip', 'release_notes', 'labviewcli-logs', 'vip-build-status', 'linux-packed-library', 'windows-packed-library', 'codex-skill-layer'\)"
        $script:ciCompositeContent | Should -Match "requiredAssets = @\('linux-packed-library', 'windows-packed-library', 'codex-skill-layer'\)"
        $script:ciCompositeContent | Should -Match 'Download Codex skill layer artifact'
    }

    It 'includes codex-skill-layer-asset in publish gate and publish prerelease needs' {
        $script:ciCompositeContent | Should -Match "needs:\s*\[run-metadata, prerelease-context, version, build-vip, build-ppl-linux-container, build-ppl-windows-container, codex-skill-layer-asset, publish-gate\]"
        $script:ciCompositeContent | Should -Match "'codex-skill-layer-asset'"
    }

    It 'defines and uploads codex-skill-layer in ci.yml contracts' {
        $script:ciContent | Should -Match 'codex-skill-layer-asset:'
        $script:ciContent | Should -Match 'artifact_name=codex-skill-layer'
        $script:ciContent | Should -Match "'codex-skill-layer-asset'"
    }
}
