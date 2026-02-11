#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATH_CONTRACT_SCRIPT="$SCRIPT_DIR/path-contract.sh"
if [[ ! -f "$PATH_CONTRACT_SCRIPT" ]]; then
  echo "ERROR: Path contract helper was not found: $PATH_CONTRACT_SCRIPT" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$PATH_CONTRACT_SCRIPT"

LV_YEAR="${LV_YEAR:-2026}"
LVIE_PROJECT_RELATIVE_PATH="${LVIE_PROJECT_RELATIVE_PATH:-${PROJECT_PATH_REL:-lv_icon_editor.lvproj}}"
LVIE_REPO_ROOT="$(resolve_lvie_repo_root "/workspace")"
LVIE_PROJECT_PATH="$(resolve_lvie_project_path "$LVIE_REPO_ROOT" "$LVIE_PROJECT_RELATIVE_PATH")"

TARGET_DIR_REL="${TARGET_DIR_REL:-Test/Templates}"
TARGET_DIR_SOURCE="\$TARGET_DIR"
if [[ -z "${TARGET_DIR:-}" ]]; then
  TARGET_DIR="$(join_lvie_repo_path "$LVIE_REPO_ROOT" "$TARGET_DIR_REL")"
  TARGET_DIR_SOURCE="\$TARGET_DIR_REL"
fi

EXCLUDE_LIST="${CONTAINER_PARITY_EXCLUDE_FILES:-Polymorphic Template.vi}"
LABVIEW_PATH="${LABVIEW_PATH:-/usr/local/natinst/LabVIEW-${LV_YEAR}-64/labviewprofull}"
PROJECT_PATH="$LVIE_PROJECT_PATH"
BUILD_SPEC_NAME="${CONTAINER_PARITY_BUILD_SPEC_NAME:-Editor Packed Library}"
TARGET_NAME="${CONTAINER_PARITY_TARGET_NAME:-My Computer}"
BUILD_OUTPUT_RELATIVE_PATH="${CONTAINER_PARITY_BUILD_OUTPUT_RELATIVE_PATH:-resource/plugins/lv_icon.lvlibp}"
BUILD_OUTPUT_PATH="$(join_lvie_repo_path "$LVIE_REPO_ROOT" "$BUILD_OUTPUT_RELATIVE_PATH")"
BUILD_SPEC_ENABLED_RAW="${CONTAINER_PARITY_BUILD_SPEC:-false}"
ENABLE_DEVMODE_RAW="${CONTAINER_PARITY_ENABLE_DEVMODE:-false}"
LOG_ROOT="$(join_lvie_repo_path "$LVIE_REPO_ROOT" "TestResults/container-parity/linux/logs")"
LABVIEW_ROOT="$(dirname "$LABVIEW_PATH")"
DEVMODE_SCRIPT="$(join_lvie_repo_path "$LVIE_REPO_ROOT" "Tooling/container-parity/devmode-linux.sh")"
SELECTOR_VI_PATH="$(join_lvie_repo_path "$LVIE_REPO_ROOT" "Tooling/Run Icon Editor from Source Selector.vi")"
SELECTOR_PORT="3363"
SELECTOR_PORT_SOURCE="default:3363"

export LVIE_REPO_ROOT
export LVIE_PROJECT_PATH
export LVIE_PROJECT_RELATIVE_PATH
export WORKSPACE_ROOT="$LVIE_REPO_ROOT"
export REPO_ROOT="$LVIE_REPO_ROOT"
export PROJECT_PATH="$LVIE_PROJECT_PATH"

echo "Resolved repo root: $LVIE_REPO_ROOT (source: $LVIE_REPO_ROOT_SOURCE)"
echo "Resolved project path: $LVIE_PROJECT_PATH (source: $LVIE_PROJECT_PATH_SOURCE)"
echo "Resolved target directory: $TARGET_DIR (source: $TARGET_DIR_SOURCE)"

is_enabled_value() {
  local value="${1:-}"
  shopt -s nocasematch
  if [[ "$value" == "1" || "$value" == "true" || "$value" == "yes" ]]; then
    shopt -u nocasematch
    return 0
  fi
  shopt -u nocasematch
  return 1
}

