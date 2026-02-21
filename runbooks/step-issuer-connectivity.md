# Runbook: Step-Issuer Cannot Reach Hub Step-CA

## Symptoms

- `StepClusterIssuer` em `homolog`/`prod` não fica `Ready`.
- Erros de conexão para `https://host.k3d.internal:19443`.

## Ações

1. Validar Step-CA no hub:
   - `kubectl --context k3d-sgp-dev -n step-ca get pods`
   - `kubectl --context k3d-sgp-dev -n step-ca get svc`
2. Validar mapeamento de porta no hub:
   - `kubectl --context k3d-sgp-dev get nodes -o wide`
   - `curl -vk https://host.k3d.internal:19443/health`
3. Re-gerar material cifrado do Step-CA:
   - `make stepca-bootstrap`
4. Re-publicar segredos no Vault para ESO:
   - `make vault-configure`
5. Re-renderizar manifests do issuer (somente `kid`, `caBundle`, `url`):
   - `./scripts/render-step-issuer-values.sh`
6. Reconciliar GitOps:
   - `make reconcile PROFILE=light`

## Notes

- Material sensível fica em `.secrets/step-ca/` e permanece cifrado (`bootstrap.enc.json` via SOPS+age).
- O `Secret` `step-issuer-provisioner-password` deve ser criado por `ExternalSecret` em `cert-manager`.
