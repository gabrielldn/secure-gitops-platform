# Documentação

Este diretório contém os guias operacionais e arquiteturais do projeto.

## Índice

- `prerequisites.md`: requisitos de host, WSL e ferramentas.
- `architecture.md`: topologia hub-and-spoke, fluxos e decisões principais.
- `operations.md`: operação de ponta a ponta com `make`.
- `demo.md`: cenários reproduzíveis de evidência (deploy ok, policy deny, rollback canary).
- `security-model.md`: separação de blast radius entre `platform` e `workloads`.
- `runner-self-hosted.md`: configuração do runner self-hosted para workflows de release.
- `pki-acme-optional.md`: fluxo ACME opcional (não obrigatório para v1).
- `public-sanitization-checklist.md`: checklist para publicação pública sanitizada.
- `adr/`: registros de decisões arquiteturais.

## Fluxo sugerido de leitura

1. Leia `prerequisites.md`.
2. Execute bootstrap conforme `operations.md`.
3. Consulte `architecture.md` para entender limites e contratos.
4. Consulte `security-model.md` para entender blast radius e RBAC.
5. Execute `demo.md` para gerar evidências reproduzíveis.
6. Configure CI local com `runner-self-hosted.md` quando for usar release assinado.
7. Use `pki-acme-optional.md` somente se precisar de paridade ACME.
