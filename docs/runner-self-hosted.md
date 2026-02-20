# Runner Self-Hosted (WSL)

Este projeto usa runner self-hosted para jobs de release que dependem do ambiente local (Docker, Vault e sync de registry).

## Workflows que usam runner self-hosted

- `.github/workflows/release.yml`
- `.github/workflows/local-registry-sync.yml`

## Labels mínimas

Registre o runner com:

- `self-hosted`
- `Linux`

## Pré-requisitos no runner

Ferramentas mínimas:

- `docker`, `crane`, `syft`, `grype`, `trivy`, `cosign`, `vault`

Você pode preparar o ambiente com:

```bash
make bootstrap
```

## Registro do runner (resumo)

1. No GitHub do repositório: `Settings -> Actions -> Runners -> New self-hosted runner`.
2. Escolha `Linux x64`.
3. Execute os comandos de registro no WSL.
4. Instale como serviço para operação contínua.

## Segredos e variáveis para release

O workflow `release.yml` aceita:

- Vault como origem da chave Cosign:
  - `VAULT_ADDR`
  - `VAULT_TOKEN`
- Ou chave direta:
  - `COSIGN_PRIVATE_KEY`

Também usa `GITHUB_TOKEN` para push no GHCR.

## Hardening recomendado

- Runner dedicado para este repositório.
- Usuário de execução sem privilégios administrativos desnecessários.
- Rotação periódica de tokens e chaves.
- Evitar reutilização do host runner para workloads não confiáveis.
- Monitorar uso de disco (`docker system df`) e limpar artefatos antigos.

## Teste rápido do runner

- Dispare manualmente `pr-security-and-policy` (`workflow_dispatch`) para validar toolchain de validação.
- Dispare `local-registry-sync` com um digest válido para validar conectividade com `localhost:5001`.
