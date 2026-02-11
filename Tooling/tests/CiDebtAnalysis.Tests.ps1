#Requires -Version 7.0
#Requires -Modules Pester

BeforeAll {
    $Script:ToolingRoot = Split-Path -Parent $PSScriptRoot
    $Script:AnalysisScript = Join-Path $Script:ToolingRoot 'agents/ci-debt/Invoke-CiDebtAnalysis.ps1'
    $Script:FixturePath = Join-Path $Script:ToolingRoot 'agents/ci-debt/fixtures/run-21840801109.json'

    . $Script:AnalysisScript
}

Describe 'Invoke-CiDebtAnalysis' {
    It 'maps fixture run 21840801109 to known signatures' {
        $outJson = Join-Path $TestDrive 'analysis.json'
        $outMarkdown = Join-Path $TestDrive 'analysis.md'

        $result = Invoke-CiDebtAnalysis `
            -Repo 'example/labview-icon-editor' `
            -RunId 21840801109 `
            -FixturePath $Script:FixturePath `
            -OutJson $outJson `
            -OutMarkdown $outMarkdown

        $result.IncidentCount | Should -Be 4
        $result.UnknownIncidentCount | Should -Be 0
        $outJson | Should -Exist
        $outMarkdown | Should -Exist

        $analysis = Get-Content -Path $outJson -Raw | ConvertFrom-Json
        $incidentIds = @($analysis.incidents | ForEach-Object { $_.id })
        $incidentIds | Should -Contain 'powershell-lint.git-missing'
        $incidentIds | Should -Contain 'verify-iepaths.setup-failed'
        $incidentIds | Should -Contain 'pipeline-contract.cascade-failure'
        $analysis.unknown_incident_count | Should -Be 0
    }

    It 'fails when unknown incidents exist and FailOnUnknown is set' {
        $unknownFixture = Join-Path $TestDrive 'unknown-fixture.json'
        @'
{
  "run": {
    "databaseId": 123456,
    "workflowName": "CI Pipeline (Composite)",
    "url": "https://example.invalid/run/123456",
    "status": "completed",
    "conclusion": "failure",
    "event": "pull_request",
    "headBranch": "feature/x",
    "headSha": "abc"
  },
  "jobs": [
    {
      "databaseId": 101,
      "name": "Custom Failure Job",
      "status": "completed",
      "conclusion": "failure",
      "log": "This is a new failure pattern not covered by signatures."
    }
  ]
}
'@ | Out-File -FilePath $unknownFixture -Encoding utf8

        $outJson = Join-Path $TestDrive 'analysis-unknown.json'
        $outMarkdown = Join-Path $TestDrive 'analysis-unknown.md'

        {
            Invoke-CiDebtAnalysis `
                -Repo 'example/labview-icon-editor' `
                -RunId 123456 `
                -FixturePath $unknownFixture `
                -OutJson $outJson `
                -OutMarkdown $outMarkdown `
                -FailOnUnknown
        } | Should -Throw '*Unknown CI debt incidents detected*'
    }
}
