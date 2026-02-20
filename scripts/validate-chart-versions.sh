#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

require_cmd yq
require_cmd helm

mapfile -t app_files < <(find "${ROOT_DIR}/gitops/clusters" -type f -name applications.yaml | sort)
if (( ${#app_files[@]} == 0 )); then
  die "no Application manifests found under gitops/clusters"
fi

declare -A seen=()
failures=0

while IFS=$'\t' read -r app_name repo_url chart version; do
  [[ -n "$chart" ]] || continue
  key="${repo_url}|${chart}|${version}"
  if [[ -n "${seen[$key]:-}" ]]; then
    continue
  fi
  seen[$key]=1

  if helm show chart "$chart" --repo "$repo_url" --version "$version" >/dev/null 2>&1; then
    echo "[PASS] ${chart}@${version} (${repo_url})"
  else
    echo "[FAIL] ${chart}@${version} (${repo_url})"
    failures=$((failures + 1))
  fi
done < <(yq -r '
  select(.kind == "Application")
  | select(.spec.source.chart != null)
  | [
      .metadata.name,
      .spec.source.repoURL,
      .spec.source.chart,
      .spec.source.targetRevision
    ]
  | @tsv
' "${app_files[@]}")

if (( failures > 0 )); then
  die "chart version validation failed (${failures} failures)"
fi

echo "chart version validation passed"
