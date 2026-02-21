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
NS="${NS:-step-ca}"
RELEASE_PREFIX="${RELEASE_PREFIX:-}"

mkdir -p "${ROOT_DIR}/.secrets/step-ca"
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
    encrypted_regex: '^(data|stringData|token|root_token|unseal_keys_b64|provisioner_password)$'
    age: ${age_pub}
YAML
fi

log "waiting Step-CA bootstrap resources on ${CTX}/${NS}"
if [[ -z "$RELEASE_PREFIX" ]]; then
  RELEASE_PREFIX="$(kubectl --context "$CTX" -n "$NS" get statefulset \
    -l app.kubernetes.io/instance=step-ca,app.kubernetes.io/name=step-certificates \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
fi
[[ -n "$RELEASE_PREFIX" ]] || die "could not detect Step-CA statefulset prefix in ${CTX}/${NS}"

kubectl --context "$CTX" -n "$NS" wait --for=jsonpath='{.status.readyReplicas}'=1 statefulset/"${RELEASE_PREFIX}" --timeout=300s
kubectl --context "$CTX" -n "$NS" get configmap "${RELEASE_PREFIX}-certs" >/dev/null
kubectl --context "$CTX" -n "$NS" get configmap "${RELEASE_PREFIX}-config" >/dev/null
kubectl --context "$CTX" -n "$NS" get secret "${RELEASE_PREFIX}-provisioner-password" >/dev/null

root_cert_file="${ROOT_DIR}/.secrets/step-ca/root_ca.crt"
bootstrap_plain="${ROOT_DIR}/.secrets/step-ca/bootstrap.json"
bootstrap_enc="${ROOT_DIR}/.secrets/step-ca/bootstrap.enc.json"

kubectl --context "$CTX" -n "$NS" get configmap "${RELEASE_PREFIX}-certs" -o jsonpath='{.data.root_ca\.crt}' > "$root_cert_file"

ca_json_tmp="$(mktemp)"
trap 'rm -f "$ca_json_tmp"' EXIT
kubectl --context "$CTX" -n "$NS" get configmap "${RELEASE_PREFIX}-config" -o jsonpath='{.data.ca\.json}' > "$ca_json_tmp"

provisioner_kid="$(jq -r '.authority.provisioners[] | select(.name=="admin") | .key.kid' "$ca_json_tmp")"
[[ -n "$provisioner_kid" && "$provisioner_kid" != "null" ]] || die "failed to extract provisioner kid"

provisioner_password="$(kubectl --context "$CTX" -n "$NS" get secret "${RELEASE_PREFIX}-provisioner-password" -o jsonpath='{.data.password}' | base64 -d)"
[[ -n "$provisioner_password" ]] || die "failed to extract provisioner password"

cat > "$bootstrap_plain" <<JSON
{
  "generated_at": "$(date -u +%FT%TZ)",
  "cluster": "${CTX}",
  "provisioner_name": "admin",
  "provisioner_kid": "${provisioner_kid}",
  "provisioner_password": "${provisioner_password}",
  "step_ca_url_external": "https://host.k3d.internal:19443",
  "step_ca_url_internal": "https://step-ca.step-ca.svc.cluster.local"
}
JSON

sops --encrypt --input-type json --output-type json "$bootstrap_plain" > "$bootstrap_enc"
rm -f "$bootstrap_plain"

log "step-ca root CA saved at ${root_cert_file}"
log "encrypted step-ca bootstrap saved at ${bootstrap_enc}"
log "next: ./scripts/render-step-issuer-values.sh"
