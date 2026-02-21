# Secure GitOps Platform

[![Licença MIT](https://img.shields.io/badge/Licen%C3%A7a-MIT-yellow.svg)](LICENSE)
![WSL Ubuntu 24.04](https://img.shields.io/badge/WSL-Ubuntu%2024.04-E95420?logo=ubuntu&logoColor=white)
![k3d 3 clusters](https://img.shields.io/badge/k3d-3%20clusters-326CE5?logo=kubernetes&logoColor=white)
![Kubernetes v1.31.5](https://img.shields.io/badge/Kubernetes-v1.31.5-326CE5?logo=kubernetes&logoColor=white)
![PR Policy](https://img.shields.io/github/actions/workflow/status/gabrielldn/secure-gitops-platform/pr.yml?label=PR%20Policy)
![Release Supply Chain](https://img.shields.io/github/actions/workflow/status/gabrielldn/secure-gitops-platform/release.yml?label=Release%20Supply%20Chain)

Plataforma Kubernetes local `production-like` para laboratório DevSecOps em WSL, com `k3d` + 3 clusters (`sgp-dev`, `sgp-homolog`, `sgp-prod`), GitOps central, políticas de segurança, supply chain, PKI, gestão de segredos, rollout progressivo e observabilidade.

## Objetivo do projeto

Entregar um ambiente reproduzível para praticar e demonstrar:

- GitOps multi-cluster com governança por ambiente.
- Progressive delivery com rollback automático.
- Policy-as-code e controles de admissão.
- Supply chain security (SBOM, scan, assinatura e attestation).
- Gestão de segredos com Vault + External Secrets.
- PKI interna com Step-CA + step-issuer.
- Observabilidade e SLO operacional.

## Stack principal

- Orquestração local: `k3d` + registry local (`localhost:5001`).
- GitOps: Argo CD + ApplicationSet.
- Delivery: Argo Rollouts.
- Policy-as-code: Kyverno.
- Segredos: Vault + External Secrets Operator.
- PKI: cert-manager + Step-CA + step-issuer.
- Runtime security: Trivy Operator + Falco (best-effort em WSL).
- Observabilidade: kube-prometheus-stack, Loki, Tempo, OpenTelemetry Collector.
- Supply chain: Syft, Grype, Trivy, Cosign, proveniência estilo SLSA.

## Topologia resumida

- `sgp-dev` (hub): Argo CD central, Vault, Step-CA, observabilidade completa e workloads de dev.
- `sgp-homolog` (spoke): workloads, operadores e Prometheus para análise de rollout/SLO.
- `sgp-prod` (spoke): workloads, operadores e Prometheus para análise de rollout/SLO.

Portas locais relevantes no host:

- Ingress `dev`: `8081` (HTTP), `8444` (HTTPS)
- Ingress `homolog`: `8082` (HTTP), `8445` (HTTPS)
- Ingress `prod`: `8083` (HTTP), `8446` (HTTPS)
- Vault hub (via LB dev): `http://host.k3d.internal:18200`
- Step-CA hub (via LB dev): `https://host.k3d.internal:19443`

## Contratos do repositório

- Operação: `Makefile` (`make doctor`, `make up`, `make reconcile`, `make verify`, etc.).
- Versões pinadas: `platform/versions.lock.yaml`.
- Perfis de sizing: `platform/profiles/light.yaml` e `platform/profiles/full.yaml`.
- Bootstrap GitOps: `gitops/bootstrap/`.
- Fonte de verdade por ambiente: `gitops/clusters/{dev,homolog,prod}/`.
- Políticas: `policies/kyverno/` + testes em `policies/tests/kyverno/`.
- SLO e alertas: `slo/`.
- Runbooks operacionais: `runbooks/`.
- Evidências reproduzíveis: `make evidence` em `artifacts/evidence/`.
- Governança técnica: `docs/adr/`, `CONTRIBUTING.md`, `CODEOWNERS`.

## Começando rápido (fluxo recomendado)

1. Validar host e ferramentas:

```bash
make doctor PROFILE=light
```

2. Instalar toolchain (quando necessário):

```bash
make bootstrap
```

Durante esse passo, quando aparecer `BECOME password:`, informe a senha do seu usuário no `sudo` do WSL (não é senha do GitHub, token nem senha de Vault).

3. Subir registry + clusters:

```bash
make up PROFILE=light
```

4. Bootstrap GitOps e convergência inicial:

```bash
make reconcile PROFILE=light
```

Verbose já é padrão no `make reconcile`. Para saída reduzida:

```bash
make reconcile PROFILE=light RECONCILE_VERBOSE=false
```

5. Material de segredos/PKI:

```bash
make vault-bootstrap
make stepca-bootstrap
make vault-configure
./scripts/render-step-issuer-values.sh
make reconcile PROFILE=light
```

6. Verificação:

```bash
make verify-quick PROFILE=light
make verify PROFILE=light
```

7. Desligar ambiente:

```bash
make down
```

8. Gerar evidências do supply chain:

```bash
./scripts/render-cosign-public-key.sh /caminho/para/cosign.pub
make reconcile PROFILE=light
gh auth status
RUN_ID="$(gh run list --workflow release.yml --limit 20 --json databaseId,conclusion -R gabrielldn/secure-gitops-platform -q '[.[] | select(.conclusion=="success")][0].databaseId')"
if [[ -z "${RUN_ID}" ]]; then
  echo "Nenhum run de release com sucesso. Execute release.yml e tente novamente."
  exit 1
fi
gh run download "${RUN_ID}" -n supply-chain-artifacts -D .tmp/release-artifacts -R gabrielldn/secure-gitops-platform
export IMAGE_REF="$(cat .tmp/release-artifacts/image-ref.txt)"
make evidence IMAGE_REF="${IMAGE_REF}"
```

Esse fluxo evita erro de digest incorreto e garante que `cosign verify` use a chave esperada.

## Comandos `make`

- `make doctor`: valida pré-requisitos, perfil e versões de chart.
- `make versions`: imprime matriz pinada de versões.
- `make bootstrap`: instala toolchain local via Ansible.
- `make up`: sobe registry + 3 clusters k3d.
- `make gitops-bootstrap`: instala Argo CD e registra clusters.
- `make reconcile`: bootstrap GitOps + espera de convergência dos apps críticos.
  - Verbose é padrão; use `RECONCILE_VERBOSE=false` para reduzir logs e `RECONCILE_POLL_INTERVAL=<segundos>` para ajustar intervalo de atualização.
- `make vault-bootstrap`: inicializa Vault e guarda bootstrap cifrado.
- `make vault-configure`: configura auth/policies do Vault para ESO e publica `kv/apps/pki/step-issuer`.
- `make stepca-bootstrap`: extrai material de bootstrap do Step-CA para `.secrets` cifrada.
- `make verify-quick`: health-check essencial.
- `make verify`: verificação E2E (inclui issuer pronto em todos os clusters).
- `make evidence`: pacote de evidência (cosign verify, attestations, SBOM, scans, policy reports).
  - Pré-condições: chave Cosign renderizada + `IMAGE_REF` vindo de run bem-sucedido do `release.yml`.
- `make sanitize-check`: auditoria não-destrutiva para publicação pública sanitizada.
- `make down`: remove clusters e registry local.
- `make clean`: limpeza local previsível.

## CI/CD e supply chain

Workflows em `.github/workflows/`:

- `pr.yml`: validação de manifestos, testes de policy e scan de configuração.
- `release.yml`: build, SBOM (Syft), scans (Grype/Trivy), assinatura (Cosign), attestation e verificações pós-assinatura.
- `local-registry-sync.yml`: sincronização manual de imagem por digest para registry local.

## Segurança

- Política de reporte: `SECURITY.md`.
- Licença: `LICENSE` (MIT).
- Material sensível de bootstrap fica em `.secrets/` cifrado com `SOPS + age`.
- `Falco` em WSL é tratado como `best-effort`; fallback obrigatório com Trivy + policies + alertas.
- Auditoria para publicação pública: `make sanitize-check`.

## Documentação

- Índice de documentação: `docs/README.md`
- Pré-requisitos: `docs/prerequisites.md`
- Arquitetura: `docs/architecture.md`
- Operação: `docs/operations.md`
- Demo reproduzível: `docs/demo.md`
- Modelo de segurança: `docs/security-model.md`
- Checklist de sanitização pública: `docs/public-sanitization-checklist.md`
- ADRs: `docs/adr/`
- Runner self-hosted: `docs/runner-self-hosted.md`
- PKI ACME opcional: `docs/pki-acme-optional.md`
- Contribuição e ownership: `CONTRIBUTING.md` e `CODEOWNERS`

## Observações práticas

- O perfil padrão para convergência local é `light`.
- O prompt `BECOME password:` no `make bootstrap` corresponde à senha de `sudo` do WSL.
- `make vault-bootstrap` agora é idempotente para ambiente local: se o Vault atual ainda não estiver inicializado e existir `.secrets/vault/init.enc.json` antigo, o arquivo é arquivado em `.secrets/vault/archive/` e um novo bootstrap é gerado.
- O fluxo recomendado é sempre concluir com `make verify`.
