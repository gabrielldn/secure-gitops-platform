# Runbook: Registry Sync Failed

## Symptoms

- Local clusters cannot pull image digest mirrored from GHCR.
- Sync workflow fails on `crane copy`.

## Actions

1. Check source digest exists:
   - `crane digest <ghcr-image@sha256:...>`
2. Retry manual sync:
   - `./scripts/sync-image-to-local-registry.sh <ghcr-image@sha256:...> localhost:5001`
3. Validate local pull:
   - `crane digest localhost:5001/<repo>@sha256:...`
4. Confirm deployment references digest, not mutable tag.
