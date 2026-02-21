#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

if [[ -f "${ROOT_DIR}/.kube/config" ]]; then
  export KUBECONFIG="${ROOT_DIR}/.kube/config"
fi

require_cmd kubectl

failures=0

check_required() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo "[PASS] ${label}"
  else
    echo "[FAIL] ${label}"
    failures=$((failures + 1))
  fi
}

for ctx in k3d-sgp-dev k3d-sgp-homolog k3d-sgp-prod; do
  check_required "cluster reachable: ${ctx}" kubectl --context "$ctx" get nodes
done

check_required "argocd namespace exists" kubectl --context k3d-sgp-dev get ns argocd
check_required "argocd server deployment exists" kubectl --context k3d-sgp-dev -n argocd get deploy argocd-server
check_required "dev root application exists" kubectl --context k3d-sgp-dev -n argocd get application dev-root
check_required "homolog root application exists" kubectl --context k3d-sgp-dev -n argocd get application homolog-root
check_required "prod root application exists" kubectl --context k3d-sgp-dev -n argocd get application prod-root

if (( failures > 0 )); then
  echo "verify-quick result: FAILED (${failures} checks)"
  exit 1
fi

echo "verify-quick result: PASSED"
