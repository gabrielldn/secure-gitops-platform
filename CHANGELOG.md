# Changelog

Todas as mudanças relevantes deste repositório são documentadas aqui.

## [1.0.0] - 2026-02-21

### Resumo

Primeira release estável do `secure-gitops-platform`, consolidando um laboratório local de plataforma/DevSecOps com:

- Kubernetes local multi-cluster (`k3d`) com topologia `hub-and-spoke`.
- GitOps central com Argo CD + ApplicationSet.
- Progressive delivery com Argo Rollouts e análise por métricas.
- Policy-as-code com Kyverno (baseline e cadeia de supply).
- Supply chain security (SBOM, scans, assinatura e attestation).
- Segredos com Vault + External Secrets Operator.
- PKI interna com Step-CA + step-issuer.
- Observabilidade e SLO com runbooks e pacote de evidências.

### Destaques Técnicos

- Entrega inicial completa da stack de plataforma, GitOps, segurança e operação local.
- Evolução de segurança/operabilidade para publicação pública:
  - migração de segredo de provisioner do Step-issuer para Vault+ESO (sem segredo sensível versionado em GitOps);
  - demo de supply chain separada (`secure-gitops-demo-app`) para não interferir no `podinfo`;
  - endurecimento de `sanitize-check` e documentação de sanitização.
- Release pipeline robusto em GitHub Actions:
  - fallback para runner GitHub-hosted quando self-hosted não está disponível;
  - fallback para assinatura keyless (OIDC) quando chave Cosign não está configurada;
  - correção para predicate type SLSA v1;
  - correção de base image da demo-app para eliminar falhas de scanner por CVEs de toolchain.
- Documentação expandida para Linux nativo (Ubuntu 24.04+) e WSL2, removendo restrição implícita a WSL.

### Escopo Entregue

- Plataforma local:
  - perfis `light/full`, lock de versões e bootstrap de toolchain via Ansible;
  - provisionamento resiliente de clusters com retry e limpeza de erro transitório;
  - automação `make` para ciclo completo (`doctor`, `up`, `reconcile`, `verify`, `evidence`, `sanitize-check`, `down`).
- GitOps e workloads:
  - bootstrap Argo CD, AppProjects e registro de clusters;
  - `podinfo` com rollout canário + `AnalysisTemplate`;
  - `demo-app` dedicado para cenários de allow/deny de supply chain.
- Segurança e compliance:
  - políticas Kyverno baseline + verifyImages/attestations por ambiente;
  - testes de policy com Kyverno + higiene adicional com Conftest;
  - auditoria de sanitização para publicação pública.
- Supply chain:
  - workflow de release com build, SBOM (Syft), scans (Grype/Trivy), assinatura Cosign e attestation (SPDX + SLSA v1);
  - validação pós-assinatura/attestation e geração de artifacts para evidência.
- Observabilidade e operação:
  - SLO/alert rules, runbooks operacionais e ADRs.

### Limitações Conhecidas (Lab Local)

- Falco permanece `best-effort` quando o kernel não oferece suporte eBPF/probe completo (cenário comum em WSL).
- O fluxo de release suporta self-hosted e GitHub-hosted; sincronização para registry local é opcional e orientada a ambiente self-hosted.

### Commits incluídos (ordem cronológica)

- `63b329d` Initial commit
- `6143f1c` Add local secure GitOps platform bootstrap and supply chain
- `28fa900` Revamps docs with detailed usage, security, and PT-BR focus
- `3ed144a` ci: fix kyverno cli asset arch for PR workflow
- `eaefe20` ci: fix kyverno cli download filename in PR workflow
- `d4a404c` ci: fix conftest asset arch in PR workflow
- `a51e883` ci: make conftest step non-blocking in PR workflow
- `4aca938` ci: scope trivy config scan to exclude test fixtures
- `b06b01c` Merge pull request #1 from gabrielldn/docs/ptbr-readme-security
- `604b972` docs: update bootstrap instructions to clarify WSL sudo password requirement
- `59b0111` fix: update script permissions to make them executable
- `f9ffeaf` feat: enhance cluster creation with retry logic and error handling
- `0100e82` improve stability
- `5444ad3` Adds supply chain evidence, sanitization audit, and ADRs
- `d503c3f` feat: enhance documentation and scripts for evidence generation and artifact handling
- `a0f02b7` Migrates workload secret provisioning to ESO; adds demo app
- `3c3d3f3` fix(ci): add github-hosted fallback for release workflow and fix PR badge status
- `df221f2` fix(supply-chain): bump demo-app builder image to patched Go 1.25.7
- `712be7a` fix(ci): fallback to keyless cosign when signing key is unavailable
- `4f1e007` fix(ci): use slsa v1 predicate type in cosign attest/verify
- `fa9b696` Generalizes Linux/WSL support and clarifies Falco limitations

