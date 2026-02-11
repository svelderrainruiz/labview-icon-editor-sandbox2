#Requires -Version 7.0
#Requires -Modules Pester

BeforeAll {
    $Script:ToolingRoot = Split-Path -Parent $PSScriptRoot
    $Script:PathContractScript = Join-Path $Script:ToolingRoot 'support\PathContract.ps1'
    . $Script:PathContractScript
}

Describe 'Resolve-LvieRepoRoot' {
    It 'prefers LVIE_REPO_ROOT over workspace and repo aliases' {
        $result = Resolve-LvieRepoRoot `
            -LvieRepoRoot 'C:\canonical\repo' `
            -WorkspaceRoot 'C:\workspace\alias' `
            -RepoRoot 'C:\repo\alias' `
            -DefaultRepoRoot 'C:\default\repo'

        $result.Path | Should -Be ([System.IO.Path]::GetFullPath('C:\canonical\repo'))
        $result.Source | Should -Be '$env:LVIE_REPO_ROOT'
    }

    It 'falls back to WORKSPACE_ROOT when canonical root is missing' {
        $result = Resolve-LvieRepoRoot `
            -LvieRepoRoot '' `
            -WorkspaceRoot 'C:\workspace\alias' `
            -RepoRoot 'C:\repo\alias' `
            -DefaultRepoRoot 'C:\default\repo'

        $result.Path | Should -Be ([System.IO.Path]::GetFullPath('C:\workspace\alias'))
        $result.Source | Should -Be '$env:WORKSPACE_ROOT or parameter:WorkspaceRoot'
    }
}

Describe 'Resolve-LvieProjectPath' {
    It 'prefers LVIE_PROJECT_PATH when provided' {
        $result = Resolve-LvieProjectPath `
            -LvieProjectPath 'C:\canonical\repo\custom.lvproj' `
            -ProjectPath 'C:\legacy\repo\legacy.lvproj' `
            -RepoRoot 'C:\canonical\repo' `
            -ProjectRelativePath 'lv_icon_editor.lvproj'

        $result.Path | Should -Be ([System.IO.Path]::GetFullPath('C:\canonical\repo\custom.lvproj'))
        $result.Source | Should -Be '$env:LVIE_PROJECT_PATH'
    }

    It 'derives project path from repo root and relative path when explicit project paths are missing' {
        $result = Resolve-LvieProjectPath `
            -LvieProjectPath '' `
            -ProjectPath '' `
            -RepoRoot 'C:\canonical\repo' `
            -ProjectRelativePath 'relative\project.lvproj'

        $result.Path | Should -Be ([System.IO.Path]::GetFullPath('C:\canonical\repo\relative\project.lvproj'))
        $result.RelativePath | Should -Be 'relative\project.lvproj'
        $result.Source | Should -Be '$env:LVIE_PROJECT_RELATIVE_PATH or default'
    }
}

Describe 'Join-LvieRepoPath' {
    It 'joins a relative path with repo root' {
        $result = Join-LvieRepoPath -RepoRoot 'C:\canonical\repo' -RelativePath 'Test\Templates'
        $result | Should -Be ([System.IO.Path]::GetFullPath('C:\canonical\repo\Test\Templates'))
    }

    It 'returns absolute path input unchanged' {
        $result = Join-LvieRepoPath -RepoRoot 'C:\canonical\repo' -RelativePath 'C:\absolute\path.txt'
        $result | Should -Be ([System.IO.Path]::GetFullPath('C:\absolute\path.txt'))
    }
}
