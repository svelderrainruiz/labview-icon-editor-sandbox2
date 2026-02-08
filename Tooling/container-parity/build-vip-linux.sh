#!/usr/bin/env bash
set -euo pipefail

WORKSPACE_ROOT="${WORKSPACE_ROOT:-/workspace}"
LV_RELEASE="${LV_RELEASE:-2026q1}"
LV_YEAR="${LV_YEAR:-${LV_RELEASE:0:4}}"
CONTAINER_VIPB_PATH="${CONTAINER_VIPB_PATH:-Tooling/deployment/NI Icon editor.vipb}"
CONTAINER_VIP_VERSION="${CONTAINER_VIP_VERSION:-}"
CONTAINER_RELEASE_NOTES_PATH="${CONTAINER_RELEASE_NOTES_PATH:-Tooling/deployment/release_notes.md}"
CONTAINER_VIPM_TIMEOUT_SECONDS="${CONTAINER_VIPM_TIMEOUT_SECONDS:-900}"
CONTAINER_VIPM_PACKAGE_URL="${CONTAINER_VIPM_PACKAGE_URL:-https://packages.jki.net/vipm/preview/vipm_latest_preview_amd64.deb}"
CONTAINER_VIPM_REWRITE_PACKAGE_LV_VERSION="${CONTAINER_VIPM_REWRITE_PACKAGE_LV_VERSION:-true}"

LOG_DIR="${WORKSPACE_ROOT}/builds/logs"
VIPM_LOG="${LOG_DIR}/vipm-build-linux.log"
VIP_OUTPUT_DIR="${WORKSPACE_ROOT}/builds/VI Package"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

