#Requires -Version 7.0
#Requires -Modules Pester

$ErrorActionPreference = 'Stop'

Describe 'Workflow VIPC dependency contract' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..\..')).Path
        $script:workflowPath = Join-Path $script:repoRoot '.github\workflows\ci-composite.yml'
        if (-not (Test-Path -Path $script:workflowPath -PathType Leaf)) {
            throw "Workflow file not found: $script:workflowPath"
        }

        $script:workflowContent = Get-Content -Path $script:workflowPath -Raw
    }

    It 'uses ApplyVIPC.ps1 as required dependency action in x64 and x86 jobs' {
        $script:workflowContent | Should -Match 'name:\s*Apply VIPC \(LV x64\)'
        $script:workflowContent | Should -Match 'name:\s*Apply VIPC \(LV x86\)'
        $script:workflowContent | Should -Match '\.github\\\\actions\\\\apply-vipc\\\\ApplyVIPC\.ps1'
        $script:workflowContent | Should -Not -Match '-AllowVipcTargetMismatch'
    }

    It 'runs VIPC audit after apply for x64 and x86' {
        $x64ApplyIndex = $script:workflowContent.IndexOf('name: Apply VIPC (LV x64)', [System.StringComparison]::Ordinal)
        $x64AuditIndex = $script:workflowContent.IndexOf('name: Audit VIPC apply (LV x64)', [System.StringComparison]::Ordinal)
        $x86ApplyIndex = $script:workflowContent.IndexOf('name: Apply VIPC (LV x86)', [System.StringComparison]::Ordinal)
        $x86AuditIndex = $script:workflowContent.IndexOf('name: Audit VIPC apply (LV x86)', [System.StringComparison]::Ordinal)

        $x64ApplyIndex | Should -BeGreaterThan -1
        $x64AuditIndex | Should -BeGreaterThan -1
        $x86ApplyIndex | Should -BeGreaterThan -1
        $x86AuditIndex | Should -BeGreaterThan -1

        $x64ApplyIndex | Should -BeLessThan $x64AuditIndex
        $x86ApplyIndex | Should -BeLessThan $x86AuditIndex
    }

    It 'keeps audit and apply log artifact uploads for both bitnesses' {
        $script:workflowContent | Should -Match 'name:\s*Upload VIPC audit artifact \(LV x64\)'
        $script:workflowContent | Should -Match 'name:\s*Upload VIPC apply log artifact \(LV x64\)'
        $script:workflowContent | Should -Match 'name:\s*Upload VIPC audit artifact \(LV x86\)'
        $script:workflowContent | Should -Match 'name:\s*Upload VIPC apply log artifact \(LV x86\)'
        $script:workflowContent | Should -Not -Match 'Apply VIPC \(LV x64, informational\)'
        $script:workflowContent | Should -Not -Match 'Apply VIPC \(LV x86, informational\)'
    }
}
