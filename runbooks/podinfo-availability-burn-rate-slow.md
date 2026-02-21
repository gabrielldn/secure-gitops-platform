# Runbook: Podinfo Availability Burn Rate (Slow)

## Trigger

- Alerta: `PodinfoAvailabilityBurnRateSlow`
- Severidade: `warning`
- Janela: `1h` com multiplicador de burn-rate `6x`

## Objetivo

Investigar degradação sustentada de disponibilidade antes de atingir o nível crítico.

## Ações

1. Confirmar tendência de erro em janela longa:
   - `kubectl -n observability port-forward svc/kube-prometheus-stack-prometheus 9090:9090`
   - Query: `1 - (sum(rate(http_requests_total{namespace="apps",app="podinfo",code=~"2..|3.."}[1h])) / sum(rate(http_requests_total{namespace="apps",app="podinfo"}[1h])))`
2. Verificar se existem rollouts recentes:
   - `kubectl -n apps argo rollouts get rollout podinfo`
   - `kubectl -n apps get analysisrun --sort-by=.metadata.creationTimestamp`
3. Correlacionar com mudanças recentes no GitOps:
   - `git log --oneline -- gitops/apps/workloads/podinfo/overlays`
4. Validar impactos em dependências (ingress, secrets, issuer):
   - `make verify-quick PROFILE=light`
5. Se houver tendência de piora, antecipar mitigação:
   - promover digest estável do ambiente anterior:
     - `./scripts/promote-image.sh dev homolog`
     - `./scripts/promote-image.sh homolog prod`

## Critério de recuperação

- Burn-rate slow volta abaixo do limiar.
- Sem recorrência do alerta por pelo menos 1 janela completa.
