<#
#    .SYNOPSIS
#        Configures the repository for development mode.
#
#    .DESCRIPTION
#        Removes existing packed libraries, adds INI tokens, prepares LabVIEW
#        sources for both 32-bit and 64-bit environments, and closes LabVIEW.
#
#    .PARAMETER RelativePath
#        Path to the repository root.
#
#    .EXAMPLE
#        .\Set_Development_Mode.ps1 -RelativePath "C:\\labview-icon-editor"
#
#>

param(
    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path $_ })]
    [string]$RelativePath
)

# Define LabVIEW project name
$LabVIEW_Project = 'lv_icon_editor'
$Build_Spec      = 'Editor Packed Library'

# Determine the directory where this script is located
$ScriptDirectory = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition
Write-Host "Script Directory: $ScriptDirectory"

# Build paths to the helper scripts
$AddTokenScript = Join-Path -Path $ScriptDirectory -ChildPath '..\add-token-to-labview\AddTokenToLabVIEW.ps1'
$PrepareScript  = Join-Path -Path $ScriptDirectory -ChildPath '..\prepare-labview-source\Prepare_LabVIEW_source.ps1'
$CloseScript    = Join-Path -Path $ScriptDirectory -ChildPath '..\close-labview\Close_LabVIEW.ps1'

Write-Host "AddTokenToLabVIEW script: $AddTokenScript"
Write-Host "Prepare_LabVIEW_source script: $PrepareScript"
Write-Host "Close_LabVIEW script: $CloseScript"

# Helper function to execute scripts and stop on error
function Execute-Script {
    param(
        [string]$ScriptCommand
    )
    Write-Host "Executing: $ScriptCommand"
    try {
        Invoke-Expression $ScriptCommand -ErrorAction Stop
        if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne $null) {
            Write-Error "Error occurred while executing: $ScriptCommand. Exit code: $LASTEXITCODE"
            exit $LASTEXITCODE
        }
    }
    catch {
        Write-Error "Error occurred while executing: $ScriptCommand. Exiting."
        Write-Error $_.Exception.Message
        exit 1
    }
}

try {
    # Remove existing packed libraries (if the folder exists)
    $PluginsPath = Join-Path -Path $RelativePath -ChildPath 'resource\plugins'
    if (Test-Path $PluginsPath) {
        # Build and execute the removal command only if the plugins folder exists
        # Wrap the plugins path in single quotes to avoid issues with spaces or special characters
        $RemoveCommand = "Get-ChildItem -Path '$PluginsPath' -Filter '*.lvlibp' | Remove-Item -Force"
        Execute-Script $RemoveCommand
    }
    else {
        Write-Host "No 'resource\\plugins' directory found at $PluginsPath; skipping removal of packed libraries."
    }

    # 32-bit actions
    $Command1 = "& `"$AddTokenScript`" -MinimumSupportedLVVersion 2021 -SupportedBitness 32 -RelativePath `"$RelativePath`""
    Execute-Script $Command1

    $Command2 = "& `"$PrepareScript`" -MinimumSupportedLVVersion 2021 -SupportedBitness 32 -RelativePath `"$RelativePath`" -LabVIEW_Project `"$LabVIEW_Project`" -Build_Spec 'Editor Packed Library'"
    Execute-Script $Command2

    $Command3 = "& `"$CloseScript`" -MinimumSupportedLVVersion 2021 -SupportedBitness 32"
    Execute-Script $Command3

    # 64-bit actions
    $Command4 = "& `"$AddTokenScript`" -MinimumSupportedLVVersion 2021 -SupportedBitness 64 -RelativePath `"$RelativePath`""
    Execute-Script $Command4

    $Command5 = "& `"$PrepareScript`" -MinimumSupportedLVVersion 2021 -SupportedBitness 64 -RelativePath `"$RelativePath`" -LabVIEW_Project `"$LabVIEW_Project`" -Build_Spec 'Editor Packed Library'"
    Execute-Script $Command5

    $Command6 = "& `"$CloseScript`" -MinimumSupportedLVVersion 2021 -SupportedBitness 64"
    Execute-Script $Command6

}
catch {
    Write-Error "An unexpected error occurred during script execution: $($_.Exception.Message)"
    exit 1
}

Write-Host "All scripts executed successfully." -ForegroundColor Green
