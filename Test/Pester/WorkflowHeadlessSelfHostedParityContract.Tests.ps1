#Requires -Version 7.0
#Requires -Modules Pester

$ErrorActionPreference = 'Stop'

Describe 'Workflow headless self-hosted parity contract' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..\..')).Path
        $script:workflowPath = Join-Path $script:repoRoot '.github\workflows\headless-self-hosted-parity.yml'
        $script:canonicalWorkflowPath = Join-Path $script:repoRoot '.github\workflows\labview-parity.yml'
        if (-not (Test-Path -Path $script:workflowPath -PathType Leaf)) {
            throw "Workflow file not found: $script:workflowPath"
        }
        if (-not (Test-Path -Path $script:canonicalWorkflowPath -PathType Leaf)) {
            throw "Workflow file not found: $script:canonicalWorkflowPath"
        }

        $script:workflowContent = Get-Content -Path $script:workflowPath -Raw
        $script:canonicalWorkflowContent = Get-Content -Path $script:canonicalWorkflowPath -Raw
    }

    It 'uses workflow_dispatch-only trigger on the self-hosted runner label contract' {
        $script:workflowContent | Should -Match 'workflow_dispatch:'
        $script:workflowContent | Should -Not -Match '(?m)^\s*push\s*:'
        $script:workflowContent | Should -Match 'runs-on:\s*\$\{\{\s*vars\.LVIE_RUNNER_LABEL'
    }

    It 'documents transitional status toward canonical labview-parity workflow' {
        $script:workflowContent | Should -Match 'Transitional workflow note'
        $script:workflowContent | Should -Match 'canonical parity execution is moving to \.github/workflows/labview-parity\.yml'
    }

    It 'acquires lock + worktree via lvie-job-setup for 64-bit parity runs' {
        $script:workflowContent | Should -Match 'uses:\s*\./\.github/actions/lvie-job-setup'
        $script:workflowContent | Should -Match "acquire_lock:\s*'true'"
        $script:workflowContent | Should -Match "create_worktree:\s*'true'"
        $script:workflowContent | Should -Match 'bitness:\s*64'
        $script:workflowContent | Should -Match 'worktree_root_mode:\s*runner_temp'
    }

    It 'runs local auto parity in sequence mode with ppl-single target' {
        $script:workflowContent | Should -Match 'Run-CICompositeLocal-Auto\.ps1'
        $script:workflowContent | Should -Match '-LabVIEWBitness\s+64'
        $script:workflowContent | Should -Match '-EnableSingleBitnessRecoverySequence'
        $script:workflowContent | Should -Match '-SuccessTarget\s+ppl-single'
        $script:workflowContent | Should -Match '-SkipVerifyIEPaths'
        $script:workflowContent | Should -Match '-SkipMissingInProject'
        $script:workflowContent | Should -Match '-SkipBuildVip'
    }

    It 'requires canonical LabVIEW parity self-hosted run to skip vi_validate' {
        $script:canonicalWorkflowContent | Should -Match 'name:\s*Run headless local parity sequence \(64-bit\)'
        $script:canonicalWorkflowContent | Should -Match 'Run-CICompositeLocal-Auto\.ps1'
        $script:canonicalWorkflowContent | Should -Match '-SkipViValidate'
    }

    It 'adds a fail-fast project LVVersion gate before parity execution' {
        $script:workflowContent | Should -Match 'name:\s*Assert project LVVersion contract'
        $script:workflowContent | Should -Match 'Assert-LabVIEWVersion\.ps1'
        $script:workflowContent | Should -Match '-EnforceProjectLvVersion'
        $script:workflowContent | Should -Match '-ProjectPath\s+"\$env:PROJECT_PATH"'
        $script:workflowContent | Should -Match "-Context\s+'headless-project-contract'"

        $setupIndex = $script:workflowContent.IndexOf('name: Job setup', [System.StringComparison]::Ordinal)
        $gateIndex = $script:workflowContent.IndexOf('name: Assert project LVVersion contract', [System.StringComparison]::Ordinal)
        $runIndex = $script:workflowContent.IndexOf('name: Run headless local parity sequence (64-bit)', [System.StringComparison]::Ordinal)

        $setupIndex | Should -BeGreaterThan -1
        $gateIndex | Should -BeGreaterThan -1
        $runIndex | Should -BeGreaterThan -1
        $gateIndex | Should -BeGreaterThan $setupIndex
        $runIndex | Should -BeGreaterThan $gateIndex
    }

    It 'uploads logs and status artifacts with always() semantics and performs teardown cleanup' {
        $script:workflowContent | Should -Match 'if:\s*always\(\)'
        $script:workflowContent | Should -Match 'name:\s*headless-self-hosted-labviewcli-logs'
        $script:workflowContent | Should -Match 'name:\s*headless-self-hosted-agent-logs'
        $script:workflowContent | Should -Match 'name:\s*headless-self-hosted-build-status'
        $script:workflowContent | Should -Match 'name:\s*headless-self-hosted-lv_icon_x64'
        $script:workflowContent | Should -Match 'uses:\s*\./\.github/actions/lvie-job-teardown'
        $script:workflowContent | Should -Match "close_labview:\s*'true'"
        $script:workflowContent | Should -Match "cleanup_worktree:\s*'true'"
        $script:workflowContent | Should -Match "release_lock:\s*'true'"
    }
}
