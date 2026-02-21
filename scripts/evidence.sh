#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

usage() {
  cat <<'EOF'
usage: ./scripts/evidence.sh --image-ref <image@sha256:...> [--key-file <cosign.pub>] [--output-dir <dir>] [--include-cluster|--no-cluster]

options:
  --image-ref <ref>     Image reference with digest to validate (required)
  --key-file <path>     Cosign public key file (optional; defaults to gitops/apps/security/cosign-public-key/cosign-public-key.yaml)
  --output-dir <dir>    Output directory (optional; default artifacts/evidence/<UTC timestamp>)
  --include-cluster     Include policyreport exports from local clusters (default)
  --no-cluster          Skip cluster policyreport exports
  -h, --help            Show this help
EOF
}

IMAGE_REF=""
KEY_FILE=""
OUTPUT_DIR=""
INCLUDE_CLUSTER="true"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --image-ref)
      IMAGE_REF="${2:-}"
      shift 2
      ;;
    --key-file)
      KEY_FILE="${2:-}"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="${2:-}"
      shift 2
      ;;
    --include-cluster)
      INCLUDE_CLUSTER="true"
      shift
      ;;
    --no-cluster)
      INCLUDE_CLUSTER="false"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

[[ -n "$IMAGE_REF" ]] || die "--image-ref is required"

if [[ -n "$OUTPUT_DIR" ]]; then
  EVIDENCE_DIR="$OUTPUT_DIR"
else
  EVIDENCE_DIR="${ROOT_DIR}/artifacts/evidence/$(date -u +%Y%m%dT%H%M%SZ)"
fi

mkdir -p \
  "${EVIDENCE_DIR}/metadata" \
  "${EVIDENCE_DIR}/sbom" \
  "${EVIDENCE_DIR}/scan" \
  "${EVIDENCE_DIR}/cosign" \
  "${EVIDENCE_DIR}/cluster"

SUMMARY_FILE="${EVIDENCE_DIR}/summary.md"
TOOLS_FILE="${EVIDENCE_DIR}/metadata/tools-versions.txt"
KEY_COPY_FILE="${EVIDENCE_DIR}/cosign/cosign.pub"

if [[ -f "${ROOT_DIR}/.kube/config" ]]; then
  export KUBECONFIG="${ROOT_DIR}/.kube/config"
fi

require_cmd cosign
require_cmd syft
require_cmd grype
require_cmd trivy

if [[ -n "$KEY_FILE" ]]; then
  [[ -f "$KEY_FILE" ]] || die "cosign key file not found: $KEY_FILE"
  cp "$KEY_FILE" "$KEY_COPY_FILE"
else
  require_cmd yq
  key_manifest="${ROOT_DIR}/gitops/apps/security/cosign-public-key/cosign-public-key.yaml"
  [[ -f "$key_manifest" ]] || die "cosign key manifest not found: $key_manifest"
  yq -r '.data."cosign.pub"' "$key_manifest" > "$KEY_COPY_FILE"
fi

if [[ ! -s "$KEY_COPY_FILE" ]]; then
  die "resolved cosign key is empty: $KEY_COPY_FILE"
fi

if [[ -z "$KEY_FILE" ]] && grep -q "REPLACE_WITH_COSIGN_PUBLIC_KEY" "$KEY_COPY_FILE"; then
  die "cosign public key manifest is not rendered. Run ./scripts/render-cosign-public-key.sh <cosign-public-key-file> or set COSIGN_PUBLIC_KEY_FILE=<cosign.pub>"
fi

printf '%s\n' "$IMAGE_REF" > "${EVIDENCE_DIR}/metadata/image-ref.txt"

collect_tool_versions() {
  {
    echo "generated_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    for tool in cosign syft grype trivy kubectl yq; do
      if command -v "$tool" >/dev/null 2>&1; then
        case "$tool" in
          kubectl)
            version="$($tool version --client 2>/dev/null | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g')"
            ;;
          *)
            version="$($tool version 2>/dev/null | head -n 1 | tr -d '\r')"
            ;;
        esac
        [[ -n "$version" ]] || version="unknown"
        printf '%s=%s\n' "$tool" "$version"
      else
        printf '%s=missing\n' "$tool"
      fi
    done
  } > "$TOOLS_FILE"
}

declare -a SUMMARY_ROWS=()
FAILURES=0

record_summary() {
  local step="$1"
  local status="$2"
  local artifact="$3"
  SUMMARY_ROWS+=("${step}|${status}|${artifact}")
}

# Capture stdout/stderr together to preserve CLI evidence exactly as executed.
run_capture() {
  local step="$1"
  local output_file="$2"
  shift 2

  if "$@" >"$output_file" 2>&1; then
    record_summary "$step" "PASS" "$output_file"
    return 0
  fi

  record_summary "$step" "FAIL" "$output_file"
  FAILURES=$((FAILURES + 1))
  return 1
}