resolve_workspace_path() {
  local path_value="$1"
  if [[ "$path_value" = /* ]]; then
    printf '%s\n' "$path_value"
  else
    printf '%s\n' "${WORKSPACE_ROOT}/${path_value}"
  fi
}

require_file() {
  local path_value="$1"
  local label="$2"
  if [[ ! -f "$path_value" ]]; then
    fail "$label not found: $path_value"
  fi
}

capture_vipm_diagnostics() {
  local diag_root="${LOG_DIR}/vipm-internal"
  mkdir -p "$diag_root"

  local sources=(
    "/usr/local/jki/vipm/error"
    "/usr/local/jki/vipm/VIPM-CLI/error"
    "/usr/local/jki/vipm/logs"
    "/usr/local/jki/vipm/VIPM-CLI/logs"
  )

  for src in "${sources[@]}"; do
    if [[ -e "$src" ]]; then
      local name
      name="$(basename "$src")"
      local parent
      parent="$(basename "$(dirname "$src")")"
      cp -R "$src" "${diag_root}/${parent}-${name}" 2>/dev/null || true
    fi
  done
}

ensure_vipm() {
  if command -v vipm >/dev/null 2>&1; then
    return 0
  fi

  echo "vipm not found on PATH. Installing VIPM CLI from ${CONTAINER_VIPM_PACKAGE_URL}."

  if ! command -v apt-get >/dev/null 2>&1; then
    fail "apt-get is required to install VIPM CLI in this container."
  fi
  if ! command -v dpkg >/dev/null 2>&1; then
    fail "dpkg is required to install VIPM CLI in this container."
  fi

  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y --no-install-recommends ca-certificates wget

  mkdir -p /usr/local/jki/vipm /etc/jki
  touch /usr/local/jki/vipm/Settings.ini /etc/jki/jki.conf

  local vipm_deb
  vipm_deb="$(mktemp /tmp/vipm.XXXXXX.deb)"
  wget -q -O "$vipm_deb" "$CONTAINER_VIPM_PACKAGE_URL"
  dpkg -i "$vipm_deb" || {
    apt-get install -f -y
    dpkg -i "$vipm_deb"
  }
  rm -f "$vipm_deb"

  if ! command -v vipm >/dev/null 2>&1; then
    fail "VIPM CLI installation completed but vipm is still not available on PATH."
  fi
}

if [[ -z "$CONTAINER_VIP_VERSION" ]]; then
  fail "CONTAINER_VIP_VERSION is required (expected format: major.minor.patch.build)."
fi

if [[ ! "$LV_YEAR" =~ ^[0-9]{4}$ ]]; then
  fail "LV_YEAR must be a 4-digit year. Resolved value: '$LV_YEAR'"
fi

ensure_vipm

VIPB_PATH="$(resolve_workspace_path "$CONTAINER_VIPB_PATH")"
RELEASE_NOTES_PATH="$(resolve_workspace_path "$CONTAINER_RELEASE_NOTES_PATH")"
PPL_X86_PATH="${WORKSPACE_ROOT}/resource/plugins/lv_icon_x86.lvlibp"
PPL_X64_PATH="${WORKSPACE_ROOT}/resource/plugins/lv_icon_x64.lvlibp"

require_file "$VIPB_PATH" "VIPB file"
require_file "$RELEASE_NOTES_PATH" "Release notes file"
require_file "$PPL_X86_PATH" "32-bit packed library"
require_file "$PPL_X64_PATH" "64-bit packed library"

mkdir -p "$LOG_DIR"
mkdir -p "$VIP_OUTPUT_DIR"

build_started_epoch="$(date +%s)"

vipm_vipb_path="$VIPB_PATH"
vipm_vipb_is_temp=0
if [[ "${CONTAINER_VIPM_REWRITE_PACKAGE_LV_VERSION,,}" == "true" ]]; then
  lv_major="$((10#$LV_YEAR - 2000))"
  if [[ "$lv_major" -le 0 ]]; then
    fail "Unable to derive LabVIEW major version from LV_YEAR='$LV_YEAR'"
  fi

  vipm_vipb_path="$(mktemp /tmp/vipm-buildspec.XXXXXX.vipb)"
  cp "$VIPB_PATH" "$vipm_vipb_path"
  sed -i -E "s|<Package_LabVIEW_Version>[^<]+</Package_LabVIEW_Version>|<Package_LabVIEW_Version>${lv_major}.0</Package_LabVIEW_Version>|g" "$vipm_vipb_path"
  vipm_vipb_is_temp=1
fi

vipm_cmd=(
  vipm
  build
  --labview-version "$LV_YEAR"
  --labview-bitness 64
  "$vipm_vipb_path"
)

run_cmd=("${vipm_cmd[@]}")
if command -v timeout >/dev/null 2>&1; then
  run_cmd=(timeout --foreground "${CONTAINER_VIPM_TIMEOUT_SECONDS}s" "${vipm_cmd[@]}")
fi

echo "Building VI Package on Linux container."
echo "Workspace root: $WORKSPACE_ROOT"
echo "LabVIEW release/year: $LV_RELEASE / $LV_YEAR"
echo "VIPB path: $VIPB_PATH"
echo "VIPM build spec path: $vipm_vipb_path"
echo "Release notes path: $RELEASE_NOTES_PATH"
echo "Requested VIP version: $CONTAINER_VIP_VERSION"
echo "Required PPLs:"
echo "  - $PPL_X86_PATH"
echo "  - $PPL_X64_PATH"
echo "Log path: $VIPM_LOG"

printf 'Executing:'
for arg in "${run_cmd[@]}"; do
  printf ' %q' "$arg"
done
printf '\n'

set +e
"${run_cmd[@]}" 2>&1 | tee "$VIPM_LOG"
vipm_exit="${PIPESTATUS[0]}"
set -e

if [[ "$vipm_exit" -eq 124 ]]; then
  capture_vipm_diagnostics
  fail "vipm build timed out after ${CONTAINER_VIPM_TIMEOUT_SECONDS}s. See $VIPM_LOG"
fi

if [[ "$vipm_exit" -ne 0 ]]; then
  capture_vipm_diagnostics
  fail "vipm build failed with exit code $vipm_exit. See $VIPM_LOG"
fi

if [[ "$vipm_vipb_is_temp" -eq 1 ]]; then
  rm -f "$vipm_vipb_path"
fi

latest_vip_line="$(
  find "$VIP_OUTPUT_DIR" -type f -name '*.vip' -printf '%T@|%p\n' 2>/dev/null \
    | sort -nr \
    | head -n 1
)"

if [[ -z "$latest_vip_line" ]]; then
  fail "No .vip output was found under $VIP_OUTPUT_DIR"
fi

latest_vip_path="${latest_vip_line#*|}"
if [[ ! -f "$latest_vip_path" ]]; then
  fail "Resolved VIP output path does not exist: $latest_vip_path"
fi

latest_vip_epoch="$(stat -c %Y "$latest_vip_path")"
if [[ "$latest_vip_epoch" -lt "$build_started_epoch" ]]; then
  fail "No newly generated .vip file detected after build start. Latest file: $latest_vip_path"
fi

latest_vip_size="$(wc -c < "$latest_vip_path" | xargs)"
echo "VI Package build succeeded: $latest_vip_path ($latest_vip_size bytes)"
echo "VIP_PATH=$latest_vip_path"
