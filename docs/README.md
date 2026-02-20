# Documentação

Este diretório contém os guias operacionais e arquiteturais do projeto.

## Índice

- `prerequisites.md`: requisitos de host, WSL e ferramentas.
- `architecture.md`: topologia hub-and-spoke, fluxos e decisões principais.
- `operations.md`: operação de ponta a ponta com `make`.
- `runner-self-hosted.md`: configuração do runner self-hosted para workflows de release.
- `pki-acme-optional.md`: fluxo ACME opcional (não obrigatório para v1).

## Fluxo sugerido de leitura

1. Leia `prerequisites.md`.
2. Execute bootstrap conforme `operations.md`.
3. Consulte `architecture.md` para entender limites e contratos.
4. Configure CI local com `runner-self-hosted.md` quando for usar release assinado.
5. Use `pki-acme-optional.md` somente se precisar de paridade ACME.
