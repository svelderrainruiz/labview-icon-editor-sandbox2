param(
    [string]$WorkspaceRoot = "C:\workspace",
    [string]$TargetDir = "",
    [string]$LabVIEWPath = "C:\Program Files\National Instruments\LabVIEW 2026\LabVIEW.exe",
    [string]$ProjectPath = "",
    [string]$BuildSpecName = "",
    [string]$TargetName = "",
    [string]$LabVIEWVersion = "",
    [switch]$BuildProjectSpec
)

$ErrorActionPreference = 'Stop'

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

function Get-LabVIEWCliLogPathsFromOutput {
    param(
        [object[]]$OutputLines
    )

    $results = @()
    foreach ($line in $OutputLines) {
        if ($null -eq $line) {
            continue
        }

        $text = [string]$line
        if ($text -match 'LabVIEWCLI started logging in file:\s*(?<path>.+)$') {
            $path = $Matches['path'].Trim().Trim('"')
            if (-not [string]::IsNullOrWhiteSpace($path)) {
                $results += $path
            }
        }
    }

    return @($results | Select-Object -Unique)
}

function Save-LabVIEWCliLog {
    param(
        [string]$WorkspaceRootPath,
        [string]$OperationName,
        [string[]]$LogPaths
    )

    $copied = @()
    if ($LogPaths.Count -eq 0) {
        return $copied
    }

    $logRoot = Join-Path $WorkspaceRootPath 'TestResults\container-parity\windows\logs'
    New-Item -Path $logRoot -ItemType Directory -Force | Out-Null
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $index = 0

    foreach ($source in $LogPaths) {
        $index++
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
            Write-Warning "LabVIEWCLI log path from output was not found: $source"
            continue
        }

        $destination = Join-Path $logRoot ("{0}-{1}-{2}.log" -f $OperationName.ToLowerInvariant(), $timestamp, $index)
        Copy-Item -LiteralPath $source -Destination $destination -Force
        $copied += $destination
        Write-Host "Captured LabVIEWCLI log: $destination"
    }

    return $copied
}

function Invoke-LabVIEWCliOperation {
    param(
        [string]$OperationName,
        [string[]]$Arguments,
        [string]$WorkspaceRootPath
    )

    $outputLines = @(& LabVIEWCLI @Arguments 2>&1)
    $exitCode = $LASTEXITCODE
    foreach ($line in $outputLines) {
        if ($null -ne $line) {
            Write-Host ([string]$line)
        }
    }

    $logPaths = Get-LabVIEWCliLogPathsFromOutput -OutputLines $outputLines
    $copiedLogs = Save-LabVIEWCliLog -WorkspaceRootPath $WorkspaceRootPath -OperationName $OperationName -LogPaths $logPaths

    return [pscustomobject]@{
        ExitCode   = $exitCode
        CopiedLogs = $copiedLogs
    }
}

if ([string]::IsNullOrWhiteSpace($TargetDir)) {
    $TargetDir = Join-Path $WorkspaceRoot 'Test\Templates'
}

if ([string]::IsNullOrWhiteSpace($ProjectPath)) {
    $ProjectPath = Join-Path $WorkspaceRoot 'lv_icon_editor.lvproj'
}

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
$buildOutputRelativePath = if ([string]::IsNullOrWhiteSpace($env:CONTAINER_PARITY_BUILD_OUTPUT_RELATIVE_PATH)) {
    'resource\plugins\lv_icon.lvlibp'
} else {
    $env:CONTAINER_PARITY_BUILD_OUTPUT_RELATIVE_PATH
}
$buildOutputPath = Join-Path $WorkspaceRoot $buildOutputRelativePath

if (-not (Get-Command LabVIEWCLI -ErrorAction SilentlyContinue)) {
    Write-Error "LabVIEWCLI is not available on PATH inside the container."
}

if (-not (Test-Path -LiteralPath $TargetDir -PathType Container)) {
    Write-Error "Target directory does not exist: $TargetDir"
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
            Write-Host "Excluding template from parity compile: $relativePath"
            Remove-Item -LiteralPath $candidate -Recurse -Force
        }
    }

    Write-Host "Running LabVIEWCLI MassCompile in headless mode."
    Write-Host "Target directory: $TargetDir"
    Write-Host "LabVIEW path: $LabVIEWPath"
    Write-Host ("Excluded templates: {0}" -f ($excludeFiles -join '; '))
    Write-Host "Staging directory: $stagingDir"

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

    Write-Host "MassCompile completed successfully."

    if (-not $buildSpecEnabled) {
        Write-Host "Build specification step disabled (set CONTAINER_PARITY_BUILD_SPEC=true to enable)."
        return
    }

    if (-not (Test-Path -LiteralPath $ProjectPath -PathType Leaf)) {
        throw "Project file does not exist: $ProjectPath"
    }

    $setDevModeScript = Join-Path $WorkspaceRoot 'Tooling\Set-DevelopmentMode-NoLabVIEW.ps1'
    $revertDevModeScript = Join-Path $WorkspaceRoot 'Tooling\Revert-DevelopmentMode-NoLabVIEW.ps1'
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

    Write-Host "Preparing no-LabVIEW dev mode before build-spec execution."
    & $setDevModeScript `
        -LabVIEWVersion $labviewYear `
        -SupportedBitness 64 `
        -RepoRoot $WorkspaceRoot `
        -SkipProcessCheck `
        -SkipRepoVersionCheck
    if ($LASTEXITCODE -ne 0) {
        throw "Set-DevelopmentMode-NoLabVIEW failed with exit code $LASTEXITCODE."
    }

    $buildSpecError = $null
    try {
        Write-Host "Running LabVIEWCLI ExecuteBuildSpec in headless mode."
        Write-Host "Project path: $ProjectPath"
        Write-Host "Build specification: $BuildSpecName"
        Write-Host "Target name: $TargetName"
        Write-Host "Expected output: $buildOutputPath"

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
        Write-Host ("Build specification completed: {0} ({1} bytes)" -f $buildOutput.FullName, $buildOutput.Length)
    } catch {
        $buildSpecError = $_
    } finally {
        Write-Host "Reverting no-LabVIEW dev mode after build-spec execution."
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

    if ($buildSpecError) {
        throw $buildSpecError.Exception
    }
} finally {
    if (Test-Path -LiteralPath $stagingDir) {
        Remove-Item -LiteralPath $stagingDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
