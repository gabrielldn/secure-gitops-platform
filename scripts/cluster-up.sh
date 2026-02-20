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
  if ! k3d cluster list 2>/dev/null | awk 'NR>1{print $1}' | grep -qx "$cluster_name"; then
    log "creating cluster ${cluster_name} using ${cfg}"
    k3d cluster create --config "$cfg"
  else
    log "cluster ${cluster_name} already exists"
  fi

  k3d kubeconfig get "$cluster_name" > "${ROOT_DIR}/.kube/${cluster_name}.yaml"
done

export KUBECONFIG="${ROOT_DIR}/.kube/sgp-dev.yaml:${ROOT_DIR}/.kube/sgp-homolog.yaml:${ROOT_DIR}/.kube/sgp-prod.yaml"
kubectl config view --flatten > "${ROOT_DIR}/.kube/config"

log "kubeconfig written to ${ROOT_DIR}/.kube/config"
log "next: run make gitops-bootstrap"
