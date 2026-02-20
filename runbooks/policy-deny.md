# Runbook: Policy Deny

## Symptoms

- ArgoCD sync fails with validation denied.
- Admission webhook returns Kyverno denial.

## Actions

1. Inspect policy report:
   - `kubectl get policyreport -A`
2. Inspect policy details:
   - `kubectl get cpol`
3. Validate manifest locally:
   - `kyverno apply policies/kyverno/base -r <manifest.yaml>`
4. Fix manifest or policy per environment matrix.

## Notes

- `dev`: expected audit-only behavior.
- `homolog`: partial enforce.
- `prod`: full enforce.
