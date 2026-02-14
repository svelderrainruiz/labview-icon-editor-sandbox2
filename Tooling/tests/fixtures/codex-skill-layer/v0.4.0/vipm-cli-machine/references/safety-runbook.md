# Safety Runbook (VIPM CLI)

## Safety Policy
Treat these as state-changing commands:
- `vipm build`
- `vipm install`
- `vipm uninstall`

In helper `run` mode, state-changing commands require `-AllowStateChange`.
In helper `run` mode with `-Tool all`, helper fails fast before execution unless `-AllowStateChange` is present.

## Process Wait Gate
Unless `-SkipProcessWait` is provided, helper waits for active `vipm`/`LabVIEW` processes before execution.
Command execution timeout defaults to `120` seconds and can be overridden with `-CommandTimeoutSeconds`.

## Out-of-Scope in v1
- `vipm activate`
  - excluded to avoid license state mutations.

## Failure Handling
1. Capture command, exit code, stdout/stderr previews, and first failure line.
   - capture `timed_out` when command exceeds timeout and is terminated.
2. Persist JSON contract output.
3. In probe mode:
  - allow `probe-expected-failure`
  - fail on `probe-fail` or `probe-unexpected-success`
  - treat VIPM lock contention timeout (`global lock acquisition`) as expected failure for non-state probes
4. In run mode:
  - fail on any `run-failure`

## Operational Guidance
- Use probe mode first for unknown environments.
- Use explicit `-LabVIEWVersion` for deterministic reproductions.
- Keep state-changing runs scoped and auditable.
