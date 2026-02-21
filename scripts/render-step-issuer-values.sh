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

if [[ $# -eq 1 ]]; then
  kid="$1"
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
else
  echo "usage: $0 [<step-provisioner-kid>]"
  exit 1
fi

if [[ -z "${kid}" || "${kid}" == "null" ]]; then
  echo "invalid provisioner material (kid empty)"
  exit 1
fi

ca_bundle="$(base64 -w 0 "$cert_path")"

for env in dev homolog prod; do
  issuer="${ROOT_DIR}/gitops/apps/pki/cluster-issuers/${env}/issuer.yaml"

  yq -i '.spec.url = "https://host.k3d.internal:19443"' "$issuer"
  yq -i ".spec.provisioner.kid = \"${kid}\"" "$issuer"
  yq -i '.spec.provisioner.passwordRef.namespace = "cert-manager"' "$issuer"
  yq -i ".spec.caBundle = \"${ca_bundle}\"" "$issuer"
done

echo "updated step-issuer manifests for dev/homolog/prod"
