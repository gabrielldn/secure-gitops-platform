#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cert_path="${ROOT_DIR}/.secrets/step-ca/root_ca.crt"
bootstrap_enc="${ROOT_DIR}/.secrets/step-ca/bootstrap.enc.json"

if [[ ! -f "$cert_path" ]]; then
  echo "root CA cert not found at $cert_path"
  exit 1
fi

if ! command -v yq >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
  echo "yq and jq are required"
  exit 1
fi

if [[ $# -eq 2 ]]; then
  kid="$1"
  password="$2"
elif [[ $# -eq 0 ]]; then
  if [[ ! -f "$bootstrap_enc" ]]; then
    echo "missing encrypted bootstrap file: $bootstrap_enc"
    exit 1
  fi
  if ! command -v sops >/dev/null 2>&1; then
    echo "sops is required to read $bootstrap_enc"
    exit 1
  fi
  bootstrap_json="$(sops --decrypt "$bootstrap_enc")"
  kid="$(echo "$bootstrap_json" | jq -r '.provisioner_kid')"
  password="$(echo "$bootstrap_json" | jq -r '.provisioner_password')"
else
  echo "usage: $0 [<step-provisioner-kid> <step-provisioner-password>]"
  exit 1
fi

if [[ -z "${kid}" || -z "${password}" || "${kid}" == "null" || "${password}" == "null" ]]; then
  echo "invalid provisioner material (kid/password empty)"
  exit 1
fi

ca_bundle="$(base64 -w 0 "$cert_path")"
password_b64="$(printf '%s' "$password" | base64 -w 0)"

for env in dev homolog prod; do
  issuer="${ROOT_DIR}/gitops/apps/pki/cluster-issuers/${env}/issuer.yaml"
  secret="${ROOT_DIR}/gitops/apps/pki/cluster-issuers/${env}/provisioner-secret.yaml"

  yq -i '.spec.url = "https://host.k3d.internal:19443"' "$issuer"
  yq -i ".spec.provisioner.kid = \"${kid}\"" "$issuer"
  yq -i '.spec.provisioner.passwordRef.namespace = "cert-manager"' "$issuer"
  yq -i ".spec.caBundle = \"${ca_bundle}\"" "$issuer"
  yq -i '.metadata.namespace = "cert-manager"' "$secret"
  yq -i '.type = "Opaque"' "$secret"
  yq -i ".data.password = \"${password_b64}\"" "$secret"
  yq -i 'del(.stringData)' "$secret"
done

echo "updated step-issuer manifests for dev/homolog/prod"
