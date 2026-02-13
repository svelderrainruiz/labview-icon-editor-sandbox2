# Proactive Loop Contract

Contract module for single-bitness recovery sequence and heuristic classification.

Stage order (sequence mode):
1. `build_pass1` (expected fail)
2. `unit_tests`
3. `build_pass2` (expected success)
4. `rename`

See `sequence-mode-matrix.json` for drift checks and required heuristic tokens.
See `sequence-diagnostics.schema.json` for diagnostics payload shape.
