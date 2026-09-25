# bank-ledger-k8s

[![CI](https://github.com/JesusBlazquez/bank-ledger-k8s/actions/workflows/ci.yml/badge.svg)](https://github.com/JesusBlazquez/bank-ledger-k8s/actions/workflows/ci.yml)
[![Release](https://github.com/JesusBlazquez/bank-ledger-k8s/actions/workflows/release.yml/badge.svg)](https://github.com/JesusBlazquez/bank-ledger-k8s/actions/workflows/release.yml)
![Java](https://img.shields.io/badge/Java-21-orange)
![Spring Boot](https://img.shields.io/badge/Spring%20Boot-4.1-6DB33F)
![License](https://img.shields.io/badge/license-MIT-blue)

**How a Spring Boot service gets from a laptop to a Kubernetes cluster**: container image, manifests,
pipeline and the checks in between.

The application is the [bank ledger](https://github.com/JesusBlazquez/bank-ledger-hexagonal) —
accounts, transfers and real domain rules with hexagonal architecture — forked at its `v1.0.0` tag.
Its history is kept, so the split between "what the software does" and "how it is shipped" is
visible in the commit log.

## The problem it solves

An application that only runs on the machine that built it is not finished. This repository answers
the questions that come after the code works:

- How is it packaged so the image is small, reproducible and safe to run as a non-root user?
- How does it run on Kubernetes: configuration, secrets, storage, health checks, zero-downtime deploys?
- How do we know the deployment instructions still work? (The pipeline runs them on every change.)
- How do we know the published image is not vulnerable, and that it really came from this repository?

## Architecture

```mermaid
flowchart LR
    subgraph infrastructure["infrastructure (Spring Boot)"]
        rest["REST adapter"]
        jpa["JPA adapter"]
        db[("PostgreSQL")]
    end
    subgraph application["application"]
        uc["Use cases"]
        ports["Ports (interfaces)"]
    end
    subgraph domain["domain (no frameworks)"]
        account["Account (aggregate)"]
        vo["Money · Iban · LedgerEntry"]
    end

    rest --> uc
    uc --> account
    uc --> ports
    jpa -.implements.-> ports
    jpa --> db
```

Dependencies only ever point inwards: `infrastructure → application → domain`. They are separate
Maven modules, so the rule is enforced by the compiler rather than by discipline: Spring is not even
on the domain's classpath.

## Tech stack

| Area | Technology |
|---|---|
| Language | Java 21 |
| Framework | Spring Boot 4.1 (web, validation, actuator, data-jpa) |
| Database | PostgreSQL, schema versioned with Flyway |
| Build | Maven multi-module (wrapper included) |
| Testing | JUnit 5, AssertJ, Mockito, Testcontainers |
| API docs | OpenAPI / Swagger UI |
| CI | GitHub Actions |

## Getting started

**Prerequisites:** JDK 21 and Docker.

```bash
git clone https://github.com/JesusBlazquez/bank-ledger-k8s.git
cd bank-ledger-hexagonal
docker compose up -d                  # starts PostgreSQL
./mvnw package -DskipTests            # builds the three modules
java -jar infrastructure/target/infrastructure-0.1.0-SNAPSHOT.jar
```

- API docs: <http://localhost:8080/swagger-ui.html>
- Health: <http://localhost:8080/actuator/health>

While developing, `./mvnw install -DskipTests` followed by `./mvnw spring-boot:run -pl infrastructure`
gives the same result with a faster edit-run loop. Note that adding `-am` would make Maven try to run
the parent POM as well, which has no main class.

### Running the tests

```bash
./mvnw verify                 # unit tests + integration tests (Testcontainers starts its own database)
```

## API

| Operation | Endpoint |
|---|---|
| Open an account | `POST /api/accounts` |
| Get balance and details | `GET /api/accounts/{id}` |
| Deposit | `POST /api/accounts/{id}/deposits` |
| Withdraw | `POST /api/accounts/{id}/withdrawals` |
| Transfer | `POST /api/transfers` |
| Transaction history | `GET /api/accounts/{id}/transactions` |

Commands accept an `Idempotency-Key` header. Errors are returned as Problem Details (RFC 9457).
Amounts travel as strings (`"100.00"`) so no client turns them into floating point numbers.

## Running it on Kubernetes

**Prerequisites:** Docker, kind and kubectl.

```bash
./scripts/deploy-kind.sh          # Windows: .\scripts\deploy-kind.ps1
```

One command creates a two-node kind cluster, installs the ingress controller, builds the image,
loads it into the cluster, deploys everything and smoke-tests it through the ingress. This is the
same script the pipeline runs, so these instructions cannot rot silently.

```bash
kubectl -n ledger get pods                          # what is running
kubectl -n ledger port-forward svc/ledger-app 8080:80   # reach it without editing /etc/hosts
kind delete cluster --name ledger                   # clean up
```

### What is deployed

| Resource | Why |
|---|---|
| `Deployment` (app) | Rolling updates with `maxUnavailable: 0`: the new pod is ready before the old one goes |
| `StatefulSet` + PVC (PostgreSQL) | Stable identity and storage that survives a restart |
| `ConfigMap` / `Secret` | Configuration apart from the image; credentials apart from the configuration |
| `Service` + `Ingress` | Stable in-cluster address and an entry point at `ledger.local` |
| `PodDisruptionBudget` (prod) | A node drain can take pods down, but never all of them |

Kustomize keeps one base and two overlays: `local` (single replica, image built on the machine) and
`prod` (three replicas, spread across nodes, larger requests).

### Three probes, three questions

| Probe | Question | What a failure does |
|---|---|---|
| `startupProbe` | Has it finished booting? | Gives the JVM and Flyway time without a long liveness delay |
| `readinessProbe` | Can it take traffic now? | Removes the pod from the Service; does not restart it |
| `livenessProbe` | Is it stuck? | Restarts the container — which is why it does not check the database |

A liveness probe that touches the database restarts every pod when the database blips, turning an
incident into an outage.

## The pipeline

| Workflow | When | What it does |
|---|---|---|
| `ci.yml` | Every push and pull request | Formatting, 77 tests, renders both overlays and validates them against the Kubernetes schemas, then deploys to a throwaway kind cluster |
| `release.yml` | On a `v*` tag | Builds for amd64 and arm64, pushes to GHCR with SBOM and provenance, fails on critical vulnerabilities (Trivy) and signs the image with cosign (keyless) |

Splitting them is deliberate: a pipeline that takes ten minutes on every commit stops being read.
The fast checks run always; the expensive ones run when something is published.

Verifying a published image:

```bash
cosign verify ghcr.io/jesusblazquez/bank-ledger-k8s:v1.0.0 \
  --certificate-identity-regexp 'https://github.com/JesusBlazquez/bank-ledger-k8s/.*' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

## Technical decisions

Each decision is recorded in full as an [Architecture Decision Record](docs/adr/).

| Decision | Why | ADR |
|---|---|---|
| Hexagonal architecture as separate Maven modules | The compiler, not a convention, keeps the domain framework-free | [0002](docs/adr/0002-hexagonal-architecture-with-maven-modules.md) |
| `Money` as a value object over `BigDecimal` | Floating point cannot represent money exactly | [0003](docs/adr/0003-money-as-a-value-object.md) |
| Append-only ledger with a derived balance | Auditable history, fast balance reads, recomputable | [0004](docs/adr/0004-append-only-ledger-with-derived-balance.md) |
| Transfers in a single local transaction | Correct and simple for one database; the distributed case is a different project | [0005](docs/adr/0005-transfers-in-a-local-transaction.md) |
| Idempotency enforced by a unique constraint | An application-level check loses under concurrency | [0006](docs/adr/0006-idempotency-via-unique-constraint.md) |
| Daily limit tracked inside the aggregate | Keeps the rule testable without a database | [0007](docs/adr/0007-daily-limit-inside-the-aggregate.md) |
| Testcontainers instead of H2 | H2 is not PostgreSQL, and the differences hide bugs | [0008](docs/adr/0008-testcontainers-over-h2.md) |
| A separate repository for deployment | Keeps the application's history readable and the deployment concerns together | [0012](docs/adr/0012-separate-deployment-repository.md) |
| Layered image, non-root, read-only filesystem | Small rebuilds and the security profile clusters expect | [0013](docs/adr/0013-layered-hardened-image.md) |
| Kustomize instead of Helm | Plain YAML anyone can read, with overlays for the differences | [0014](docs/adr/0014-kustomize-over-helm.md) |
| PostgreSQL inside the cluster | The demo runs with one command; production would use a managed database | [0015](docs/adr/0015-postgres-inside-the-cluster.md) |
| The pipeline deploys before merging | Deployment instructions that are never executed are documentation, not proof | [0016](docs/adr/0016-pipeline-gates.md) |
| JPA entities kept apart from the model | The aggregate should not carry a framework or the schema's shape | [0009](docs/adr/0009-separate-jpa-entities-from-the-domain.md) |
| Errors as Problem Details (RFC 9457) | Clients branch on a stable `type`, not on English text | [0010](docs/adr/0010-errors-as-problem-details.md) |
| Use cases wired by hand, not scanned | Keeps the application layer testable without Spring | [0011](docs/adr/0011-wire-use-cases-explicitly.md) |

## What I would do differently / next steps

- **Authentication and authorization are missing.** Every endpoint is open. They are the subject of a
  separate project, and the account holder would become the natural authorization boundary here.
- **The balance is stored as well as derivable.** That redundancy earns fast reads, but it should be
  guarded by a reconciliation job that recomputes balances from the ledger and reports any drift.
- **A transfer between accounts in different services cannot use a local transaction.** That case
  needs a Saga with compensating events, which is what the event-driven project in my profile shows.
- **Multi-currency accounts and exchange rates are deliberately left out:** they add accounting
  complexity without demonstrating anything new about the architecture.
- **Explicit wiring has a cost.** Declaring every use case by hand is what keeps the application
  layer free of Spring, and it is also where I made my only wiring mistake. It is a trade, not a
  free win.

### Notes from building it

Spring Boot 4 splits its auto-configuration into per-technology starters: having `flyway-core` on
the classpath is no longer enough for migrations to run, `spring-boot-starter-flyway` is required.
Testcontainers 2.0 renamed both its artifacts and its packages. And the PostgreSQL 18 image moved
its data directory, so a volume mounted at the old path stops the container from starting — caught
only by running the application from scratch, never by the tests.

## License

[MIT](LICENSE) © Jesús Blázquez Durán
