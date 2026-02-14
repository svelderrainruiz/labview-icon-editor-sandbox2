# VIPM CLI Tool Contracts (Machine-Validated)

## Shared Global Pattern
Use LabVIEW year and bitness consistently when applicable:
- `vipm --labview-version <YYYY> --labview-bitness <32|64> <command> ...`

`.lvversion` is the source of truth for default year resolution in helper flows.

Use `vipm help <command>` for authoritative syntax checks before composing run-mode commands.

Helper preflight contract:
- `vipm` must be available on `PATH`.
- command timeout defaults to `120` seconds (`LVIE_VIPM_COMMAND_TIMEOUT_SECONDS` override).

## Command Forms
- About:
  - `vipm about`
- Version:
  - `vipm version`
- Search:
  - `vipm search <query>`
- List installed:
  - `vipm list --installed`
- Build project spec/package artifacts:
  - `vipm build <path-to-.lvproj-or-.vipb>`
- Install package(s)/VIPC/Dragon:
  - `vipm install <package|.vip|.ogp|.vipc|.dragon> [...]`
- Uninstall package(s):
  - `vipm uninstall <package> [...]`

## Helper Probe Behavior
`scripts/Invoke-VipmCliToolProbe.ps1` uses deterministic probe commands:
- `build` probe uses missing `.vipb` path to force safe expected failure.
- `install` probe uses missing `.vipc` path to force safe expected failure.
- `uninstall` probe uses missing package token to force safe expected failure.

Expected probe classes:
- `probe-pass`
- `probe-expected-failure`
- `probe-fail`
- `probe-unexpected-success`

Lock contention behavior:
- If VIPM reports another operation lock timeout (`global lock acquisition`) during non-state probe commands, helper classifies it as `probe-expected-failure`.

Timeout behavior:
- If a command exceeds timeout, helper kills the process and records `timed_out=true`.
- Timeout classification:
  - `probe`: `probe-fail`
  - `run`: `run-failure`

## Version Normalization
Accepted inputs:
- Year: `2026`
- Numeric major: `26.0`

Normalization:
- `26.0` -> `2026`
