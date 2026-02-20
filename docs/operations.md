# Operations

## Bootstrap

```bash
make doctor PROFILE=light
make bootstrap
```

## Bring platform up

```bash
make up PROFILE=light
make reconcile
make vault-bootstrap
make vault-configure
make stepca-bootstrap
```

## Post-bootstrap materialization

1. Render Step issuer values from encrypted bootstrap material:

```bash
./scripts/render-step-issuer-values.sh
```

2. Render Cosign public key:

```bash
./scripts/render-cosign-public-key.sh /path/to/cosign.pub
```

3. Trust Step root CA:

```bash
./scripts/trust-stepca-wsl.sh
pwsh -File scripts/trust-stepca-windows.ps1 -CertificatePath .\\.secrets\\step-ca\\root_ca.crt
```

## Verify and teardown

```bash
make verify-quick
make verify
make down
```

## GitOps source override

By default, `make reconcile` prepares a local rendered git daemon and uses it as `REPO_URL`.

If you need an explicit repository and revision:

```bash
make reconcile REPO_URL=https://github.com/your-org/secure-gitops-platform.git GITOPS_REVISION=main
```

## Promotion by PR

Use digest promotion helpers before opening PRs:

```bash
./scripts/promote-image.sh dev homolog
./scripts/promote-image.sh homolog prod
```
