# secure-gitops-platform

Production-like local Kubernetes platform for WSL using `k3d` + 3 clusters (`dev`, `homolog`, `prod`) with:

- GitOps: ArgoCD + ApplicationSet (hub-and-spoke)
- Progressive Delivery: Argo Rollouts (canary + analysis + rollback)
- Policy as Code: Kyverno (baseline + supply chain gates)
- Secrets and PKI: Vault + External Secrets + Step-CA + step-issuer
- Supply Chain Security: SBOM, image scan, cosign signatures, SLSA-style attestation
- Runtime Security: Trivy Operator (+ Falco best-effort on WSL)
- Observability: Prometheus/Loki/Tempo + OpenTelemetry Collector

## Repository contracts

- `Makefile` is the operational entrypoint.
- `platform/versions.lock.yaml` pins CLI/chart/image versions.
- `platform/profiles/{full,light}.yaml` controls host sizing expectations.
- `gitops/bootstrap/` contains ArgoCD projects and root ApplicationSet.
- `gitops/clusters/{dev,homolog,prod}/` defines cluster-specific Application sets.
- Deployments should use immutable image digests.

## Quick start

1. Check prerequisites and host profile:

```bash
make doctor PROFILE=light
```

2. Install toolchain:

```bash
make bootstrap
```

If `make` is not installed yet:

```bash
cd ansible
ansible-playbook playbooks/bootstrap.yml --ask-become-pass
```

3. Provision registry + clusters:

```bash
make up PROFILE=light
```

4. Bootstrap ArgoCD and converge critical GitOps apps:

```bash
make reconcile
```

5. Initialize Vault/Step-CA bootstrap material and configure ESO auth:

```bash
make vault-bootstrap
make vault-configure
make stepca-bootstrap
./scripts/render-step-issuer-values.sh
```

6. Verify platform status:

```bash
make verify-quick
make verify
```

7. Teardown:

```bash
make down
```

## Important docs

- Prerequisites: `docs/prerequisites.md`
- Operations: `docs/operations.md`
- Self-hosted runner: `docs/runner-self-hosted.md`
- Optional ACME flow: `docs/pki-acme-optional.md`

## Notes

- Falco is optional/best-effort in WSL; fallback controls remain mandatory.
- Step-issuer is the primary certificate path. ACME is optional.
- Vault bootstrap material is encrypted with SOPS+age under `.secrets/`.
