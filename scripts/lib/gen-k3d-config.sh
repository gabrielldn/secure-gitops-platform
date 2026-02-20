#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 7 ]]; then
  echo "usage: $0 <name> <servers> <agents> <api_port> <http_port> <https_port> <out_file>" >&2
  exit 1
fi

name="$1"
servers="$2"
agents="$3"
api_port="$4"
http_port="$5"
https_port="$6"
out_file="$7"

cat > "$out_file" <<YAML
apiVersion: k3d.io/v1alpha5
kind: Simple
metadata:
  name: ${name}
servers: ${servers}
agents: ${agents}
image: rancher/k3s:v1.31.5-k3s1
kubeAPI:
  hostIP: "0.0.0.0"
  hostPort: "${api_port}"
ports:
  - port: ${http_port}:80
    nodeFilters:
      - loadbalancer
  - port: ${https_port}:443
    nodeFilters:
      - loadbalancer
$(if [[ "$name" == "sgp-dev" ]]; then cat <<'PORTS'
  - port: 18200:30200
    nodeFilters:
      - loadbalancer
  - port: 19443:30443
    nodeFilters:
      - loadbalancer
PORTS
fi)
options:
  k3d:
    wait: true
    timeout: "300s"
  k3s:
    extraArgs:
      - arg: --disable=traefik
        nodeFilters:
          - server:*
      - arg: --disable=servicelb
        nodeFilters:
          - server:*
      - arg: --tls-san=host.k3d.internal
        nodeFilters:
          - server:*
registries:
  use:
    - k3d-sgp-registry.localhost:5001
YAML
