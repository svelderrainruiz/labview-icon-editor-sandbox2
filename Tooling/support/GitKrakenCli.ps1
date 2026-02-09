#Requires -Version 7.0
<##
.SYNOPSIS
    Enables GitKraken CLI-backed git usage for tooling.

.DESCRIPTION
    Prepends a git shim directory to PATH so git invocations route through
    GitKraken CLI (gk). Use -Require to fail fast when gk is missing.

.PARAMETER Require
    Fail if gk is not available on PATH.
#>
[CmdletBinding()]
param(
    [switch]$Require
)

$ErrorActionPreference = 'Stop'

function Enable-GitKrakenGitShim {
    param([switch]$Require)

    $gk = Get-Command gk -ErrorAction SilentlyContinue
    if (-not $gk) {
        if ($Require) {
            throw "GitKraken CLI 'gk' not found. Install it or add it to PATH."
        }
        return $false
    }

    $shimDir = $PSScriptRoot
    if ([string]::IsNullOrWhiteSpace($env:PATH)) {
        $env:PATH = $shimDir
    } elseif ($env:PATH -notlike "${shimDir}*") {
        $env:PATH = "$shimDir;$env:PATH"
    }

    return $true
}

if ($Require.IsPresent) {
    Enable-GitKrakenGitShim -Require | Out-Null
}
