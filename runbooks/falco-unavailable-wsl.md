# Runbook: Falco Unavailable (WSL/Kernel)

## Symptoms

- Falco DaemonSet crashloop.
- Driver/eBPF probe errors on startup.

## Actions

1. Confirm host kernel:
   - `uname -r`
2. Inspect Falco logs:
   - `kubectl -n falco logs ds/falco`
3. If the host kernel lacks required support (common on WSL), mark Falco as optional fallback path.
4. Keep mandatory controls active:
   - Kyverno enforcement
   - Trivy Operator findings
   - Kubernetes audit + alert rules

## Acceptance

`make verify` may report Falco as `SKIP` when kernel support is insufficient while still passing mandatory controls.
