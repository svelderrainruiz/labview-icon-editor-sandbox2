$ErrorActionPreference = 'Stop'

Describe 'RunUnitTests operation-directory resolution' {
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

        $requiredFunctions = @(
            'Test-LUnitOperationFolder',
            'Resolve-LUnitOperationRootFromPath',
            'Get-LUnitOperationRootsFromVipmIndex',
            'Resolve-LUnitOperationDirectory'
        )

        foreach ($functionName in $requiredFunctions) {
            $functionAst = $ast.Find(
                {
                    param($node)
                    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $functionName
                },
                $true
            )
            if (-not $functionAst) {
                throw "Function '$functionName' not found in RunUnitTests.ps1"
            }
            $functionScriptBlock = [ScriptBlock]::Create($functionAst.Extent.Text)
            . $functionScriptBlock
        }
    }

    BeforeEach {
        $script:prevSpecific = $env:LVIE_LUNIT_OPERATION_DIR_64
        $script:prevGeneric = $env:LVIE_LUNIT_OPERATION_DIR
        $script:prevProgramData = $env:ProgramData

        Remove-Item Env:LVIE_LUNIT_OPERATION_DIR_64 -ErrorAction SilentlyContinue
        Remove-Item Env:LVIE_LUNIT_OPERATION_DIR -ErrorAction SilentlyContinue

        $script:testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("lvie-op-root-" + [Guid]::NewGuid().ToString('N'))
        New-Item -Path $script:testRoot -ItemType Directory -Force | Out-Null

        $script:labviewCliPath = Join-Path $script:testRoot 'LabVIEWCLI.exe'
        New-Item -Path $script:labviewCliPath -ItemType File -Force | Out-Null
        $script:defaultOperationsRoot = Join-Path $script:testRoot 'Operations'

        $script:programDataRoot = Join-Path $script:testRoot 'ProgramData'
        New-Item -Path $script:programDataRoot -ItemType Directory -Force | Out-Null
        $env:ProgramData = $script:programDataRoot
    }

    AfterEach {
        if ($null -eq $script:prevSpecific) {
            Remove-Item Env:LVIE_LUNIT_OPERATION_DIR_64 -ErrorAction SilentlyContinue
        } else {
            $env:LVIE_LUNIT_OPERATION_DIR_64 = $script:prevSpecific
        }

        if ($null -eq $script:prevGeneric) {
            Remove-Item Env:LVIE_LUNIT_OPERATION_DIR -ErrorAction SilentlyContinue
        } else {
            $env:LVIE_LUNIT_OPERATION_DIR = $script:prevGeneric
        }

        if ($null -eq $script:prevProgramData) {
            Remove-Item Env:ProgramData -ErrorAction SilentlyContinue
        } else {
            $env:ProgramData = $script:prevProgramData
        }

        if (Test-Path -Path $script:testRoot) {
            Remove-Item -Path $script:testRoot -Recurse -Force
        }
    }

    It 'prefers bitness-specific operation-directory override' {
        $specificRoot = Join-Path $script:testRoot 'specific-ops'
        New-Item -Path (Join-Path $specificRoot 'LUnit') -ItemType Directory -Force | Out-Null
        New-Item -Path (Join-Path $specificRoot 'LUnit\RunOperation.vi') -ItemType File -Force | Out-Null
        $specificRoot = (Resolve-Path -Path $specificRoot).Path

        $genericRoot = Join-Path $script:testRoot 'generic-ops'
        New-Item -Path (Join-Path $genericRoot 'LUnit') -ItemType Directory -Force | Out-Null
        New-Item -Path (Join-Path $genericRoot 'LUnit\RunOperation.vi') -ItemType File -Force | Out-Null
        $genericRoot = (Resolve-Path -Path $genericRoot).Path
        $env:LVIE_LUNIT_OPERATION_DIR_64 = $specificRoot
        $env:LVIE_LUNIT_OPERATION_DIR = $genericRoot

        $resolved = Resolve-LUnitOperationDirectory -Bitness '64' -LabVIEWCliPath $script:labviewCliPath -LabVIEWNumericVersion '21.0'

        $resolved.Found | Should -BeTrue
        $resolved.OperationRoot | Should -Be $specificRoot
        $resolved.Source | Should -Match '\$env:LVIE_LUNIT_OPERATION_DIR_64'
    }

    It 'uses generic operation-directory override when bitness override is absent' {
        $genericRoot = Join-Path $script:testRoot 'generic-ops'
        New-Item -Path (Join-Path $genericRoot 'LUnit') -ItemType Directory -Force | Out-Null
        New-Item -Path (Join-Path $genericRoot 'LUnit\RunOperation.vi') -ItemType File -Force | Out-Null
        $genericRoot = (Resolve-Path -Path $genericRoot).Path
        $env:LVIE_LUNIT_OPERATION_DIR = $genericRoot

        $resolved = Resolve-LUnitOperationDirectory -Bitness '64' -LabVIEWCliPath $script:labviewCliPath -LabVIEWNumericVersion '21.0'

        $resolved.Found | Should -BeTrue
        $resolved.OperationRoot | Should -Be $genericRoot
        $resolved.Source | Should -Be '$env:LVIE_LUNIT_OPERATION_DIR'
    }

    It 'uses default LabVIEW CLI Operations root when LUnit operation exists there' {
        $defaultRoot = $script:defaultOperationsRoot
        New-Item -Path (Join-Path $defaultRoot 'LUnit') -ItemType Directory -Force | Out-Null
        New-Item -Path (Join-Path $defaultRoot 'LUnit\RunOperation.vi') -ItemType File -Force | Out-Null
        $defaultRoot = (Resolve-Path -Path $defaultRoot).Path

        $resolved = Resolve-LUnitOperationDirectory -Bitness '64' -LabVIEWCliPath $script:labviewCliPath -LabVIEWNumericVersion '21.0'

        $resolved.Found | Should -BeTrue
        $resolved.OperationRoot | Should -Be $defaultRoot
        $resolved.RequiresAdditionalOperationDirectory | Should -BeFalse
        $resolved.Source | Should -Be 'default LabVIEW CLI Operations directory'
    }

    It 'falls back to VIPM files-installed candidates when default root is missing' {
        $vipmOpsRoot = Join-Path $script:testRoot 'vipm-ops'
        New-Item -Path (Join-Path $vipmOpsRoot 'LUnit') -ItemType Directory -Force | Out-Null
        New-Item -Path (Join-Path $vipmOpsRoot 'LUnit\RunOperation.vi') -ItemType File -Force | Out-Null
        $vipmOpsRoot = (Resolve-Path -Path $vipmOpsRoot).Path
        $installedPath = Join-Path (Join-Path $vipmOpsRoot 'LUnit') 'RunOperation.vi'

        $indexDir = Join-Path $script:programDataRoot 'JKI\VIPM\databases\LV 21.0 (64-bit)\astemes_lib_lunit_cli'
        New-Item -Path $indexDir -ItemType Directory -Force | Out-Null
        Set-Content -Path (Join-Path $indexDir 'files-installed') -Value $installedPath -Encoding ascii

        $resolved = Resolve-LUnitOperationDirectory -Bitness '64' -LabVIEWCliPath $script:labviewCliPath -LabVIEWNumericVersion '21.0'

        $resolved.Found | Should -BeTrue
        $resolved.OperationRoot | Should -Be $vipmOpsRoot
        $resolved.RequiresAdditionalOperationDirectory | Should -BeTrue
        $resolved.Source | Should -Match 'VIPM files-installed'
    }

    It 'returns unresolved when no operation directory can be discovered' {
        $resolved = Resolve-LUnitOperationDirectory -Bitness '64' -LabVIEWCliPath $script:labviewCliPath -LabVIEWNumericVersion '21.0'

        $resolved.Found | Should -BeFalse
        $resolved.OperationRoot | Should -BeNullOrEmpty
        @($resolved.SourceTrail).Count | Should -BeGreaterThan 0
    }
}
