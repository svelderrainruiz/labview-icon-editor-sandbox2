#!/usr/bin/env bash

resolve_lvie_repo_root() {
  local default_root="${1:-}"
  local candidate=""

  if [[ -n "${LVIE_REPO_ROOT:-}" ]]; then
    candidate="$LVIE_REPO_ROOT"
    LVIE_REPO_ROOT_SOURCE="\$LVIE_REPO_ROOT"
  elif [[ -n "${WORKSPACE_ROOT:-}" ]]; then
    candidate="$WORKSPACE_ROOT"
    LVIE_REPO_ROOT_SOURCE="\$WORKSPACE_ROOT"
  elif [[ -n "${REPO_ROOT:-}" ]]; then
    candidate="$REPO_ROOT"
    LVIE_REPO_ROOT_SOURCE="\$REPO_ROOT"
  elif [[ -n "$default_root" ]]; then
    candidate="$default_root"
    LVIE_REPO_ROOT_SOURCE="default:$default_root"
  else
    printf '%s\n' "Unable to resolve repo root from LVIE_REPO_ROOT/WORKSPACE_ROOT/REPO_ROOT/default." >&2
    return 1
  fi

  printf '%s\n' "$candidate"
}

join_lvie_repo_path() {
  local repo_root="$1"
  local candidate="$2"

  if [[ "$candidate" = /* || "$candidate" =~ ^[A-Za-z]:[\\/].* ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi

  if [[ "$repo_root" =~ [\\/]$ ]]; then
    printf '%s\n' "${repo_root}${candidate}"
  else
    printf '%s\n' "${repo_root}/${candidate}"
  fi
}

resolve_lvie_project_path() {
  local repo_root="$1"
  local default_relative="${2:-lv_icon_editor.lvproj}"
  local effective_relative="${LVIE_PROJECT_RELATIVE_PATH:-$default_relative}"

  if [[ -n "${LVIE_PROJECT_PATH:-}" ]]; then
    LVIE_PROJECT_PATH_SOURCE="\$LVIE_PROJECT_PATH"
    printf '%s\n' "$(join_lvie_repo_path "$repo_root" "$LVIE_PROJECT_PATH")"
    return 0
  fi

  if [[ -n "${PROJECT_PATH:-}" ]]; then
    LVIE_PROJECT_PATH_SOURCE="\$PROJECT_PATH"
    printf '%s\n' "$(join_lvie_repo_path "$repo_root" "$PROJECT_PATH")"
    return 0
  fi

  LVIE_PROJECT_PATH_SOURCE="\$LVIE_PROJECT_RELATIVE_PATH (or default)"
  printf '%s\n' "$(join_lvie_repo_path "$repo_root" "$effective_relative")"
}
