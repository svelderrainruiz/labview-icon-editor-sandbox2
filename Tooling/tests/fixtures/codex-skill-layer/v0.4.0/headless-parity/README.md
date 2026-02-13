# Headless Parity Preflight Contract

This module captures the fail-fast compatibility gate used in headless self-hosted parity.

## Gate Requirements
- `.lvversion` is canonical.
- RunnerCLI resolves repo/project context in place for parity execution.
- Project root `LVVersion` and project-parent path are not version/path gates.
