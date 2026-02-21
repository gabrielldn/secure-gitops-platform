#!/usr/bin/env bash
set -euo pipefail

kernel="$(uname -r)"

if [[ "$kernel" == *microsoft* ]]; then
  echo "falco_support=best-effort"
  echo "falco_reason=WSL kernel may not provide required eBPF/probe features"
  exit 0
fi

echo "falco_support=likely"
