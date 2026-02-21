# ADR 0001: Deploy por Digest e GHCR como Source of Truth

- Status: Accepted
- Data: 2026-02-21

## Contexto

Deploy por tag é mutável e dificulta rastreabilidade. O projeto precisa provar integridade de supply chain e promoção consistente entre ambientes.

## Decisão

1. Publicar imagens no `ghcr.io`.
2. Referenciar imagens por digest (`image@sha256:...`) nos overlays.
3. Usar workflow de release para gerar SBOM, scan, assinatura e attestation.
4. Tratar registry local (`localhost:5001`) apenas como espelho opcional para laboratório.

## Consequências

- Ganho de imutabilidade e auditabilidade.
- Promoção `dev -> homolog -> prod` passa a ser rastreável por digest.
- Maior custo operacional para atualizar digests explicitamente.

## Trade-offs

- Prós: segurança e reproducibilidade mais fortes.
- Contras: fluxo de promoção é mais rígido e exige disciplina de CI/CD.
