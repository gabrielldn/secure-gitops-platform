#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <from-env> <to-env>"
  echo "example: $0 dev homolog"
  exit 1
fi

from_env="$1"
to_env="$2"

from_file="${ROOT_DIR}/gitops/apps/workloads/podinfo/overlays/${from_env}/rollout-patch.yaml"
to_file="${ROOT_DIR}/gitops/apps/workloads/podinfo/overlays/${to_env}/rollout-patch.yaml"

[[ -f "$from_file" ]] || { echo "missing file: $from_file"; exit 1; }
[[ -f "$to_file" ]] || { echo "missing file: $to_file"; exit 1; }

if ! command -v yq >/dev/null 2>&1; then
  echo "yq is required"
  exit 1
fi

digest_image="$(yq -r '.spec.template.spec.containers[] | select(.name=="podinfo") | .image' "$from_file")"
yq -i "(.spec.template.spec.containers[] | select(.name==\"podinfo\") | .image) = \"${digest_image}\"" "$to_file"

echo "promoted image ${digest_image} from ${from_env} to ${to_env}"
