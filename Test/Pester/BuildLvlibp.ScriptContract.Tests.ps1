#Requires -Version 7.0
#Requires -Modules Pester

$ErrorActionPreference = 'Stop'

Describe 'Build_lvlibp compatibility shim contract' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..\..')).Path
        $script:buildScript = Join-Path $script:repoRoot '.github\actions\build-lvlibp\Build_lvlibp.ps1'
        if (-not (Test-Path -Path $script:buildScript -PathType Leaf)) {
            throw "Build_lvlibp.ps1 not found at $script:buildScript"
        }

        $script:pwshExe = (Get-Command pwsh -ErrorAction Stop).Source
    }

    function script:New-BuildLvlibpFixtureRepo {
        $fixtureRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -Path (Join-Path $fixtureRoot 'Tooling\support') -ItemType Directory -Force | Out-Null
        New-Item -Path (Join-Path $fixtureRoot 'resource\plugins') -ItemType Directory -Force | Out-Null
        New-Item -Path (Join-Path $fixtureRoot 'resource\plugins\NIIconEditor\Miscellaneous') -ItemType Directory -Force | Out-Null
        New-Item -Path (Join-Path $fixtureRoot 'vi.lib\LabVIEW Icon API') -ItemType Directory -Force | Out-Null
        New-Item -Path (Join-Path $fixtureRoot 'Test\Templates') -ItemType Directory -Force | Out-Null
        New-Item -Path (Join-Path $fixtureRoot 'FakeLabVIEW') -ItemType Directory -Force | Out-Null

        @'
function Resolve-LabVIEWExecutablePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$VersionYear,
        [Parameter(Mandatory = $true)]
        [ValidateSet('32','64')]
        [string]$Bitness
    )

    $repoRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    return (Join-Path -Path $repoRoot -ChildPath 'FakeLabVIEW\LabVIEW.exe')
}
'@ | Set-Content -Path (Join-Path $fixtureRoot 'Tooling\support\LabVIEWExecutablePath.ps1') -Encoding ascii

        'fake-template' | Set-Content -Path (Join-Path $fixtureRoot 'Test\Templates\template.vi') -Encoding ascii
        'fake-excluded-template' | Set-Content -Path (Join-Path $fixtureRoot 'Test\Templates\Polymorphic Template.vi') -Encoding ascii
        'fake-classes-init' | Set-Content -Path (Join-Path $fixtureRoot 'resource\plugins\NIIconEditor\Miscellaneous\Classes Initialization.vi') -Encoding ascii
        'fake-icon-lib' | Set-Content -Path (Join-Path $fixtureRoot 'resource\plugins\lv_IconEditor.lvlib') -Encoding ascii
        'fake-icon-vi' | Set-Content -Path (Join-Path $fixtureRoot 'resource\plugins\lv_icon.vi') -Encoding ascii
        'fake-icon-vit' | Set-Content -Path (Join-Path $fixtureRoot 'resource\plugins\lv_icon.vit') -Encoding ascii
        'fake-sample-icon-vi' | Set-Content -Path (Join-Path $fixtureRoot 'resource\plugins\SAMPLE_lv_icon.vi') -Encoding ascii
        'fake-icon-api' | Set-Content -Path (Join-Path $fixtureRoot 'vi.lib\LabVIEW Icon API\Icon API.vi') -Encoding ascii

        @'
<?xml version="1.0" encoding="UTF-8"?>
<Project Type="Project" LVVersion="21008000">
  <Item Name="My Computer" Type="My Computer">
    <Item Name="Build Specifications" Type="Build">
      <Item Name="Editor Packed Library" Type="Packed Library">
        <Property Name="Bld_version.major" Type="Int">0</Property>
        <Property Name="Bld_version.minor" Type="Int">0</Property>
        <Property Name="Bld_version.patch" Type="Int">0</Property>
        <Property Name="Bld_version.build" Type="Int">0</Property>
      </Item>
    </Item>
  </Item>
