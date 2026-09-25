# 0016. The pipeline deploys, scans and signs

- **Status:** Accepted
- **Date:** 2026-09-25

## Context

A pipeline that only compiles and runs tests says nothing about whether the thing can be deployed,
whether the published image is vulnerable, or where that image came from.

## Decision

Two workflows. On every push and pull request: formatting, tests, rendering both overlays and
validating them against the Kubernetes schemas, and a real deployment to a throwaway kind cluster
using the same script a developer runs. On a version tag: a multi-architecture build pushed to GHCR
with SBOM and provenance, a Trivy scan that fails the release on a fixable critical vulnerability,
and a keyless cosign signature.

## Alternatives considered

- **Everything on every push:** ten-minute feedback on a typo, and a pipeline people stop reading.
- **No deployment step:** cheaper, but then the README's instructions are only ever tested by
  whoever clones the repository, which is exactly the person who should not be debugging them.
- **Signing with a stored private key:** a secret to rotate and protect; keyless signing ties the
  signature to the workflow identity instead.

## Consequences

Instructions that break turn the build red. A release cannot ship a known critical vulnerability
without someone deciding to override it. The cost is about five minutes per change and ten per
release, and one more thing to understand when the signature fails to verify.
