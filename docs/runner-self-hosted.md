# GitHub Self-Hosted Runner (WSL)

This project assumes release jobs run on a self-hosted runner in WSL to access:

- local Vault
- local k3d registry mirror
- local Docker daemon

## Runner labels

Register the runner with at least:

- `self-hosted`
- `Linux`

## Required env/secrets for release workflow

- `VAULT_ADDR` and `VAULT_TOKEN`, or
- `COSIGN_PRIVATE_KEY`

## Minimum tools on runner

`docker`, `crane`, `syft`, `grype`, `trivy`, `cosign`, `vault`.
