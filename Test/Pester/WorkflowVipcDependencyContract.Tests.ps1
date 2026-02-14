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
        $script:x64Section = [regex]::Match($script:workflowContent, '(?s)apply-deps-lv-x64:.*?apply-deps-x86:').Value
        $script:x86Section = [regex]::Match($script:workflowContent, '(?s)apply-deps-x86:.*?version:').Value
    }

    It 'runs x64 apply before x64 audit' {
        $applyIndex = $script:x64Section.IndexOf('name: Apply VIPC (LV x64)')
        $auditIndex = $script:x64Section.IndexOf('name: Audit VIPC apply (LV x64)')

        $applyIndex | Should -BeGreaterThan -1
        $auditIndex | Should -BeGreaterThan -1
        $applyIndex | Should -BeLessThan $auditIndex
    }

    It 'runs x86 apply before x86 audit' {
        $applyIndex = $script:x86Section.IndexOf('name: Apply VIPC (LV x86)')
        $auditIndex = $script:x86Section.IndexOf('name: Audit VIPC apply (LV x86)')

        $applyIndex | Should -BeGreaterThan -1
        $auditIndex | Should -BeGreaterThan -1
        $applyIndex | Should -BeLessThan $auditIndex
    }

    It 'passes migration mismatch override during apply stages' {
        $script:x64Section | Should -Match '-AllowVipcTargetMismatch'
        $script:x86Section | Should -Match '-AllowVipcTargetMismatch'
    }
}
