# Runbook: Podinfo Availability Burn Rate (Fast)

## Trigger

- Alerta: `PodinfoAvailabilityBurnRateFast`
- Severidade: `critical`
- Janela: `5m` com multiplicador de burn-rate `14.4x`

## Objetivo

Conter degradação rápida de disponibilidade do `podinfo` no namespace `apps` e confirmar se houve rollback automático do canary.

## Ações

1. Confirmar o estado atual do rollout:
   - `kubectl -n apps argo rollouts get rollout podinfo`
2. Confirmar falhas recentes de análise:
   - `kubectl -n apps get analysisrun --sort-by=.metadata.creationTimestamp`
   - `kubectl -n apps describe analysisrun <analysisrun-name>`
3. Confirmar erro em métricas:
   - `kubectl -n observability port-forward svc/kube-prometheus-stack-prometheus 9090:9090`
   - Query: `sum(rate(http_requests_total{namespace="apps",app="podinfo",code=~"5.."}[5m]))`
4. Se rollout estiver pausado/degradado, interromper progressão:
   - `kubectl -n apps argo rollouts abort podinfo`
5. Se necessário, restaurar imagem estável do overlay e reconciliar:
   - atualizar digest em `gitops/apps/workloads/podinfo/overlays/<env>/rollout-patch.yaml`
   - `make reconcile PROFILE=light`

## Critério de recuperação

- `kubectl -n apps argo rollouts get rollout podinfo` retorna `Healthy`.
- Taxa de erro volta ao patamar esperado.
- Alertas fast window deixam de disparar.
