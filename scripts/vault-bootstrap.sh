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

if [[ -f "$enc_file" ]]; then
  die "encrypted init file already exists: $enc_file"
fi

kubectl --context "$CTX" -n "$NS" exec "$POD" -- vault operator init -key-shares=1 -key-threshold=1 -format=json > "$plain_file"

unseal_key="$(jq -r '.unseal_keys_b64[0]' "$plain_file")"
root_token="$(jq -r '.root_token' "$plain_file")"

kubectl --context "$CTX" -n "$NS" exec "$POD" -- vault operator unseal "$unseal_key" >/dev/null

sops --encrypt --input-type json --output-type json "$plain_file" > "$enc_file"
rm -f "$plain_file"

log "vault initialized and sealed material encrypted at ${enc_file}"
log "root token saved encrypted; use sops to decrypt only when needed"

if [[ -n "$root_token" ]]; then
  log "vault bootstrap completed"
fi
