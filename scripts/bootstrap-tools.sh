#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

: "${K3D_VERSION:=v5.8.3}"
: "${KUBECTL_VERSION:=v1.31.5}"
: "${HELM_VERSION:=v3.16.4}"
: "${KUSTOMIZE_VERSION:=v5.5.0}"
: "${YQ_VERSION:=v4.45.1}"
: "${TRIVY_VERSION:=v0.56.2}"
: "${SYFT_VERSION:=v1.18.1}"
: "${GRYPE_VERSION:=v0.84.0}"
: "${COSIGN_VERSION:=v2.4.1}"
: "${CONFTEST_VERSION:=v0.57.0}"
: "${KYVERNO_VERSION:=v1.13.4}"
: "${SOPS_VERSION:=v3.9.1}"
: "${STEP_VERSION:=v0.29.0}"
: "${VAULT_VERSION:=1.18.3}"
: "${CRANE_VERSION:=v0.20.3}"

if [[ ${EUID} -ne 0 ]]; then
  echo "run this script as root (ansible become)"
  exit 1
fi

arch="$(uname -m)"
case "$arch" in
  x86_64) arch=amd64; arch_alt=x86_64; trivy_arch=64bit ;;
  aarch64|arm64) arch=arm64; arch_alt=aarch64; trivy_arch=ARM64 ;;
  *) echo "unsupported architecture: $arch"; exit 1 ;;
esac

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y --no-install-recommends \
  ca-certificates curl git gnupg lsb-release jq unzip tar make age rsync

install_bin() {
  local src="$1"
  local dest="$2"
  install -m 0755 "$src" "$dest"
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

# kubectl
curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${arch}/kubectl" -o "$tmp_dir/kubectl"
install_bin "$tmp_dir/kubectl" /usr/local/bin/kubectl

# k3d
curl -fsSL https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | TAG="${K3D_VERSION}" bash

# helm
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 -o "$tmp_dir/get_helm.sh"
chmod +x "$tmp_dir/get_helm.sh"
DESIRED_VERSION="${HELM_VERSION}" "$tmp_dir/get_helm.sh"

# kustomize
curl -fsSL "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" -o "$tmp_dir/install_kustomize.sh"
chmod +x "$tmp_dir/install_kustomize.sh"
"$tmp_dir/install_kustomize.sh" "${KUSTOMIZE_VERSION#v}"
install_bin kustomize /usr/local/bin/kustomize
rm -f kustomize

# yq
curl -fsSL "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_${arch}" -o "$tmp_dir/yq"
install_bin "$tmp_dir/yq" /usr/local/bin/yq

# trivy
curl -fsSL "https://github.com/aquasecurity/trivy/releases/download/${TRIVY_VERSION}/trivy_${TRIVY_VERSION#v}_Linux-${trivy_arch}.tar.gz" -o "$tmp_dir/trivy.tgz"
tar -xzf "$tmp_dir/trivy.tgz" -C "$tmp_dir" trivy
install_bin "$tmp_dir/trivy" /usr/local/bin/trivy

# syft
auto_syft="${SYFT_VERSION#v}"
curl -fsSL "https://github.com/anchore/syft/releases/download/${SYFT_VERSION}/syft_${auto_syft}_linux_${arch}.tar.gz" -o "$tmp_dir/syft.tgz"
tar -xzf "$tmp_dir/syft.tgz" -C "$tmp_dir" syft
install_bin "$tmp_dir/syft" /usr/local/bin/syft

# grype
auto_grype="${GRYPE_VERSION#v}"
curl -fsSL "https://github.com/anchore/grype/releases/download/${GRYPE_VERSION}/grype_${auto_grype}_linux_${arch}.tar.gz" -o "$tmp_dir/grype.tgz"
tar -xzf "$tmp_dir/grype.tgz" -C "$tmp_dir" grype
install_bin "$tmp_dir/grype" /usr/local/bin/grype

# cosign
curl -fsSL "https://github.com/sigstore/cosign/releases/download/${COSIGN_VERSION}/cosign-linux-${arch}" -o "$tmp_dir/cosign"
install_bin "$tmp_dir/cosign" /usr/local/bin/cosign

# conftest
conftest_raw="${CONFTEST_VERSION#v}"
curl -fsSL "https://github.com/open-policy-agent/conftest/releases/download/${CONFTEST_VERSION}/conftest_${conftest_raw}_Linux_${arch_alt}.tar.gz" -o "$tmp_dir/conftest.tgz"
tar -xzf "$tmp_dir/conftest.tgz" -C "$tmp_dir" conftest
install_bin "$tmp_dir/conftest" /usr/local/bin/conftest

# kyverno cli
curl -fsSL "https://github.com/kyverno/kyverno/releases/download/${KYVERNO_VERSION}/kyverno-cli_${KYVERNO_VERSION}_linux_${arch_alt}.tar.gz" -o "$tmp_dir/kyverno.tgz"
tar -xzf "$tmp_dir/kyverno.tgz" -C "$tmp_dir" kyverno
install_bin "$tmp_dir/kyverno" /usr/local/bin/kyverno

# sops
curl -fsSL "https://github.com/getsops/sops/releases/download/${SOPS_VERSION}/sops-${SOPS_VERSION}.linux.${arch}" -o "$tmp_dir/sops"
install_bin "$tmp_dir/sops" /usr/local/bin/sops

# step cli
curl -fsSL "https://github.com/smallstep/cli/releases/download/${STEP_VERSION}/step_linux_${STEP_VERSION#v}_${arch}.tar.gz" -o "$tmp_dir/step.tgz"
tar -xzf "$tmp_dir/step.tgz" -C "$tmp_dir"
install_bin "$tmp_dir/step_${STEP_VERSION#v}/bin/step" /usr/local/bin/step

# vault
curl -fsSL "https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_${arch}.zip" -o "$tmp_dir/vault.zip"
unzip -q -o "$tmp_dir/vault.zip" -d "$tmp_dir"
install_bin "$tmp_dir/vault" /usr/local/bin/vault

# crane
curl -fsSL "https://github.com/google/go-containerregistry/releases/download/${CRANE_VERSION}/go-containerregistry_Linux_${arch_alt}.tar.gz" -o "$tmp_dir/crane.tgz"
tar -xzf "$tmp_dir/crane.tgz" -C "$tmp_dir" crane
install_bin "$tmp_dir/crane" /usr/local/bin/crane

if command -v docker >/dev/null 2>&1; then
  user_name="${SUDO_USER:-${USER:-}}"
  if [[ -n "$user_name" ]]; then
    usermod -aG docker "$user_name" || true
  fi
fi

echo "tool bootstrap complete"
