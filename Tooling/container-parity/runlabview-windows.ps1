param(
    [string]$WorkspaceRoot = "",
    [string]$TargetDir = "",
    [string]$LabVIEWPath = "C:\Program Files\National Instruments\LabVIEW 2026\LabVIEW.exe",
    [string]$ProjectPath = "",
    [string]$BuildSpecName = "",
    [string]$TargetName = "",
    [string]$LabVIEWVersion = "",
    [switch]$BuildProjectSpec
)

$ErrorActionPreference = 'Stop'

$pathContractScript = Join-Path -Path $PSScriptRoot -ChildPath '..\support\PathContract.ps1'
if (-not (Test-Path -LiteralPath $pathContractScript -PathType Leaf)) {
    throw "Path contract helper was not found: $pathContractScript"
}
. $pathContractScript

function Test-EnabledValue {
    param(
        [AllowNull()]
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $false
    }

    return $Value.Equals('1', [System.StringComparison]::OrdinalIgnoreCase) `
        -or $Value.Equals('true', [System.StringComparison]::OrdinalIgnoreCase) `
        -or $Value.Equals('yes', [System.StringComparison]::OrdinalIgnoreCase)
}

function Resolve-LabVIEWVersionYear {
    param(
        [string]$VersionInput,
        [string]$LabVIEWExecutablePath
    )

    if (-not [string]::IsNullOrWhiteSpace($VersionInput)) {
        return $VersionInput
    }

    if (-not [string]::IsNullOrWhiteSpace($env:CONTAINER_PARITY_LABVIEW_VERSION)) {
        return $env:CONTAINER_PARITY_LABVIEW_VERSION
    }

    if ($LabVIEWExecutablePath -match 'LabVIEW\s+(?<year>\d{4})') {
        return $Matches['year']
    }

    return ''
}

function ConvertTo-LabVIEWCliPortNumber {
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$RawValue,

        [Parameter(Mandatory = $true)]
        [string]$Source
    )

    if ([string]::IsNullOrWhiteSpace($RawValue)) {
        return $null
    }

    $parsedPort = 0
    if (-not [int]::TryParse($RawValue.Trim(), [ref]$parsedPort) -or $parsedPort -lt 1 -or $parsedPort -gt 65535) {
        Write-Warning ("Ignoring invalid port value '{0}' from {1}. Expected integer range 1-65535." -f $RawValue, $Source)
        return $null
    }

    return $parsedPort
}

function Get-LabVIEWIniTcpPort {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LabVIEWExecutablePath
    )

    $iniPath = Join-Path -Path (Split-Path -Path $LabVIEWExecutablePath -Parent) -ChildPath 'LabVIEW.ini'
    $portRaw = $null

    if (-not (Test-Path -LiteralPath $iniPath -PathType Leaf)) {
        return [pscustomobject]@{
            IniPath = $iniPath
            PortRaw = $portRaw
        }
    }

    try {
        $lines = Get-Content -LiteralPath $iniPath -ErrorAction Stop
    } catch {
        Write-Warning ("Unable to read LabVIEW.ini at {0}: {1}" -f $iniPath, $_.Exception.Message)
        return [pscustomobject]@{
            IniPath = $iniPath
            PortRaw = $portRaw
        }
    }

    foreach ($line in $lines) {
        if ($null -eq $line) {
            continue
        }

        if ($line -match '^\s*server\.tcp\.port\s*=\s*(.+?)\s*$') {
            $portRaw = $Matches[1].Trim()
            break
        }
    }

    return [pscustomobject]@{
        IniPath = $iniPath
        PortRaw = $portRaw
    }
}

