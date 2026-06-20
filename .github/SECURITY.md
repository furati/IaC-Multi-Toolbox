# Security Policy

## Reporting a vulnerability

Please report security issues privately via GitHub's
[security advisories](https://github.com/furati/IaC-Multi-Toolbox/security/advisories/new)
rather than opening a public issue. You can expect an initial response within a
few days.

## Supply-chain assurances

Every published image (`ghcr.io/furati/iac-toolbox`) is:

- **Pinned & reproducible** — all bundled tool versions are fixed at build time.
- **Scanned** — Trivy runs on each build; results are uploaded to the repository
  Security tab. The build fails on *fixable* CRITICAL CVEs.
- **Attested** — built with SBOM and provenance attestations (`buildx`).
- **Signed** — signed keylessly with [cosign](https://docs.sigstore.dev/).

### Verifying a published image

```bash
cosign verify ghcr.io/furati/iac-toolbox:latest \
  --certificate-identity-regexp 'https://github.com/furati/IaC-Multi-Toolbox/.*' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

> Note: HIGH-severity CVEs originating in upstream third-party binaries
> (Terraform, Packer, govc, tflint — typically Go stdlib) are reported but do
> not block releases, since they cannot be patched downstream.
