# Runbook: Podinfo Availability Burn Rate (Slow)

## Trigger

- Alerta: `PodinfoAvailabilityBurnRateSlow`
- Severidade: `warning`
- Janela: `1h` com multiplicador de burn-rate `6x`

## Objetivo

Investigar degradação sustentada de disponibilidade antes de atingir o nível crítico.

## Ações

1. Definir contexto alvo (`k3d-sgp-dev`, `k3d-sgp-homolog` ou `k3d-sgp-prod`):
   - `export CTX=k3d-sgp-homolog`
2. Confirmar tendência de erro em janela longa:
   - `kubectl --context "$CTX" -n observability port-forward svc/kube-prometheus-stack-prometheus 9090:9090`
   - Query: `1 - (sum(rate(http_requests_total{namespace="apps",app="podinfo",code=~"2..|3.."}[1h])) / sum(rate(http_requests_total{namespace="apps",app="podinfo"}[1h])))`
3. Verificar rollouts recentes:
   - `kubectl --context "$CTX" -n apps argo rollouts get rollout podinfo`
   - `kubectl --context "$CTX" -n apps get analysisrun --sort-by=.metadata.creationTimestamp`
4. Correlacionar com mudanças recentes no GitOps:
   - `git log --oneline -- gitops/apps/workloads/podinfo/overlays`
5. Validar impactos em dependências (ingress, secrets, issuer):
   - `make verify-quick PROFILE=light`
6. Se houver tendência de piora, antecipar mitigação:
   - promover digest estável:
     - `./scripts/promote-image.sh dev homolog`
     - `./scripts/promote-image.sh homolog prod`

## Critério de recuperação

- Burn-rate slow volta abaixo do limiar.
- Sem recorrência do alerta por pelo menos 1 janela completa.
