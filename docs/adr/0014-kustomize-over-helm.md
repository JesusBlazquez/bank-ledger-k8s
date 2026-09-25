# 0014. Kustomize instead of a Helm chart

- **Status:** Accepted
- **Date:** 2026-09-25

## Context

The same application has to run on a local kind cluster and on a production-like cluster, with
different replica counts, resources and image sources.

## Decision

Plain Kubernetes manifests with Kustomize: one base and two overlays, `local` and `prod`. Labels are
added with `labels` and `includeSelectors: false`, never with `commonLabels`, because a label added
to a Deployment's selector cannot be changed afterwards.

## Alternatives considered

- **Helm:** more common in large organisations and better for redistributing software, but the
  manifests end up behind templating, and a reader has to run `helm template` to see what is
  actually applied. For showing that I understand Kubernetes itself, plain YAML is more honest.
- **Both:** twice the maintenance for one application.

## Consequences

Anyone can read `k8s/base` and know exactly what will be created; `kubectl kustomize` renders it
without extra tooling. If this were distributed to other teams, a chart would be the next step.
