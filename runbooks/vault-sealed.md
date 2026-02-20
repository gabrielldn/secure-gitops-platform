# Runbook: Vault Sealed/Unavailable

## Symptoms

- External Secrets cannot refresh.
- Vault health endpoint reports sealed.

## Actions

1. Check pod and status:
   - `kubectl -n vault get pods`
   - `kubectl -n vault exec vault-0 -- vault status`
   - `curl -fsS http://host.k3d.internal:18200/v1/sys/health`
2. Decrypt bootstrap material:
   - `sops --decrypt .secrets/vault/init.enc.json`
3. Unseal:
   - `kubectl -n vault exec vault-0 -- vault operator unseal <UNSEAL_KEY>`
4. Validate ESO auth mounts and roles:
   - `make vault-configure`

## Security

Never store root token or unseal key in plaintext files.
