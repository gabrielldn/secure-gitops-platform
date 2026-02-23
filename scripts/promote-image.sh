#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ $# -lt 2 || $# -gt 4 ]]; then
  echo "usage: $0 <from-env> <to-env> [workload] [container]"
  echo "example: $0 dev homolog"
  echo "example: $0 dev homolog podinfo podinfo"
  exit 1
fi

from_env="$1"
to_env="$2"
workload="${3:-java-api}"
container="${4:-java-api}"

from_file="${ROOT_DIR}/gitops/apps/workloads/${workload}/overlays/${from_env}/rollout-patch.yaml"
to_file="${ROOT_DIR}/gitops/apps/workloads/${workload}/overlays/${to_env}/rollout-patch.yaml"

[[ -f "$from_file" ]] || { echo "missing file: $from_file"; exit 1; }
[[ -f "$to_file" ]] || { echo "missing file: $to_file"; exit 1; }

if ! command -v yq >/dev/null 2>&1; then
  echo "yq is required"
  exit 1
fi

digest_image="$(yq -r ".spec.template.spec.containers[] | select(.name==\"${container}\") | .image" "$from_file")"
if [[ -z "$digest_image" || "$digest_image" == "null" ]]; then
  echo "container not found in $from_file: ${container}"
  exit 1
fi

yq -i "(.spec.template.spec.containers[] | select(.name==\"${container}\") | .image) = \"${digest_image}\"" "$to_file"

echo "promoted image ${digest_image} (${workload}/${container}) from ${from_env} to ${to_env}"
