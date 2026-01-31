# Set Development Mode 🔧

Execute **`Set_Development_Mode.ps1`** to prepare the repository for active development.

## Inputs
| Name | Required | Example | Description |
|------|----------|---------|-------------|
| `labview_version` | **Yes** | `2021` | LabVIEW 2021 (21.0) only. |
| `minimum_supported_lv_version` | No | `2021` | Deprecated. Use `labview_version`. |
| `supported_bitness` | No | `64` | LabVIEW bitness (32 or 64). Omit to run both. |
| `repo_root` | No | `${{ github.workspace }}` | Repository root path (optional). |

## Quick-start
```yaml
- uses: ./.github/actions/set-development-mode
  with:
    labview_version: 2021
    supported_bitness: 64
    repo_root: ${{ github.workspace }}
```

## License
This directory inherits the root repository’s license (MIT, unless otherwise noted).
