# Belt-and-Suspenders Runbook

## Recommended command pattern
```powershell
pwsh -NoProfile -File .\Tooling\Invoke-BeltAndSuspendersCI.ps1 \
  -MaxLocalAttempts 5
```

## PPL-focused local mode (default)
- Success target: `ppl`
- Skips: Verify IE Paths, MissingInProject, BuildVip

## Failure triage
- Capture local logs under `TestResults/agent-logs`.
- Capture remote run id/url from status JSON.
- Run CI debt analysis for non-success remote runs.
