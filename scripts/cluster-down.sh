#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

require_cmd k3d
require_cmd docker
require_cmd kubectl
require_cmd yq

profile="$(profile_name)"
registry_name="$(profile_value '.registry.name')"
registry_id="k3d-${registry_name}"
CLUSTER_ENVS="${CLUSTER_ENVS:-dev homolog prod}"

read -r -a cluster_envs <<< "$CLUSTER_ENVS"
(( ${#cluster_envs[@]} > 0 )) || die "CLUSTER_ENVS must include at least one environment"
for env in "${cluster_envs[@]}"; do
  case "$env" in
    dev|homolog|prod) ;;
    *) die "unsupported environment in CLUSTER_ENVS: ${env} (allowed: dev homolog prod)" ;;
  esac
done

log "selected cluster environments for teardown: ${cluster_envs[*]}"
for env in "${cluster_envs[@]}"; do
  cluster="sgp-${env}"
  if k3d cluster list 2>/dev/null | awk 'NR>1{print $1}' | grep -qx "$cluster"; then
    log "deleting cluster ${cluster}"
    k3d cluster delete "$cluster"
  else
    log "cluster ${cluster} not found"
  fi

  network="k3d-${cluster}"
  if docker network inspect "$network" >/dev/null 2>&1; then
    log "removing leftover network ${network}"
    if ! docker network rm "$network" >/dev/null 2>&1; then
      warn "failed to remove network ${network}; it may still have active endpoints"
    fi
  fi
done

mapfile -t remaining_clusters < <(k3d cluster list 2>/dev/null | awk 'NR>1{print $1}' | grep '^sgp-' || true)
if (( ${#remaining_clusters[@]} == 0 )); then
  if k3d registry list 2>/dev/null | awk 'NR>1{print $1}' | grep -qx "$registry_id"; then
    log "deleting registry ${registry_name}"
    k3d registry delete "$registry_name"
  fi
  rm -rf "${ROOT_DIR}/.kube"
  log "local cluster resources removed"
  exit 0
fi

log "remaining clusters kept: ${remaining_clusters[*]}"
mkdir -p "${ROOT_DIR}/.kube"
rm -f "${ROOT_DIR}/.kube"/sgp-*.yaml "${ROOT_DIR}/.kube/config"

kubeconfig_parts=()
for cluster in "${remaining_clusters[@]}"; do
  kubeconfig_file="${ROOT_DIR}/.kube/${cluster}.yaml"
  k3d kubeconfig get "$cluster" > "$kubeconfig_file"
  kubeconfig_parts+=("$kubeconfig_file")
done

export KUBECONFIG="$(IFS=:; echo "${kubeconfig_parts[*]}")"
kubectl config view --flatten > "${ROOT_DIR}/.kube/config"
log "updated kubeconfig written to ${ROOT_DIR}/.kube/config"