sync_icon_editor_sources_for_build_spec() {
  local repo_plugins
  repo_plugins="$(join_lvie_repo_path "$LVIE_REPO_ROOT" "resource/plugins")"
  local install_plugins="$LABVIEW_ROOT/resource/plugins"
  local repo_icon_api
  repo_icon_api="$(join_lvie_repo_path "$LVIE_REPO_ROOT" "vi.lib/LabVIEW Icon API")"
  local install_icon_api="$LABVIEW_ROOT/vi.lib/LabVIEW Icon API"

  local required_paths=(
    "$repo_plugins/NIIconEditor"
    "$repo_plugins/lv_IconEditor.lvlib"
    "$repo_plugins/lv_icon.vi"
    "$repo_icon_api"
  )

  for path in "${required_paths[@]}"; do
    if [[ ! -e "$path" ]]; then
      echo "ERROR: Required Icon Editor source path is missing: $path" >&2
      return 1
    fi
  done

  mkdir -p "$install_plugins"
  cp -a "$repo_plugins/NIIconEditor" "$install_plugins/"
  for file_name in lv_IconEditor.lvlib lv_icon.vi lv_icon.vit SAMPLE_lv_icon.vi; do
    local source_path="$repo_plugins/$file_name"
    if [[ -e "$source_path" ]]; then
      cp -a "$source_path" "$install_plugins/"
    fi
  done

  mkdir -p "$install_icon_api"
  cp -a "$repo_icon_api/." "$install_icon_api/"

  local probe="$install_plugins/NIIconEditor/Miscellaneous/Classes Initialization.vi"
  if [[ ! -f "$probe" ]]; then
    echo "ERROR: Icon Editor source synchronization failed. Missing probe file: $probe" >&2
    return 1
  fi

  echo "Synchronized Icon Editor sources into LabVIEW install:"
  echo "  resource/plugins -> $install_plugins"
  echo "  vi.lib/LabVIEW Icon API -> $install_icon_api"
}

list_labviewcli_temp_logs() {
  if compgen -G '/tmp/lvtemporary_*.log' > /dev/null; then
    compgen -G '/tmp/lvtemporary_*.log' | sort -u
  fi
}

is_valid_port_number() {
  local value="${1:-}"
  if [[ ! "$value" =~ ^[0-9]+$ ]]; then
    return 1
  fi

  if (( value < 1 || value > 65535 )); then
    return 1
  fi

  return 0
}

resolve_labview_ini_path_for_port() {
  local labview_dir
  labview_dir="$(dirname "$LABVIEW_PATH")"

  if [[ -f "$labview_dir/LabVIEW.ini" ]]; then
    printf '%s' "$labview_dir/LabVIEW.ini"
    return
  fi

  if [[ -f "$labview_dir/labviewprofull.ini" ]]; then
    printf '%s' "$labview_dir/labviewprofull.ini"
    return
  fi

  printf '%s' "$labview_dir/LabVIEW.ini"
}

read_labview_ini_tcp_port() {
  local ini_path="$1"
  if [[ ! -f "$ini_path" ]]; then
    return 0
  fi

  awk '
    BEGIN { IGNORECASE = 1 }
    /^[[:space:]]*server\.tcp\.port[[:space:]]*=/ {
      sub(/^[^=]*=/, "")
      gsub(/^[[:space:]]+|[[:space:]]+$/, "")
      print
      exit
    }
  ' "$ini_path"
}

resolve_selector_port() {
  local candidate
  local ini_path
  local ini_port_raw

  candidate="${LVIE_LUNIT_PORT_64:-}"
  if [[ -n "$candidate" ]]; then
    if is_valid_port_number "$candidate"; then
      SELECTOR_PORT="$candidate"
      SELECTOR_PORT_SOURCE="\$LVIE_LUNIT_PORT_64"
      return 0
    fi

    echo "WARNING: Ignoring invalid port value '$candidate' from \$LVIE_LUNIT_PORT_64. Expected integer range 1-65535." >&2
  fi

  candidate="${LVIE_LUNIT_PORT:-}"
  if [[ -n "$candidate" ]]; then
    if is_valid_port_number "$candidate"; then
      SELECTOR_PORT="$candidate"
      SELECTOR_PORT_SOURCE="\$LVIE_LUNIT_PORT"
      return 0
    fi

    echo "WARNING: Ignoring invalid port value '$candidate' from \$LVIE_LUNIT_PORT. Expected integer range 1-65535." >&2
  fi

  ini_path="$(resolve_labview_ini_path_for_port)"
  ini_port_raw="$(read_labview_ini_tcp_port "$ini_path")"
  if [[ -n "$ini_port_raw" ]]; then
    if is_valid_port_number "$ini_port_raw"; then
      SELECTOR_PORT="$ini_port_raw"
      SELECTOR_PORT_SOURCE="$ini_path (server.tcp.port)"
      return 0
    fi

    echo "WARNING: Ignoring invalid port value '$ini_port_raw' from $ini_path (server.tcp.port). Expected integer range 1-65535." >&2
  fi

  SELECTOR_PORT="3363"
  SELECTOR_PORT_SOURCE="default:3363"
}

