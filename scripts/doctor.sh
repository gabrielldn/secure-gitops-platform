#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

profile="$(profile_name)"
profile_path="$(profile_file)"

log "running doctor with profile=${profile}"

if [[ ! -S /var/run/docker.sock ]]; then
  die "docker socket not found (/var/run/docker.sock)"
fi

docker_access="yes"
if ! docker info >/dev/null 2>&1; then
  docker_access="no"
fi

cpu="$(nproc)"
mem_gb="$(awk '/MemTotal/ {printf "%.1f", $2/1024/1024}' /proc/meminfo)"

if command -v yq >/dev/null 2>&1; then
  min_cpu="$(profile_value '.host.min_cpu')"
  min_mem="$(profile_value '.host.min_memory_gb')"
else
  if [[ "$profile" == "full" ]]; then
    min_cpu="8"
    min_mem="16"
  else
    min_cpu="6"
    min_mem="8"
  fi
fi

printf 'profile: %s\n' "$profile"
printf 'profile_file: %s\n' "$profile_path"
printf 'cpu: %s (min %s)\n' "$cpu" "$min_cpu"
printf 'memory_gb: %s (min %s)\n' "$mem_gb" "$min_mem"
printf 'docker_access: %s\n' "$docker_access"

if (( cpu < min_cpu )); then
  warn "cpu below recommended minimum"
fi

mem_int="${mem_gb%.*}"
if (( mem_int < min_mem )); then
  warn "memory below recommended minimum"
fi

required_tools=(docker ansible)
optional_tools=(k3d kubectl helm yq jq trivy syft grype cosign conftest kyverno sops step vault rsync)

for tool in "${required_tools[@]}"; do
  if command -v "$tool" >/dev/null 2>&1; then
    echo "tool:${tool}=ok"
  else
    echo "tool:${tool}=missing"
  fi
done

for tool in "${optional_tools[@]}"; do
  if command -v "$tool" >/dev/null 2>&1; then
    echo "tool:${tool}=ok"
  else
    echo "tool:${tool}=missing"
  fi
done

if [[ "$docker_access" == "no" ]]; then
  warn "docker is installed but current user cannot access /var/run/docker.sock"
  warn "run make bootstrap (adds user to docker group) and restart shell"
fi

if command -v helm >/dev/null 2>&1 && command -v yq >/dev/null 2>&1; then
  "${ROOT_DIR}/scripts/validate-chart-versions.sh"
else
  warn "skipping chart version validation (helm/yq missing)"
fi
