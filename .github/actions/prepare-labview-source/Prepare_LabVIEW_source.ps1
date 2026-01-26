<#
.SYNOPSIS
    Prepares LabVIEW source code for development mode.

.DESCRIPTION
    Executes PrepareIESource.vi via g-cli. The VI handles packaging the
    LabVIEW Icon API, renaming lv_icon.lvlibp to lv_icon.ship, and setting
    the LabVIEW token to the repository root. LabVIEW is closed after the
    VI executes so subsequent steps load the changes.

.PARAMETER MinimumSupportedLVVersion
    LabVIEW version used by g-cli (e.g., "2021").

.PARAMETER SupportedBitness
    Target bitness of the LabVIEW environment ("32" or "64").

.PARAMETER RelativePath
    Optional path to the repository root. If omitted, resolved relative to
    this script's location.

.EXAMPLE
    .\Prepare_LabVIEW_source.ps1 -MinimumSupportedLVVersion "2021" -SupportedBitness "64"
#>

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('2020', '2021', '2022', '2023', '2024', '2025')]
    [string]$MinimumSupportedLVVersion,

    [Parameter(Mandatory = $true)]
    [ValidateSet('32', '64', IgnoreCase = $true)]
    [string]$SupportedBitness,

    [Parameter(Mandatory = $false)]
    [string]$RelativePath
)

$ErrorActionPreference = 'Stop'

function Resolve-RepoRoot {
    param(
        [string]$PathOverride
    )

    if ($PathOverride) {
        if (-not (Test-Path -Path $PathOverride)) {
            throw "RelativePath does not exist: $PathOverride"
        }
        return (Resolve-Path -Path $PathOverride).Path
    }

    return (Resolve-Path -Path (Join-Path $PSScriptRoot '..\..\..')).Path
}

function Get-LabVIEWInstallRoot {
    param(
        [string]$Version,
        [string]$Bitness
    )

    $candidates = @()
    $regPaths = @()
    if ($Bitness -eq '32') {
        $candidates += "C:\Program Files (x86)\National Instruments\LabVIEW $Version"
        $regPaths += "HKLM:\SOFTWARE\WOW6432Node\National Instruments\LabVIEW $Version"
    } else {
        $candidates += "C:\Program Files\National Instruments\LabVIEW $Version"
        $regPaths += "HKLM:\SOFTWARE\National Instruments\LabVIEW $Version"
    }

    foreach ($candidate in $candidates) {
        if (Test-Path -Path $candidate) {
            return $candidate
        }
    }

    foreach ($regPath in $regPaths) {
        try {
            $props = Get-ItemProperty -Path $regPath -ErrorAction Stop
            foreach ($name in @('Path', 'InstallDir', 'InstallPath')) {
                $value = $props.$name
                if (-not [string]::IsNullOrWhiteSpace($value) -and (Test-Path -Path $value)) {
                    return $value
                }
            }
        } catch {
            continue
        }
    }

    return $null
}

$repoRoot = Resolve-RepoRoot -PathOverride $RelativePath
$viPath = Join-Path -Path $repoRoot -ChildPath 'Tooling\PrepareIESource.vi'

if (-not (Test-Path -Path $viPath)) {
    throw "PrepareIESource.vi not found at $viPath"
}

if (-not (Get-LabVIEWInstallRoot -Version $MinimumSupportedLVVersion -Bitness $SupportedBitness)) {
    throw "LabVIEW $MinimumSupportedLVVersion ($SupportedBitness-bit) install not found."
}

if (-not (Get-Command g-cli -ErrorAction SilentlyContinue)) {
    throw "g-cli.exe not found in PATH."
}

$gCliArgs = @(
    '--lv-ver', $MinimumSupportedLVVersion,
    '--arch', $SupportedBitness,
    '-v', $viPath
)

Write-Host ("Executing: g-cli {0}" -f ($gCliArgs -join ' '))
$previousErrorAction = $ErrorActionPreference
$nativePreferenceSet = $false
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $previousNativePreference = $PSNativeCommandUseErrorActionPreference
    $PSNativeCommandUseErrorActionPreference = $false
    $nativePreferenceSet = $true
}

$ErrorActionPreference = 'Continue'
try {
    $output = & g-cli @gCliArgs 2>&1
    $exitCode = $LASTEXITCODE
}
finally {
    $ErrorActionPreference = $previousErrorAction
    if ($nativePreferenceSet) {
        $PSNativeCommandUseErrorActionPreference = $previousNativePreference
    }
}

$output | ForEach-Object { Write-Host $_ }

$combinedOutput = $output -join "`n"
if ($combinedOutput -match '-593450') {
    throw "PrepareIESource.vi reported error -593450 (development mode could not be set)."
}

if ($exitCode -ne 0) {
    throw "PrepareIESource.vi failed with exit code $exitCode."
}

$closeScript = Join-Path -Path $PSScriptRoot -ChildPath '..\close-labview\Close_LabVIEW.ps1'
if (-not (Test-Path -Path $closeScript)) {
    throw "Close_LabVIEW.ps1 not found at $closeScript"
}

Write-Host "Closing LabVIEW $MinimumSupportedLVVersion ($SupportedBitness-bit)..."
& $closeScript -MinimumSupportedLVVersion $MinimumSupportedLVVersion -SupportedBitness $SupportedBitness

if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne $null) {
    throw "Close_LabVIEW.ps1 failed with exit code $LASTEXITCODE."
}
