# PKI ACME Opcional (Step-CA)

## Contexto

O caminho oficial da v1 deste projeto é:

- `cert-manager + step-issuer`

O modo ACME é opcional e só deve ser usado quando você precisar validar paridade de comportamento ACME (ex.: HTTP01/DNS01) em laboratório.

## Quando usar ACME

Use ACME somente se você precisar:

- Testar fluxo de challenge ACME.
- Simular integração de clientes que dependem explicitamente de endpoint ACME.

## Pré-condições

- Step-CA do hub acessível em HTTPS estável.
- Roteamento de challenge definido no ingress.
- Confiança da CA local instalada no host Linux (nativo ou WSL), quando aplicável.

## Exemplo de `ClusterIssuer` ACME (referência)

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: step-ca-acme
spec:
  acme:
    email: devnull@example.local
    server: https://host.k3d.internal:19443/acme/acme/directory
    privateKeySecretRef:
      name: step-ca-acme-account-key
    solvers:
      - http01:
          ingress:
            class: traefik
```

Ajuste este exemplo conforme seu roteamento e namespace de operação.

## Riscos e trade-offs

- Mais moving parts do que step-issuer.
- Maior chance de falhas de challenge em ambiente local.
- Maior esforço de troubleshooting para pouco ganho em cenários de laboratório padrão.

## Recomendação

Para confiabilidade local e convergência rápida, mantenha `step-issuer` como primário e use ACME apenas em testes específicos.
