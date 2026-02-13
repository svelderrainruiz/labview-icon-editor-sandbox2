#Requires -Version 7.0
#Requires -Modules Pester

$ErrorActionPreference = 'Stop'

BeforeAll {
    $script:toolingRoot = Split-Path -Parent $PSScriptRoot
    $script:vipmHelperPath = Join-Path $script:toolingRoot 'support\VipmCli.ps1'
    if (-not (Test-Path -Path $script:vipmHelperPath -PathType Leaf)) {
        throw "VIPM helper not found at $script:vipmHelperPath"
    }

    . $script:vipmHelperPath
}

Describe 'VIPM list parser contract' {
    It 'parses package IDs and versions from VIPM list output' {
        $output = @(
            'Found 2 packages:'
            '  OpenG Array Library (oglib_array v6.0.1.20)'
            '  LUnit (astemes_lib_lunit v1.12.5.6)'
            'Listing installed packages'
            'Using LabVIEW 2026 (64-bit)'
        ) -join [Environment]::NewLine

        $parsed = @(ConvertFrom-VipmListPackage -OutputText $output)
        $parsed.Count | Should -Be 2
        ($parsed | Where-Object { $_.package_id -eq 'oglib_array' }).version | Should -Be '6.0.1.20'
        ($parsed | Where-Object { $_.package_id -eq 'astemes_lib_lunit' }).version | Should -Be '1.12.5.6'
    }
}

Describe 'VIPM expected-vs-installed comparison contract' {
    It 'fails when expected package is missing' {
        $expected = @(
            [pscustomobject]@{ display_name = 'Pkg A'; package_id = 'pkg_a'; version = '1.0.0' },
            [pscustomobject]@{ display_name = 'Pkg B'; package_id = 'pkg_b'; version = '2.0.0' }
        )
        $installed = @(
            [pscustomobject]@{ display_name = 'Pkg A'; package_id = 'pkg_a'; version = '1.0.0' }
        )

        $comparison = Compare-VipmPackageState -ExpectedPackages $expected -InstalledPackages $installed

        $comparison.has_blocking_mismatch | Should -BeTrue
        @($comparison.missing_expected).Count | Should -Be 1
        @($comparison.version_mismatches).Count | Should -Be 0
    }

    It 'fails when expected package version mismatches installed version' {
        $expected = @(
            [pscustomobject]@{ display_name = 'Pkg A'; package_id = 'pkg_a'; version = '1.0.0' }
        )
        $installed = @(
            [pscustomobject]@{ display_name = 'Pkg A'; package_id = 'pkg_a'; version = '1.2.0' }
        )

        $comparison = Compare-VipmPackageState -ExpectedPackages $expected -InstalledPackages $installed

        $comparison.has_blocking_mismatch | Should -BeTrue
        @($comparison.missing_expected).Count | Should -Be 0
        @($comparison.version_mismatches).Count | Should -Be 1
        $comparison.version_mismatches[0].expected_version | Should -Be '1.0.0'
        $comparison.version_mismatches[0].installed_version | Should -Be '1.2.0'
    }

    It 'does not fail for unexpected installed packages only' {
        $expected = @(
            [pscustomobject]@{ display_name = 'Pkg A'; package_id = 'pkg_a'; version = '1.0.0' }
        )
        $installed = @(
            [pscustomobject]@{ display_name = 'Pkg A'; package_id = 'pkg_a'; version = '1.0.0' },
            [pscustomobject]@{ display_name = 'Pkg Z'; package_id = 'pkg_z'; version = '9.9.9' }
        )

        $comparison = Compare-VipmPackageState -ExpectedPackages $expected -InstalledPackages $installed

        $comparison.has_blocking_mismatch | Should -BeFalse
        @($comparison.missing_expected).Count | Should -Be 0
        @($comparison.version_mismatches).Count | Should -Be 0
        @($comparison.unexpected_installed).Count | Should -Be 1
        $comparison.unexpected_installed[0].package_id | Should -Be 'pkg_z'
    }
}
