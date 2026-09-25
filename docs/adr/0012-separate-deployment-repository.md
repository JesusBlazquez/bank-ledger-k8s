# 0012. Deployment lives in its own repository

- **Status:** Accepted
- **Date:** 2026-09-25

## Context

The ledger application was already finished and tagged `v1.0.0`. Everything about shipping it —
container image, manifests, pipeline — had to live somewhere.

## Decision

This repository is a fork of the application at `v1.0.0`, keeping its history, and it owns the
deployment concerns. The original repository stays focused on the domain and the API.

## Alternatives considered

- **Adding the deployment to the original repository:** fewer repositories, but the application's
  history stops being about the application, and a reader looking for the domain model wades through
  YAML.
- **A deployment repository with no application code:** closer to GitOps, but then nothing in it can
  be built or run on its own, and the pipeline could not prove that the instructions work.

## Consequences

Each repository reads as one story, and the fork point makes the split explicit. The cost is real
duplication: a change to the application has to be brought across deliberately, which is acceptable
while this is a portfolio piece and would not be in a product.
