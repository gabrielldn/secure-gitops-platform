# Modelo de Segurança e Blast Radius

Este documento descreve o particionamento de privilégios entre componentes de plataforma e workloads.

## Princípios

1. Separar identidade de automação por domínio:
   - `platform`: operadores e recursos cluster-scope.
   - `workloads`: aplicações no namespace `apps`.
2. Reduzir blast radius entre ambientes:
   - credenciais distintas para `dev`, `homolog`, `prod`.
3. Aplicar policy enforcement por ambiente:
   - `dev`: audit majoritário.
   - `homolog`: enforcement de supply chain.
   - `prod`: enforcement total.

## AppProjects e destinos

Definidos em `gitops/bootstrap/appprojects.yaml`:

- `platform-core`:
  - destinos: `sgp-*-platform`
  - escopo: cluster-scope + namespaces de operadores.
- `workloads-dev`, `workloads-homolog`, `workloads-prod`:
  - destinos: `sgp-*-workloads`
  - namespace permitido: `apps`
  - sourceRepos permitidos:
    - `git://host.k3d.internal:9418/*`
    - `https://github.com/*/*`
  - namespaceResourceWhitelist explícito:
    - `apps/Deployment`
    - `argoproj.io/Rollout`
    - `argoproj.io/AnalysisTemplate`
    - `networking.k8s.io/Ingress`
    - `v1/Service`
    - `monitoring.coreos.com/PodMonitor`

## Registro de clusters e Service Accounts

Definido em `scripts/register-clusters.sh`:

- SA `argocd-platform-<env>`:
  - binding: `cluster-admin` (necessário para instalação/gestão de CRDs e operadores).
  - secret no Argo CD: `cluster-sgp-<env>-platform`.
- SA `argocd-workloads-<env>`:
  - leitura cluster-wide para discovery (`get/list/watch`), sem `nonResourceURLs`.
  - escrita limitada via `Role` no namespace `apps` para:
    - `Deployment`
    - `Rollout`
    - `AnalysisTemplate`
    - `Ingress`
    - `Service`
    - `PodMonitor`
  - secret no Argo CD: `cluster-sgp-<env>-workloads`.

## Matriz de permissões (resumo)

| Domínio | Identidade | Escopo de escrita | Escopo de leitura |
|---|---|---|---|
| Platform | `argocd-platform-<env>` | cluster-scope | cluster-scope |
| Workloads | `argocd-workloads-<env>` | namespace `apps` (lista explícita de recursos) | cluster-scope (somente leitura) |

## Separação de instalações

- Instalações de plataforma (cluster-scope):
  - Argo Rollouts, Kyverno, cert-manager, External Secrets, Trivy Operator, Falco, observabilidade, Step-issuer.
- Instalações de workload:
  - overlays em `gitops/apps/workloads/*`, com deploy em `apps`.

## Controles complementares

1. Supply chain: Kyverno `verify-image-signatures` e `verify-image-attestations`.
2. Segredos: Vault + External Secrets Operator.
3. PKI interna: Step-CA + step-issuer.
4. Evidência contínua:
   - `make evidence IMAGE_REF=...`
   - `make sanitize-check`
