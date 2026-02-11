$ErrorActionPreference = 'Stop'

Describe 'RunUnitTests backend resolution' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..\..')).Path
        $script:scriptPath = Join-Path $script:repoRoot '.github\actions\run-unit-tests\RunUnitTests.ps1'
        if (-not (Test-Path -Path $script:scriptPath -PathType Leaf)) {
            throw "RunUnitTests.ps1 not found at $script:scriptPath"
        }

        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($script:scriptPath, [ref]$tokens, [ref]$errors)
        if ($errors -and $errors.Count -gt 0) {
            throw ("Failed to parse RunUnitTests.ps1: {0}" -f $errors[0].Message)
        }

        $functionAst = $ast.Find(
            {
                param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Resolve-LUnitBackendMode'
            },
            $true
        )
        if (-not $functionAst) {
            throw "Function 'Resolve-LUnitBackendMode' not found in RunUnitTests.ps1"
        }
        $functionScriptBlock = [ScriptBlock]::Create($functionAst.Extent.Text)
        . $functionScriptBlock
    }

    BeforeEach {
        $script:previousBackend = $env:LVIE_LUNIT_BACKEND
        $script:previousForceGcli = $env:LVIE_FORCE_GCLI_LUNIT
        Remove-Item Env:LVIE_LUNIT_BACKEND -ErrorAction SilentlyContinue
        Remove-Item Env:LVIE_FORCE_GCLI_LUNIT -ErrorAction SilentlyContinue
    }

    AfterEach {
        if ($null -eq $script:previousBackend) {
            Remove-Item Env:LVIE_LUNIT_BACKEND -ErrorAction SilentlyContinue
        } else {
            $env:LVIE_LUNIT_BACKEND = $script:previousBackend
        }

        if ($null -eq $script:previousForceGcli) {
            Remove-Item Env:LVIE_FORCE_GCLI_LUNIT -ErrorAction SilentlyContinue
        } else {
            $env:LVIE_FORCE_GCLI_LUNIT = $script:previousForceGcli
        }
    }

    It 'defaults to labviewcli when no backend override is set' {
        $resolved = Resolve-LUnitBackendMode

        $resolved.Mode | Should -Be 'labviewcli'
        $resolved.Source | Should -Be 'default:labviewcli'
    }

    It 'uses LVIE_LUNIT_BACKEND when set to gcli' {
        $env:LVIE_LUNIT_BACKEND = 'gcli'

        $resolved = Resolve-LUnitBackendMode

        $resolved.Mode | Should -Be 'gcli'
        $resolved.Source | Should -Be '$env:LVIE_LUNIT_BACKEND'
    }

    It 'uses LVIE_FORCE_GCLI_LUNIT alias when explicit backend is not set' {
        $env:LVIE_FORCE_GCLI_LUNIT = '1'

        $resolved = Resolve-LUnitBackendMode

        $resolved.Mode | Should -Be 'gcli'
        $resolved.Source | Should -Be '$env:LVIE_FORCE_GCLI_LUNIT'
    }

    It 'lets explicit LVIE_LUNIT_BACKEND override LVIE_FORCE_GCLI_LUNIT alias' {
        $env:LVIE_LUNIT_BACKEND = 'labviewcli'
        $env:LVIE_FORCE_GCLI_LUNIT = '1'

        $resolved = Resolve-LUnitBackendMode

        $resolved.Mode | Should -Be 'labviewcli'
        $resolved.Source | Should -Be '$env:LVIE_LUNIT_BACKEND'
    }

    It 'warns and defaults to labviewcli when LVIE_LUNIT_BACKEND is invalid' {
        $env:LVIE_LUNIT_BACKEND = 'invalid'

        $captured = @(Resolve-LUnitBackendMode 3>&1)
        $warningRecords = @($captured | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
        $outputObjects = @($captured | Where-Object { $_ -isnot [System.Management.Automation.WarningRecord] })
        $resolved = $outputObjects[0]

        $warningRecords.Count | Should -BeGreaterThan 0
        $warningRecords[0].Message | Should -Match 'Ignoring invalid LVIE_LUNIT_BACKEND value'
        $outputObjects.Count | Should -Be 1
        $resolved.Mode | Should -Be 'labviewcli'
        $resolved.Source | Should -Be 'default:labviewcli'
    }
}
