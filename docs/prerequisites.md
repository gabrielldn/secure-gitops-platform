# Pré-requisitos

## Ambiente alvo

- WSL2 com Ubuntu 24.04.
- Docker Engine funcional no WSL.
- Ansible disponível.
- Acesso à internet para baixar charts/imagens.

## Perfis suportados

Perfis definidos em `platform/profiles/`:

- `light` (padrão para convergência local):
  - CPU mínima: 6
  - Memória mínima: 8 GB
  - Disco mínimo: 30 GB
- `full` (cenário mais próximo de produção local):
  - CPU mínima: 8
  - Memória mínima: 16 GB
  - Disco mínimo: 50 GB

## Configuração recomendada do WSL (`full`)

Crie `%UserProfile%\\.wslconfig` no Windows:

```ini
[wsl2]
memory=20GB
processors=10
swap=8GB
localhostForwarding=true
```

Depois execute no PowerShell do Windows:

```powershell
wsl --shutdown
```

Modelos prontos:

- `scripts/wslconfig-full.template`
- `scripts/wslconfig-light.template`

## Ferramentas exigidas

Validadas por `make doctor`:

- `docker`, `ansible`, `k3d`, `kubectl`, `helm`, `jq`, `yq`
- `trivy`, `syft`, `grype`, `cosign`, `conftest`, `kyverno`
- `sops`, `age`, `step`, `vault`, `rsync`
- `gh` (recomendado para extrair `IMAGE_REF` dos artifacts do release)

Para instalar automaticamente (incluindo `make`):

```bash
make bootstrap
```

Quando o comando pedir `BECOME password:`, use a senha do seu usuário no `sudo` do WSL.

## Ferramenta adicional para demo de canary

Os comandos de demo e alguns runbooks usam `kubectl argo rollouts ...`.

Verificação:

```bash
kubectl argo rollouts version
```

Se o comando falhar com `unknown command "argo" for "kubectl"`, instale o plugin:

```bash
ROLLOUTS_VERSION="$(curl -fsSL https://api.github.com/repos/argoproj/argo-rollouts/releases/latest | jq -r .tag_name)"
curl -fsSL -o /tmp/kubectl-argo-rollouts "https://github.com/argoproj/argo-rollouts/releases/download/${ROLLOUTS_VERSION}/kubectl-argo-rollouts-linux-amd64"
chmod +x /tmp/kubectl-argo-rollouts
sudo mv /tmp/kubectl-argo-rollouts /usr/local/bin/kubectl-argo-rollouts
kubectl argo rollouts version --short
```

## Verificação inicial

```bash
make doctor PROFILE=light
make versions
```

## Portas locais utilizadas

- Registry local: `localhost:5001`
- API Kubernetes:
  - `sgp-dev`: `6550`
  - `sgp-homolog`: `6551`
  - `sgp-prod`: `6552`
- Ingress:
  - `dev`: `8081/8444`
  - `homolog`: `8082/8445`
  - `prod`: `8083/8446`
- Serviços de hub expostos para spokes:
  - Vault: `18200`
  - Step-CA: `19443`

## Acesso ao Docker sem sudo

`make bootstrap` adiciona o usuário ao grupo `docker`.

Após bootstrap, reinicie o shell/sessão:

```bash
newgrp docker
```

## Observação sobre Falco no WSL

Falco depende de suporte de kernel/eBPF e em WSL pode não funcionar.

Contrato do projeto:

- Falco: `best-effort`.
- Fallback obrigatório: Kyverno + Trivy Operator + auditoria/alertas.
- `make verify` trata Falco como condicional em WSL.
