#Requires -Version 7.0
#Requires -Modules Pester

$ErrorActionPreference = 'Stop'

Describe 'BuildProjectSpec container parity contract' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..\..')).Path
        $script:hostBuildPath = Join-Path $script:repoRoot '.github\actions\build-lvlibp\BuildProjectSpec.ps1'
        $script:windowsParityPath = Join-Path $script:repoRoot 'Tooling\container-parity\runlabview-windows.ps1'
        $script:linuxParityPath = Join-Path $script:repoRoot 'Tooling\container-parity\runlabview-linux.sh'

        foreach ($path in @($script:hostBuildPath, $script:windowsParityPath, $script:linuxParityPath)) {
            if (-not (Test-Path -Path $path -PathType Leaf)) {
                throw "Required file not found: $path"
            }
        }

        $script:hostBuildContent = Get-Content -Path $script:hostBuildPath -Raw
        $script:windowsParityContent = Get-Content -Path $script:windowsParityPath -Raw
        $script:linuxParityContent = Get-Content -Path $script:linuxParityPath -Raw
    }

    It 'keeps container-aligned defaults for target directory, exclusion list, and build output path' {
        $script:hostBuildContent | Should -Match 'Test\\Templates'
        $script:windowsParityContent | Should -Match 'Test\\Templates'
        $script:linuxParityContent | Should -Match 'Test/Templates'

        $script:hostBuildContent | Should -Match 'Polymorphic Template\.vi'
        $script:windowsParityContent | Should -Match 'Polymorphic Template\.vi'
        $script:linuxParityContent | Should -Match 'Polymorphic Template\.vi'

        $script:hostBuildContent | Should -Match 'resource[\\/]+plugins[\\/]+lv_icon\.lvlibp'
        $script:windowsParityContent | Should -Match 'resource[\\/]+plugins[\\/]+lv_icon\.lvlibp'
        $script:linuxParityContent | Should -Match 'resource[\\/]+plugins[\\/]+lv_icon\.lvlibp'
    }

    It 'runs MassCompile before ExecuteBuildSpec across host and container scripts' {
        $hostLower = $script:hostBuildContent.ToLowerInvariant()
        $windowsLower = $script:windowsParityContent.ToLowerInvariant()
        $linuxLower = $script:linuxParityContent.ToLowerInvariant()

        $hostMassIndex = $hostLower.IndexOf("operationname', 'masscompile")
        $hostExecuteIndex = $hostLower.IndexOf("operationname', 'executebuildspec")
        $windowsMassIndex = $windowsLower.IndexOf("operationname', 'masscompile")
        $windowsExecuteIndex = $windowsLower.IndexOf("operationname', 'executebuildspec")
        $linuxMassIndex = $linuxLower.IndexOf('invoke_labviewcli "masscompile"')
        $linuxExecuteIndex = $linuxLower.IndexOf('invoke_labviewcli "executebuildspec"')

        $hostMassIndex | Should -BeGreaterThan -1
        $hostExecuteIndex | Should -BeGreaterThan -1
        $hostMassIndex | Should -BeLessThan $hostExecuteIndex

        $windowsMassIndex | Should -BeGreaterThan -1
        $windowsExecuteIndex | Should -BeGreaterThan -1
        $windowsMassIndex | Should -BeLessThan $windowsExecuteIndex

        $linuxMassIndex | Should -BeGreaterThan -1
        $linuxExecuteIndex | Should -BeGreaterThan -1
        $linuxMassIndex | Should -BeLessThan $linuxExecuteIndex
    }

    It 'synchronizes Icon Editor sources before ExecuteBuildSpec in each script' {
        $hostLower = $script:hostBuildContent.ToLowerInvariant()
        $windowsLower = $script:windowsParityContent.ToLowerInvariant()
        $linuxLower = $script:linuxParityContent.ToLowerInvariant()

        $hostSyncIndex = $hostLower.IndexOf('sync-iconeditorsourcesforbuildspec')
        $hostExecuteIndex = $hostLower.IndexOf("operationname', 'executebuildspec")
        $windowsSyncIndex = $windowsLower.IndexOf('sync-iconeditorsourcesforbuildspec')
        $windowsExecuteIndex = $windowsLower.IndexOf("operationname', 'executebuildspec")
        $linuxSyncIndex = $linuxLower.IndexOf('sync_icon_editor_sources_for_build_spec')
        $linuxExecuteIndex = $linuxLower.IndexOf('invoke_labviewcli "executebuildspec"')

        $hostSyncIndex | Should -BeGreaterThan -1
        $hostExecuteIndex | Should -BeGreaterThan -1
        $hostSyncIndex | Should -BeLessThan $hostExecuteIndex

        $windowsSyncIndex | Should -BeGreaterThan -1
        $windowsExecuteIndex | Should -BeGreaterThan -1
        $windowsSyncIndex | Should -BeLessThan $windowsExecuteIndex

        $linuxSyncIndex | Should -BeGreaterThan -1
        $linuxExecuteIndex | Should -BeGreaterThan -1
        $linuxSyncIndex | Should -BeLessThan $linuxExecuteIndex
    }

    It 'resolves and passes LabVIEWCLI PortNumber for Windows parity operations' {
        $script:windowsParityContent | Should -Match 'function\s+Resolve-LabVIEWCliPort'
        $script:windowsParityContent | Should -Match 'Using LabVIEWCLI port: \{0\} \(source: \{1\}\)'

        $portMatchCount = [regex]::Matches($script:windowsParityContent, "'-PortNumber'")
        $portMatchCount.Count | Should -BeGreaterThan 1
    }

    It 'keeps LabVIEW prelaunch enabled for self-hosted and disabled for container workspace by default' {
        $script:windowsParityContent | Should -Match 'function\s+Should-PrelaunchLabVIEWForCli'
        $script:windowsParityContent | Should -Match 'C:\\workspace'
        $script:windowsParityContent | Should -Match 'LVIE_PRELAUNCH_LABVIEW_FOR_CLI'
        $script:windowsParityContent | Should -Match 'Skipping LabVIEW prelaunch for CLI operations in container workspace mode\.'
    }
}