run_json_with_stderr() {
  local step="$1"
  local output_json="$2"
  local output_err="$3"
  shift 3

  if "$@" >"$output_json" 2>"$output_err"; then
    record_summary "$step" "PASS" "$output_json"
    return 0
  fi

  record_summary "$step" "FAIL" "$output_json (stderr: ${output_err})"
  FAILURES=$((FAILURES + 1))
  return 1
}

collect_cluster_policy_reports() {
  local contexts=(k3d-sgp-dev k3d-sgp-homolog k3d-sgp-prod)
  local ctx

  if [[ "$INCLUDE_CLUSTER" != "true" ]]; then
    record_summary "cluster-policyreports" "SKIP" "disabled by --no-cluster"
    return
  fi

  if ! command -v kubectl >/dev/null 2>&1; then
    record_summary "cluster-policyreports" "SKIP" "kubectl not available"
    return
  fi

  for ctx in "${contexts[@]}"; do
    local ctx_dir="${EVIDENCE_DIR}/cluster/${ctx}"
    local policyreport_file="${ctx_dir}/policyreport.yaml"
    local clusterpolicyreport_file="${ctx_dir}/clusterpolicyreport.yaml"

    mkdir -p "$ctx_dir"

    if ! kubectl --context "$ctx" get ns >/dev/null 2>&1; then
      record_summary "${ctx}-policyreports" "SKIP" "context unavailable"
      continue
    fi

    if kubectl --context "$ctx" get policyreport -A -o yaml >"$policyreport_file" 2>"${ctx_dir}/policyreport.err.log"; then
      record_summary "${ctx}-policyreport" "PASS" "$policyreport_file"
    else
      record_summary "${ctx}-policyreport" "FAIL" "${ctx_dir}/policyreport.err.log"
      FAILURES=$((FAILURES + 1))
    fi

    if kubectl --context "$ctx" get clusterpolicyreport -o yaml >"$clusterpolicyreport_file" 2>"${ctx_dir}/clusterpolicyreport.err.log"; then
      record_summary "${ctx}-clusterpolicyreport" "PASS" "$clusterpolicyreport_file"
    else
      record_summary "${ctx}-clusterpolicyreport" "FAIL" "${ctx_dir}/clusterpolicyreport.err.log"
      FAILURES=$((FAILURES + 1))
    fi
  done
}

write_summary() {
  {
    echo "# Evidence Summary"
    echo
    echo "- generated_at_utc: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "- image_ref: \`${IMAGE_REF}\`"
    echo "- cosign_key: \`${KEY_COPY_FILE}\`"
    echo "- include_cluster_reports: \`${INCLUDE_CLUSTER}\`"
    echo
    echo "| Step | Status | Artifact |"
    echo "|---|---|---|"
    local row step status artifact
    for row in "${SUMMARY_ROWS[@]}"; do
      IFS='|' read -r step status artifact <<<"$row"
      echo "| ${step} | ${status} | \`${artifact}\` |"
    done
    echo
    if (( FAILURES > 0 )); then
      echo "**result:** FAILED (${FAILURES} step(s) com falha)"
    else
      echo "**result:** PASSED"
    fi
  } > "$SUMMARY_FILE"
}

collect_tool_versions

run_capture "cosign-verify-signature" "${EVIDENCE_DIR}/cosign/verify-signature.txt" \
  cosign verify --key "$KEY_COPY_FILE" "$IMAGE_REF" || true

run_capture "cosign-verify-attestation-spdx" "${EVIDENCE_DIR}/cosign/verify-attestation-spdx.txt" \
  cosign verify-attestation --key "$KEY_COPY_FILE" --type spdx "$IMAGE_REF" || true

run_capture "cosign-verify-attestation-slsa" "${EVIDENCE_DIR}/cosign/verify-attestation-slsa.txt" \
  cosign verify-attestation --key "$KEY_COPY_FILE" --type slsaprovenance "$IMAGE_REF" || true

run_json_with_stderr "syft-sbom" "${EVIDENCE_DIR}/sbom/sbom.spdx.json" "${EVIDENCE_DIR}/sbom/syft.err.log" \
  syft "$IMAGE_REF" -o spdx-json || true

run_json_with_stderr "grype-scan" "${EVIDENCE_DIR}/scan/grype.json" "${EVIDENCE_DIR}/scan/grype.err.log" \
  grype "$IMAGE_REF" --fail-on high -o json || true

run_json_with_stderr "trivy-scan" "${EVIDENCE_DIR}/scan/trivy.json" "${EVIDENCE_DIR}/scan/trivy.err.log" \
  trivy image --format json --severity HIGH,CRITICAL --exit-code 1 "$IMAGE_REF" || true

collect_cluster_policy_reports
write_summary

echo "evidence directory: ${EVIDENCE_DIR}"
echo "summary: ${SUMMARY_FILE}"

if (( FAILURES > 0 )); then
  exit 1
fi
