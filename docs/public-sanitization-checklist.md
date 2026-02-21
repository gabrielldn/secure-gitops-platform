# Checklist de Sanitização para Tornar Público

Use este checklist antes de mudar o repositório de `private` para `public`.

## 1) Auditoria automatizada

1. Execute:

```bash
make sanitize-check
```

2. Valide o relatório:
   - `artifacts/sanitization/report.md`
3. Corrija qualquer finding crítico antes de prosseguir.

## 2) Revisão de segredos e dados sensíveis

1. Confirmar que `.secrets/` não está versionada.
2. Garantir que tokens/chaves reais não aparecem em:
   - workflows (`.github/workflows/`)
   - scripts (`scripts/`)
   - documentação (`docs/`, `README.md`)
3. Revisar endpoints internos e substituir por placeholders quando necessário.

## 3) Segurança de supply chain

1. Confirmar presença de material público somente:
   - chave pública de Cosign em `gitops/apps/security/cosign-public-key/cosign-public-key.yaml`.
2. Confirmar ausência de chave privada Cosign no repositório.

## 4) Evidência mínima para público

1. Publicar artefatos de release no GitHub Actions (SBOM, scans, verify, attestation).
2. Garantir `docs/demo.md` com cenários reproduzíveis.
3. Garantir `docs/security-model.md` e ADRs atualizados.

## 5) Governança

1. `CONTRIBUTING.md` presente e coerente com fluxo de PR.
2. `CODEOWNERS` definido.
3. `SECURITY.md` revisado.

## 6) Verificação final

1. `make policy-test`
2. `make verify-quick PROFILE=light`
3. `make evidence IMAGE_REF=<digest assinado>`

Se todos os checks passarem, o repositório está apto para publicação sanitizada.
