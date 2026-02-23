#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

require_cmd kubectl
require_cmd jq
require_cmd sops
require_cmd age-keygen
require_cmd vault
require_cmd timeout

if [[ -f "${ROOT_DIR}/.kube/config" ]]; then
  export KUBECONFIG="${ROOT_DIR}/.kube/config"
fi

CTX="${CTX:-k3d-sgp-dev}"
NS="${NS:-vault}"
POD="${POD:-vault-0}"
LOCAL_VAULT_PORT="${LOCAL_VAULT_PORT:-18201}"
VAULT_PORT_FORWARD_WAIT_SECONDS="${VAULT_PORT_FORWARD_WAIT_SECONDS:-3}"
VAULT_CMD_TIMEOUT_SECONDS="${VAULT_CMD_TIMEOUT_SECONDS:-45}"

mkdir -p "${ROOT_DIR}/.secrets"
mkdir -p "${ROOT_DIR}/.secrets/vault"
mkdir -p "${HOME}/.config/sops/age"

age_key_file="${HOME}/.config/sops/age/keys.txt"
if [[ ! -f "$age_key_file" ]]; then
  log "creating age key at ${age_key_file}"
  age-keygen -o "$age_key_file"
  chmod 600 "$age_key_file"
fi

age_pub="$(grep '^# public key:' "$age_key_file" | awk '{print $4}' | tail -n1)"
[[ -n "$age_pub" ]] || die "failed to read age public key"

if [[ ! -f "${ROOT_DIR}/.sops.yaml" ]]; then
  cat > "${ROOT_DIR}/.sops.yaml" <<YAML
creation_rules:
  - path_regex: \.secrets/.*\.(yaml|yml|json)$
    encrypted_regex: '^(data|stringData|token|root_token|unseal_keys_b64)$'
    age: ${age_pub}
YAML
fi

log "waiting for Vault pod to be Running"
kubectl --context "$CTX" -n "$NS" wait --for=jsonpath='{.status.phase}'=Running pod/"$POD" --timeout=300s

plain_file="${ROOT_DIR}/.secrets/vault/init.json"
enc_file="${ROOT_DIR}/.secrets/vault/init.enc.json"
archive_dir="${ROOT_DIR}/.secrets/vault/archive"
port_forward_log="$(mktemp)"

kubectl --context "$CTX" -n "$NS" port-forward pod/"$POD" "${LOCAL_VAULT_PORT}:8200" >"$port_forward_log" 2>&1 &
pf_pid=$!
trap 'kill "$pf_pid" >/dev/null 2>&1 || true; rm -f "$port_forward_log" "$plain_file"' EXIT

sleep "$VAULT_PORT_FORWARD_WAIT_SECONDS"
if ! kill -0 "$pf_pid" >/dev/null 2>&1; then
  cat "$port_forward_log" || true
  die "failed to start vault port-forward on ${LOCAL_VAULT_PORT}"
fi

export VAULT_ADDR="http://127.0.0.1:${LOCAL_VAULT_PORT}"

read_vault_status_json() {
  local status_json
  local rc
  set +e
  status_json="$(timeout "${VAULT_CMD_TIMEOUT_SECONDS}s" vault status -format=json 2>/dev/null)"
  rc=$?
  set -e
  if [[ "$rc" -eq 124 ]]; then
    die "vault status timed out after ${VAULT_CMD_TIMEOUT_SECONDS}s"
  fi
  [[ -n "$status_json" ]] || die "unable to read Vault status from ${NS}/${POD}"
  echo "$status_json"
}

vault_status_json="$(read_vault_status_json)"
vault_initialized="$(echo "$vault_status_json" | jq -r '.initialized // "false"')"

if [[ "$vault_initialized" == "true" ]]; then
  if [[ -f "$enc_file" ]]; then
    log "vault already initialized and encrypted init material already exists at ${enc_file}; skipping bootstrap"
    exit 0
  fi
  die "vault is already initialized, but ${enc_file} is missing. Refusing to continue without existing bootstrap material."
fi

if [[ -f "$enc_file" ]]; then
  mkdir -p "$archive_dir"
  backup_file="${archive_dir}/init.$(date -u +%Y%m%dT%H%M%SZ).enc.json"
  mv "$enc_file" "$backup_file"
  warn "vault is uninitialized but encrypted init material existed; archived stale file to ${backup_file}"
fi

timeout "${VAULT_CMD_TIMEOUT_SECONDS}s" vault operator init -key-shares=1 -key-threshold=1 -format=json > "$plain_file"
[[ -s "$plain_file" ]] || die "vault init produced empty output"

unseal_key="$(jq -r '.unseal_keys_b64[0]' "$plain_file")"
root_token="$(jq -r '.root_token' "$plain_file")"
[[ -n "$unseal_key" && "$unseal_key" != "null" ]] || die "failed to read unseal key from init output"
[[ -n "$root_token" && "$root_token" != "null" ]] || die "failed to read root token from init output"

sops --encrypt --input-type json --output-type json "$plain_file" > "$enc_file"
rm -f "$plain_file"

if ! timeout "${VAULT_CMD_TIMEOUT_SECONDS}s" vault operator unseal "$unseal_key" >/dev/null; then
  warn "vault unseal command failed during bootstrap; encrypted init material is available for retry"
fi

sealed_state="true"
for _ in $(seq 1 15); do
  sealed_state="$(read_vault_status_json | jq -r '.sealed // "true"')"
  if [[ "$sealed_state" == "false" ]]; then
    break
  fi
  sleep 2
done
if [[ "$sealed_state" != "false" ]]; then
  warn "vault init completed, but ${POD} remains sealed; proceed with make vault-configure to retry unseal"
  log "vault initialized and sealed material encrypted at ${enc_file}"
  exit 0
fi

log "vault initialized and sealed material encrypted at ${enc_file}"
log "root token saved encrypted; use sops to decrypt only when needed"
log "vault bootstrap completed"
