#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

require_cmd docker
require_cmd k3d
require_cmd kubectl
require_cmd yq

profile="$(profile_name)"
log "creating local platform resources with profile=${profile}"

registry_name="$(profile_value '.registry.name')"
registry_port="$(profile_value '.registry.port')"
registry_id="k3d-${registry_name}"
create_retries="${K3D_CREATE_RETRIES:-3}"
create_timeout="${K3D_CREATE_TIMEOUT:-420s}"
retry_base_delay_seconds="${K3D_RETRY_BASE_DELAY_SECONDS:-20}"
retry_on_any_error="${K3D_RETRY_ON_ANY_ERROR:-false}"

cluster_exists() {
  local cluster_name="$1"
  k3d cluster list 2>/dev/null | awk 'NR>1{print $1}' | grep -qx "$cluster_name"
}

cluster_nodes_all_running() {
  local cluster_name="$1"
  local node_statuses

  node_statuses="$(k3d node list 2>/dev/null | awk -v cluster="$cluster_name" 'NR>1 && $3==cluster {print $4}')"
  [[ -n "$node_statuses" ]] || return 1

  while IFS= read -r status; do
    [[ "$status" == "running" ]] || return 1
  done <<<"$node_statuses"
}

cleanup_failed_cluster_artifacts() {
  local cluster_name="$1"
  local network_name="k3d-${cluster_name}"

  k3d cluster delete "$cluster_name" >/dev/null 2>&1 || true

  if docker network inspect "$network_name" >/dev/null 2>&1; then
    docker network disconnect -f "$network_name" "$registry_id" >/dev/null 2>&1 || true
    if ! docker network rm "$network_name" >/dev/null 2>&1; then
      warn "failed to remove network ${network_name}; it may still have active endpoints"
    fi
  fi
}

is_retryable_cluster_create_failure() {
  local log_file="$1"
  grep -Eqi \
    'context deadline exceeded|failed to add one or more agents|failed to get ready|stopped returning log lines|timed out|i/o timeout|tls handshake timeout|active endpoints' \
    "$log_file"
}

create_cluster_with_retry() {
  local cluster_name="$1"
  local cfg="$2"
  local attempt=1

  while (( attempt <= create_retries )); do
    local attempt_log
    attempt_log="$(mktemp)"

    log "creating cluster ${cluster_name} using ${cfg} (attempt ${attempt}/${create_retries}, timeout=${create_timeout})"
    set +e
    k3d cluster create --config "$cfg" --timeout "$create_timeout" 2>&1 | tee "$attempt_log"
    local rc="${PIPESTATUS[0]}"
    set -e

    if [[ "$rc" -eq 0 ]]; then
      rm -f "$attempt_log"
      return 0
    fi

    warn "cluster ${cluster_name} create failed on attempt ${attempt}/${create_retries}"

    if [[ "${retry_on_any_error}" != "true" ]] && ! is_retryable_cluster_create_failure "$attempt_log"; then
      rm -f "$attempt_log"
      warn "non-retryable cluster create error detected for ${cluster_name}; failing fast"
      return 1
    fi

    rm -f "$attempt_log"
    cleanup_failed_cluster_artifacts "$cluster_name"

    if (( attempt < create_retries )); then
      local delay=$(( retry_base_delay_seconds * attempt ))
      log "retrying cluster ${cluster_name} in ${delay}s"
      sleep "$delay"
    fi

    attempt=$((attempt + 1))
  done

  return 1
}

cluster_api_ready() {
  local kubeconfig_file="$1"
  KUBECONFIG="$kubeconfig_file" kubectl --request-timeout=15s get --raw='/readyz' >/dev/null 2>&1
}

if ! k3d registry list 2>/dev/null | awk 'NR>1{print $1}' | grep -qx "$registry_id"; then
  log "creating registry ${registry_name}:${registry_port}"
  k3d registry create "$registry_name" --port "${registry_port}"
else
  log "registry ${registry_name} already exists"
fi

mkdir -p "${ROOT_DIR}/.kube"

for cluster in dev homolog prod; do
  cluster_name="sgp-${cluster}"
  cfg="$(k3d_config_file "$cluster")"

  if cluster_exists "$cluster_name" && ! cluster_nodes_all_running "$cluster_name"; then
    warn "cluster ${cluster_name} exists but has non-running nodes; recreating"
    cleanup_failed_cluster_artifacts "$cluster_name"
  fi

  if ! cluster_exists "$cluster_name"; then
    if ! create_cluster_with_retry "$cluster_name" "$cfg"; then
      die "failed to create cluster ${cluster_name} after ${create_retries} attempts"
    fi
  else
    log "cluster ${cluster_name} already exists"
  fi

  k3d kubeconfig get "$cluster_name" > "${ROOT_DIR}/.kube/${cluster_name}.yaml"

  if ! cluster_api_ready "${ROOT_DIR}/.kube/${cluster_name}.yaml"; then
    warn "cluster ${cluster_name} API is not reachable after kubeconfig export; recreating"
    cleanup_failed_cluster_artifacts "$cluster_name"
    if ! create_cluster_with_retry "$cluster_name" "$cfg"; then
      die "failed to recover cluster ${cluster_name} after kubeconfig/API validation failure"
    fi
    k3d kubeconfig get "$cluster_name" > "${ROOT_DIR}/.kube/${cluster_name}.yaml"
    cluster_api_ready "${ROOT_DIR}/.kube/${cluster_name}.yaml" || \
      die "cluster ${cluster_name} API still unreachable after recovery attempt"
  fi
done

export KUBECONFIG="${ROOT_DIR}/.kube/sgp-dev.yaml:${ROOT_DIR}/.kube/sgp-homolog.yaml:${ROOT_DIR}/.kube/sgp-prod.yaml"
kubectl config view --flatten > "${ROOT_DIR}/.kube/config"

log "kubeconfig written to ${ROOT_DIR}/.kube/config"
log "next: run make gitops-bootstrap"
