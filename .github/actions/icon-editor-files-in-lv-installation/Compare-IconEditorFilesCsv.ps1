#Requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$BeforeCsv,

    [Parameter(Mandatory)]
    [string]$AfterCsv,

    [Parameter(Mandatory)]
    [string]$RepoRoot,

    [switch]$IncludeGitMetadata,

    [string]$SummaryTitle = 'Icon Editor Files Diff',

    [string]$WorktreeRoot,

    [switch]$SkipWorktreeRootCheck
)

$ErrorActionPreference = 'Stop'

$headers = @('File Path', 'Bytes', 'Last modified')

function Ensure-SummaryFile {
    param(
        [string]$SummaryPath
    )

    if ([string]::IsNullOrWhiteSpace($SummaryPath)) {
        return $false
    }

    if (-not (Test-Path -Path $SummaryPath)) {
        $null = New-Item -ItemType File -Path $SummaryPath -Force
    }

    return $true
}

function Import-IconEditorCsv {
    param(
        [string]$Path
    )

    $firstLine = Get-Content -Path $Path -TotalCount 1
    $headerLine = ($headers -join ',')
    $headerQuoted = '"' + ($headers -join '","') + '"'
    $hasHeader = ($firstLine -eq $headerLine) -or ($firstLine -eq $headerQuoted)

    if ($hasHeader) {
        return (Import-Csv -Path $Path)
    }

    return (Import-Csv -Path $Path -Header $headers)
}

function Resolve-RepoRoot {
    param(
        [string]$PathOverride
    )

    if ([string]::IsNullOrWhiteSpace($PathOverride)) {
        throw "RepoRoot is required."
    }

    if (-not (Test-Path -Path $PathOverride)) {
        throw "RepoRoot does not exist: $PathOverride"
    }

    return (Resolve-Path -Path $PathOverride).Path
}

function Get-RepoRelativePath {
    param(
        [string]$RepoRoot,
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($RepoRoot) -or [string]::IsNullOrWhiteSpace($Path)) {
        return $null
    }

    try {
        $repoFull = [System.IO.Path]::GetFullPath($RepoRoot)
        $separator = [System.IO.Path]::DirectorySeparatorChar
        if (-not $repoFull.EndsWith($separator)) {
            $repoFull += $separator
        }

        $fileFull = if ([System.IO.Path]::IsPathRooted($Path)) {
            [System.IO.Path]::GetFullPath($Path)
        } else {
            [System.IO.Path]::GetFullPath((Join-Path $repoFull $Path))
        }

        if ($fileFull.StartsWith($repoFull, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $fileFull.Substring($repoFull.Length)
        }
    }
    catch {
        return $null
    }

    return $null
}

function Get-GitMetadata {
    param(
        [string]$RepoRoot,
        [string]$RelativePath
    )

    if (-not $script:GitEnabled -or [string]::IsNullOrWhiteSpace($RelativePath)) {
        return $null
    }

    if ($script:GitMetadataCache.ContainsKey($RelativePath)) {
        return $script:GitMetadataCache[$RelativePath]
    }

    $meta = $null
    try {
        $output = & git -C $RepoRoot log -1 --format="%H`t%an`t%ad" --date=iso-strict -- $RelativePath 2>$null
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($output)) {
            $parts = $output -split "`t", 3
            if ($parts.Count -ge 3) {
                $meta = [pscustomobject]@{
                    'Commit SHA'    = $parts[0]
                    'Commit Author' = $parts[1]
                    'Commit Date'   = $parts[2]
                }
            }
        }
    }
    catch {
        $meta = $null
    }

    $script:GitMetadataCache[$RelativePath] = $meta
    return $meta
}

