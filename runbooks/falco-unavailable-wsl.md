# Runbook: Falco Unavailable on WSL

## Symptoms

- Falco DaemonSet crashloop.
- Driver/eBPF probe errors on startup.

## Actions

1. Confirm host kernel:
   - `uname -r`
2. Inspect Falco logs:
   - `kubectl -n falco logs ds/falco`
3. If WSL kernel lacks required support, mark Falco as optional fallback path.
4. Keep mandatory controls active:
   - Kyverno enforcement
   - Trivy Operator findings
   - Kubernetes audit + alert rules

## Acceptance

`make verify` may report Falco as `SKIP` on WSL while still passing mandatory controls.
