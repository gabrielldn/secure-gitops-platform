#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <source-image[@digest]> [target-registry]"
  exit 1
fi

source_image="$1"
target_registry="${2:-localhost:5001}"

if ! command -v crane >/dev/null 2>&1; then
  echo "crane is required"
  exit 1
fi

# Keep repository path and digest/tag, replacing the registry host.
image_ref="${source_image#*/}"
target_image="${target_registry}/${image_ref}"

crane copy "$source_image" "$target_image"
echo "$target_image"