function Resolve-LabVIEWCliPort {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LabVIEWExecutablePath
    )

    $bitnessPort = ConvertTo-LabVIEWCliPortNumber -RawValue $env:LVIE_LUNIT_PORT_64 -Source '$env:LVIE_LUNIT_PORT_64'
    if ($null -ne $bitnessPort) {
        return [pscustomobject]@{
            PortNumber = $bitnessPort
            Source     = '$env:LVIE_LUNIT_PORT_64'
        }
    }

    $genericPort = ConvertTo-LabVIEWCliPortNumber -RawValue $env:LVIE_LUNIT_PORT -Source '$env:LVIE_LUNIT_PORT'
    if ($null -ne $genericPort) {
        return [pscustomobject]@{
            PortNumber = $genericPort
            Source     = '$env:LVIE_LUNIT_PORT'
        }
    }

    $iniPortInfo = Get-LabVIEWIniTcpPort -LabVIEWExecutablePath $LabVIEWExecutablePath
    $iniPort = ConvertTo-LabVIEWCliPortNumber -RawValue $iniPortInfo.PortRaw -Source ('{0} (server.tcp.port)' -f $iniPortInfo.IniPath)
    if ($null -ne $iniPort) {
        return [pscustomobject]@{
            PortNumber = $iniPort
            Source     = ('{0} (server.tcp.port)' -f $iniPortInfo.IniPath)
        }
    }

    return [pscustomobject]@{
        PortNumber = 3363
        Source     = 'default:3363'
    }
}

function Test-LabVIEWCliConnectionFailure {
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$OutputText
    )

    if ([string]::IsNullOrWhiteSpace($OutputText)) {
        return $false
    }

    return $OutputText -match '(?i)Error\s*code\s*:\s*-350000'
}

function Get-LabVIEWCliSelectorPortAttemptList {
    param(
        [Parameter(Mandatory = $true)]
        [int]$PrimaryPortNumber
    )

    $attemptPorts = New-Object System.Collections.Generic.List[int]
    $seenPorts = @{}

    foreach ($candidatePort in @($PrimaryPortNumber, 3370, 3363)) {
        if ($candidatePort -lt 1 -or $candidatePort -gt 65535) {
            continue
        }

        if ($seenPorts.ContainsKey($candidatePort)) {
            continue
        }

        $attemptPorts.Add($candidatePort) | Out-Null
        $seenPorts[$candidatePort] = $true
    }

    return @($attemptPorts.ToArray())
}

