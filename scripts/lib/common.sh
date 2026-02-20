#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

log() {
  printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*"
}

warn() {
  printf '[%s] WARN: %s\n' "$(date -u +%H:%M:%S)" "$*" >&2
}

die() {
  printf '[%s] ERROR: %s\n' "$(date -u +%H:%M:%S)" "$*" >&2
  exit 1
}

require_cmd() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || die "missing required command: $cmd"
}

profile_name() {
  echo "${PROFILE:-full}"
}

profile_file() {
  local selected
  selected="$(profile_name)"
  local file="${ROOT_DIR}/platform/profiles/${selected}.yaml"
  [[ -f "$file" ]] || die "profile file not found: $file"
  echo "$file"
}

k3d_config_file() {
  local cluster="$1"
  local selected
  selected="$(profile_name)"
  local file="${ROOT_DIR}/platform/k3d/configs/${selected}/${cluster}.yaml"
  [[ -f "$file" ]] || die "k3d config not found: $file"
  echo "$file"
}

require_yq() {
  require_cmd yq
}

profile_value() {
  local query="$1"
  require_yq
  yq -r "$query" "$(profile_file)"
}

repo_slug() {
  git -C "$ROOT_DIR" remote get-url origin 2>/dev/null | sed -E 's#^https://github.com/##; s#\.git$##'
}
