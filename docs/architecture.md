# Architecture

## Topology

- `sgp-dev`: hub cluster (ArgoCD, Vault, Step-CA, central observability, dev workloads).
- `sgp-homolog`: spoke cluster.
- `sgp-prod`: spoke cluster.

ArgoCD runs in `sgp-dev` and applies environment apps to all clusters.

### Argo destinations

- Platform destinations: `sgp-<env>-platform` (cluster-scope operators and infra).
- Workload destinations: `sgp-<env>-workloads` (namespace-scoped workloads in `apps`).

### Hub endpoints for spokes

- Vault (hub service): `http://host.k3d.internal:18200`.
- Step-CA (hub service): `https://host.k3d.internal:19443`.

## Promotion model

- Promotion is PR-based (`dev -> homolog -> prod`).
- Environment overlays are stored in `gitops/apps/workloads/podinfo/overlays/*`.

## Policy enforcement matrix

- `dev`: audit.
- `homolog`: partial enforce (supply-chain policies audit).
- `prod`: full enforce.

## Registry model

- Source of truth: GHCR.
- Local k3d registry: mirror/cache for local runtime.
- All deployments should reference digests.
