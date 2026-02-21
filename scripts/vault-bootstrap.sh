#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

require_cmd kubectl
require_cmd jq
require_cmd sops
require_cmd age-keygen

if [[ -f "${ROOT_DIR}/.kube/config" ]]; then
  export KUBECONFIG="${ROOT_DIR}/.kube/config"
fi

CTX="${CTX:-k3d-sgp-dev}"
NS="${NS:-vault}"
POD="${POD:-vault-0}"

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

kubectl --context "$CTX" -n "$NS" exec "$POD" -- vault operator init -key-shares=1 -key-threshold=1 -format=json > "$plain_file"

unseal_key="$(jq -r '.unseal_keys_b64[0]' "$plain_file")"
root_token="$(jq -r '.root_token' "$plain_file")"

kubectl --context "$CTX" -n "$NS" exec "$POD" -- vault operator unseal "$unseal_key" >/dev/null

sealed_state="$(kubectl --context "$CTX" -n "$NS" exec "$POD" -- vault status -format=json 2>/dev/null | jq -r '.sealed' 2>/dev/null || true)"
[[ "$sealed_state" == "false" ]] || die "vault init completed, but ${POD} remains sealed"

sops --encrypt --input-type json --output-type json "$plain_file" > "$enc_file"
rm -f "$plain_file"

log "vault initialized and sealed material encrypted at ${enc_file}"
log "root token saved encrypted; use sops to decrypt only when needed"

if [[ -n "$root_token" ]]; then
  log "vault bootstrap completed"
fi
