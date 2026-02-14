#Requires -Version 7.0
#Requires -Modules Pester

$ErrorActionPreference = 'Stop'

BeforeAll {
    $script:toolingRoot = Split-Path -Parent $PSScriptRoot
    $script:supportScript = Join-Path $script:toolingRoot 'support/CodexSkillLayer.ps1'
    $script:fixtureLayerRoot = Join-Path $script:toolingRoot 'tests/fixtures/codex-skill-layer'
    . $script:supportScript

    $script:repoRoot = Split-Path -Parent $script:toolingRoot
    $script:lockInfo = Get-CodexSkillLayerLock -RepoRoot $script:repoRoot
    $script:expectedTag = [string]$script:lockInfo.Lock.tag
    $script:requiredFiles = @($script:lockInfo.Lock.required_files | ForEach-Object { [string]$_ })
    $script:newFixtureVersion = {
        param(
            [Parameter(Mandatory = $true)]
            [string]$VersionRoot,

            [Parameter(Mandatory = $true)]
            [string[]]$RequiredFiles,

            [Parameter(Mandatory = $false)]
            [string]$LicenseSpdx = '0BSD'
        )

        foreach ($relative in $RequiredFiles) {
            $target = Join-Path $VersionRoot ([string]$relative)
            $targetDir = Split-Path -Parent $target
            if (-not [string]::IsNullOrWhiteSpace($targetDir)) {
                New-Item -Path $targetDir -ItemType Directory -Force | Out-Null
            }

            switch -Wildcard ($relative) {
                'manifest.json' { continue }
                'ci-debt/signatures.json' { Set-Content -Path $target -Value '{"signatures":[]}' -Encoding utf8; continue }
                '*.json' { Set-Content -Path $target -Value '{}' -Encoding utf8; continue }
                '*.xml' { Set-Content -Path $target -Value '<root />' -Encoding utf8; continue }
                '*.ps1' { Set-Content -Path $target -Value '# fixture' -Encoding utf8; continue }
                '*.md' { Set-Content -Path $target -Value '# fixture' -Encoding utf8; continue }
                default { Set-Content -Path $target -Value 'fixture' -Encoding utf8 }
            }
        }

        $manifestPath = Join-Path $VersionRoot 'manifest.json'
        $manifest = @{
            name = 'lvie-codex-skill-layer'
            version = 'fixture'
            license_spdx = $LicenseSpdx
            required_files = $RequiredFiles
        } | ConvertTo-Json -Depth 5 -Compress
        Set-Content -Path $manifestPath -Value $manifest -Encoding utf8
    }
}

Describe 'Codex skill layer helpers' {
    It 'fails when layer root is missing' {
        $state = Get-CodexSkillLayerState -RepoRoot $script:repoRoot -LayerRoot (Join-Path $TestDrive 'missing-layer-root')
        { Test-CodexSkillLayerVersionRoot -State $state } | Should -Throw '*not installed*'
    }

    It 'fails when manifest license_spdx is missing or wrong' {
        $layerRoot = Join-Path $TestDrive 'layer'
        $versionRoot = Join-Path $layerRoot $script:expectedTag
        & $script:newFixtureVersion -VersionRoot $versionRoot -RequiredFiles $script:requiredFiles -LicenseSpdx 'MIT'

        $state = Get-CodexSkillLayerState -RepoRoot $script:repoRoot -LayerRoot $layerRoot
        { Test-CodexSkillLayerVersionRoot -State $state } | Should -Throw '*license mismatch*'
    }

    It 'succeeds when fixture layer contains required files and 0BSD manifest' {
        $state = Get-CodexSkillLayerState -RepoRoot $script:repoRoot -LayerRoot $script:fixtureLayerRoot
        { Test-CodexSkillLayerVersionRoot -State $state } | Should -Not -Throw
    }

    It 'fails install when downloaded asset hash does not match lock' {
        $assetSourceRoot = Join-Path $TestDrive 'asset-src'
        $assetVersionRoot = Join-Path $assetSourceRoot $script:expectedTag
        & $script:newFixtureVersion -VersionRoot $assetVersionRoot -RequiredFiles $script:requiredFiles -LicenseSpdx '0BSD'

        $assetExe = Join-Path $TestDrive 'lvie-codex-skill-layer-installer.exe'
        Set-Content -Path $assetExe -Value 'fixture-installer' -Encoding utf8

        $state = [pscustomobject]@{
            RepoRoot = $script:repoRoot
            LockPath = Join-Path $script:repoRoot 'Tooling/codex-skill-layer.lock.json'
            Lock = [pscustomobject]@{
                repo = 'example/repo'
                tag = $script:expectedTag
                asset_name = 'lvie-codex-skill-layer-installer.exe'
                asset_sha256 = 'deadbeef'
                install_args = @('/S')
                install_root_template = '{layer_root}\{tag}'
                license_spdx = '0BSD'
                required_files = $script:requiredFiles
            }
            LayerRoot = Join-Path $TestDrive 'installed'
            VersionRoot = Join-Path (Join-Path $TestDrive 'installed') $script:expectedTag
        }

        function global:gh {
            param([Parameter(ValueFromRemainingArguments = $true)] [string[]]$Args)
            if ($Args[0] -eq 'release' -and $Args[1] -eq 'download') {
                $dirIndex = [Array]::IndexOf($Args, '--dir')
                $patternIndex = [Array]::IndexOf($Args, '--pattern')
                if ($dirIndex -lt 0 -or $patternIndex -lt 0) {
                    throw 'Missing --dir or --pattern in gh stub.'
                }
                $destDir = $Args[$dirIndex + 1]
                $pattern = $Args[$patternIndex + 1]
                New-Item -Path $destDir -ItemType Directory -Force | Out-Null
                Copy-Item -Path $assetExe -Destination (Join-Path $destDir $pattern) -Force
                $global:LASTEXITCODE = 0
                return
            }

            throw ("Unexpected gh command in test stub: {0}" -f ($Args -join ' '))
        }

        try {
            { Install-CodexSkillLayerInternal -State $state -Force } | Should -Throw '*SHA256 mismatch*'
        } finally {
            Remove-Item Function:\global:gh -ErrorAction SilentlyContinue
        }
    }
}
