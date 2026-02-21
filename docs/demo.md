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
2. Ferramentas no host: `yq`, `kubectl`, `cosign`, `syft`, `grype`, `trivy`, `gh`.
3. Plugin de Rollouts disponível (necessário para comandos `kubectl argo rollouts`):
   - `kubectl argo rollouts version`
4. Chave pública do Cosign renderizada nos manifests:

```bash
gh auth status
./scripts/render-cosign-public-key.sh /caminho/para/cosign.pub
make reconcile PROFILE=light
```

5. `IMAGE_REF` de um release assinado e atestado:

```bash
RUN_ID="$(gh run list --workflow release.yml --limit 20 --json databaseId,conclusion -R gabrielldn/secure-gitops-platform -q '[.[] | select(.conclusion=="success")][0].databaseId')"
if [[ -z "${RUN_ID}" ]]; then
  echo "Nenhum run de release com sucesso. Execute o workflow release.yml e tente novamente."
  exit 1
fi
mkdir -p .tmp/release-artifacts
gh run download "${RUN_ID}" -n supply-chain-artifacts -D .tmp/release-artifacts -R gabrielldn/secure-gitops-platform
export IMAGE_REF="$(cat .tmp/release-artifacts/image-ref.txt)"
echo "IMAGE_REF=${IMAGE_REF}"
```

## Cenário A: deploy aprovado

1. Atualize apenas o `demo-app` em `homolog` e `prod`:

```bash
yq -i '.spec.replicas = 2' gitops/apps/workloads/demo-app/overlays/homolog/deployment-patch.yaml
yq -i '.spec.replicas = 2' gitops/apps/workloads/demo-app/overlays/prod/deployment-patch.yaml
yq -i '(.spec.template.spec.containers[] | select(.name=="app") | .image) = strenv(IMAGE_REF)' gitops/apps/workloads/demo-app/overlays/homolog/deployment-patch.yaml
yq -i '(.spec.template.spec.containers[] | select(.name=="app") | .image) = strenv(IMAGE_REF)' gitops/apps/workloads/demo-app/overlays/prod/deployment-patch.yaml
```

2. Reconcile:

```bash
make reconcile PROFILE=light
```

3. Confirme o deploy saudável:

```bash
kubectl --context k3d-sgp-homolog -n apps get deploy secure-gitops-demo-app
kubectl --context k3d-sgp-prod -n apps get deploy secure-gitops-demo-app
kubectl --context k3d-sgp-homolog -n apps get events --sort-by=.lastTimestamp | tail -n 20
kubectl --context k3d-sgp-prod -n apps get events --sort-by=.lastTimestamp | tail -n 20
```

Resultado esperado:

- Deployment `secure-gitops-demo-app` disponível nos dois ambientes.
- Sem erro de admission do Kyverno para essa versão assinada/atestada.

4. Gere evidência do supply chain:

```bash
make evidence IMAGE_REF="${IMAGE_REF}"
```

## Cenário B: bloqueio de assinatura/attestation

1. Aplique um Pod com digest inválido em `homolog` e `prod`:

```bash
cat <<'EOF2' >/tmp/demo-app-deny.yaml
apiVersion: v1
kind: Pod
metadata:
  name: demo-app-deny-test
  namespace: apps
spec:
  containers:
    - name: app
      image: ghcr.io/gabrielldn/secure-gitops-demo-app@sha256:1111111111111111111111111111111111111111111111111111111111111111
EOF2

for ctx in k3d-sgp-homolog k3d-sgp-prod; do
  kubectl --context "${ctx}" apply -f /tmp/demo-app-deny.yaml || true
done
```

2. Colete evidência do deny:

```bash
for ctx in k3d-sgp-homolog k3d-sgp-prod; do
  kubectl --context "${ctx}" -n apps describe pod demo-app-deny-test || true
  kubectl --context "${ctx}" -n apps get policyreport -o yaml > "/tmp/policyreport-${ctx}.yaml"
  kubectl --context "${ctx}" get clusterpolicyreport -o yaml > "/tmp/clusterpolicyreport-${ctx}.yaml"
done
```

Resultado esperado:

- `kubectl apply` falha com deny do Kyverno (`verify-image-signatures` ou `verify-image-attestations`).
- `policyreport`/`clusterpolicyreport` registram violação em ambos os ambientes.

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
- Rollout entra em `Degraded` e aborta progressão canary.

## Limpeza e reversão

1. Remova artefato de teste do cenário B:

```bash
for ctx in k3d-sgp-homolog k3d-sgp-prod; do
  kubectl --context "${ctx}" -n apps delete pod demo-app-deny-test --ignore-not-found
done
```

2. Restaure manifests alterados localmente no cenário A:

```bash
git restore gitops/apps/workloads/demo-app/overlays/homolog/deployment-patch.yaml gitops/apps/workloads/demo-app/overlays/prod/deployment-patch.yaml
```

3. Restaure o estado GitOps dos clusters:

```bash
make reconcile PROFILE=light
make verify PROFILE=light
```
