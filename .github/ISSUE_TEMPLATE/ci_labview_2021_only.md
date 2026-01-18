---
name: CI: LabVIEW 2021-only (21.0)
about: Remove LabVIEW 2023 usage and harden CI to rely only on LabVIEW 2021 (21.0).
title: "CI: LabVIEW 2021-only (21.0) pipeline hardening"
labels: ["Enhancement"]
---

## Summary

Update `.github/workflows/ci-composite.yml` (and a small set of supporting composite actions) so CI relies only on **LabVIEW 2021 (21.0)**.

This includes:
- Removing any LabVIEW 2023 usage.
- Adding a manual override to force VIPC dependency re-application on a freshly reprovisioned runner.
- Adding traceability artifacts for the VIPC used in CI.
- Enforcing VIPB metadata contracts (including fork-aware `Company_Name` and `Package_File_Name`).
- Removing any g-cli kill-flag usage (graceful-only).

## Decisions / Constraints (confirmed)

- Target LabVIEW: **2021** with minor revision **0** (i.e., **21.0**).
- Keep **x86 coverage** (both x64 and x86 deps/tests/builds remain).
- Runner label `self-hosted-windows-lv` is a **single runner**.
- `workflow_dispatch` only: add `force_apply_vipc` to force VIPC apply for **both** bitness.
- `missing-in-project-*` must do a guaranteed `actions/checkout@v4` (default clean behavior).
- No forced termination: remove the kill flag from preflight and build invocations.
- VIPC traceability must run on **every** workflow run (even if VIPC apply is skipped):
  - Upload both `.vipc` and `.sha256`
  - Artifact retention: **90 days**
- Fork behavior:
  - `Company_Name` must be **fork owner** when repo is a fork; otherwise literal **"NI"**
  - `Package_File_Name` must be fork-owner dependent when repo is a fork (example: `svelderrainruiz_Icon_Editor`)
  - Fork owner sanitization for `Package_File_Name`: **replace any non-alphanumeric character with `_`** (also collapse multiple `_` and trim leading/trailing `_`).
  - `VI_Package_Configuration_File` stays fixed.

## Work Items

### A) Workflow: LabVIEW 2021-only

- [ ] `.github/workflows/ci-composite.yml`: Remove `apply-deps-2023-x64` job and all dependencies that require it.
- [ ] `.github/workflows/ci-composite.yml`: Rename `close-lv-2021-before-2023` to `close-lv-2021-after-deps` and update `needs:` links.
- [ ] `.github/workflows/ci-composite.yml`: Ensure `missing-in-project-2021-x64.needs` depends on the 2021 deps chain end (e.g. `close-lv-2021-after-deps`).
- [ ] `.github/workflows/ci-composite.yml`: Update `build-vip` steps:
  - `modify-vipb-display-info`: `minimum_supported_lv_version: 2021`, `labview_minor_revision: 0`
  - `build-vip`: `minimum_supported_lv_version: 2021`, `labview_minor_revision: 0`
  - final `close-labview`: `minimum_supported_lv_version: 2021`

### B) Workflow: Forced VIPC apply (workflow_dispatch only)

- [ ] `.github/workflows/ci-composite.yml`: Add `workflow_dispatch.inputs.force_apply_vipc` (boolean, default `false`).
- [ ] `.github/workflows/ci-composite.yml`: Update both `apply-deps-2021-x64` and `apply-deps-2021-x86` to apply VIPC when:
  - `needs.changes.outputs.vipc == 'true'` OR
  - `(github.event_name == 'workflow_dispatch' && github.event.inputs.force_apply_vipc == 'true')`
- [ ] `.github/workflows/ci-composite.yml`: Add a clear console banner when `force_apply_vipc` is enabled.

### C) Workflow: VIPC traceability (always on)

- [ ] `.github/workflows/ci-composite.yml`: Narrow VIPC change detection filter to only:
  - `.github/actions/apply-vipc/runner_dependencies.vipc`
