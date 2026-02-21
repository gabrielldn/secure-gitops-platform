# Operações

## Fluxo E2E recomendado

### 1) Preparação

```bash
make doctor PROFILE=light
make versions
```

Se faltar toolchain:

```bash
make bootstrap
```

No `make bootstrap`, o prompt `BECOME password:` pede a senha de `sudo` do usuário atual no WSL.

### 2) Provisionamento local

```bash
make up PROFILE=light
```

Cria:

- Registry local (`localhost:5001`)
- Clusters `sgp-dev`, `sgp-homolog`, `sgp-prod`
- Kubeconfig local em `.kube/config`

Parâmetros úteis para ambientes com CPU limitada/instável:

```bash
K3D_CREATE_RETRIES=3 \
K3D_CREATE_TIMEOUT=420s \
K3D_RETRY_BASE_DELAY_SECONDS=20 \
make up PROFILE=light
```

Comportamento de retry:

- Retry automático para erros transitórios conhecidos do `k3d` (ex.: `context deadline exceeded` no agent join).
- Limpeza automática entre tentativas (cluster parcial + rede órfã).
- Fail-fast para erros não transitórios.

### 3) Bootstrap GitOps

```bash
make reconcile PROFILE=light
```

Observações:

- `make reconcile` executa bootstrap do Argo CD, registro de clusters e espera de convergência dos apps críticos.
- Por padrão, sem `REPO_URL`, o projeto gera repo renderizado local e publica via `git daemon` em `git://host.k3d.internal:9418/...`.
- O comando exibe progresso (barra, percentual, apps prontos, tempo decorrido/restante).
- Verbose vem habilitado por padrão para detalhar apps pendentes em cada ciclo.
- Para reduzir saída, use `RECONCILE_VERBOSE=false`.

Para usar repositório remoto:

```bash
make reconcile PROFILE=light \
  REPO_URL=https://github.com/<org>/secure-gitops-platform.git \
  GITOPS_REVISION=main \
  ARGO_WAIT_TIMEOUT=1800
```

Ajustes úteis para feedback mais frequente durante convergência:

```bash
make reconcile PROFILE=light \
  RECONCILE_VERBOSE=true \
  RECONCILE_POLL_INTERVAL=5
```

### 4) Segredos e PKI

```bash
make vault-bootstrap
make stepca-bootstrap
make vault-configure
./scripts/render-step-issuer-values.sh
make reconcile PROFILE=light
```

Notas importantes:

- `vault-bootstrap` é idempotente no fluxo local: se o Vault atual não estiver inicializado e já existir `.secrets/vault/init.enc.json`, o arquivo antigo é arquivado em `.secrets/vault/archive/` e um novo bootstrap é criado.
- `stepca-bootstrap` salva material cifrado em `.secrets/step-ca/bootstrap.enc.json`.
- `vault-configure` publica `provisioner_password` em `kv/apps/pki/step-issuer` para consumo via ESO.
- `render-step-issuer-values.sh` materializa `kid`, `caBundle` e `url` nos manifests do `StepClusterIssuer`.

### 5) Verificação

```bash
make verify-quick PROFILE=light
make verify PROFILE=light
```

`make verify` cobre:

- Reachability dos 3 clusters
- Namespaces críticos
- Service `kube-prometheus-stack-prometheus` nos 3 clusters
- `StepClusterIssuer` pronto nos 3 ambientes
- Argo CD no hub
- Vault/Step namespaces
- Falco condicional em WSL
- Testes de policy (`kyverno test`)

## Operações auxiliares

- Testar políticas localmente:

```bash
make policy-test
```

- Promover digest entre ambientes:

```bash
./scripts/promote-image.sh dev homolog
./scripts/promote-image.sh homolog prod
```

- Gerar pacote de evidência (SBOM, scan, verify e policy reports):

Antes de executar `make evidence`, garanta dois insumos:

1. Chave pública do Cosign (para validar assinatura/attestation):

```bash
gh auth status
./scripts/render-cosign-public-key.sh /caminho/para/cosign.pub
make reconcile PROFILE=light
```

2. `IMAGE_REF` de um release bem-sucedido (para não usar digest inválido):

```bash
RUN_ID="$(gh run list --workflow release.yml --limit 20 --json databaseId,conclusion -R gabrielldn/secure-gitops-platform -q '[.[] | select(.conclusion=="success")][0].databaseId')"
if [[ -z "${RUN_ID}" ]]; then
  echo "Nenhum run de release com sucesso. Execute release.yml e tente novamente."
  exit 1
fi
mkdir -p .tmp/release-artifacts
gh run download "${RUN_ID}" -n supply-chain-artifacts -D .tmp/release-artifacts -R gabrielldn/secure-gitops-platform
export IMAGE_REF="$(cat .tmp/release-artifacts/image-ref.txt)"
```

Com os insumos prontos:

```bash
make evidence IMAGE_REF="${IMAGE_REF}"
```

Comportamento:

- Saída padrão em `artifacts/evidence/<UTC-YYYYMMDDTHHMMSSZ>/`.
- Use `COSIGN_PUBLIC_KEY_FILE=<arquivo>` para chave explícita (quando não quiser usar o manifest renderizado no repo).
- Use `EVIDENCE_DIR=<diretorio>` para saída customizada.
- Use `EVIDENCE_INCLUDE_CLUSTER=false` para pular export de policy reports.

- Rodar auditoria de sanitização para publicação pública:

```bash
make sanitize-check
```

Relatório:

- `artifacts/sanitization/report.md`

- Sincronizar imagem para registry local:

```bash
./scripts/sync-image-to-local-registry.sh <imagem@sha256:...> localhost:5001
```

## Teardown e limpeza

```bash
make down
make clean
```

## Troubleshooting rápido

- Rollout degradado: `runbooks/rollout-degraded.md`
- Burn-rate fast: `runbooks/podinfo-availability-burn-rate-fast.md`
- Burn-rate slow: `runbooks/podinfo-availability-burn-rate-slow.md`
- Policy deny: `runbooks/policy-deny.md`
- Vault sealed: `runbooks/vault-sealed.md`
- Step-issuer conectividade: `runbooks/step-issuer-connectivity.md`
- Falco indisponível em WSL: `runbooks/falco-unavailable-wsl.md`
- Falha de sync do registry: `runbooks/registry-sync-failed.md`
