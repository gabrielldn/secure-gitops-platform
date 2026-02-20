#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

require_cmd kubectl
require_cmd helm
require_cmd git
require_cmd sed

DEV_CONTEXT="${DEV_CONTEXT:-k3d-sgp-dev}"
ARGOCD_CHART_VERSION="${ARGOCD_CHART_VERSION:-7.8.5}"
GITOPS_REVISION="${GITOPS_REVISION:-main}"
REPO_URL="${REPO_URL:-}"

if [[ -f "${ROOT_DIR}/.kube/config" ]]; then
  export KUBECONFIG="${ROOT_DIR}/.kube/config"
fi

prepare_local_git_repo() {
  require_cmd rsync

  local render_root="${ROOT_DIR}/.tmp/gitops-rendered"
  local pid_file="${ROOT_DIR}/.tmp/git-daemon.pid"
  local log_file="${ROOT_DIR}/.tmp/git-daemon.log"
  local repo_name
  local worktree
  local repo_url

  mkdir -p "${ROOT_DIR}/.tmp"

  if [[ -f "$pid_file" ]]; then
    old_pid="$(cat "$pid_file" 2>/dev/null || true)"
    if [[ -n "$old_pid" ]] && kill -0 "$old_pid" >/dev/null 2>&1; then
      kill "$old_pid" >/dev/null 2>&1 || true
      sleep 1
    fi
    rm -f "$pid_file"
  fi

  repo_name="$(basename "$ROOT_DIR")"
  worktree="${render_root}/${repo_name}.git"
  repo_url="git://host.k3d.internal:9418/${repo_name}.git"

  rm -rf "$render_root"
  mkdir -p "$worktree"

  rsync -a \
    --delete \
    --exclude '.git' \
    --exclude '.kube' \
    --exclude '.secrets' \
    --exclude '.tmp' \
    "${ROOT_DIR}/" "${worktree}/"

  find "$worktree" -type f \( -name '*.yaml' -o -name '*.yml' -o -name '*.sh' \) -print0 \
    | xargs -0 sed -i \
      -e "s#__REPO_URL__#${repo_url}#g" \
      -e "s#__GITOPS_REVISION__#${GITOPS_REVISION}#g"

  git -C "$worktree" init -b main >/dev/null
  git -C "$worktree" config user.name "sgp-bootstrap"
  git -C "$worktree" config user.email "sgp-bootstrap@local"
  git -C "$worktree" add . >/dev/null
  git -C "$worktree" commit -m "render gitops manifests" >/dev/null

  git daemon \
    --export-all \
    --base-path="$render_root" \
    --reuseaddr \
    --informative-errors \
    --listen=0.0.0.0 \
    --port=9418 \
    --detach \
    --pid-file="$pid_file" \
    "$render_root" >"$log_file" 2>&1 || true

  sleep 1
  if [[ ! -f "$pid_file" ]]; then
    tail -n 100 "$log_file" || true
    die "failed to start local git daemon (pid file missing)"
  fi

  daemon_pid="$(cat "$pid_file")"
  if ! kill -0 "$daemon_pid" >/dev/null 2>&1; then
    tail -n 100 "$log_file" || true
    die "failed to start local git daemon"
  fi

  echo "$repo_url"
}

normalize_repo_url() {
  local url="$1"
  if [[ "$url" == git@github.com:* ]]; then
    url="https://github.com/${url#git@github.com:}"
  fi
  echo "${url%.git}.git"
}

if [[ -z "$REPO_URL" ]]; then
  REPO_URL="$(prepare_local_git_repo)"
  log "using local rendered git repo: ${REPO_URL}"
else
  REPO_URL="$(normalize_repo_url "$REPO_URL")"
  log "using provided git repo: ${REPO_URL}"
fi

log "installing ArgoCD on ${DEV_CONTEXT}"
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null
helm repo update >/dev/null
kubectl --context "$DEV_CONTEXT" create namespace argocd --dry-run=client -o yaml | kubectl --context "$DEV_CONTEXT" apply -f -
helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --version "$ARGOCD_CHART_VERSION" \
  --values "${ROOT_DIR}/platform/argocd-values.yaml"

"${ROOT_DIR}/scripts/register-clusters.sh"

log "applying ArgoCD projects and applicationset"
kubectl --context "$DEV_CONTEXT" apply -f "${ROOT_DIR}/gitops/bootstrap/appprojects.yaml"

appset_tmp="$(mktemp)"
trap 'rm -f "$appset_tmp"' EXIT
sed \
  -e "s#__REPO_URL__#${REPO_URL}#g" \
  -e "s#__GITOPS_REVISION__#${GITOPS_REVISION}#g" \
  "${ROOT_DIR}/gitops/bootstrap/applicationset.yaml" > "$appset_tmp"
kubectl --context "$DEV_CONTEXT" apply -f "$appset_tmp"

log "GitOps bootstrap done"