- [ ] `.github/workflows/ci-composite.yml`: In the `changes` job (Ubuntu), always:
  - compute SHA256 of `.github/actions/apply-vipc/runner_dependencies.vipc`
  - write hash + path to `$GITHUB_STEP_SUMMARY`
  - upload artifact with `retention-days: 90` containing:
    - `.github/actions/apply-vipc/runner_dependencies.vipc`
    - generated `.sha256` file (e.g. `runner_dependencies.vipc.sha256`)

### D) Workflow: Preflight (graceful-only) and missing-in-project checkout

- [ ] `.github/workflows/ci-composite.yml`: Add job `preflight-lv-2021` on `self-hosted-windows-lv` that does graceful quit only for:
  - `2021/64`
  - `2021/32`
  (recommended: reuse `./.github/actions/close-labview`).
- [ ] `.github/workflows/ci-composite.yml`: Gate all self-hosted work behind preflight:
  - add to `apply-deps-2021-x64.needs`
  - add as `needs:` for `version`
- [ ] `.github/workflows/ci-composite.yml`: Add `actions/checkout@v4` (default clean) as the first step in:
  - `missing-in-project-2021-x64`
  - `missing-in-project-2021-x86`

### E) Fork-aware VIPB metadata + assertions

- [ ] `.github/workflows/ci-composite.yml`: Update "Generate display information JSON":
  - `Company Name` should be:
    - fork: `github.repository_owner`
    - not fork: `"NI"`
- [ ] `.github/workflows/ci-composite.yml`: Before VIP build, set VIPB `<Package_File_Name>` based on fork status:
  - fork: `${owner_sanitized}_Icon_Editor`
  - not fork: `NI_Icon_editor`
  - where `owner_sanitized` uses: `[^A-Za-z0-9] -> _`, collapse `_+`, trim `_`.
- [ ] `.github/workflows/ci-composite.yml`: After `modify-vipb-display-info`, add a pwsh assert step that parses `Tooling/deployment/NI Icon editor.vipb` (XML) and fails unless:
  - `Package_LabVIEW_Version == "21.0 (64-bit)"`
  - `Library_Version == "${MAJOR}.${MINOR}.${PATCH}.${BUILD}"` (from `needs.version.outputs.*`)
  - `Company_Name == (fork owner or "NI")`
  - `Package_File_Name == (fork-dependent or "NI_Icon_editor")`
  - `VI_Package_Configuration_File` unchanged (fixed)
  - plus contract checks for `Library_Source_Folder` and `Library_Output_Folder`
  - write actual vs expected into `$GITHUB_STEP_SUMMARY`

## Supporting Action Updates (graceful-only)

- [ ] `.github/actions/build-vip/action.yml`: Remove the kill flag and kill-timeout flag from the preflight g-cli args and ensure “LabVIEW not running” is treated as success (graceful-only).
- [ ] `.github/actions/build-vip/build_vip.ps1`: Remove the kill flag and kill-timeout flag from the `g-cli vipb` invocation args.

## Validation / Acceptance Criteria

- [ ] `rg -n "2023" .github/workflows/ci-composite.yml` returns nothing.
- [ ] No kill flag remains under `.github` (verify with ripgrep).
- [ ] Every run uploads a VIPC traceability artifact containing both `.vipc` and `.sha256` (retention 90 days), and the SHA appears in the job summary.
- [ ] `workflow_dispatch` with `force_apply_vipc: true` applies VIPC for both x64 and x86, even if the VIPC file did not change.
- [ ] `missing-in-project-*` jobs always start with a clean `actions/checkout@v4`.
- [ ] On forks: `Company_Name` equals fork owner, and `Package_File_Name` equals `${sanitized_owner}_Icon_Editor`.
- [ ] On upstream/non-fork: `Company_Name` equals `"NI"`, and `Package_File_Name` equals `NI_Icon_editor`.