</Project>
'@ | Set-Content -Path (Join-Path $fixtureRoot 'lv_icon_editor.lvproj') -Encoding ascii

        return $fixtureRoot
    }

    function script:Invoke-BuildLvlibp {
        param(
            [Parameter(Mandatory = $true)]
            [string]$RepoRoot,

            [Parameter(Mandatory = $false)]
            [string]$PathValue,

            [Parameter(Mandatory = $false)]
            [hashtable]$Environment = @{},

            [Parameter(Mandatory = $false)]
            [int]$Major = 1,

            [Parameter(Mandatory = $false)]
            [int]$Minor = 2,

            [Parameter(Mandatory = $false)]
            [int]$Patch = 3,

            [Parameter(Mandatory = $false)]
            [int]$Build = 4
        )

        $savedPath = $env:PATH
        $savedEnv = @{}
        foreach ($key in $Environment.Keys) {
            $savedEnv[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
            [Environment]::SetEnvironmentVariable($key, [string]$Environment[$key], 'Process')
        }

        if ($null -ne $PathValue) {
            $env:PATH = $PathValue
        }

        try {
            $output = & $script:pwshExe -NoProfile -File $script:buildScript `
                -LabVIEWVersion 2021 `
                -SupportedBitness 64 `
                -RepoRoot $RepoRoot `
                -Major $Major `
                -Minor $Minor `
                -Patch $Patch `
                -Build $Build `
                -Commit 'deadbeef' 2>&1

            $exitCode = if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }
            return [pscustomobject]@{
                ExitCode = $exitCode
                Output   = @($output | ForEach-Object { [string]$_ })
            }
        }
        finally {
            $env:PATH = $savedPath
            foreach ($key in $Environment.Keys) {
                [Environment]::SetEnvironmentVariable($key, $savedEnv[$key], 'Process')
            }
        }
    }

    It 'fails fast when LabVIEWCLI is missing from PATH' {
        $fixtureRoot = New-BuildLvlibpFixtureRepo
        $emptyToolPath = Join-Path $fixtureRoot 'no-cli'
        New-Item -Path $emptyToolPath -ItemType Directory -Force | Out-Null

        $result = Invoke-BuildLvlibp -RepoRoot $fixtureRoot -PathValue $emptyToolPath

        $result.ExitCode | Should -Not -Be 0
        ($result.Output -join "`n") | Should -Match 'Build_lvlibp\.ps1 is deprecated'
        ($result.Output -join "`n") | Should -Match 'LabVIEWCLI is not available on PATH'
    }

    It 'invokes MassCompile then ExecuteBuildSpec, stamps version values, and restores lvproj on failure' {
        $fixtureRoot = New-BuildLvlibpFixtureRepo
        $toolPath = Join-Path $fixtureRoot 'toolbin'
        New-Item -Path $toolPath -ItemType Directory -Force | Out-Null

        $argsCapturePath = Join-Path $fixtureRoot 'labviewcli-args.txt'
        $snapshotPath = Join-Path $fixtureRoot 'project-snapshot.lvproj'
        $projectPath = Join-Path $fixtureRoot 'lv_icon_editor.lvproj'
        $originalProject = Get-Content -Path $projectPath -Raw

        @'
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$CliArgs
)

if (-not [string]::IsNullOrWhiteSpace($env:LVIE_TEST_ARGS_PATH)) {
    ($CliArgs -join ' ') | Add-Content -Path $env:LVIE_TEST_ARGS_PATH -Encoding ascii
}

$projectPath = $null
for ($index = 0; $index -lt $CliArgs.Count - 1; $index++) {
    if ($CliArgs[$index] -eq '-ProjectPath') {
        $projectPath = $CliArgs[$index + 1]
        break
    }
}

