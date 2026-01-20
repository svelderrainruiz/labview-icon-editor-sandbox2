# Set Development Mode 🔧

Execute **`Set_Development_Mode.ps1`** to prepare the repository for active development.

## Inputs
| Name | Required | Example | Description |
|------|----------|---------|-------------|
| `repo_root` | **Yes** | `${{ github.workspace }}` | Repository root path. |

## Quick-start
```yaml
- uses: ./.github/actions/set-development-mode
  with:
    repo_root: ${{ github.workspace }}
```

## License
This directory inherits the root repository’s license (MIT, unless otherwise noted).

