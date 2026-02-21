#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

if [[ -f "${ROOT_DIR}/.kube/config" ]]; then
  export KUBECONFIG="${ROOT_DIR}/.kube/config"
fi

require_cmd kubectl

REPO_URL="${REPO_URL:-}"
GITOPS_REVISION="${GITOPS_REVISION:-main}"
ARGO_WAIT_TIMEOUT="${ARGO_WAIT_TIMEOUT:-1800}"

REPO_URL="${REPO_URL}" GITOPS_REVISION="${GITOPS_REVISION}" "${ROOT_DIR}/scripts/gitops-bootstrap.sh"

effective_repo_url="$(kubectl --context k3d-sgp-dev -n argocd get applicationset cluster-roots -o jsonpath='{.spec.template.spec.source.repoURL}')"
effective_revision="$(kubectl --context k3d-sgp-dev -n argocd get applicationset cluster-roots -o jsonpath='{.spec.template.spec.source.targetRevision}')"
[[ -n "$effective_repo_url" ]] || die "unable to resolve effective repoURL from ApplicationSet"
[[ -n "$effective_revision" ]] || die "unable to resolve effective revision from ApplicationSet"

for env in dev homolog prod; do
  rendered_apps="$(mktemp)"
  sed \
    -e "s#__REPO_URL__#${effective_repo_url}#g" \
    -e "s#__GITOPS_REVISION__#${effective_revision}#g" \
    "${ROOT_DIR}/gitops/clusters/${env}/applications.yaml" > "$rendered_apps"
  kubectl --context k3d-sgp-dev -n argocd apply -f "$rendered_apps" >/dev/null
  rm -f "$rendered_apps"
done

critical_apps=(
  dev-cert-manager
  homolog-cert-manager
  prod-cert-manager
  dev-vault
  dev-step-issuer
  homolog-step-issuer
  prod-step-issuer
  dev-external-secrets
  homolog-external-secrets
  prod-external-secrets
  dev-argo-rollouts
  homolog-argo-rollouts
  prod-argo-rollouts
)

refresh_app() {
  local app="$1"
  kubectl --context k3d-sgp-dev -n argocd annotate application "$app" \
    argocd.argoproj.io/refresh=hard --overwrite >/dev/null 2>&1 || true
}

clear_operation() {
  local app="$1"
  kubectl --context k3d-sgp-dev -n argocd patch application "$app" \
    --type merge -p '{"operation":null}' >/dev/null 2>&1 || true
  kubectl --context k3d-sgp-dev -n argocd patch application "$app" \
    --type merge -p '{"status":{"operationState":null}}' >/dev/null 2>&1 || true
}

for app in "${critical_apps[@]}"; do
  refresh_app "$app"
done

end_epoch=$(( $(date +%s) + ARGO_WAIT_TIMEOUT ))
while (( $(date +%s) < end_epoch )); do
  now_epoch="$(date +%s)"
  pending=0
  failed=0

  for app in "${critical_apps[@]}"; do
    if ! kubectl --context k3d-sgp-dev -n argocd get application "$app" >/dev/null 2>&1; then
      refresh_app "$app"
      pending=$((pending + 1))
      continue
    fi

    sync_status="$(kubectl --context k3d-sgp-dev -n argocd get application "$app" -o jsonpath='{.status.sync.status}')"
    health_status="$(kubectl --context k3d-sgp-dev -n argocd get application "$app" -o jsonpath='{.status.health.status}')"
    comparison_error="$(kubectl --context k3d-sgp-dev -n argocd get application "$app" -o jsonpath='{.status.conditions[?(@.type=="ComparisonError")].message}')"
    operation_phase="$(kubectl --context k3d-sgp-dev -n argocd get application "$app" -o jsonpath='{.status.operationState.phase}')"
    operation_started_at="$(kubectl --context k3d-sgp-dev -n argocd get application "$app" -o jsonpath='{.status.operationState.startedAt}')"

    if [[ "$operation_phase" == "Running" && -n "$operation_started_at" ]]; then
      started_epoch="$(date -d "$operation_started_at" +%s 2>/dev/null || echo "$now_epoch")"
      if (( now_epoch - started_epoch > 240 )); then
        clear_operation "$app"
        refresh_app "$app"
      fi
    fi

    if [[ -n "$comparison_error" ]]; then
      refresh_app "$app"
      pending=$((pending + 1))
      continue
    fi

    if [[ "$sync_status" != "Synced" ]]; then
      refresh_app "$app"
      pending=$((pending + 1))
      continue
    fi

    if [[ "$health_status" == "Healthy" ]]; then
      continue
    fi

    if [[ "$health_status" == "Progressing" ]]; then
      continue
    fi

    echo "[FAIL] ${app} sync=${sync_status} health=${health_status}"
    failed=$((failed + 1))
  done

  if (( failed > 0 )); then
    die "reconcile failed due degraded applications"
  fi

  if (( pending == 0 )); then
    log "reconcile completed: critical applications are synced/healthy"
    exit 0
  fi

  log "waiting Argo convergence: ${pending} applications still pending"
  sleep 10
done

echo "timed out waiting for Argo convergence after ${ARGO_WAIT_TIMEOUT}s"
kubectl --context k3d-sgp-dev -n argocd get applications -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status
exit 1