function Invoke-LabVIEWCliSelectorMode {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('set', 'unset')]
        [string]$Mode,

        [Parameter(Mandatory = $true)]
        [string]$LabVIEWExecutablePath,

        [Parameter(Mandatory = $true)]
        [string]$SelectorViAbsolutePath,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$PrimaryPort,

        [Parameter(Mandatory = $true)]
        [string]$WorkspaceRootPath
    )

    $attemptSummaries = New-Object System.Collections.Generic.List[string]
    $lastResult = $null
    $lastPortNumber = $null
    $lastPortSource = $null
    $sawConnectionFailure = $false

    $portAttempts = @(Get-LabVIEWCliSelectorPortAttemptList -PrimaryPortNumber $PrimaryPort.PortNumber)
    foreach ($portNumber in $portAttempts) {
        $portSource = if ($portNumber -eq $PrimaryPort.PortNumber) {
            $PrimaryPort.Source
        } else {
            "fallback:$portNumber"
        }

        Write-Output ("Running selector mode '{0}' via LabVIEWCLI on port {1} (source: {2})." -f $Mode, $portNumber, $portSource)
        $selectorArgs = @(
            '-LogToConsole', 'TRUE',
            '-OperationName', 'RunVI',
            '-LabVIEWPath', $LabVIEWExecutablePath,
            '-PortNumber', $portNumber.ToString(),
            '-VIPath', $SelectorViAbsolutePath,
            '-Headless',
            $Mode
        )
        $selectorResult = Invoke-LabVIEWCliOperation -OperationName ("Selector-{0}-Port{1}" -f $Mode, $portNumber) -Arguments $selectorArgs -WorkspaceRootPath $WorkspaceRootPath
        $lastResult = $selectorResult
        $lastPortNumber = $portNumber
        $lastPortSource = $portSource

        if ($selectorResult.ExitCode -eq 0) {
            return [pscustomobject]@{
                ExitCode         = 0
                PortNumber       = $portNumber
                PortSource       = $portSource
                UsedImplicitPort = $false
                Attempts         = @($attemptSummaries)
            }
        }

        $attemptSummaries.Add(("port:{0} source:{1} exit:{2}" -f $portNumber, $portSource, $selectorResult.ExitCode)) | Out-Null
        if (Test-LabVIEWCliConnectionFailure -OutputText $selectorResult.OutputText) {
            $sawConnectionFailure = $true
            continue
        }

        break
    }

    if ($sawConnectionFailure) {
        Write-Warning ("Selector mode '{0}' failed to connect on explicit ports. Retrying without explicit -PortNumber." -f $Mode)
        $implicitArgs = @(
            '-LogToConsole', 'TRUE',
            '-OperationName', 'RunVI',
            '-LabVIEWPath', $LabVIEWExecutablePath,
            '-VIPath', $SelectorViAbsolutePath,
            '-Headless',
            $Mode
        )
        $implicitResult = Invoke-LabVIEWCliOperation -OperationName ("Selector-{0}-ImplicitPort" -f $Mode) -Arguments $implicitArgs -WorkspaceRootPath $WorkspaceRootPath
        $lastResult = $implicitResult
        $lastPortNumber = $null
        $lastPortSource = 'implicit-default'

        if ($implicitResult.ExitCode -eq 0) {
            return [pscustomobject]@{
                ExitCode         = 0
                PortNumber       = $null
                PortSource       = 'implicit-default'
                UsedImplicitPort = $true
                Attempts         = @($attemptSummaries)
            }
        }

        $attemptSummaries.Add(("port:implicit source:implicit-default exit:{0}" -f $implicitResult.ExitCode)) | Out-Null
    }

    return [pscustomobject]@{
        ExitCode         = if ($null -eq $lastResult) { 1 } else { $lastResult.ExitCode }
        PortNumber       = $lastPortNumber
        PortSource       = $lastPortSource
        UsedImplicitPort = $false
        Attempts         = @($attemptSummaries)
    }
}

function Sync-IconEditorSourcesForBuildSpec {
    param(
        [string]$WorkspaceRootPath,
        [string]$LabVIEWExecutablePath
    )

    if (-not (Test-Path -LiteralPath $WorkspaceRootPath -PathType Container)) {
        throw "Workspace root does not exist: $WorkspaceRootPath"
    }

    $labviewRoot = Split-Path -Path $LabVIEWExecutablePath -Parent
    if ([string]::IsNullOrWhiteSpace($labviewRoot) -or -not (Test-Path -LiteralPath $labviewRoot -PathType Container)) {
        throw "Unable to resolve LabVIEW install root from LabVIEW path: $LabVIEWExecutablePath"
    }

    $repoPlugins = Join-Path $WorkspaceRootPath 'resource\plugins'
    $repoIconApi = Join-Path $WorkspaceRootPath 'vi.lib\LabVIEW Icon API'
    $requiredPaths = @(
        (Join-Path $repoPlugins 'NIIconEditor'),
        (Join-Path $repoPlugins 'lv_IconEditor.lvlib'),
        (Join-Path $repoPlugins 'lv_icon.vi'),
        $repoIconApi
    )

    foreach ($path in $requiredPaths) {
        if (-not (Test-Path -LiteralPath $path)) {
            throw "Required Icon Editor source path is missing: $path"
        }
    }

    $installPlugins = Join-Path $labviewRoot 'resource\plugins'
    $installIconApi = Join-Path $labviewRoot 'vi.lib\LabVIEW Icon API'
    New-Item -Path $installPlugins -ItemType Directory -Force | Out-Null
    New-Item -Path $installIconApi -ItemType Directory -Force | Out-Null

    Copy-Item -LiteralPath (Join-Path $repoPlugins 'NIIconEditor') -Destination $installPlugins -Recurse -Force

    foreach ($fileName in @('lv_IconEditor.lvlib', 'lv_icon.vi', 'lv_icon.vit', 'SAMPLE_lv_icon.vi')) {
        $sourcePath = Join-Path $repoPlugins $fileName
        if (Test-Path -LiteralPath $sourcePath -PathType Leaf) {
            Copy-Item -LiteralPath $sourcePath -Destination $installPlugins -Force
        }
    }

    Get-ChildItem -LiteralPath $repoIconApi -Force | Copy-Item -Destination $installIconApi -Recurse -Force

    $probe = Join-Path $installPlugins 'NIIconEditor\Miscellaneous\Classes Initialization.vi'
    if (-not (Test-Path -LiteralPath $probe -PathType Leaf)) {
        throw "Icon Editor source synchronization failed. Missing probe file: $probe"
    }

    Write-Output "Synchronized Icon Editor sources into LabVIEW install:"
    Write-Output "  resource\\plugins -> $installPlugins"
    Write-Output "  vi.lib\\LabVIEW Icon API -> $installIconApi"
}

