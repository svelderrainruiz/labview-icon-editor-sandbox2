---
name: vipm-cli-machine
description: Use installed VIPM CLI on this Windows machine with safe-first probe and run workflows, .lvversion-aware LabVIEW version defaults, and deterministic JSON result capture. Trigger this skill when requests involve vipm build/install/uninstall/list/search/version/about, VIPC apply from CLI, package state diagnostics, or validating VIPM behavior before CI/release operations.
---

# VIPM CLI Machine

## Scope
- Cover only `vipm` command-line operations on this machine.
- Prefer helper-driven execution through `scripts/Invoke-VipmCliToolProbe.ps1`.
- Keep `activate` out of scope in v1 to avoid licensing mutations.

## Quick Start
- Validate environment:
  - `vipm --version`
- Safe probe of non-state commands:
  - `pwsh -NoProfile -File .\scripts\Invoke-VipmCliToolProbe.ps1 -Tool version -Mode probe`
  - `pwsh -NoProfile -File .\scripts\Invoke-VipmCliToolProbe.ps1 -Tool list -Mode probe`
- Safe probe of state-changing path using expected failure:
  - `pwsh -NoProfile -File .\scripts\Invoke-VipmCliToolProbe.ps1 -Tool build -Mode probe`

## Preflight
- Confirm CLI availability: `vipm --version`.
- Resolve LabVIEW year from:
  - explicit `-LabVIEWVersion`
  - `LVIE_VIPM_LABVIEW_VERSION`
  - nearest `.lvversion` from current directory upward
- Resolve bitness from:
  - explicit `-Bitness`
  - `LVIE_VIPM_LABVIEW_BITNESS`
  - fallback `64`
- Apply wait gate for running `vipm`/`LabVIEW` processes unless `-SkipProcessWait` is set.

## Workflow Decision Tree
1. Determine intent:
  - `probe` for validation/diagnostics.
  - `run` for real state mutation.
2. Determine tool class:
  - non-state tools: `about`, `version`, `search`, `list`
  - state-changing tools: `build`, `install`, `uninstall`
3. Apply safety gate:
  - If `run` + state-changing, require `-AllowStateChange`.
  - If `run` + `-Tool all`, helper fails fast unless `-AllowStateChange` is present.
4. Execute helper and inspect `result_class`.

## Execution Workflow
1. Choose `-Mode probe|run` and `-Tool`.
2. Resolve version/bitness deterministically.
3. Enforce safety policy:
  - `build`, `install`, `uninstall` are state-changing.
  - In `run` mode, state-changing tools require `-AllowStateChange`.
4. Execute command and capture stdout/stderr/exit code.
5. Classify result (`probe-pass`, `probe-expected-failure`, `probe-fail`, `run-success`, `run-failure`, `probe-unexpected-success`).
6. Write JSON result (`./TestResults/agent-logs/vipm-cli-machine.latest.json` by default).

## Helper Interface
Use `scripts/Invoke-VipmCliToolProbe.ps1`.

### Parameters
- `-Tool about|version|search|list|build|install|uninstall|all`
- `-Mode probe|run` (default `probe`)
- `-LabVIEWVersion <year-or-numeric>`
- `-Bitness 32|64` (default `64`)
- `-AllowStateChange`
- `-JsonOutputPath <path>`
- `-WaitTimeoutSeconds <int>` (default `40`)
- `-WaitPollSeconds <int>` (default `2`)
- `-SkipProcessWait`
- `-CommandTimeoutSeconds <int>` (default `120`)

### Environment Fallbacks
- `LVIE_VIPM_LABVIEW_VERSION`
- `LVIE_VIPM_LABVIEW_BITNESS`
- `LVIE_VIPM_JSON_OUTPUT_PATH`
- `LVIE_VIPM_WAIT_TIMEOUT_SECONDS`
- `LVIE_VIPM_WAIT_POLL_SECONDS`
- `LVIE_VIPM_COMMAND_TIMEOUT_SECONDS`

### JSON Contract Highlights
- Per-run required fields include:
  - `timestamp_utc`, `tool`, `mode`, `resolved_labview_year`, `resolved_bitness`
  - `command`, `exit_code`, `result_class`, `stdout_preview`, `stderr_preview`
  - `timed_out`, `state_change_allowed`, `failure_message`
- Payload-level fields include:
  - `command_timeout_seconds`, `run_count`, `failure_count`, `state_changing_requested`

## References
- Read `references/tool-contracts.md` when selecting exact command forms and interpreting probe class outcomes.
- Read `references/safety-runbook.md` before any `run` operation or when a probe classification is unexpected.
- Read `references/machine-inventory.md` when troubleshooting environment drift or confirming installed baseline versions.
