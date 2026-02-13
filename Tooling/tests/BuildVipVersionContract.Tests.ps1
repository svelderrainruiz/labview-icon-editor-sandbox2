#Requires -Version 7.0
#Requires -Modules Pester

$ErrorActionPreference = 'Stop'

Describe 'Build VIP version contract' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..\..')).Path
        $script:invokeVipBuildPath = Join-Path $script:repoRoot 'Tooling\Invoke-VipBuild.ps1'
        $script:buildVipActionPath = Join-Path $script:repoRoot '.github\actions\build-vip\build_vip.ps1'

        if (-not (Test-Path -Path $script:invokeVipBuildPath -PathType Leaf)) {
            throw "Invoke-VipBuild.ps1 not found: $script:invokeVipBuildPath"
        }
        if (-not (Test-Path -Path $script:buildVipActionPath -PathType Leaf)) {
            throw "build_vip.ps1 not found: $script:buildVipActionPath"
        }

        $script:invokeVipBuildContent = Get-Content -Path $script:invokeVipBuildPath -Raw
        $script:buildVipActionContent = Get-Content -Path $script:buildVipActionPath -Raw
    }

    It 'composes year.minor before lvversion validation when minor is bound' {
        $script:invokeVipBuildContent | Should -Match '\$versionInput = \[string\]\$LabVIEWVersion'
        $script:invokeVipBuildContent | Should -Match '\$versionInput = "\{0\}\.\{1\}" -f \$LabVIEWVersion, \$LabVIEWMinorRevision'
        $script:invokeVipBuildContent | Should -Match 'Get-LabVIEWVersionInfo -VersionInput \$versionInput -RepoRoot \$resolvedRepoRoot'
        $script:invokeVipBuildContent | Should -Not -Match 'Get-LabVIEWVersionInfo -VersionInput \$LabVIEWVersion -RepoRoot \$resolvedRepoRoot'

        $script:buildVipActionContent | Should -Match '\$versionInput = \[string\]\$LabVIEWVersion'
        $script:buildVipActionContent | Should -Match '\$versionInput = "\{0\}\.\{1\}" -f \$LabVIEWVersion, \$LabVIEWMinorRevision'
        $script:buildVipActionContent | Should -Match 'Get-LabVIEWVersionInfo -VersionInput \$versionInput -RepoRoot \$ResolvedRepoRoot'
        $script:buildVipActionContent | Should -Not -Match 'Get-LabVIEWVersionInfo -VersionInput \$LabVIEWVersion -RepoRoot \$ResolvedRepoRoot'
    }

    It 'keeps hard-fail mismatch enforcement for minor revision drift' {
        $script:invokeVipBuildContent | Should -Match "throw ""LabVIEWMinorRevision '"
        $script:invokeVipBuildContent | Should -Match 'does not match \.lvversion minor'

        $script:buildVipActionContent | Should -Match "throw ""LabVIEWMinorRevision '"
        $script:buildVipActionContent | Should -Match 'does not match \.lvversion minor'
    }
}