function Get-LabVIEWCliTempLogPath {
    param(
        [string]$TempRoot = ([System.IO.Path]::GetTempPath())
    )

    return @(
        Get-ChildItem -LiteralPath $TempRoot -Filter 'lvtemporary_*.log' -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTimeUtc -Descending |
            Select-Object -ExpandProperty FullName
    )
}

function Save-LabVIEWCliLog {
    param(
        [string]$WorkspaceRootPath,
        [string]$OperationName,
        [string[]]$BeforeLogPaths
    )

    $logRoot = Join-Path $WorkspaceRootPath 'TestResults\container-parity\windows\logs'
    New-Item -Path $logRoot -ItemType Directory -Force | Out-Null
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $beforeSet = @{}
    foreach ($path in $BeforeLogPaths) {
        if (-not [string]::IsNullOrWhiteSpace($path)) {
            $beforeSet[$path] = $true
        }
    }

    $afterLogPaths = @(Get-LabVIEWCliTempLogPath)
    $newLogPaths = @()
    foreach ($source in $afterLogPaths) {
        if (-not $beforeSet.ContainsKey($source)) {
            $newLogPaths += $source
        }
    }

    if ($newLogPaths.Count -eq 0 -and $afterLogPaths.Count -gt 0) {
        $newLogPaths = @($afterLogPaths[0])
    }

    $copied = @()
    $index = 0
    foreach ($source in $newLogPaths) {
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
            continue
        }
        $index++
        $destination = Join-Path $logRoot ("{0}-{1}-{2}.log" -f $OperationName.ToLowerInvariant(), $timestamp, $index)
        Copy-Item -LiteralPath $source -Destination $destination -Force
        $copied += $destination
        Write-Output "Captured LabVIEWCLI log: $destination"
    }

    return $copied
}

