#!/usr/bin/env bash
set -euo pipefail

kernel="$(uname -r)"

if [[ "$kernel" == *microsoft* ]]; then
  echo "falco_support=best-effort"
  echo "falco_reason=host kernel may not provide required eBPF/probe features (common on WSL)"
  exit 0
fi

echo "falco_support=likely"
