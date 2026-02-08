# LabVIEW Container Parity Lane

This repository includes a hosted parity workflow at `.github/workflows/labview-container-parity.yml`.

## Purpose

- Shift baseline LabVIEWCLI parity checks to hosted runners (`ubuntu-latest`, `windows-latest`).
- Reduce pressure on the Windows self-hosted runner pool for early CI signal.
- Keep parity checks aligned with NI LabVIEW container guidance (`-Headless` with LabVIEWCLI).

## Current Scope

- Linux container image: `nationalinstruments/labview:<release>-linux`
- Windows container image: `nationalinstruments/labview:<release>-windows`
- Always-on operation: `LabVIEWCLI MassCompile` on `Test/Templates`
- Default exclusion: `Polymorphic Template.vi` is excluded from parity MassCompile via `CONTAINER_PARITY_EXCLUDE_FILES` because it is a known headless bad VI in container runs.

The workflow defaults to release tag `2026q1`, and supports override via `workflow_dispatch` input `lv_release`.

## Manual-Only Build-Spec Phase

Build-spec parity is manual-only in this phase and does not run on pull requests by default.

- Manual input: `run_build_spec` (`true` or `false`, default `false`).
- Gate behavior:
  - `workflow_dispatch` with `run_build_spec=true`: runs `ExecuteBuildSpec` for `Editor Packed Library`.
  - `pull_request`: forces build-spec off and runs only MassCompile parity.
- Hard-fail policy: when build-spec is enabled, Linux and Windows lanes must both pass.

Build-spec environment contract used by container scripts:

- `CONTAINER_PARITY_BUILD_SPEC`
- `CONTAINER_PARITY_BUILD_SPEC_NAME`
- `CONTAINER_PARITY_TARGET_NAME`
- `CONTAINER_PARITY_BUILD_OUTPUT_RELATIVE_PATH`

Default build-spec settings:

- Build spec name: `Editor Packed Library`
- Target name: `My Computer`
- Output path: `resource/plugins/lv_icon.lvlibp`

## Artifacts and Logs

Build-spec outputs in this phase are diagnostic-only artifacts (not release inputs):

- `labview-container-editor-packed-library-windows`
- `labview-container-editor-packed-library-linux`

LabVIEWCLI operation logs are captured and uploaded per OS as diagnostics:

- `labview-container-logs-windows`
- `labview-container-logs-linux`

## How To Run

Manual run:

1. Open Actions and run **LabVIEW Container Parity**.
2. Optionally set `lv_release` (for example `2026q1`).
3. Set `run_build_spec=true` only when you want build-spec parity checks.

PR run:

- Triggered automatically when parity workflow/script files, `.lvversion`, `lv_icon_editor.lvproj`, or `Test/Templates` change.
- PR runs execute MassCompile parity only.
