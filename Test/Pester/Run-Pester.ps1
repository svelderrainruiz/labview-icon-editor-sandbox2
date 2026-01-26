param(
    [ValidateSet('2021')]
    [string]$LabVIEWVersion = '2021',

    [switch]$CI
)

$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path -Path (Join-Path $PSScriptRoot '..\..')
$env:LABVIEW_VERSION = $LabVIEWVersion

$configuration = New-PesterConfiguration
$configuration.Run.Path = $PSScriptRoot
$configuration.Run.PassThru = $true
$configuration.Output.Verbosity = 'Detailed'

if ($CI) {
    $resultsDir = Join-Path $repoRoot 'TestResults'
    if (-not (Test-Path -Path $resultsDir)) {
        New-Item -Path $resultsDir -ItemType Directory | Out-Null
    }

    $configuration.TestResult.Enabled = $true
    $configuration.TestResult.OutputFormat = 'NUnitXml'
    $configuration.TestResult.OutputPath = (Join-Path $resultsDir 'pester-devmode-2021.xml')
}

$results = Invoke-Pester -Configuration $configuration
if ($results.FailedCount -gt 0) {
    exit 1
}
