# 0015. PostgreSQL runs inside the cluster, for the demo

- **Status:** Accepted
- **Date:** 2026-09-25

## Context

The application needs a database. In production, databases are usually managed services outside the
cluster; in a repository meant to be cloned and run, a missing database means nothing works.

## Decision

A `StatefulSet` with a `PersistentVolumeClaim` and credentials in a `Secret` runs PostgreSQL inside
the cluster, so the whole system comes up with one command. The README states plainly that a real
deployment would point at a managed database (or a database operator) by changing the `Secret` and
the `DB_URL` in the `ConfigMap`, and nothing else.

## Alternatives considered

- **Expecting an external database:** more realistic and impossible for anyone else to try.
- **A database operator (CloudNativePG or similar):** the right answer for running PostgreSQL on
  Kubernetes seriously, and far more machinery than this demonstration needs.

## Consequences

The demo is self-contained and the production path is a configuration change, not a redesign. The
committed credentials are demo-only and labelled as such: real ones would come from a sealed secret
or an external secrets operator.
