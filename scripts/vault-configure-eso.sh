#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

require_cmd kubectl
require_cmd vault
require_cmd jq
require_cmd sops

if [[ -f "${ROOT_DIR}/.kube/config" ]]; then
  export KUBECONFIG="${ROOT_DIR}/.kube/config"
fi

enc_file="${ROOT_DIR}/.secrets/vault/init.enc.json"
[[ -f "$enc_file" ]] || die "missing encrypted init file: $enc_file"

CTX="${CTX:-k3d-sgp-dev}"
NS="${NS:-vault}"
POD="${POD:-vault-0}"

tmp_init="$(mktemp)"
trap 'rm -f "$tmp_init"' EXIT
sops --decrypt "$enc_file" > "$tmp_init"
root_token="$(jq -r '.root_token' "$tmp_init")"
unseal_key="$(jq -r '.unseal_keys_b64[0]' "$tmp_init")"
[[ -n "$unseal_key" && "$unseal_key" != "null" ]] || die "missing unseal key in encrypted init material"

read_vault_status_json() {
  local status_json
  set +e
  status_json="$(kubectl --context "$CTX" -n "$NS" exec "$POD" -- vault status -format=json 2>/dev/null)"
  set -e
  [[ -n "$status_json" ]] || die "unable to read Vault status from ${NS}/${POD}"
  echo "$status_json"
}

vault_status_json="$(read_vault_status_json)"
vault_initialized="$(echo "$vault_status_json" | jq -r '.initialized // "false"')"
if [[ "$vault_initialized" != "true" ]]; then
  die "vault is not initialized. Run 'make vault-bootstrap' first (stale .secrets/vault/init.enc.json is auto-archived when needed)."
fi

for pod in $(kubectl --context "$CTX" -n "$NS" get pods -l app.kubernetes.io/name=vault -o jsonpath='{.items[*].metadata.name}'); do
  phase="$(kubectl --context "$CTX" -n "$NS" get pod "$pod" -o jsonpath='{.status.phase}')"
  if [[ "$phase" != "Running" ]]; then
    continue
  fi
  kubectl --context "$CTX" -n "$NS" exec "$pod" -- vault operator unseal "$unseal_key" >/dev/null 2>&1 || true
done

for _ in $(seq 1 15); do
  sealed_state="$(kubectl --context "$CTX" -n "$NS" exec "$POD" -- vault status -format=json 2>/dev/null | jq -r '.sealed' 2>/dev/null || true)"
  if [[ "$sealed_state" == "false" ]]; then
    break
  fi
  sleep 2
done

sealed_state="$(kubectl --context "$CTX" -n "$NS" exec "$POD" -- vault status -format=json 2>/dev/null | jq -r '.sealed' 2>/dev/null || true)"
[[ "$sealed_state" == "false" ]] || die "${POD} is still sealed after unseal attempts"

port_forward_log="$(mktemp)"
LOCAL_VAULT_PORT="${LOCAL_VAULT_PORT:-18201}"
kubectl --context "$CTX" -n "$NS" port-forward pod/"$POD" "${LOCAL_VAULT_PORT}:8200" >"$port_forward_log" 2>&1 &
pf_pid=$!
trap 'kill $pf_pid >/dev/null 2>&1 || true; rm -f "$tmp_init" "$port_forward_log"' EXIT
sleep 3
if ! kill -0 "$pf_pid" >/dev/null 2>&1; then
  cat "$port_forward_log" || true
  die "failed to start vault port-forward on ${LOCAL_VAULT_PORT}"
fi

export VAULT_ADDR="http://127.0.0.1:${LOCAL_VAULT_PORT}"
vault login "$root_token" >/dev/null

if ! vault secrets list -format=json | jq -e 'has("kv/")' >/dev/null; then
  vault secrets enable -path=kv kv-v2
fi

vault kv put kv/apps/podinfo message="secure-gitops-platform"

JAVA_API_DB_HOST="${JAVA_API_DB_HOST:-host.k3d.internal}"
JAVA_API_DB_PORT="${JAVA_API_DB_PORT:-15432}"
JAVA_API_DB_NAME="${JAVA_API_DB_NAME:-appdb}"
JAVA_API_DB_USER="${JAVA_API_DB_USER:-appuser}"
JAVA_API_DB_PASS="${JAVA_API_DB_PASS:-dummy-apppass-change-me}"
JAVA_API_DB_URL="${JAVA_API_DB_URL:-jdbc:postgresql://${JAVA_API_DB_HOST}:${JAVA_API_DB_PORT}/${JAVA_API_DB_NAME}}"

