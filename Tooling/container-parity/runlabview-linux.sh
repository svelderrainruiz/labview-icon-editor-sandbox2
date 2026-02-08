#!/usr/bin/env bash
set -euo pipefail

LV_YEAR="${LV_YEAR:-2026}"
WORKSPACE_ROOT="${WORKSPACE_ROOT:-/workspace}"
TARGET_DIR="${TARGET_DIR:-$WORKSPACE_ROOT/Test/Templates}"
EXCLUDE_LIST="${CONTAINER_PARITY_EXCLUDE_FILES:-Polymorphic Template.vi}"
LABVIEW_PATH="${LABVIEW_PATH:-/usr/local/natinst/LabVIEW-${LV_YEAR}-64/labviewprofull}"
PROJECT_PATH="${PROJECT_PATH:-$WORKSPACE_ROOT/lv_icon_editor.lvproj}"
BUILD_SPEC_NAME="${CONTAINER_PARITY_BUILD_SPEC_NAME:-Editor Packed Library}"
TARGET_NAME="${CONTAINER_PARITY_TARGET_NAME:-My Computer}"
BUILD_OUTPUT_RELATIVE_PATH="${CONTAINER_PARITY_BUILD_OUTPUT_RELATIVE_PATH:-resource/plugins/lv_icon.lvlibp}"
BUILD_OUTPUT_PATH="$WORKSPACE_ROOT/$BUILD_OUTPUT_RELATIVE_PATH"
BUILD_SPEC_ENABLED_RAW="${CONTAINER_PARITY_BUILD_SPEC:-false}"
ENABLE_DEVMODE_RAW="${CONTAINER_PARITY_ENABLE_DEVMODE:-false}"
LOG_ROOT="$WORKSPACE_ROOT/TestResults/container-parity/linux/logs"
LABVIEW_ROOT="$(dirname "$LABVIEW_PATH")"
DEVMODE_SCRIPT="$WORKSPACE_ROOT/Tooling/container-parity/devmode-linux.sh"

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

list_labviewcli_temp_logs() {
  if compgen -G '/tmp/lvtemporary_*.log' > /dev/null; then
    compgen -G '/tmp/lvtemporary_*.log' | sort -u
  fi
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

echo "Running LabVIEWCLI MassCompile in headless mode."
echo "Target directory: $TARGET_DIR"
echo "LabVIEW path: $LABVIEW_PATH"
echo "Excluded templates: $EXCLUDE_LIST"

STAGING_DIR="$(mktemp -d)"
DEVMODE_ENABLED=0
cleanup() {
  local original_exit="$?"
  local final_exit="$original_exit"

  if [[ "$DEVMODE_ENABLED" -eq 1 ]]; then
    echo "Reverting no-LabVIEW dev mode after build-spec execution."
    if ! "$DEVMODE_SCRIPT" revert "$LABVIEW_ROOT" "$WORKSPACE_ROOT"; then
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

if ! invoke_labviewcli "MassCompile" \
  -LogToConsole TRUE \
  -OperationName MassCompile \
  -DirectoryToCompile "$STAGING_DIR" \
  -LabVIEWPath "$LABVIEW_PATH" \
  -Headless; then
  echo "ERROR: LabVIEWCLI MassCompile failed." >&2
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

if is_enabled_value "$ENABLE_DEVMODE_RAW"; then
  if [[ ! -x "$DEVMODE_SCRIPT" ]]; then
    chmod +x "$DEVMODE_SCRIPT"
  fi
  echo "Preparing no-LabVIEW dev mode before build-spec execution."
  "$DEVMODE_SCRIPT" enable "$LABVIEW_ROOT" "$WORKSPACE_ROOT"
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