function Add-GitMetadataToRow {
    param(
        [object]$Row,
        [string]$FilePath
    )

    if (-not $script:GitEnabled) {
        return $Row
    }

    $repoRelative = Get-RepoRelativePath -RepoRoot $script:RepoRootResolved -Path $FilePath
    if (-not $repoRelative) {
        return $Row
    }

    $Row | Add-Member -NotePropertyName 'Repo Path' -NotePropertyValue $repoRelative -Force
    $meta = Get-GitMetadata -RepoRoot $script:RepoRootResolved -RelativePath $repoRelative
    if ($meta) {
        $Row | Add-Member -NotePropertyName 'Commit SHA' -NotePropertyValue $meta.'Commit SHA' -Force
        $Row | Add-Member -NotePropertyName 'Commit Author' -NotePropertyValue $meta.'Commit Author' -Force
        $Row | Add-Member -NotePropertyName 'Commit Date' -NotePropertyValue $meta.'Commit Date' -Force
    }

    return $Row
}

function Escape-Markdown {
    param(
        [string]$Value
    )

    if ($null -eq $Value) {
        return ''
    }

    return ($Value -replace '\|', '\\|')
}

function Write-TableSection {
    param(
        [string]$SummaryPath,
        [string]$Title,
        [string[]]$Columns,
        [object[]]$Rows
    )

    $rowList = @($Rows)
    Add-Content -Path $SummaryPath -Value ("#### {0} ({1})" -f $Title, $rowList.Count)

    if ($rowList.Count -eq 0) {
        Add-Content -Path $SummaryPath -Value ""
        Add-Content -Path $SummaryPath -Value "None"
        Add-Content -Path $SummaryPath -Value ""
        return
    }

    Add-Content -Path $SummaryPath -Value "<details>"
    Add-Content -Path $SummaryPath -Value "<summary>Show details</summary>"
    Add-Content -Path $SummaryPath -Value ""

    $headerRow = '| ' + ($Columns -join ' | ') + ' |'
    $separator = '| ' + (($Columns | ForEach-Object { '---' }) -join ' | ') + ' |'

    Add-Content -Path $SummaryPath -Value $headerRow
    Add-Content -Path $SummaryPath -Value $separator

    foreach ($row in $rowList) {
        $values = foreach ($column in $Columns) {
            Escape-Markdown -Value ($row.$column)
        }
        Add-Content -Path $SummaryPath -Value ('| ' + ($values -join ' | ') + ' |')
    }

    Add-Content -Path $SummaryPath -Value ""
    Add-Content -Path $SummaryPath -Value "</details>"
    Add-Content -Path $SummaryPath -Value ""
}

$summaryPath = $env:GITHUB_STEP_SUMMARY
if (-not (Ensure-SummaryFile -SummaryPath $summaryPath)) {
    return
}

$repoRootResolved = Resolve-RepoRoot -PathOverride $RepoRoot
$preflightScript = Join-Path $repoRootResolved 'Tooling\Invoke-Preflight.ps1'
if (Test-Path -Path $preflightScript) {
    . $preflightScript
    $scriptArgs = Convert-BoundParametersToArgs -BoundParameters $PSBoundParameters
    $relativeScript = if ($PSCommandPath) { Get-RepoRelativePath -RepoRoot $repoRootResolved -Path $PSCommandPath } else { $null }
    $preflight = Invoke-Preflight `
        -RepoRoot $repoRootResolved `
        -WorktreeRoot $WorktreeRoot `
        -LabVIEWVersion '' `
        -LabVIEWBitness '' `
        -SkipWorktreeRootCheck:$SkipWorktreeRootCheck `
        -AutoWorktree:$false `
        -ScriptPath $relativeScript `
        -ScriptArguments $scriptArgs
    if ($preflight.Reinvoked) {
        return
    }
    $repoRootResolved = $preflight.RepoRoot
}
$script:RepoRootResolved = $null
$script:GitEnabled = $false
$script:GitMetadataCache = @{}
$gitColumns = @()

if ($IncludeGitMetadata) {
    if ($repoRootResolved -and (Get-Command git -ErrorAction SilentlyContinue)) {
        $insideRepo = & git -C $repoRootResolved rev-parse --is-inside-work-tree 2>$null
        if ($LASTEXITCODE -eq 0 -and $insideRepo -eq 'true') {
            $script:GitEnabled = $true
            $script:RepoRootResolved = $repoRootResolved
            $gitColumns = @('Repo Path', 'Commit SHA', 'Commit Author', 'Commit Date')
        }
    }
}

