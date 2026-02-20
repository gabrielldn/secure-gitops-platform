# Runbook: Step-Issuer Cannot Reach Hub Step-CA

## Symptoms

- `StepClusterIssuer` in `homolog`/`prod` not ready.
- Errors connecting to `https://host.k3d.internal:19443`.

## Actions

1. Validate Step-CA on hub:
   - `kubectl --context k3d-sgp-dev -n step-ca get pods`
   - `kubectl --context k3d-sgp-dev -n step-ca get svc`
2. Validate dev hub host port mapping:
   - `kubectl --context k3d-sgp-dev get nodes -o wide`
   - `curl -vk https://host.k3d.internal:19443/health`
3. Re-bootstrap and render issuer material:
   - `make stepca-bootstrap`
   - `./scripts/render-step-issuer-values.sh`
4. Re-sync Argo applications:
   - `make reconcile`

## Notes

- Step-CA root trust material is in `.secrets/step-ca/`.
- Keep bootstrap payload encrypted (`bootstrap.enc.json` via SOPS+age).
