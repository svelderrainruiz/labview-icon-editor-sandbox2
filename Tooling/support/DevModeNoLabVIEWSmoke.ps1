#Requires -Version 7.0
<#
.SYNOPSIS
    Helper functions for DevMode no-LabVIEW smoke coverage.
#>

function Get-DevModeNoLabVIEWSmokeSuite {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [ValidateSet('minimal', 'balanced', 'full')]
        [string]$Depth = 'balanced'
    )

    $tests = @(
        [pscustomobject]@{
            Path = 'Test/Pester/DevMode.NoLabVIEW.Tests.ps1'
            Kind = 'unit'
        }
    )

    switch ($Depth) {
        'balanced' {
            $tests += [pscustomobject]@{
                Path = 'Test/Pester/MissingInProject.DevMode.NoLabVIEW.Integration.Tests.ps1'
                Kind = 'integration'
            }
            $tests += [pscustomobject]@{
                Path = 'Test/Pester/LUnit.DevMode.NoLabVIEW.Integration.Tests.ps1'
                Kind = 'integration'
            }
            break
        }
        'full' {
            $tests += [pscustomobject]@{
                Path = 'Test/Pester/MissingInProject.DevMode.NoLabVIEW.Integration.Tests.ps1'
                Kind = 'integration'
            }
            $tests += [pscustomobject]@{
                Path = 'Test/Pester/LUnit.DevMode.NoLabVIEW.Integration.Tests.ps1'
                Kind = 'integration'
            }
            $tests += [pscustomobject]@{
                Path = 'Test/Pester/VerifyIEPaths.DevMode.Integration.Tests.ps1'
                Kind = 'integration'
            }
            $tests += [pscustomobject]@{
                Path = 'Test/Pester/BuildLvlibp.DevMode.NoLabVIEW.Integration.Tests.ps1'
                Kind = 'integration'
            }
            break
        }
        default {
            break
        }
    }

    return [pscustomobject]@{
        Depth = $Depth
        Tests = @($tests)
    }
}

function Test-DevModeNoLabVIEWSmokeCoverage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$PesterResult,

        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$Suite
    )

    $repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..\..')).Path

    $suiteTests = @()
    if ($Suite -and $Suite.PSObject.Properties.Name -contains 'Tests') {
        $suiteTests = @($Suite.Tests)
    } elseif ($Suite -is [System.Collections.IEnumerable]) {
        $suiteTests = @($Suite)
    }

    $integrationTests = @(
        $suiteTests |
            Where-Object {
                $_ -and
                $_.PSObject.Properties.Name -contains 'Kind' -and
                $_.Kind -eq 'integration'
            }
    )

    $pesterTests = @()
    if ($PesterResult -and $PesterResult.PSObject.Properties.Name -contains 'Tests') {
        $pesterTests = @($PesterResult.Tests)
    }

    $messages = New-Object System.Collections.Generic.List[string]
    $details = @()
    $passed = $true

    foreach ($integration in $integrationTests) {
        $expectedPath = [System.IO.Path]::GetFullPath((Join-Path -Path $repoRoot -ChildPath $integration.Path))
        $matchingTests = @(
            $pesterTests |
                Where-Object {
                    $filePath = $null
                    if ($_.PSObject.Properties.Name -contains 'ScriptBlock' -and $_.ScriptBlock) {
                        if ($_.ScriptBlock.PSObject.Properties.Name -contains 'File') {
                            $filePath = $_.ScriptBlock.File
                        }
                    }

                    if ([string]::IsNullOrWhiteSpace($filePath)) {
                        return $false
                    }

                    try {
                        $candidatePath = [System.IO.Path]::GetFullPath($filePath)
                        return $candidatePath.Equals($expectedPath, [System.StringComparison]::OrdinalIgnoreCase)
                    } catch {
                        return $false
                    }
                }
        )

        $executedTests = @(
            $matchingTests |
                Where-Object {
                    $resultName = if ($_.PSObject.Properties.Name -contains 'Result') { [string]$_.Result } else { '' }
                    -not [string]::IsNullOrWhiteSpace($resultName) -and $resultName -notin @('Skipped', 'NotRun', 'Inconclusive')
                }
        )

        $detail = [pscustomobject]@{
            Path          = $integration.Path
            TotalTests    = $matchingTests.Count
            ExecutedTests = $executedTests.Count
        }
        $details += $detail

        if ($matchingTests.Count -eq 0) {
            $passed = $false
            $messages.Add(("Integration smoke produced no test results: {0}" -f $integration.Path))
            continue
        }

        if ($executedTests.Count -eq 0) {
            $passed = $false
            $messages.Add(("Integration smoke was fully skipped: {0}" -f $integration.Path))
        }
    }

    return [pscustomobject]@{
        Passed   = $passed
        Messages = @($messages)
        Details  = @($details)
    }
}

function Get-GitStatusLinesForPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot,

        [Parameter(Mandatory = $true)]
        [string]$ProjectRelativePath
    )

    $git = Get-Command git -ErrorAction SilentlyContinue
    if (-not $git) {
        throw "git is required to validate '$ProjectRelativePath' clean state."
    }

    $rawOutput = & $git.Source -C $RepoRoot status --porcelain -- $ProjectRelativePath 2>&1
    if ($LASTEXITCODE -ne 0) {
        $message = ($rawOutput | ForEach-Object { [string]$_ }) -join ' '
        throw ("Unable to check git status for '{0}': {1}" -f $ProjectRelativePath, $message.Trim())
    }

    $lines = @(
        $rawOutput |
            ForEach-Object { [string]$_ } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
    return $lines
}

function Test-ProjectFileCleanFromStatusLines {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string[]]$StatusLines
    )

    if (-not $StatusLines -or $StatusLines.Count -eq 0) {
        return $true
    }

    foreach ($line in $StatusLines) {
        if (-not [string]::IsNullOrWhiteSpace([string]$line)) {
            return $false
        }
    }

    return $true
}

function Assert-DevModeNoLabVIEWProjectFileClean {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot,

        [Parameter(Mandatory = $false)]
        [string]$ProjectRelativePath = 'lv_icon_editor.lvproj',

        [AllowNull()]
        [string[]]$StatusLines
    )

    $lines = if ($PSBoundParameters.ContainsKey('StatusLines')) {
        @($StatusLines)
    } else {
        Get-GitStatusLinesForPath -RepoRoot $RepoRoot -ProjectRelativePath $ProjectRelativePath
    }

    if (-not (Test-ProjectFileCleanFromStatusLines -StatusLines $lines)) {
        throw "'$ProjectRelativePath' must be clean before smoke/parity. Clear it, then rerun."
    }
}
