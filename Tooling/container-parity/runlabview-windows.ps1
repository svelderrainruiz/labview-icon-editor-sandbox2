param(
    [string]$WorkspaceRoot = "C:\workspace",
    [string]$TargetDir = "",
    [string]$LabVIEWPath = "C:\Program Files\National Instruments\LabVIEW 2026\LabVIEW.exe",
    [string]$ProjectPath = "",
    [string]$BuildSpecName = "",
    [string]$BuildTargetName = "",
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

if ([string]::IsNullOrWhiteSpace($BuildTargetName)) {
    $BuildTargetName = if ([string]::IsNullOrWhiteSpace($env:CONTAINER_PARITY_BUILD_TARGET_NAME)) {
        'My Computer'
    } else {
        $env:CONTAINER_PARITY_BUILD_TARGET_NAME
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

& LabVIEWCLI `
    -LogToConsole TRUE `
    -OperationName MassCompile `
    -DirectoryToCompile $stagingDir `
    -LabVIEWPath $LabVIEWPath `
    -Headless

if ($LASTEXITCODE -ne 0) {
    throw "LabVIEWCLI MassCompile failed with exit code $LASTEXITCODE."
}

Write-Host "MassCompile completed successfully."

if (-not $buildSpecEnabled) {
    Write-Host "Build specification step disabled (set CONTAINER_PARITY_BUILD_SPEC=true to enable)."
    return
}

if (-not (Test-Path -LiteralPath $ProjectPath -PathType Leaf)) {
    throw "Project file does not exist: $ProjectPath"
}

Write-Host "Running LabVIEWCLI ExecuteBuildSpec in headless mode."
Write-Host "Project path: $ProjectPath"
Write-Host "Build specification: $BuildSpecName"
Write-Host "Build target: $BuildTargetName"
Write-Host "Expected output: $buildOutputPath"

& LabVIEWCLI `
    -LogToConsole TRUE `
    -OperationName ExecuteBuildSpec `
    -ProjectPath $ProjectPath `
    -BuildSpecName $BuildSpecName `
    -BuildTargetName $BuildTargetName `
    -LabVIEWPath $LabVIEWPath `
    -Headless

if ($LASTEXITCODE -ne 0) {
    throw "LabVIEWCLI ExecuteBuildSpec failed with exit code $LASTEXITCODE."
}

if (-not (Test-Path -LiteralPath $buildOutputPath -PathType Leaf)) {
    throw "Build specification output not found at expected path: $buildOutputPath"
}

$buildOutput = Get-Item -LiteralPath $buildOutputPath
Write-Host ("Build specification completed: {0} ({1} bytes)" -f $buildOutput.FullName, $buildOutput.Length)
