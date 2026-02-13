# Apply VIPC Dependencies 📦

Ensure a runner has all required LabVIEW packages installed before building or testing. This composite action calls **`ApplyVIPC.ps1`** to apply a `.vipc` **VI Package Configuration** through **VIPM CLI**.

---

## Table of Contents
1. [Prerequisites](#prerequisites)
2. [Inputs](#inputs)
3. [Quick-start](#quick-start)
4. [How it works](#how-it-works)
5. [Troubleshooting](#troubleshooting)
6. [License](#license)

---

## Prerequisites
| Requirement | Notes |
|-------------|-------|
| **Windows runner** | LabVIEW and VIPM CLI are Windows only. |
| **LabVIEW matching `.lvversion`** | `ApplyVIPC.ps1` resolves version from `.lvversion` by default and hard-fails on VIPC target mismatches. |
| **vipm** in `PATH` | Used to apply the `.vipc` configuration. |
| **PowerShell 7** | Composite steps use PowerShell Core (`pwsh`). |

---

## Inputs
| Name | Required | Example | Description |
|------|----------|---------|-------------|
| `labview_version` | No | `2026` | LabVIEW *major* version that the repo supports. Defaults to `.lvversion` when omitted. |
| `supported_bitness` | **Yes** | `32` or `64` | LabVIEW bitness to target. |
| `repo_root` | **Yes** | `${{ github.workspace }}` | Root path of the repository on disk. |
| `vipc_path` | **Yes** | `.github/actions/apply-vipc/runner_dependencies.vipc` | Path (relative to `repo_root`) of the VI Package Configuration to apply. |
| `vipm_timeout_seconds` | No | `600` | Timeout per VIPM CLI command attempt. |
| `vipm_max_attempts` | No | `3` | Max retries for lock-contention retry flow. |
| `vipm_retry_delay_seconds` | No | `5` | Delay between VIPM lock-contention retries. |

---

## Quick-start
```yaml
# .github/workflows/ci-composite.yml (excerpt)
steps:
  - uses: actions/checkout@v4
  - name: Install LabVIEW dependencies
    uses: ./.github/actions/apply-vipc
    with:
      supported_bitness: 64
      repo_root: ${{ github.workspace }}
      vipc_path: .github/actions/apply-vipc/runner_dependencies.vipc
```

---

## How it works
1. **Checkout** – pulls the repository to ensure scripts and the `.vipc` file are present.
2. **PowerShell wrapper** – executes `ApplyVIPC.ps1` with the provided inputs.
3. **VIPM CLI invocation** – `ApplyVIPC.ps1` launches `vipm install` with `.lvversion`-resolved LabVIEW year/bitness.
4. **Retry on lock contention** – command retries on VIPM global lock-acquisition contention.
5. **Strict target guard** – the `.vipc` target numeric version must exactly match `.lvversion`; mismatches fail before install.
6. **Failure propagation** – any error in path resolution, VIPM CLI, or script guards causes the step (and job) to fail.

---

## Troubleshooting
| Symptom | Hint |
|---------|------|
| *vipm executable not found* | Ensure VIPM CLI is installed and on `PATH`. |
| *`.vipc` file not found* | Check `repo_root` and `vipc_path` values. |
| *LabVIEW version mismatch* | Regenerate the VIPC file target metadata to match `.lvversion`; strict target-version contract blocks execution on mismatch. |

---

## License
This directory inherits the root repository’s license (MIT, unless otherwise noted).
