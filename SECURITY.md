# Política de Segurança

## Versões suportadas

Este projeto é orientado a laboratório local e evolui principalmente na branch `main`.

| Versão | Suporte de segurança |
| --- | --- |
| `main` | Suportada |
| Releases antigas | Melhor esforço |

## Como reportar uma vulnerabilidade

Se você identificar uma vulnerabilidade, não abra issue pública com detalhes sensíveis.

Use preferencialmente:

- GitHub Security Advisories (reporte privado do repositório)

Ao reportar, inclua:

- Descrição clara do problema
- Impacto potencial
- Passos para reprodução
- Evidências (logs, payloads, manifests)
- Versão/commit afetado

## Processo de resposta

Fluxo esperado:

1. Triagem inicial do reporte.
2. Confirmação do impacto.
3. Definição de mitigação/correção.
4. Divulgação coordenada após patch disponível.

## Escopo de segurança

Áreas críticas deste repositório:

- Workflows de supply chain (`.github/workflows/`)
- Manifests de política (`policies/`)
- Fluxos de segredos e PKI (`scripts/vault-*`, `scripts/stepca-*`, `gitops/apps/pki/`)
- Material cifrado em `.secrets/` (nunca em texto puro)

## Boas práticas para contribuidores

- Nunca commitar tokens, chaves ou credenciais.
- Usar apenas imagens por digest em workloads promovidos.
- Validar mudanças com `make verify` antes de PR.
- Revisar regras de policy e impacto de enforcement por ambiente.
