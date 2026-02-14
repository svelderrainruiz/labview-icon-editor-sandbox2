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
| **Windows runner** | LabVIEW + VIPM CLI flow is validated on Windows runners. |
| **LabVIEW version matching `.lvversion`** | `labview_version` must match `.lvversion` (year+minor contract). |
| **VIPM CLI (`vipm`) in `PATH`** | Authoritative installer path for `.vipc` application and dependency audit. |
| **PowerShell 7** | Composite steps use PowerShell Core (`pwsh`). |

---

## Inputs
| Name | Required | Example | Description |
|------|----------|---------|-------------|
| `labview_version` | No | `2021` | LabVIEW *major* version that the repo supports. Defaults to `.lvversion` when omitted. |
| `supported_bitness` | **Yes** | `32` or `64` | LabVIEW bitness to target. |
| `repo_root` | **Yes** | `${{ github.workspace }}` | Root path of the repository on disk. |
| `vipc_path` | **Yes** | `Tooling/deployment/runner_dependencies.vipc` | Path (relative to `repo_root`) of the VI Package Configuration to apply. |
| `allow_vipc_target_mismatch` | No | `false` | Temporary migration override for VIPC target mismatch. |
| `vipm_timeout_seconds` | No | `1800` | Timeout for each VIPM command. |
| `vipm_max_attempts` | No | `3` | Retry attempts on VIPM lock contention. |
| `vipm_retry_delay_seconds` | No | `5` | Delay between retries. |

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
      vipc_path: Tooling/deployment/runner_dependencies.vipc
```

---

## How it works
1. **Checkout** – pulls the repository to ensure scripts and the `.vipc` file are present.
2. **PowerShell wrapper** – executes `ApplyVIPC.ps1` with the provided inputs.
3. **VIPM CLI invocation** – `ApplyVIPC.ps1` runs `vipm install` with resolved LabVIEW year+bitness.
4. **Failure propagation** – any error in path resolution, VIPM CLI execution, or the script causes the step (and job) to fail.

---

## Troubleshooting
| Symptom | Hint |
|---------|------|
| *vipm executable not found* | Ensure VIPM CLI is installed and on `PATH`. |
| *`.vipc` file not found* | Check `repo_root` and `vipc_path` values. |
| *LabVIEW version mismatch* | Ensure `labview_version` and `.lvversion` are aligned (year + minor revision). |

---

## License
This directory inherits the root repository’s license (MIT, unless otherwise noted).