function Invoke-LabVIEWCliOperation {
    param(
        [string]$OperationName,
        [string[]]$Arguments,
        [string]$WorkspaceRootPath
    )

    $beforeLogPaths = @(Get-LabVIEWCliTempLogPath)
    $outputLines = & LabVIEWCLI @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    $outputText = if ($null -eq $outputLines) {
        ''
    } else {
        @($outputLines | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
    }
    if (-not [string]::IsNullOrWhiteSpace($outputText)) {
        Write-Output $outputText
    }
    $copiedLogs = Save-LabVIEWCliLog -WorkspaceRootPath $WorkspaceRootPath -OperationName $OperationName -BeforeLogPaths $beforeLogPaths

    return [pscustomobject]@{
        ExitCode   = $exitCode
        CopiedLogs = $copiedLogs
        OutputText = $outputText
    }
}

$repoRootResolution = Resolve-LvieRepoRoot `
    -LvieRepoRoot $env:LVIE_REPO_ROOT `
    -WorkspaceRoot $WorkspaceRoot `
    -RepoRoot $env:REPO_ROOT `
    -DefaultRepoRoot 'C:\workspace'
$WorkspaceRoot = $repoRootResolution.Path

$projectRelativePath = if ([string]::IsNullOrWhiteSpace($env:LVIE_PROJECT_RELATIVE_PATH)) {
    if ([string]::IsNullOrWhiteSpace($env:PROJECT_PATH_REL)) {
        'lv_icon_editor.lvproj'
    } else {
        $env:PROJECT_PATH_REL
    }
} else {
    $env:LVIE_PROJECT_RELATIVE_PATH
}

$projectPathCanonicalCandidate = if ([string]::IsNullOrWhiteSpace($ProjectPath)) { $env:LVIE_PROJECT_PATH } else { $ProjectPath }
$projectPathAliasCandidate = if ([string]::IsNullOrWhiteSpace($ProjectPath)) { $env:PROJECT_PATH } else { $null }
$projectPathResolution = Resolve-LvieProjectPath `
    -LvieProjectPath $projectPathCanonicalCandidate `
    -ProjectPath $projectPathAliasCandidate `
    -RepoRoot $WorkspaceRoot `
    -ProjectRelativePath $projectRelativePath `
    -DefaultProjectRelativePath 'lv_icon_editor.lvproj'
$ProjectPath = $projectPathResolution.Path

$targetDirRelativePath = if ([string]::IsNullOrWhiteSpace($env:TARGET_DIR_REL)) {
    'Test\Templates'
} else {
    $env:TARGET_DIR_REL
}
$targetDirSource = 'parameter:TargetDir'
if ([string]::IsNullOrWhiteSpace($TargetDir)) {
    if (-not [string]::IsNullOrWhiteSpace($env:TARGET_DIR)) {
        $TargetDir = $env:TARGET_DIR
        $targetDirSource = '$env:TARGET_DIR'
    } else {
        $TargetDir = Join-LvieRepoPath -RepoRoot $WorkspaceRoot -RelativePath $targetDirRelativePath
        $targetDirSource = '$env:TARGET_DIR_REL'
    }
}

$env:LVIE_REPO_ROOT = $WorkspaceRoot
$env:LVIE_PROJECT_PATH = $ProjectPath
$env:LVIE_PROJECT_RELATIVE_PATH = $projectPathResolution.RelativePath
$env:WORKSPACE_ROOT = $WorkspaceRoot
$env:REPO_ROOT = $WorkspaceRoot
$env:PROJECT_PATH = $ProjectPath

Write-Output ("Resolved repo root: {0} (source: {1})" -f $WorkspaceRoot, $repoRootResolution.Source)
Write-Output ("Resolved project path: {0} (source: {1})" -f $ProjectPath, $projectPathResolution.Source)
Write-Output ("Resolved target directory: {0} (source: {1})" -f $TargetDir, $targetDirSource)

if ([string]::IsNullOrWhiteSpace($BuildSpecName)) {
    $BuildSpecName = if ([string]::IsNullOrWhiteSpace($env:CONTAINER_PARITY_BUILD_SPEC_NAME)) {
        'Editor Packed Library'
    } else {
        $env:CONTAINER_PARITY_BUILD_SPEC_NAME
    }
}

if ([string]::IsNullOrWhiteSpace($TargetName)) {
    $TargetName = if ([string]::IsNullOrWhiteSpace($env:CONTAINER_PARITY_TARGET_NAME)) {
        'My Computer'
    } else {
        $env:CONTAINER_PARITY_TARGET_NAME
    }
}

$buildSpecEnabled = $BuildProjectSpec.IsPresent -or (Test-EnabledValue -Value $env:CONTAINER_PARITY_BUILD_SPEC)
$enableDevMode = Test-EnabledValue -Value $env:CONTAINER_PARITY_ENABLE_DEVMODE
$buildOutputRelativePath = if ([string]::IsNullOrWhiteSpace($env:CONTAINER_PARITY_BUILD_OUTPUT_RELATIVE_PATH)) {
    'resource\plugins\lv_icon.lvlibp'
} else {
    $env:CONTAINER_PARITY_BUILD_OUTPUT_RELATIVE_PATH
}
$buildOutputPath = Join-LvieRepoPath -RepoRoot $WorkspaceRoot -RelativePath $buildOutputRelativePath

if (-not (Get-Command LabVIEWCLI -ErrorAction SilentlyContinue)) {
    Write-Error "LabVIEWCLI is not available on PATH inside the container."
}

if (-not (Test-Path -LiteralPath $TargetDir -PathType Container)) {
    Write-Error "Target directory does not exist: $TargetDir"
}

$selectorViPath = Join-LvieRepoPath -RepoRoot $WorkspaceRoot -RelativePath 'Tooling\Run Icon Editor from Source Selector.vi'
if (-not (Test-Path -LiteralPath $selectorViPath -PathType Leaf)) {
    Write-Error "Selector VI does not exist: $selectorViPath"
}

$selectorPrimaryPort = Resolve-LabVIEWCliPort -LabVIEWExecutablePath $LabVIEWPath
Write-Output ("Using selector VI Server primary port: {0} ({1})" -f $selectorPrimaryPort.PortNumber, $selectorPrimaryPort.Source)
$selectorPortAttempts = @(Get-LabVIEWCliSelectorPortAttemptList -PrimaryPortNumber $selectorPrimaryPort.PortNumber)
if ($selectorPortAttempts.Count -gt 1) {
    Write-Output ("Selector port fallback order: {0}" -f (($selectorPortAttempts | ForEach-Object { $_.ToString() }) -join ', '))
}

$excludeRaw = $env:CONTAINER_PARITY_EXCLUDE_FILES
if ([string]::IsNullOrWhiteSpace($excludeRaw)) {
    $excludeRaw = 'Polymorphic Template.vi'
}
$excludeFiles = @($excludeRaw.Split(';', [System.StringSplitOptions]::RemoveEmptyEntries) | ForEach-Object { $_.Trim() } | Where-Object { $_ })

$stagingDir = Join-Path ([System.IO.Path]::GetTempPath()) ("lvie-parity-{0}" -f [Guid]::NewGuid().ToString('N'))
New-Item -Path $stagingDir -ItemType Directory -Force | Out-Null

try {
    Copy-Item -Path (Join-Path $TargetDir '*') -Destination $stagingDir -Recurse -Force
    foreach ($relativePath in $excludeFiles) {
        $candidate = Join-Path $stagingDir $relativePath
        if (Test-Path -LiteralPath $candidate) {
            Write-Output "Excluding template from parity compile: $relativePath"
            Remove-Item -LiteralPath $candidate -Recurse -Force
        }
    }

    $massCompileStageError = $null
    $selectorUnsetErrorMessage = $null
    $selectorSetSucceeded = $false
    $selectorSetContext = $null
    try {
        $selectorSet = Invoke-LabVIEWCliSelectorMode `
            -Mode 'set' `
            -LabVIEWExecutablePath $LabVIEWPath `
            -SelectorViAbsolutePath $selectorViPath `
            -PrimaryPort $selectorPrimaryPort `
            -WorkspaceRootPath $WorkspaceRoot
        if ($selectorSet.ExitCode -ne 0) {
            $selectorSetAttempts = if ($selectorSet.Attempts.Count -gt 0) {
                " Attempts: $($selectorSet.Attempts -join '; ')"
            } else {
                ''
            }
            throw ("LabVIEWCLI selector set failed with exit code {0}.{1}" -f $selectorSet.ExitCode, $selectorSetAttempts)
        }

        if ($selectorSet.UsedImplicitPort) {
            Write-Output "Selector mode 'set' succeeded without explicit -PortNumber."
        } elseif ($selectorSet.PortNumber -ne $selectorPrimaryPort.PortNumber) {
            Write-Output ("Selector mode 'set' succeeded on fallback port {0} (source: {1})." -f $selectorSet.PortNumber, $selectorSet.PortSource)
        }
        $selectorSetContext = $selectorSet
        $selectorSetSucceeded = $true

        Write-Output "Running LabVIEWCLI MassCompile in headless mode."
        Write-Output "Target directory: $TargetDir"
        Write-Output "LabVIEW path: $LabVIEWPath"
        Write-Output ("Excluded templates: {0}" -f ($excludeFiles -join '; '))
        Write-Output "Staging directory: $stagingDir"

        $massCompile = Invoke-LabVIEWCliOperation -OperationName 'MassCompile' -Arguments @(
            '-LogToConsole', 'TRUE',
            '-OperationName', 'MassCompile',
            '-DirectoryToCompile', $stagingDir,
            '-LabVIEWPath', $LabVIEWPath,
            '-Headless'
        ) -WorkspaceRootPath $WorkspaceRoot
        if ($massCompile.ExitCode -ne 0) {
            throw "LabVIEWCLI MassCompile failed with exit code $($massCompile.ExitCode)."
        }
    } catch {
        $massCompileStageError = $_
    } finally {
        if ($selectorSetSucceeded) {
            $unsetPrimaryPort = $selectorPrimaryPort
            if ($null -ne $selectorSetContext -and -not $selectorSetContext.UsedImplicitPort -and $null -ne $selectorSetContext.PortNumber) {
                $unsetPrimaryPort = [pscustomobject]@{
                    PortNumber = [int]$selectorSetContext.PortNumber
                    Source     = "selector-set-success:$($selectorSetContext.PortSource)"
                }
            }

            $selectorUnset = Invoke-LabVIEWCliSelectorMode `
                -Mode 'unset' `
                -LabVIEWExecutablePath $LabVIEWPath `
                -SelectorViAbsolutePath $selectorViPath `
                -PrimaryPort $unsetPrimaryPort `
                -WorkspaceRootPath $WorkspaceRoot
            if ($selectorUnset.ExitCode -ne 0) {
                $selectorUnsetAttempts = if ($selectorUnset.Attempts.Count -gt 0) {
                    " Attempts: $($selectorUnset.Attempts -join '; ')"
                } else {
                    ''
                }
                $selectorUnsetErrorMessage = ("LabVIEWCLI selector unset failed with exit code {0}.{1}" -f $selectorUnset.ExitCode, $selectorUnsetAttempts)
            }
        }
    }

    if ($massCompileStageError -and $selectorUnsetErrorMessage) {
        throw ("{0} Selector unset error: {1}" -f $massCompileStageError.Exception.Message, $selectorUnsetErrorMessage)
    }
    if ($massCompileStageError) {
        throw $massCompileStageError.Exception
    }
    if ($selectorUnsetErrorMessage) {
        throw $selectorUnsetErrorMessage
    }

    Write-Output "MassCompile completed successfully."

    if (-not $buildSpecEnabled) {
        Write-Output "Build specification step disabled (set CONTAINER_PARITY_BUILD_SPEC=true to enable)."
        return
    }

    if (-not (Test-Path -LiteralPath $ProjectPath -PathType Leaf)) {
        throw "Project file does not exist: $ProjectPath"
    }

    Write-Output "Synchronizing workspace Icon Editor sources into LabVIEW install before build-spec execution."
    Sync-IconEditorSourcesForBuildSpec -WorkspaceRootPath $WorkspaceRoot -LabVIEWExecutablePath $LabVIEWPath

    $setDevModeScript = $null
    $revertDevModeScript = $null
    $labviewYear = $null
    $devModeEnabled = $false
    if ($enableDevMode) {
        $setDevModeScript = Join-LvieRepoPath -RepoRoot $WorkspaceRoot -RelativePath 'Tooling\Set-DevelopmentMode-NoLabVIEW.ps1'
        $revertDevModeScript = Join-LvieRepoPath -RepoRoot $WorkspaceRoot -RelativePath 'Tooling\Revert-DevelopmentMode-NoLabVIEW.ps1'
        if (-not (Test-Path -LiteralPath $setDevModeScript -PathType Leaf)) {
            throw "Required script not found: $setDevModeScript"
        }
        if (-not (Test-Path -LiteralPath $revertDevModeScript -PathType Leaf)) {
            throw "Required script not found: $revertDevModeScript"
        }

        $labviewYear = Resolve-LabVIEWVersionYear -VersionInput $LabVIEWVersion -LabVIEWExecutablePath $LabVIEWPath
        if ([string]::IsNullOrWhiteSpace($labviewYear)) {
            throw "Unable to resolve LabVIEW version year for no-LabVIEW dev mode plumbing."
        }

        Write-Output "Preparing no-LabVIEW dev mode before build-spec execution."
        & $setDevModeScript `
            -LabVIEWVersion $labviewYear `
            -SupportedBitness 64 `
            -RepoRoot $WorkspaceRoot `
            -SkipProcessCheck `
            -SkipRepoVersionCheck
        if ($LASTEXITCODE -ne 0) {
            throw "Set-DevelopmentMode-NoLabVIEW failed with exit code $LASTEXITCODE."
        }
        $devModeEnabled = $true
    } else {
        Write-Output "No-LabVIEW dev mode is disabled for container parity (set CONTAINER_PARITY_ENABLE_DEVMODE=true to enable)."
    }

    $buildSpecError = $null
    try {
        Write-Output "Running LabVIEWCLI ExecuteBuildSpec in headless mode."
        Write-Output "Project path: $ProjectPath"
        Write-Output "Build specification: $BuildSpecName"
        Write-Output "Target name: $TargetName"
        Write-Output "Expected output: $buildOutputPath"

        $buildSpec = Invoke-LabVIEWCliOperation -OperationName 'ExecuteBuildSpec' -Arguments @(
            '-LogToConsole', 'TRUE',
            '-OperationName', 'ExecuteBuildSpec',
            '-ProjectPath', $ProjectPath,
            '-BuildSpecName', $BuildSpecName,
            '-TargetName', $TargetName,
            '-LabVIEWPath', $LabVIEWPath,
            '-Headless'
        ) -WorkspaceRootPath $WorkspaceRoot
        if ($buildSpec.ExitCode -ne 0) {
            throw "LabVIEWCLI ExecuteBuildSpec failed with exit code $($buildSpec.ExitCode)."
        }

        if (-not (Test-Path -LiteralPath $buildOutputPath -PathType Leaf)) {
            throw "Build specification output not found at expected path: $buildOutputPath"
        }

        $buildOutput = Get-Item -LiteralPath $buildOutputPath
        Write-Output ("Build specification completed: {0} ({1} bytes)" -f $buildOutput.FullName, $buildOutput.Length)
    } catch {
        $buildSpecError = $_
    } finally {
        if ($devModeEnabled) {
            Write-Output "Reverting no-LabVIEW dev mode after build-spec execution."
            & $revertDevModeScript `
                -LabVIEWVersion $labviewYear `
                -SupportedBitness 64 `
                -RepoRoot $WorkspaceRoot `
                -SkipProcessCheck `
                -SkipRepoVersionCheck
            if ($LASTEXITCODE -ne 0) {
                $revertError = "Revert-DevelopmentMode-NoLabVIEW failed with exit code $LASTEXITCODE."
                if ($buildSpecError) {
                    throw ("{0} Revert error: {1}" -f $buildSpecError.Exception.Message, $revertError)
                }
                throw $revertError
            }
        }
    }

    if ($buildSpecError) {
        throw $buildSpecError.Exception
    }
} finally {
    if (Test-Path -LiteralPath $stagingDir) {
        Remove-Item -LiteralPath $stagingDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
