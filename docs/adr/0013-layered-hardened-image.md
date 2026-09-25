# 0013. A layered image that runs as a non-root user

- **Status:** Accepted
- **Date:** 2026-09-25

## Context

The simplest container image copies the executable jar and runs it as root. It works, it is one
layer of 60 MB that changes completely on every commit, and it is rejected by any cluster with a
pod security standard applied.

## Decision

A multi-stage build compiles with a JDK and ships only a JRE. The jar is split with
`jarmode=tools extract --layers` into dependencies, loader, snapshot dependencies and application
code, copied in that order. The container runs as an unprivileged user, with a read-only root
filesystem, no privilege escalation and all Linux capabilities dropped, and the JVM sizes its heap
from the container limit with `MaxRAMPercentage`.

## Alternatives considered

- **Single-layer fat jar:** every commit rewrites the whole image, so every deploy pushes and pulls
  the dependencies again.
- **Buildpacks (`spring-boot:build-image`):** excellent defaults and almost no configuration, but the
  result is a black box; writing the Dockerfile is part of what this project is meant to show.

## Consequences

Rebuilds after a code change touch only the last layer. The image satisfies a restricted pod
security standard as it is. The read-only filesystem forces an explicit writable volume for `/tmp`,
which is a fair trade for removing a whole class of runtime tampering.
