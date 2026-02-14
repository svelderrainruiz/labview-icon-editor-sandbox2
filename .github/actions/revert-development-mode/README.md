# Revert Development Mode 🔄

Invoke **`RevertDevelopmentMode.ps1`** to restore packaged sources after development work.

## Inputs
| Name | Required | Example | Description |
|------|----------|---------|-------------|
| `labview_version` | **Yes** | `2021` | LabVIEW version (year or numeric). |
| `supported_bitness` | **Yes** | `64` | LabVIEW bitness (32 or 64). |
| `repo_root` | No | `${{ github.workspace }}` | Repository root path (optional). |
| `use_labview` | No | `false` | Use LabVIEW + g-cli instead of the no-LabVIEW path. |

## Quick-start
```yaml
- uses: ./.github/actions/revert-development-mode
  with:
    labview_version: 2021
    supported_bitness: 64
    repo_root: ${{ github.workspace }}
    use_labview: false
```

## License
This directory inherits the root repository’s license (MIT, unless otherwise noted).