if (-not [string]::IsNullOrWhiteSpace($projectPath) -and -not [string]::IsNullOrWhiteSpace($env:LVIE_TEST_PROJECT_SNAPSHOT)) {
    Copy-Item -Path $projectPath -Destination $env:LVIE_TEST_PROJECT_SNAPSHOT -Force
}

if ($env:LVIE_TEST_CREATE_TEMP_LOG -eq '1') {
    $tempLogPath = Join-Path $env:TEMP ("lvtemporary_{0}.log" -f [guid]::NewGuid().ToString('N'))
    'fake labviewcli log' | Set-Content -Path $tempLogPath -Encoding ascii
}

exit 0
'@ | Set-Content -Path (Join-Path $toolPath 'LabVIEWCLI.ps1') -Encoding ascii

        $pathValue = "{0};{1}" -f $toolPath, $env:PATH
        $envOverrides = @{
            LVIE_TEST_ARGS_PATH        = $argsCapturePath
            LVIE_TEST_PROJECT_SNAPSHOT = $snapshotPath
            LVIE_TEST_CREATE_TEMP_LOG  = '1'
        }

        $result = Invoke-BuildLvlibp `
            -RepoRoot $fixtureRoot `
            -PathValue $pathValue `
            -Environment $envOverrides `
            -Major 11 `
            -Minor 22 `
            -Patch 33 `
            -Build 44

        $result.ExitCode | Should -Not -Be 0
        ($result.Output -join "`n") | Should -Match 'Build specification output not found at expected path'

        (Test-Path -Path $argsCapturePath -PathType Leaf) | Should -BeTrue
        $capturedArgLines = Get-Content -Path $argsCapturePath
        $capturedArgs = $capturedArgLines -join "`n"
        $capturedArgs | Should -Match '-OperationName MassCompile'
        $capturedArgs | Should -Match '-OperationName ExecuteBuildSpec'
        $capturedArgs | Should -Match '-DirectoryToCompile'
        $capturedArgs | Should -Match '-PortNumber 3363'
        $capturedArgs | Should -Not -Match '\blvbuildspec\b'
        ($capturedArgs.IndexOf('-OperationName MassCompile')) | Should -BeLessThan ($capturedArgs.IndexOf('-OperationName ExecuteBuildSpec'))

        (Test-Path -Path $snapshotPath -PathType Leaf) | Should -BeTrue
        [xml]$snapshotXml = Get-Content -Path $snapshotPath -Raw
        $buildNode = $snapshotXml.SelectSingleNode("//Item[@Type='Packed Library' and @Name='Editor Packed Library']")
        ($buildNode.SelectSingleNode("Property[@Name='Bld_version.major']").InnerText) | Should -Be '11'
        ($buildNode.SelectSingleNode("Property[@Name='Bld_version.minor']").InnerText) | Should -Be '22'
        ($buildNode.SelectSingleNode("Property[@Name='Bld_version.patch']").InnerText) | Should -Be '33'
        ($buildNode.SelectSingleNode("Property[@Name='Bld_version.build']").InnerText) | Should -Be '44'

        $restoredProject = Get-Content -Path $projectPath -Raw
        $restoredProject | Should -BeExactly $originalProject
    }

    It 'fails when LabVIEWCLI exits zero but the expected output artifact is missing' {
        $fixtureRoot = New-BuildLvlibpFixtureRepo
        $toolPath = Join-Path $fixtureRoot 'toolbin'
        New-Item -Path $toolPath -ItemType Directory -Force | Out-Null

        @'
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$CliArgs
)

exit 0
'@ | Set-Content -Path (Join-Path $toolPath 'LabVIEWCLI.ps1') -Encoding ascii

        $pathValue = "{0};{1}" -f $toolPath, $env:PATH
        $result = Invoke-BuildLvlibp -RepoRoot $fixtureRoot -PathValue $pathValue

        $result.ExitCode | Should -Not -Be 0
        ($result.Output -join "`n") | Should -Match 'Build specification output not found at expected path'
    }
}
