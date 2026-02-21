#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

require_cmd kubectl
require_cmd jq

DEV_CONTEXT="${DEV_CONTEXT:-k3d-sgp-dev}"

kubectl --context "$DEV_CONTEXT" create namespace argocd --dry-run=client -o yaml | kubectl --context "$DEV_CONTEXT" apply -f -

create_cluster_secret() {
  local env="$1"
  local profile="$2"
  local token="$3"
  local server="$4"
  local ca_data="$5"

  cat <<YAML | kubectl --context "$DEV_CONTEXT" apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: cluster-sgp-${env}-${profile}
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: cluster
stringData:
  name: sgp-${env}-${profile}
  server: ${server}
  config: |
    {
      "bearerToken": "${token}",
      "tlsClientConfig": {
        "caData": "${ca_data}"
      }
    }
YAML
}

register_cluster() {
  local env="$1"
  local ctx="k3d-sgp-${env}"

  local platform_sa="argocd-platform-${env}"
  local workloads_sa="argocd-workloads-${env}"
  local workloads_read_role="argocd-workloads-read-${env}"
  local workloads_write_role="argocd-workloads-write-${env}"

  log "registering cluster ${ctx} (platform/workloads split)"

  kubectl --context "$ctx" create namespace argocd --dry-run=client -o yaml | kubectl --context "$ctx" apply -f -
  kubectl --context "$ctx" create namespace apps --dry-run=client -o yaml | kubectl --context "$ctx" apply -f -

  cat <<YAML | kubectl --context "$ctx" apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ${platform_sa}
  namespace: argocd
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: ${platform_sa}
subjects:
  - kind: ServiceAccount
    name: ${platform_sa}
    namespace: argocd
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ${workloads_sa}
  namespace: argocd
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: ${workloads_read_role}
rules:
  - apiGroups: ["*"]
    resources: ["*"]
    verbs: ["get", "list", "watch"]
  - nonResourceURLs: ["*"]
    verbs: ["get"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: ${workloads_read_role}
subjects:
  - kind: ServiceAccount
    name: ${workloads_sa}
    namespace: argocd
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: ${workloads_read_role}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: ${workloads_write_role}
  namespace: apps
rules:
  - apiGroups: ["*"]
    resources: ["*"]
    verbs: ["create", "delete", "get", "list", "patch", "update", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: ${workloads_write_role}
  namespace: apps
subjects:
  - kind: ServiceAccount
    name: ${workloads_sa}
    namespace: argocd
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: ${workloads_write_role}
YAML

  local platform_token
  local workloads_token
  platform_token="$(kubectl --context "$ctx" -n argocd create token "$platform_sa" --duration=24h)"
  workloads_token="$(kubectl --context "$ctx" -n argocd create token "$workloads_sa" --duration=24h)"

  local server
  local ca_data
  server="$(kubectl config view --raw -o jsonpath="{.clusters[?(@.name==\"${ctx}\")].cluster.server}")"
  ca_data="$(kubectl config view --raw -o jsonpath="{.clusters[?(@.name==\"${ctx}\")].cluster.certificate-authority-data}")"

  server="${server/https:\/\/127.0.0.1:/https://host.k3d.internal:}"
  server="${server/https:\/\/0.0.0.0:/https://host.k3d.internal:}"

  create_cluster_secret "$env" "platform" "$platform_token" "$server" "$ca_data"
  create_cluster_secret "$env" "workloads" "$workloads_token" "$server" "$ca_data"
}

# Cleanup old registration objects from previous layout.
kubectl --context "$DEV_CONTEXT" -n argocd delete secret cluster-k3d-sgp-dev cluster-k3d-sgp-homolog cluster-k3d-sgp-prod --ignore-not-found >/dev/null 2>&1 || true

for env in dev homolog prod; do
  register_cluster "$env"
done

log "cluster registration completed"