run_selector_mode() {
  local mode="$1"
  local port="$2"

  echo "Running selector mode '$mode' via LabVIEWCLI on port $port (source: $SELECTOR_PORT_SOURCE)."
  invoke_labviewcli "selector-$mode" \
    -LogToConsole TRUE \
    -OperationName RunVI \
    -LabVIEWPath "$LABVIEW_PATH" \
    -PortNumber "$port" \
    -VIPath "$SELECTOR_VI_PATH" \
    -Headless \
    "$mode"
}

invoke_labviewcli() {
  local operation="$1"
  shift

  local before_logs_file
  before_logs_file="$(mktemp)"
  list_labviewcli_temp_logs > "$before_logs_file"

  local status
  set +e
  LabVIEWCLI "$@"
  status=$?
  set -e

  local timestamp
  timestamp="$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$LOG_ROOT"

  local index=0
  while IFS= read -r candidate; do
    if [[ -z "$candidate" || ! -f "$candidate" ]]; then
      continue
    fi
    if grep -Fxq "$candidate" "$before_logs_file"; then
      continue
    fi
    index=$((index + 1))
    local destination="$LOG_ROOT/${operation,,}-${timestamp}-${index}.log"
    cp "$candidate" "$destination"
    echo "Captured LabVIEWCLI log: $destination"
  done < <(list_labviewcli_temp_logs)

  if [[ "$index" -eq 0 ]]; then
    local fallback
    fallback="$(ls -1t /tmp/lvtemporary_*.log 2>/dev/null | head -n 1 || true)"
    if [[ -n "$fallback" && -f "$fallback" ]]; then
      local destination="$LOG_ROOT/${operation,,}-${timestamp}-fallback.log"
      cp "$fallback" "$destination"
      echo "Captured LabVIEWCLI log (fallback): $destination"
    fi
  fi

  rm -f "$before_logs_file"
  return "$status"
}

if ! command -v LabVIEWCLI >/dev/null 2>&1; then
  echo "ERROR: LabVIEWCLI is not available on PATH inside the container." >&2
  exit 1
fi

if [[ ! -d "$TARGET_DIR" ]]; then
  echo "ERROR: Target directory does not exist: $TARGET_DIR" >&2
  exit 1
fi

if [[ ! -f "$SELECTOR_VI_PATH" ]]; then
  echo "ERROR: Selector VI does not exist: $SELECTOR_VI_PATH" >&2
  exit 1
fi

resolve_selector_port
echo "Using selector VI Server port: $SELECTOR_PORT ($SELECTOR_PORT_SOURCE)"

STAGING_DIR="$(mktemp -d)"
DEVMODE_ENABLED=0
cleanup() {
  local original_exit="$?"
  local final_exit="$original_exit"

  if [[ "$DEVMODE_ENABLED" -eq 1 ]]; then
    echo "Reverting no-LabVIEW dev mode after build-spec execution."
    if ! "$DEVMODE_SCRIPT" revert "$LABVIEW_ROOT" "$LVIE_REPO_ROOT"; then
      echo "ERROR: Failed to revert no-LabVIEW dev mode." >&2
      final_exit=1
    fi
  fi

  rm -rf "$STAGING_DIR"
  if [[ "$final_exit" -ne "$original_exit" ]]; then
    exit "$final_exit"
  fi
}
trap cleanup EXIT

cp -a "$TARGET_DIR/." "$STAGING_DIR/"