if (-not (Test-Path -Path $BeforeCsv)) {
    Add-Content -Path $summaryPath -Value ("### {0}" -f $SummaryTitle)
    Add-Content -Path $summaryPath -Value ("Before CSV not found: {0}" -f $BeforeCsv)
    Add-Content -Path $summaryPath -Value ""
    return
}

if (-not (Test-Path -Path $AfterCsv)) {
    Add-Content -Path $summaryPath -Value ("### {0}" -f $SummaryTitle)
    Add-Content -Path $summaryPath -Value ("After CSV not found: {0}" -f $AfterCsv)
    Add-Content -Path $summaryPath -Value ""
    return
}

$beforeRows = Import-IconEditorCsv -Path $BeforeCsv
$afterRows = Import-IconEditorCsv -Path $AfterCsv

if (-not $beforeRows -or -not $afterRows) {
    Add-Content -Path $summaryPath -Value ("### {0}" -f $SummaryTitle)
    Add-Content -Path $summaryPath -Value "One or both CSV files were empty."
    Add-Content -Path $summaryPath -Value ""
    return
}

$beforeMap = @{}
foreach ($row in $beforeRows) {
    $path = $row.'File Path'
    if (-not [string]::IsNullOrWhiteSpace($path)) {
        $beforeMap[$path] = $row
    }
}

$afterMap = @{}
foreach ($row in $afterRows) {
    $path = $row.'File Path'
    if (-not [string]::IsNullOrWhiteSpace($path)) {
        $afterMap[$path] = $row
    }
}

$added = @()
$removed = @()
$modified = @()

foreach ($path in $afterMap.Keys) {
    if (-not $beforeMap.ContainsKey($path)) {
        $row = $afterMap[$path]
        $added += (Add-GitMetadataToRow -Row $row -FilePath $path)
    }
}

foreach ($path in $beforeMap.Keys) {
    if (-not $afterMap.ContainsKey($path)) {
        $row = $beforeMap[$path]
        $removed += (Add-GitMetadataToRow -Row $row -FilePath $path)
    }
}

foreach ($path in $beforeMap.Keys) {
    if (-not $afterMap.ContainsKey($path)) {
        continue
    }

    $beforeRow = $beforeMap[$path]
    $afterRow = $afterMap[$path]

    if (($beforeRow.Bytes -ne $afterRow.Bytes) -or
        ($beforeRow.'Last modified' -ne $afterRow.'Last modified')) {
        $row = [pscustomobject]@{
            'File Path'            = $path
            'Before Bytes'         = $beforeRow.Bytes
            'After Bytes'          = $afterRow.Bytes
            'Before Last modified' = $beforeRow.'Last modified'
            'After Last modified'  = $afterRow.'Last modified'
        }

        $modified += (Add-GitMetadataToRow -Row $row -FilePath $path)
    }
}

$added = @($added | Sort-Object -Property 'File Path')
$removed = @($removed | Sort-Object -Property 'File Path')
$modified = @($modified | Sort-Object -Property 'File Path')

Add-Content -Path $summaryPath -Value ("### {0}" -f $SummaryTitle)
Add-Content -Path $summaryPath -Value ("Added: {0} | Removed: {1} | Modified: {2}" -f $added.Count, $removed.Count, $modified.Count)
Add-Content -Path $summaryPath -Value ""

$addedColumns = @($headers)
$removedColumns = @($headers)
if ($gitColumns.Count -gt 0) {
    $addedColumns += $gitColumns
    $removedColumns += $gitColumns
}

Write-TableSection -SummaryPath $summaryPath -Title 'Added' -Columns $addedColumns -Rows $added
Write-TableSection -SummaryPath $summaryPath -Title 'Removed' -Columns $removedColumns -Rows $removed
$modifiedColumns = @('File Path', 'Before Bytes', 'After Bytes', 'Before Last modified', 'After Last modified')
if ($gitColumns.Count -gt 0) {
    $modifiedColumns += $gitColumns
}

Write-TableSection -SummaryPath $summaryPath -Title 'Modified' -Columns $modifiedColumns -Rows $modified
