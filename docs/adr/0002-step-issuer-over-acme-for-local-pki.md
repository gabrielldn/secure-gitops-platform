# ADR 0002: Step-Issuer em vez de ACME como padrão de PKI local

- Status: Accepted
- Data: 2026-02-21

## Contexto

O objetivo principal é laboratório local reproduzível, sem dependência obrigatória de DNS público ou resolvedores externos.

## Decisão

1. Adotar Step-CA no cluster hub (`sgp-dev`) como autoridade interna.
2. Usar `step-issuer` + `StepClusterIssuer` nos três ambientes.
3. Manter ACME como opção documentada, não como padrão.

## Consequências

- Fluxo de bootstrap mais controlado e offline-friendly.
- Dependência de configuração local de confiança de CA.
- Menor paridade com cenários públicos baseados em ACME.

## Trade-offs

- Prós: autonomia local, menor fragilidade externa.
- Contras: esforço adicional para trust bootstrap e menor aderência a fluxos internet-facing.
