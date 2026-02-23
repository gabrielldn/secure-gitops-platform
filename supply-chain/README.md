# Supply Chain Security

This directory contains build and provenance assets used by GitHub Actions:

- workload source: `<owner>/java-api-with-otlp-sdk` (checked out during release workflow).
- `attestations/`: provenance templates.
- workflows in `.github/workflows/` implement SBOM, scanning, signing and attestation.

## Signing model

- Source of truth registry: `ghcr.io`.
- Deployments must reference immutable digests.
- Cosign transparency log upload is disabled by default (`--tlog-upload=false`) for offline-friendly local runs.
