# Runbook: Podinfo Availability Burn Rate (Fast)

## Trigger

- Alerta: `PodinfoAvailabilityBurnRateFast`
- Severidade: `critical`
- Janela: `5m` com multiplicador de burn-rate `14.4x`

## Objetivo

Conter degradação rápida de disponibilidade do `podinfo` no namespace `apps` e confirmar se houve rollback automático do canary.

## Ações

1. Definir contexto alvo (`k3d-sgp-dev`, `k3d-sgp-homolog` ou `k3d-sgp-prod`):
   - `export CTX=k3d-sgp-homolog`
2. Confirmar estado atual do rollout:
   - `kubectl --context "$CTX" -n apps argo rollouts get rollout podinfo`
3. Confirmar falhas recentes de análise:
   - `kubectl --context "$CTX" -n apps get analysisrun --sort-by=.metadata.creationTimestamp`
   - `kubectl --context "$CTX" -n apps describe analysisrun <analysisrun-name>`
4. Confirmar erro em métricas:
   - `kubectl --context "$CTX" -n observability port-forward svc/kube-prometheus-stack-prometheus 9090:9090`
   - Query: `sum(rate(http_requests_total{namespace="apps",app="podinfo",code=~"5.."}[5m]))`
5. Se rollout estiver pausado/degradado, interromper progressão:
   - `kubectl --context "$CTX" -n apps argo rollouts abort podinfo`
6. Se necessário, restaurar imagem estável do overlay e reconciliar:
   - atualizar digest em `gitops/apps/workloads/podinfo/overlays/<env>/rollout-patch.yaml`
   - `make reconcile PROFILE=light`

## Critério de recuperação

- `kubectl --context "$CTX" -n apps argo rollouts get rollout podinfo` retorna `Healthy`.
- Taxa de erro volta ao patamar esperado.
- Alerta fast window deixa de disparar.
