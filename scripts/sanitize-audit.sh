#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

require_cmd git

REPORT_DIR="${ROOT_DIR}/artifacts/sanitization"
REPORT_FILE="${REPORT_DIR}/report.md"
mkdir -p "$REPORT_DIR"

CRITICAL_COUNT=0
declare -a FINDINGS=()

add_finding() {
  local category="$1"
  local details="$2"
  FINDINGS+=("${category}|${details}")
  CRITICAL_COUNT=$((CRITICAL_COUNT + 1))
}

check_pattern() {
  local category="$1"
  local pattern="$2"
  local matches

  matches="$(git -C "$ROOT_DIR" grep -nI -E -e "$pattern" -- . || true)"
  if [[ -n "$matches" ]]; then
    add_finding "$category" "$matches"
  fi
}

tracked_sensitive_paths="$(git -C "$ROOT_DIR" ls-files '.secrets/**' || true)"
if [[ -n "$tracked_sensitive_paths" ]]; then
  add_finding "tracked-.secrets" "$tracked_sensitive_paths"
fi

if command -v rg >/dev/null 2>&1; then
  tracked_sensitive_names="$(git -C "$ROOT_DIR" ls-files | rg -n '(\.pem$|\.key$|\.p12$|id_rsa$|id_ed25519$)' || true)"
else
  tracked_sensitive_names="$(git -C "$ROOT_DIR" ls-files | grep -nE '(\.pem$|\.key$|\.p12$|id_rsa$|id_ed25519$)' || true)"
fi

if [[ -n "$tracked_sensitive_names" ]]; then
  add_finding "sensitive-filenames" "$tracked_sensitive_names"
fi

check_pattern "private-key-header" '-----BEGIN (EC|RSA|OPENSSH|DSA|PGP|PRIVATE) KEY-----'
check_pattern "aws-access-key-id" 'AKIA[0-9A-Z]{16}'
check_pattern "aws-session-key-id" 'ASIA[0-9A-Z]{16}'
check_pattern "github-classic-token" 'ghp_[A-Za-z0-9]{36}'
check_pattern "github-fine-grained-token" 'github_pat_[A-Za-z0-9_]{20,}'
check_pattern "slack-token" 'xox[baprs]-[A-Za-z0-9-]{10,}'
check_pattern "google-api-key" 'AIza[0-9A-Za-z_-]{35}'

{
  echo "# Public Sanitization Audit"
  echo
  echo "- generated_at_utc: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "- repository: $(basename "$ROOT_DIR")"
  echo
  if (( CRITICAL_COUNT == 0 )); then
    echo "## Result"
    echo
    echo "**PASSED**: nenhum indicador crítico encontrado nos arquivos versionados."
  else
    echo "## Result"
    echo
    echo "**FAILED**: ${CRITICAL_COUNT} indicador(es) crítico(s) encontrados."
    echo
    echo "## Critical Findings"
    echo
    finding=""
    category=""
    details=""
    for finding in "${FINDINGS[@]}"; do
      IFS='|' read -r category details <<<"$finding"
      echo "### ${category}"
      echo
      echo '```text'
      echo "$details"
      echo '```'
      echo
    done
  fi
} > "$REPORT_FILE"

echo "sanitization report: ${REPORT_FILE}"

if (( CRITICAL_COUNT > 0 )); then
  exit 1
fi
