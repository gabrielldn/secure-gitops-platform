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

check_optional() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo "[PASS] ${label}"
  else
    echo "[SKIP] ${label}"
  fi
}

check_step_issuer_ready() {
  local ctx="$1"
  local ready
  ready="$(kubectl --context "$ctx" get stepclusterissuer step-ca-issuer -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)"
  [[ "$ready" == "True" ]]
}

for ctx in k3d-sgp-dev k3d-sgp-homolog k3d-sgp-prod; do
  check_required "cluster reachable: ${ctx}" kubectl --context "$ctx" get nodes
  check_required "kubesystem healthy: ${ctx}" kubectl --context "$ctx" -n kube-system get pods
  check_required "cert-manager namespace: ${ctx}" kubectl --context "$ctx" get ns cert-manager
  check_required "trivy-operator namespace: ${ctx}" kubectl --context "$ctx" get ns trivy-system
  check_required "kyverno namespace: ${ctx}" kubectl --context "$ctx" get ns kyverno
  check_required "step cluster issuer ready: ${ctx}" check_step_issuer_ready "$ctx"
done

check_required "argocd installed on dev" kubectl --context k3d-sgp-dev -n argocd get deploy argocd-server
check_required "vault namespace on dev" kubectl --context k3d-sgp-dev get ns vault
check_required "step namespace on dev" kubectl --context k3d-sgp-dev get ns step-ca

if "${ROOT_DIR}/scripts/falco-check.sh" | grep -q "best-effort"; then
  check_optional "falco running (best effort on WSL)" kubectl --context k3d-sgp-dev -n falco get ds falco
else
  check_required "falco running" kubectl --context k3d-sgp-dev -n falco get ds falco
fi

if command -v kyverno >/dev/null 2>&1; then
  check_required "kyverno tests" kyverno test "${ROOT_DIR}/policies/tests/kyverno"
else
  echo "[SKIP] kyverno CLI not found"
fi

if command -v conftest >/dev/null 2>&1; then
  check_optional "conftest policy checks" conftest test "${ROOT_DIR}/gitops/apps/workloads/podinfo/base"
fi

if (( failures > 0 )); then
  echo "verify result: FAILED (${failures} checks)"
  exit 1
fi

echo "verify result: PASSED"
