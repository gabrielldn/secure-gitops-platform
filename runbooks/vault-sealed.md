# Runbook: Vault Sealed/Unavailable

## Symptoms

- External Secrets cannot refresh.
- Vault health endpoint reports sealed.

## Actions

1. Check pod and status:
   - `kubectl -n vault get pods`
   - `kubectl -n vault exec vault-0 -- vault status -format=json`
   - `curl -fsS http://host.k3d.internal:18200/v1/sys/health`
2. If `initialized=false`:
   - run `make vault-bootstrap` (it archives stale `.secrets/vault/init.enc.json` automatically when needed).
3. If `initialized=true` and `sealed=true`:
   - decrypt bootstrap material: `sops --decrypt .secrets/vault/init.enc.json`
   - unseal: `kubectl -n vault exec vault-0 -- vault operator unseal <UNSEAL_KEY>`
4. Validate ESO auth mounts and roles:
   - `make vault-configure`

## Security

Never store root token or unseal key in plaintext files.