IFS=';' read -r -a _exclude_items <<< "$EXCLUDE_LIST"
for _item in "${_exclude_items[@]}"; do
  _trimmed="$(echo "$_item" | xargs)"
  if [[ -z "$_trimmed" ]]; then
    continue
  fi
  _candidate="$STAGING_DIR/$_trimmed"
  if [[ -e "$_candidate" ]]; then
    echo "Excluding template from parity compile: $_trimmed"
    rm -rf "$_candidate"
  fi
done

if ! run_selector_mode "set" "$SELECTOR_PORT"; then
  echo "ERROR: LabVIEWCLI selector set failed." >&2
  exit 1
fi

masscompile_error=""
unset_error=""
echo "Running LabVIEWCLI MassCompile in headless mode."
echo "Target directory: $TARGET_DIR"
echo "LabVIEW path: $LABVIEW_PATH"
echo "Excluded templates: $EXCLUDE_LIST"
echo "Staging directory: $STAGING_DIR"
if ! invoke_labviewcli "MassCompile" \
  -LogToConsole TRUE \
  -OperationName MassCompile \
  -DirectoryToCompile "$STAGING_DIR" \
  -LabVIEWPath "$LABVIEW_PATH" \
  -Headless; then
  masscompile_error="LabVIEWCLI MassCompile failed."
fi

if ! run_selector_mode "unset" "$SELECTOR_PORT"; then
  unset_error="LabVIEWCLI selector unset failed."
fi

if [[ -n "$masscompile_error" && -n "$unset_error" ]]; then
  echo "ERROR: $masscompile_error Selector unset error: $unset_error" >&2
  exit 1
fi

if [[ -n "$masscompile_error" ]]; then
  echo "ERROR: $masscompile_error" >&2
  exit 1
fi

if [[ -n "$unset_error" ]]; then
  echo "ERROR: $unset_error" >&2
  exit 1
fi

echo "MassCompile completed successfully."

if ! is_enabled_value "$BUILD_SPEC_ENABLED_RAW"; then
  echo "Build specification step disabled (set CONTAINER_PARITY_BUILD_SPEC=true to enable)."
  exit 0
fi

if [[ ! -f "$PROJECT_PATH" ]]; then
  echo "ERROR: Project file does not exist: $PROJECT_PATH" >&2
  exit 1
fi

echo "Synchronizing workspace Icon Editor sources into LabVIEW install before build-spec execution."
if ! sync_icon_editor_sources_for_build_spec; then
  exit 1
fi

if is_enabled_value "$ENABLE_DEVMODE_RAW"; then
  if [[ ! -x "$DEVMODE_SCRIPT" ]]; then
    chmod +x "$DEVMODE_SCRIPT"
  fi
  echo "Preparing no-LabVIEW dev mode before build-spec execution."
  "$DEVMODE_SCRIPT" enable "$LABVIEW_ROOT" "$LVIE_REPO_ROOT"
  DEVMODE_ENABLED=1
else
  echo "No-LabVIEW dev mode is disabled for container parity (set CONTAINER_PARITY_ENABLE_DEVMODE=true to enable)."
fi

echo "Running LabVIEWCLI ExecuteBuildSpec in headless mode."
echo "Project path: $PROJECT_PATH"
echo "Build specification: $BUILD_SPEC_NAME"
echo "Target name: $TARGET_NAME"
echo "Expected output: $BUILD_OUTPUT_PATH"

if ! invoke_labviewcli "ExecuteBuildSpec" \
  -LogToConsole TRUE \
  -OperationName ExecuteBuildSpec \
  -ProjectPath "$PROJECT_PATH" \
  -BuildSpecName "$BUILD_SPEC_NAME" \
  -TargetName "$TARGET_NAME" \
  -LabVIEWPath "$LABVIEW_PATH" \
  -Headless; then
  echo "ERROR: LabVIEWCLI ExecuteBuildSpec failed." >&2
  exit 1
fi

if [[ ! -f "$BUILD_OUTPUT_PATH" ]]; then
  echo "ERROR: Build specification output not found at expected path: $BUILD_OUTPUT_PATH" >&2
  exit 1
fi

bytes="$(wc -c < "$BUILD_OUTPUT_PATH" | xargs)"
echo "Build specification completed: $BUILD_OUTPUT_PATH ($bytes bytes)"
