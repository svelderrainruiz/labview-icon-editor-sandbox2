$ErrorActionPreference = 'Stop'

Describe 'Dev mode (no LabVIEW) scripts' {
    BeforeAll {
        $script:repoRoot = Resolve-Path -Path (Join-Path $PSScriptRoot '..\..')
        $script:enableScript = Join-Path $script:repoRoot 'Tooling\Set-DevelopmentMode-NoLabVIEW.ps1'
        $script:revertScript = Join-Path $script:repoRoot 'Tooling\Revert-DevelopmentMode-NoLabVIEW.ps1'

        if (-not (Test-Path -Path $script:enableScript)) {
            throw "Enable script not found at $script:enableScript"
        }
        if (-not (Test-Path -Path $script:revertScript)) {
            throw "Revert script not found at $script:revertScript"
        }

        . $script:enableScript
        . $script:revertScript
    }

    function script:New-TestInstall {
        param(
            [string]$Root
        )

        $installRoot = Join-Path $Root 'LabVIEW 2021'
        $iconApiDir = Join-Path $installRoot 'vi.lib\LabVIEW Icon API'
        $pluginsDir = Join-Path $installRoot 'resource\plugins'

        New-Item -ItemType Directory -Path $iconApiDir -Force | Out-Null
        Set-Content -Path (Join-Path $iconApiDir 'dummy.txt') -Value 'data' -Encoding ascii
        New-Item -ItemType Directory -Path $pluginsDir -Force | Out-Null
        Set-Content -Path (Join-Path $pluginsDir 'lv_icon.lvlibp') -Value 'bin' -Encoding ascii

        return $installRoot
    }

    It 'enables and reverts dev mode without LabVIEW' {
        $root = Join-Path $env:TEMP ("lvie-devmode-" + [guid]::NewGuid().ToString('N'))
        $repoRoot = Join-Path $root 'repo'
        New-Item -ItemType Directory -Path $repoRoot -Force | Out-Null
        $installRoot = New-TestInstall -Root $root
        $iniPath = Join-Path $installRoot 'LabVIEW.ini'
        Set-Content -Path $iniPath -Value "Other=1`nLocalhost.LibraryPaths=C:\keep" -Encoding ascii

        Mock -CommandName Get-LabVIEWInstallRoot -MockWith { return $installRoot }

        try {
            Enable-DevModeNoLabVIEW -Bitness '64' -RepoRoot $repoRoot -LabVIEWYear '2021'

            (Test-Path -Path (Join-Path $installRoot 'vi.lib\LabVIEW Icon API')) | Should -Be $false
            (Test-Path -Path (Join-Path $installRoot 'vi.lib\LabVIEW Icon API.zip')) | Should -Be $true
            (Test-Path -Path (Join-Path $installRoot 'resource\plugins\lv_icon.ship')) | Should -Be $true
            (Test-Path -Path (Join-Path $installRoot 'resource\plugins\lv_icon.lvlibp')) | Should -Be $false
            $lineAfterEnable = Get-Content -Path $iniPath | Where-Object { $_ -match '(?i)^\s*localhost\.librarypaths\s*=' } | Select-Object -First 1
            $lineAfterEnable | Should -Match ([regex]::Escape($repoRoot))
            $lineAfterEnable | Should -Not -Match ([regex]::Escape('C:\keep'))
            ($lineAfterEnable.Split(';').Count) | Should -Be 1

            Disable-DevModeNoLabVIEW -Bitness '64' -RepoRoot $repoRoot -LabVIEWYear '2021'

            (Test-Path -Path (Join-Path $installRoot 'vi.lib\LabVIEW Icon API')) | Should -Be $true
            (Test-Path -Path (Join-Path $installRoot 'vi.lib\LabVIEW Icon API.zip')) | Should -Be $false
            (Test-Path -Path (Join-Path $installRoot 'resource\plugins\lv_icon.lvlibp')) | Should -Be $true
            (Test-Path -Path (Join-Path $installRoot 'resource\plugins\lv_icon.ship')) | Should -Be $false
            $lineAfterRevert = Get-Content -Path $iniPath | Where-Object { $_ -match '(?i)^\s*localhost\.librarypaths\s*=' } | Select-Object -First 1
            $lineAfterRevert | Should -BeNullOrEmpty
        }
        finally {
            Remove-Item -Path $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'sanitizes corrupted and multi-value Localhost.LibraryPaths tokens to repo-only strict mode' {
        $root = Join-Path $env:TEMP ("lvie-devmode-ini-" + [guid]::NewGuid().ToString('N'))
        $repoRoot = Join-Path $root 'repo'
        New-Item -ItemType Directory -Path $repoRoot -Force | Out-Null
        $installRoot = New-TestInstall -Root $root
        $iniPath = Join-Path $installRoot 'LabVIEW.ini'
        Set-Content -Path $iniPath -Value ("Other=1`nLocalhost.LibraryPaths=C:\keep;C:\actions-runner\_work\lvie\w\ci-305B2CFF-32;C:\ ;{0};{0}" -f $repoRoot) -Encoding ascii

        Mock -CommandName Get-LabVIEWInstallRoot -MockWith { return $installRoot }

        try {
            Set-IniLibraryPath -IniPath $iniPath -RepoRoot $repoRoot
            $lineAfterSet = Get-Content -Path $iniPath | Where-Object { $_ -match '(?i)^\s*localhost\.librarypaths\s*=' } | Select-Object -First 1
            $lineAfterSet | Should -Match ([regex]::Escape($repoRoot))
            $lineAfterSet | Should -Not -Match ([regex]::Escape('C:\keep'))
            $lineAfterSet | Should -Not -Match '(?i)(^|;)\s*[A-Za-z]:\\\s*(;|$)'
            ($lineAfterSet.Split(';').Count) | Should -Be 1

            Remove-IniLibraryPath -IniPath $iniPath
            $lineAfterRevert = Get-Content -Path $iniPath | Where-Object { $_ -match '(?i)^\s*localhost\.librarypaths\s*=' } | Select-Object -First 1
            $lineAfterRevert | Should -BeNullOrEmpty
        }
        finally {
            Remove-Item -Path $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'normalizes duplicate and case-insensitive Localhost.LibraryPaths keys to one path on enable and zero on revert' {
        $root = Join-Path $env:TEMP ("lvie-devmode-dup-" + [guid]::NewGuid().ToString('N'))
        $repoRoot = Join-Path $root 'repo'
        New-Item -ItemType Directory -Path $repoRoot -Force | Out-Null
        $installRoot = New-TestInstall -Root $root
        $iniPath = Join-Path $installRoot 'LabVIEW.ini'
        $iniBody = @(
            'Other=1'
            'Localhost.LibraryPaths=C:\first'
            'LOCALHOST.LIBRARYPATHS=C:\second;C:\'
            'localhost.librarypaths='
        ) -join "`n"
        Set-Content -Path $iniPath -Value $iniBody -Encoding ascii

        Mock -CommandName Get-LabVIEWInstallRoot -MockWith { return $installRoot }

        try {
            Set-IniLibraryPath -IniPath $iniPath -RepoRoot $repoRoot
            $keyLinesAfterSet = @(Get-Content -Path $iniPath | Where-Object { $_ -match '(?i)^\s*localhost\.librarypaths\s*=' })
            $keyLinesAfterSet.Count | Should -Be 1
            $keyLinesAfterSet[0] | Should -Match ([regex]::Escape($repoRoot))
            ($keyLinesAfterSet[0].Split(';').Count) | Should -Be 1

            Remove-IniLibraryPath -IniPath $iniPath
            $keyLinesAfterRevert = @(Get-Content -Path $iniPath | Where-Object { $_ -match '(?i)^\s*localhost\.librarypaths\s*=' })
            $keyLinesAfterRevert.Count | Should -Be 0
        }
        finally {
            Remove-Item -Path $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
