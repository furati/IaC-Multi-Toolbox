## Summary

<!-- What does this change and why? -->

## Checklist

- [ ] `make lint` passes (ansible-lint / yamllint / tflint)
- [ ] `make build` succeeds and `make test` / `make test-functional` pass
- [ ] `make scan` passes (hadolint + trivy CRITICAL gate)
- [ ] Version discovery still flows through `scripts/discover-versions.sh`
- [ ] Workflows pass `actionlint`
- [ ] README / docs updated if behaviour changed
