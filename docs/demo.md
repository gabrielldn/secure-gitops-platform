# Demo Reproduzível (Evidence Pack)

Este guia produz evidências auditáveis para três cenários:

- Cenário A: deploy assinado/atestado aprovado em `homolog` e `prod`.
- Cenário B: deploy inválido bloqueado pelo admission do Kyverno.
- Cenário C: canary com falha induzida e rollback automático do Argo Rollouts.

## Pré-requisitos

1. Ambiente local pronto:
   - `make up PROFILE=light`
   - `make reconcile PROFILE=light`
   - `make verify PROFILE=light`
2. Ferramentas no host: `yq`, `kubectl`, `cosign`, `syft`, `grype`, `trivy`.
3. Digest assinado do release:
   - `IMAGE_REF="ghcr.io/gabrielldn/secure-gitops-demo-app@sha256:<digest-valido>"`

## Cenário A: deploy aprovado

1. Atualize a imagem de `homolog` e `prod` para o digest assinado:

```bash
export IMAGE_REF="ghcr.io/gabrielldn/secure-gitops-demo-app@sha256:<digest-valido>"
yq -i '(.spec.template.spec.containers[] | select(.name=="podinfo") | .image) = strenv(IMAGE_REF)' gitops/apps/workloads/podinfo/overlays/homolog/rollout-patch.yaml
yq -i '(.spec.template.spec.containers[] | select(.name=="podinfo") | .image) = strenv(IMAGE_REF)' gitops/apps/workloads/podinfo/overlays/prod/rollout-patch.yaml
```

2. Reconcile:

```bash
make reconcile PROFILE=light
```

3. Confirme rollout saudável:

```bash
kubectl --context k3d-sgp-homolog -n apps argo rollouts get rollout podinfo
kubectl --context k3d-sgp-prod -n apps argo rollouts get rollout podinfo
```

Resultado esperado:

- `STATUS: Healthy` no rollout.
- Sem erro de admission nos eventos do namespace `apps`.

4. Gere evidência do supply chain:

```bash
make evidence IMAGE_REF="${IMAGE_REF}"
```

Resultado esperado:

- Pacote em `artifacts/evidence/<UTC-YYYYMMDDTHHMMSSZ>/`.
- `summary.md` com `PASS` para `cosign verify`, attestations, SBOM e scans.

## Cenário B: bloqueio de assinatura/attestation

1. Aplique um Pod com digest inválido, no mesmo padrão de imagem, em `homolog` e `prod`:

```bash
cat <<'EOF' >/tmp/podinfo-deny.yaml
apiVersion: v1
kind: Pod
metadata:
  name: podinfo-deny-test
  namespace: apps
spec:
  containers:
    - name: podinfo
      image: ghcr.io/gabrielldn/secure-gitops-demo-app@sha256:1111111111111111111111111111111111111111111111111111111111111111
EOF

for ctx in k3d-sgp-homolog k3d-sgp-prod; do
  kubectl --context "${ctx}" apply -f /tmp/podinfo-deny.yaml || true
done
```

2. Colete a evidência do deny:

```bash
for ctx in k3d-sgp-homolog k3d-sgp-prod; do
  kubectl --context "${ctx}" -n apps describe pod podinfo-deny-test || true
  kubectl --context "${ctx}" -n apps get policyreport -o yaml > "/tmp/policyreport-${ctx}.yaml"
  kubectl --context "${ctx}" get clusterpolicyreport -o yaml > "/tmp/clusterpolicyreport-${ctx}.yaml"
done
```

Resultado esperado:

- `kubectl apply` falha com mensagem de deny do Kyverno (`verify-image-signatures` ou `verify-image-attestations`) em `homolog` e `prod`.
- `policyreport`/`clusterpolicyreport` registra resultado de violação em ambos os ambientes.

## Cenário C: falha de canary e rollback automático

1. Induza falha determinística no AnalysisTemplate de `homolog`:

```bash
kubectl --context k3d-sgp-homolog -n apps patch analysistemplate podinfo-success-rate \
  --type=json \
  -p='[{"op":"replace","path":"/spec/metrics/0/successCondition","value":"result[0] >= 1.10"}]'
```

2. Dispare nova revisão do rollout:

```bash
kubectl --context k3d-sgp-homolog -n apps argo rollouts restart podinfo
kubectl --context k3d-sgp-homolog -n apps argo rollouts get rollout podinfo --watch
```

3. Colete evidências:

```bash
kubectl --context k3d-sgp-homolog -n apps get analysisrun --sort-by=.metadata.creationTimestamp
kubectl --context k3d-sgp-homolog -n apps describe analysisrun <analysisrun-name>
kubectl --context k3d-sgp-homolog -n apps argo rollouts get rollout podinfo
```

Resultado esperado:

- AnalysisRun com falha.
- Rollout entra em `Degraded` e aborta progressão canary (rollback automático para a revisão estável).

## Limpeza e reversão

1. Remova artefato de teste do cenário B:

```bash
for ctx in k3d-sgp-homolog k3d-sgp-prod; do
  kubectl --context "${ctx}" -n apps delete pod podinfo-deny-test --ignore-not-found
done
```

2. Restaure manifests alterados localmente (cenário A):

```bash
git restore gitops/apps/workloads/podinfo/overlays/homolog/rollout-patch.yaml gitops/apps/workloads/podinfo/overlays/prod/rollout-patch.yaml
```

3. Restaure o estado GitOps dos clusters (inclui AnalysisTemplate do cenário C):

```bash
make reconcile PROFILE=light
make verify PROFILE=light
```
