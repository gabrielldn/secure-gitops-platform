#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CERT_PATH="${1:-${ROOT_DIR}/.secrets/step-ca/root_ca.crt}"
TARGET="/usr/local/share/ca-certificates/sgp-step-ca.crt"

if [[ ! -f "$CERT_PATH" ]]; then
  echo "certificate not found: $CERT_PATH"
  echo "expected after Step-CA bootstrap"
  exit 1
fi

sudo cp "$CERT_PATH" "$TARGET"
sudo update-ca-certificates

echo "Step-CA root trusted in WSL"
