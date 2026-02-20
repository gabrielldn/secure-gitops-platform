#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSIONS_FILE="${ROOT_DIR}/platform/versions.lock.yaml"

if ! command -v yq >/dev/null 2>&1; then
  echo "yq is required to render platform/versions.lock.yaml"
  echo "cat ${VERSIONS_FILE}"
  exit 1
fi

echo "== CLI =="
yq -r '.cli | to_entries[] | "\(.key)=\(.value)"' "$VERSIONS_FILE"
echo
echo "== Charts =="
yq -r '.charts | to_entries[] | "\(.key)=\(.value)"' "$VERSIONS_FILE"
echo
echo "== Kubernetes =="
yq -r '.kubernetes | to_entries[] | "\(.key)=\(.value)"' "$VERSIONS_FILE"
