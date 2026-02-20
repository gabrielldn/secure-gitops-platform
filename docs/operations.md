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

### 3) Bootstrap GitOps

```bash
make reconcile PROFILE=light
```

Observações:

- `make reconcile` executa bootstrap do Argo CD, registro de clusters e espera de convergência dos apps críticos.
- Por padrão, sem `REPO_URL`, o projeto gera repo renderizado local e publica via `git daemon` em `git://host.k3d.internal:9418/...`.

Para usar repositório remoto:

```bash
make reconcile PROFILE=light \
  REPO_URL=https://github.com/<org>/secure-gitops-platform.git \
  GITOPS_REVISION=main \
  ARGO_WAIT_TIMEOUT=1800
```

### 4) Segredos e PKI

```bash
make vault-bootstrap
make vault-configure
make stepca-bootstrap
./scripts/render-step-issuer-values.sh
make reconcile PROFILE=light
```

Notas importantes:

- `vault-bootstrap` é de primeira execução; se `.secrets/vault/init.enc.json` já existir, o comando aborta por segurança.
- `stepca-bootstrap` salva material cifrado em `.secrets/step-ca/bootstrap.enc.json`.
- `render-step-issuer-values.sh` materializa `kid`, `caBundle` e `password` nos manifests de issuer.

### 5) Verificação

```bash
make verify-quick PROFILE=light
make verify PROFILE=light
```

`make verify` cobre:

- Reachability dos 3 clusters
- Namespaces críticos
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
- Policy deny: `runbooks/policy-deny.md`
- Vault sealed: `runbooks/vault-sealed.md`
- Step-issuer conectividade: `runbooks/step-issuer-connectivity.md`
- Falco indisponível em WSL: `runbooks/falco-unavailable-wsl.md`
- Falha de sync do registry: `runbooks/registry-sync-failed.md`
