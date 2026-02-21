# ADR 0003: Matriz de Enforcement Kyverno para verifyImages

- Status: Accepted
- Data: 2026-02-21

## Contexto

O laboratório precisa balancear segurança com velocidade de iteração entre ambientes.

## Decisão

Aplicar políticas `verify-image-signatures` e `verify-image-attestations` por ambiente:

1. `dev`: `Audit` para facilitar experimentação.
2. `homolog`: `Enforce` para validação pré-produção.
3. `prod`: `Enforce` com gate obrigatório.

As políticas são gerenciadas via overlays:

- `policies/kyverno/env/dev`
- `policies/kyverno/env/homolog`
- `policies/kyverno/env/prod`

## Consequências

- Evolução mais segura rumo a produção.
- Menor risco de bloqueio prematuro em desenvolvimento.
- Necessidade de evidência clara para justificar divergência entre ambientes.

## Trade-offs

- Prós: progressão gradual de segurança.
- Contras: possível diferença de comportamento entre `dev` e ambientes de validação final.
