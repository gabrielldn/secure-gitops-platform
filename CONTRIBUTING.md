# Contribuindo

## Fluxo de contribuição

1. Crie uma branch a partir de `main`.
2. Faça mudanças pequenas, focadas e com commit descritivo.
3. Abra PR para `main`.
4. Garanta que os checks obrigatórios passaram antes do merge.

## Critérios mínimos para PR

1. Validar manifests e políticas:

```bash
make policy-test
```

2. Validar host e tooling quando a mudança impactar operação local:

```bash
make doctor PROFILE=light
```

3. Quando houver alteração de supply chain:

```bash
make evidence IMAGE_REF=<image@sha256:...>
```

4. Quando houver alteração de segurança/governança pública:

```bash
make sanitize-check
```

## Padrões de mudança

1. Evitar alteração não relacionada no mesmo PR.
2. Atualizar documentação quando houver mudança de contrato (Makefile, workflow, manifests, runbooks).
3. Preservar deploy por digest em workloads.
4. Não incluir segredos reais no repositório.

## Mensagem de PR recomendada

Inclua:

1. Problema e contexto.
2. Mudanças realizadas.
3. Evidências (comandos executados e resultado).
4. Riscos e rollback.
