#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <cosign-public-key-file>"
  exit 1
fi

key_file="$1"
[[ -f "$key_file" ]] || { echo "missing key file: $key_file"; exit 1; }

if ! command -v yq >/dev/null 2>&1; then
  echo "yq is required"
  exit 1
fi

export KEY_CONTENT
KEY_CONTENT="$(cat "$key_file")"

for policy in \
  "${ROOT_DIR}/policies/kyverno/base/verify-image-signatures.yaml"; do
  yq -i '.spec.rules[].verifyImages[].attestors[].entries[].keys.publicKeys = strenv(KEY_CONTENT)' "$policy"
done

yq -i '.spec.rules[].verifyImages[].attestations[].attestors[].entries[].keys.publicKeys = strenv(KEY_CONTENT)' \
  "${ROOT_DIR}/policies/kyverno/base/verify-image-attestations.yaml"

yq -i '.data."cosign.pub" = strenv(KEY_CONTENT)' \
  "${ROOT_DIR}/gitops/apps/security/cosign-public-key/cosign-public-key.yaml"

echo "cosign public key rendered into policy and configmap manifests"
