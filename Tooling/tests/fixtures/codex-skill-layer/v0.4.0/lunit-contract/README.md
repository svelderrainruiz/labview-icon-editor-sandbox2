# LUnit Parser Contract

Contract module for direct `g-cli lunit` execution + parser-only report handling.

## Canonical Commands
- Help: `g-cli --lv-ver <year> --arch <bitness> lunit -- -h`
- Run: `g-cli --lv-ver <year> --arch <bitness> lunit -- -r <report.xml> <project.lvproj>`

Invalid forms (do not use):
- `g-cli lunit --help`
- `g-cli lunit -- --help`

## Exit Precedence
1. If `g-cli lunit` exits non-zero, use that exit code.
2. Else parse report and use parser exit code.

## Removed Legacy Knobs
- `LVIE_LUNIT_BACKEND`
- `LVIE_FORCE_GCLI_LUNIT`

Callers should fail fast when these are set.
