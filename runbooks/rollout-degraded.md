# Runbook: Rollout Degraded

## Symptoms

- Argo Rollout stuck in `Degraded` or `Paused`.
- Canary analysis metric failures.

## Actions

1. Inspect rollout status:
   - `kubectl -n apps argo rollouts get rollout podinfo`
2. Inspect AnalysisRuns:
   - `kubectl -n apps get analysisrun`
3. Check Prometheus query output in `AnalysisTemplate`.
4. Abort or promote manually only after root cause is identified:
   - `kubectl -n apps argo rollouts abort podinfo`
   - `kubectl -n apps argo rollouts promote podinfo`

## Escalation

Open incident if rollback repeats in two consecutive deploys.
