#Requires -Version 7.0
#Requires -Modules Pester

BeforeAll {
    $Script:RepoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..\..')).Path
    $Script:HelperPath = Join-Path $Script:RepoRoot 'Tooling\support\DevModeNoLabVIEWSmoke.ps1'
    if (-not (Test-Path -Path $Script:HelperPath -PathType Leaf)) {
        throw "DevModeNoLabVIEWSmoke helper not found at $Script:HelperPath"
    }
    . $Script:HelperPath
}

Describe 'Get-DevModeNoLabVIEWSmokeSuite' {
    It 'returns the minimal suite with only DevMode.NoLabVIEW unit tests' {
        $suite = Get-DevModeNoLabVIEWSmokeSuite -Depth 'minimal'

        $suite.Depth | Should -Be 'minimal'
        $suite.Tests | Should -HaveCount 1
        $suite.Tests[0].Path | Should -Be 'Test/Pester/DevMode.NoLabVIEW.Tests.ps1'
        $suite.Tests[0].Kind | Should -Be 'unit'
    }

    It 'returns the balanced suite with unit plus LUnit/missing-in-project integration smoke' {
        $suite = Get-DevModeNoLabVIEWSmokeSuite -Depth 'balanced'

        $suite.Depth | Should -Be 'balanced'
        $suite.Tests | Should -HaveCount 3
        $suite.Tests[0].Path | Should -Be 'Test/Pester/DevMode.NoLabVIEW.Tests.ps1'
        $suite.Tests[1].Path | Should -Be 'Test/Pester/MissingInProject.DevMode.NoLabVIEW.Integration.Tests.ps1'
        $suite.Tests[2].Path | Should -Be 'Test/Pester/LUnit.DevMode.NoLabVIEW.Integration.Tests.ps1'
        ($suite.Tests | Where-Object { $_.Kind -eq 'integration' }).Count | Should -Be 2
    }

    It 'returns the full suite with all no-LabVIEW integration smoke files' {
        $suite = Get-DevModeNoLabVIEWSmokeSuite -Depth 'full'

        $suite.Depth | Should -Be 'full'
        $suite.Tests | Should -HaveCount 5
        $suite.Tests[0].Path | Should -Be 'Test/Pester/DevMode.NoLabVIEW.Tests.ps1'
        $suite.Tests[1].Path | Should -Be 'Test/Pester/MissingInProject.DevMode.NoLabVIEW.Integration.Tests.ps1'
        $suite.Tests[2].Path | Should -Be 'Test/Pester/LUnit.DevMode.NoLabVIEW.Integration.Tests.ps1'
        $suite.Tests[3].Path | Should -Be 'Test/Pester/VerifyIEPaths.DevMode.Integration.Tests.ps1'
        $suite.Tests[4].Path | Should -Be 'Test/Pester/BuildLvlibp.DevMode.NoLabVIEW.Integration.Tests.ps1'
        ($suite.Tests | Where-Object { $_.Kind -eq 'integration' }).Count | Should -Be 4
    }
}

Describe 'Test-DevModeNoLabVIEWSmokeCoverage' {
    It 'fails when integration smoke files are fully skipped' {
        $suite = Get-DevModeNoLabVIEWSmokeSuite -Depth 'balanced'
        $integrationPaths = @(
            [System.IO.Path]::GetFullPath((Join-Path $Script:RepoRoot 'Test/Pester/MissingInProject.DevMode.NoLabVIEW.Integration.Tests.ps1')),
            [System.IO.Path]::GetFullPath((Join-Path $Script:RepoRoot 'Test/Pester/LUnit.DevMode.NoLabVIEW.Integration.Tests.ps1'))
        )

        $pesterResult = [pscustomobject]@{
            Tests = @(
                [pscustomobject]@{ ScriptBlock = [pscustomobject]@{ File = $integrationPaths[0] }; Result = 'Skipped' },
                [pscustomobject]@{ ScriptBlock = [pscustomobject]@{ File = $integrationPaths[1] }; Result = 'Skipped' }
            )
        }

        $coverage = Test-DevModeNoLabVIEWSmokeCoverage -PesterResult $pesterResult -Suite $suite

        $coverage.Passed | Should -BeFalse
        $coverage.Messages.Count | Should -Be 2
        ($coverage.Messages -join ' ') | Should -Match 'fully skipped'
    }

    It 'passes when integration smoke executes at least one test per integration file' {
        $suite = Get-DevModeNoLabVIEWSmokeSuite -Depth 'balanced'
        $integrationPaths = @(
            [System.IO.Path]::GetFullPath((Join-Path $Script:RepoRoot 'Test/Pester/MissingInProject.DevMode.NoLabVIEW.Integration.Tests.ps1')),
            [System.IO.Path]::GetFullPath((Join-Path $Script:RepoRoot 'Test/Pester/LUnit.DevMode.NoLabVIEW.Integration.Tests.ps1'))
        )

        $pesterResult = [pscustomobject]@{
            Tests = @(
                [pscustomobject]@{ ScriptBlock = [pscustomobject]@{ File = $integrationPaths[0] }; Result = 'Passed' },
                [pscustomobject]@{ ScriptBlock = [pscustomobject]@{ File = $integrationPaths[0] }; Result = 'Skipped' },
                [pscustomobject]@{ ScriptBlock = [pscustomobject]@{ File = $integrationPaths[1] }; Result = 'Passed' }
            )
        }

        $coverage = Test-DevModeNoLabVIEWSmokeCoverage -PesterResult $pesterResult -Suite $suite

        $coverage.Passed | Should -BeTrue
        @($coverage.Messages).Count | Should -Be 0
        $coverage.Details | Should -HaveCount 2
    }
}

Describe 'Assert-DevModeNoLabVIEWProjectFileClean' {
    It 'passes when project status output is empty' {
        {
            Assert-DevModeNoLabVIEWProjectFileClean `
                -RepoRoot $Script:RepoRoot `
                -ProjectRelativePath 'lv_icon_editor.lvproj' `
                -StatusLines @()
        } | Should -Not -Throw
    }

    It 'fails when project status output indicates a dirty file' {
        {
            Assert-DevModeNoLabVIEWProjectFileClean `
                -RepoRoot $Script:RepoRoot `
                -ProjectRelativePath 'lv_icon_editor.lvproj' `
                -StatusLines @(' M lv_icon_editor.lvproj')
        } | Should -Throw "'lv_icon_editor.lvproj' must be clean before smoke/parity. Clear it, then rerun."
    }
}
