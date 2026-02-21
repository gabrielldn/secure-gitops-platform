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
RECONCILE_VERBOSE="${RECONCILE_VERBOSE:-true}"
RECONCILE_POLL_INTERVAL="${RECONCILE_POLL_INTERVAL:-10}"
RECONCILE_PROGRESS_WIDTH="${RECONCILE_PROGRESS_WIDTH:-24}"
RECONCILE_PENDING_DETAILS_LIMIT="${RECONCILE_PENDING_DETAILS_LIMIT:-6}"

is_truthy() {
  local value="${1:-}"
  case "${value,,}" in
    1|true|yes|on) return 0 ;;
    *) return 1 ;;
  esac
}

require_positive_integer() {
  local value="$1"
  local name="$2"
  if ! [[ "$value" =~ ^[0-9]+$ ]] || (( value <= 0 )); then
    die "${name} must be a positive integer (received: ${value})"
  fi
}

format_duration() {
  local total_seconds="$1"
  local hours minutes seconds

  hours=$(( total_seconds / 3600 ))
  minutes=$(( (total_seconds % 3600) / 60 ))
  seconds=$(( total_seconds % 60 ))

  if (( hours > 0 )); then
    printf '%02dh%02dm%02ds' "$hours" "$minutes" "$seconds"
    return
  fi

  printf '%02dm%02ds' "$minutes" "$seconds"
}

render_progress_bar() {
  local current="$1"
  local total="$2"
  local width="$3"
  local filled empty
  local filled_segment empty_segment

  filled=0
  if (( total > 0 )); then
    filled=$(( current * width / total ))
  fi
  (( filled > width )) && filled="$width"
  empty=$(( width - filled ))

  printf -v filled_segment '%*s' "$filled" ''
  printf -v empty_segment '%*s' "$empty" ''
  filled_segment="${filled_segment// /#}"
  empty_segment="${empty_segment// /-}"
  printf '%s%s' "$filled_segment" "$empty_segment"
}

summarize_items() {
  local limit="$1"
  shift || true
  local -a items=("$@")
  local count="${#items[@]}"
  local summary

  if (( count == 0 )); then
    echo "none"
    return
  fi

  if (( count > limit )); then
    summary="$(IFS=', '; echo "${items[*]:0:limit}")"
    echo "${summary}, +$((count - limit)) more"
    return
  fi

  summary="$(IFS=', '; echo "${items[*]}")"
  echo "$summary"
}

require_positive_integer "$ARGO_WAIT_TIMEOUT" "ARGO_WAIT_TIMEOUT"
require_positive_integer "$RECONCILE_POLL_INTERVAL" "RECONCILE_POLL_INTERVAL"
require_positive_integer "$RECONCILE_PROGRESS_WIDTH" "RECONCILE_PROGRESS_WIDTH"
require_positive_integer "$RECONCILE_PENDING_DETAILS_LIMIT" "RECONCILE_PENDING_DETAILS_LIMIT"

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
  dev-kube-prometheus-stack
  homolog-kube-prometheus-stack
  prod-kube-prometheus-stack
  dev-step-issuer
  homolog-step-issuer
  prod-step-issuer
  dev-external-secrets
  homolog-external-secrets
  prod-external-secrets
  dev-external-secret-config
  homolog-external-secret-config
  prod-external-secret-config
  dev-step-cluster-issuer
  homolog-step-cluster-issuer
  prod-step-cluster-issuer
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

total_apps="${#critical_apps[@]}"
start_epoch="$(date +%s)"
end_epoch=$(( start_epoch + ARGO_WAIT_TIMEOUT ))

log "waiting Argo convergence for ${total_apps} critical apps (timeout=$(format_duration "$ARGO_WAIT_TIMEOUT"), poll=${RECONCILE_POLL_INTERVAL}s, verbose=${RECONCILE_VERBOSE})"

while (( $(date +%s) < end_epoch )); do
  now_epoch="$(date +%s)"
  pending=0
  failed=0
  pending_details=()
  progressing_apps=()

  for app in "${critical_apps[@]}"; do
    if ! kubectl --context k3d-sgp-dev -n argocd get application "$app" >/dev/null 2>&1; then
      refresh_app "$app"
      pending=$((pending + 1))
      if is_truthy "$RECONCILE_VERBOSE"; then
        pending_details+=("${app}:missing")
      fi
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
      if is_truthy "$RECONCILE_VERBOSE"; then
        pending_details+=("${app}:comparison-error")
      fi
      continue
    fi

    if [[ "$sync_status" != "Synced" ]]; then
      refresh_app "$app"
      pending=$((pending + 1))
      if is_truthy "$RECONCILE_VERBOSE"; then
        pending_details+=("${app}:sync=${sync_status}")
      fi
      continue
    fi

    if [[ "$health_status" == "Healthy" ]]; then
      continue
    fi

    if [[ "$health_status" == "Progressing" ]]; then
      if is_truthy "$RECONCILE_VERBOSE"; then
        progressing_apps+=("$app")
      fi
      continue
    fi

    echo "[FAIL] ${app} sync=${sync_status} health=${health_status}"
    failed=$((failed + 1))
  done

  if (( failed > 0 )); then
    die "reconcile failed due degraded applications"
  fi

  if (( pending == 0 )); then
    done_bar="$(render_progress_bar "$total_apps" "$total_apps" "$RECONCILE_PROGRESS_WIDTH")"
    log "reconcile completed: [${done_bar}] ${total_apps}/${total_apps} (100%) critical applications are synced/healthy"
    exit 0
  fi

  ready_apps=$(( total_apps - pending ))
  progress_pct=$(( ready_apps * 100 / total_apps ))
  elapsed_seconds=$(( now_epoch - start_epoch ))
  remaining_seconds=$(( end_epoch - now_epoch ))
  (( remaining_seconds < 0 )) && remaining_seconds=0
  progress_bar="$(render_progress_bar "$ready_apps" "$total_apps" "$RECONCILE_PROGRESS_WIDTH")"

  log "waiting Argo convergence: [${progress_bar}] ${ready_apps}/${total_apps} (${progress_pct}%) pending=${pending} elapsed=$(format_duration "$elapsed_seconds") timeout-in=$(format_duration "$remaining_seconds")"
  if is_truthy "$RECONCILE_VERBOSE"; then
    log "pending detail: $(summarize_items "$RECONCILE_PENDING_DETAILS_LIMIT" "${pending_details[@]}")"
    if (( ${#progressing_apps[@]} > 0 )); then
      log "synced but progressing: $(summarize_items "$RECONCILE_PENDING_DETAILS_LIMIT" "${progressing_apps[@]}")"
    fi
  fi

  sleep "$RECONCILE_POLL_INTERVAL"
done

echo "timed out waiting for Argo convergence after ${ARGO_WAIT_TIMEOUT}s"
kubectl --context k3d-sgp-dev -n argocd get applications -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status
exit 1
