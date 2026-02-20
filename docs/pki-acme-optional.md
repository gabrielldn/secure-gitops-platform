# Optional: Step-CA ACME Flow

The default path in this repository is `cert-manager + step-issuer`.

If you need ACME parity tests:

1. Expose Step-CA with stable HTTPS ingress.
2. Create cert-manager `ClusterIssuer` using ACME server URL from Step-CA.
3. Validate HTTP01/DNS01 challenge routing from each target cluster.

Use this only if you explicitly need ACME semantics. For local reliability, keep `step-issuer` as primary.