vault kv put kv/apps/java-api/db \
  spring_datasource_url="${JAVA_API_DB_URL}" \
  spring_datasource_username="${JAVA_API_DB_USER}" \
  spring_datasource_password="${JAVA_API_DB_PASS}" \
  spring_datasource_driver_class_name="org.postgresql.Driver"

step_bootstrap_enc="${ROOT_DIR}/.secrets/step-ca/bootstrap.enc.json"
[[ -f "$step_bootstrap_enc" ]] || die "missing step-ca bootstrap material: $step_bootstrap_enc"
step_bootstrap_tmp="$(mktemp)"
trap 'kill $pf_pid >/dev/null 2>&1 || true; rm -f "$tmp_init" "$port_forward_log" "$step_bootstrap_tmp"' EXIT
sops --decrypt "$step_bootstrap_enc" > "$step_bootstrap_tmp"
step_provisioner_password="$(jq -r '.provisioner_password' "$step_bootstrap_tmp")"
[[ -n "$step_provisioner_password" && "$step_provisioner_password" != "null" ]] || die "missing provisioner_password in step bootstrap material"
vault kv put kv/apps/pki/step-issuer provisioner_password="$step_provisioner_password"

for env in dev homolog prod; do
  ctx="k3d-sgp-${env}"
  mount="kubernetes-${env}"
  role="eso-${env}"

  log "validating Vault reachability from ${ctx}"
  cat <<YAML | kubectl --context "$ctx" -n external-secrets apply -f - >/dev/null
apiVersion: batch/v1
kind: Job
metadata:
  name: vault-reachability-check
spec:
  ttlSecondsAfterFinished: 600
  backoffLimit: 0
  template:
    spec:
      securityContext:
        runAsNonRoot: true
        seccompProfile:
          type: RuntimeDefault
      restartPolicy: Never
      volumes: []
      containers:
        - name: curl
          image: curlimages/curl:8.11.1
          securityContext:
            runAsNonRoot: true
            runAsUser: 1000
            runAsGroup: 1000
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            privileged: false
            capabilities:
              drop: ["ALL"]
          resources:
            requests:
              cpu: 10m
              memory: 32Mi
            limits:
              cpu: 100m
              memory: 128Mi
          command: ["/bin/sh", "-c"]
          args:
            - curl -sS --max-time 10 http://host.k3d.internal:18200/v1/sys/health >/dev/null
YAML
  if ! kubectl --context "$ctx" -n external-secrets wait --for=condition=Complete job/vault-reachability-check --timeout=120s >/dev/null 2>&1; then
    if ! kubectl --context "$ctx" -n external-secrets get job vault-reachability-check >/dev/null 2>&1; then
      log "vault reachability check job already cleaned up on ${ctx}; continuing"
      continue
    fi
    kubectl --context "$ctx" -n external-secrets logs job/vault-reachability-check || true
    kubectl --context "$ctx" -n external-secrets delete job vault-reachability-check --ignore-not-found >/dev/null 2>&1 || true
    die "vault reachability check failed on ${ctx}"
  fi
  kubectl --context "$ctx" -n external-secrets delete job vault-reachability-check --ignore-not-found >/dev/null 2>&1 || true

  host="$(kubectl config view --raw -o jsonpath="{.clusters[?(@.name==\"${ctx}\")].cluster.server}")"
  host="${host/https:\/\/127.0.0.1:/https://host.k3d.internal:}"
  host="${host/https:\/\/0.0.0.0:/https://host.k3d.internal:}"
  ca_b64="$(kubectl config view --raw -o jsonpath="{.clusters[?(@.name==\"${ctx}\")].cluster.certificate-authority-data}")"
  reviewer_jwt="$(kubectl --context "$ctx" -n argocd create token "argocd-platform-${env}" --duration=24h 2>/dev/null || true)"
  if [[ -z "$reviewer_jwt" ]]; then
    reviewer_jwt="$(kubectl --context "$ctx" -n external-secrets create token external-secrets --duration=24h)"
  fi

  if ! vault auth list -format=json | jq -e "has(\"${mount}/\")" >/dev/null; then
    vault auth enable -path="$mount" kubernetes
  fi

  vault write "auth/${mount}/config" \
    token_reviewer_jwt="$reviewer_jwt" \
    kubernetes_host="$host" \
    kubernetes_ca_cert="$(echo "$ca_b64" | base64 -d)"

  cat <<POLICY | vault policy write "$role" -
path "kv/data/apps/*" {
  capabilities = ["read"]
}
POLICY

  vault write "auth/${mount}/role/${role}" \
    bound_service_account_names="external-secrets" \
    bound_service_account_namespaces="external-secrets" \
    policies="$role" \
    ttl="1h"
done

log "vault configured for External Secrets across dev/homolog/prod"
