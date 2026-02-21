#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

require_cmd k3d
require_cmd docker
require_cmd yq

profile="$(profile_name)"
registry_name="$(profile_value '.registry.name')"
registry_id="k3d-${registry_name}"

for cluster in sgp-dev sgp-homolog sgp-prod; do
  if k3d cluster list 2>/dev/null | awk 'NR>1{print $1}' | grep -qx "$cluster"; then
    log "deleting cluster ${cluster}"
    k3d cluster delete "$cluster"
  else
    log "cluster ${cluster} not found"
  fi
done

if k3d registry list 2>/dev/null | awk 'NR>1{print $1}' | grep -qx "$registry_id"; then
  log "deleting registry ${registry_name}"
  k3d registry delete "$registry_name"
fi

for network in k3d-sgp-dev k3d-sgp-homolog k3d-sgp-prod; do
  if docker network inspect "$network" >/dev/null 2>&1; then
    log "removing leftover network ${network}"
    if ! docker network rm "$network" >/dev/null 2>&1; then
      warn "failed to remove network ${network}; it may still have active endpoints"
    fi
  fi
done

rm -rf "${ROOT_DIR}/.kube"
log "local cluster resources removed"
