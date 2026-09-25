# syntax=docker/dockerfile:1

# ---------------------------------------------------------------- build stage
# The JDK, Maven and the whole dependency tree live here and never reach the final image.
FROM eclipse-temurin:21-jdk AS build
WORKDIR /workspace

# Copy the build descriptors first: as long as they do not change, the dependency
# download layer is reused even when the source code changes.
COPY mvnw ./
COPY .mvn/ .mvn/
COPY pom.xml ./
COPY domain/pom.xml domain/
COPY application/pom.xml application/
COPY infrastructure/pom.xml infrastructure/

COPY domain/src domain/src
COPY application/src application/src
COPY infrastructure/src infrastructure/src

# The cache mount keeps ~/.m2 between builds without baking it into a layer.
RUN --mount=type=cache,target=/root/.m2 \
    ./mvnw -B -ntp package -DskipTests

# Split the executable jar into layers ordered by how often they change.
# The application layer holds a thin jar that points at the extracted dependencies,
# so the container starts it with `java -jar`, not by calling the loader directly.
RUN cp infrastructure/target/infrastructure-*.jar application.jar && \
    java -Djarmode=tools -jar application.jar extract --layers --destination extracted

# -------------------------------------------------------------- runtime stage
# Only a JRE and the application: no compiler, no Maven, no source code.
FROM eclipse-temurin:21-jre AS runtime

# Running as root inside a container is an unnecessary risk, and many clusters forbid it.
RUN groupadd --system --gid 1001 ledger && \
    useradd --system --uid 1001 --gid ledger --home /app ledger
WORKDIR /app

# Copied in order of stability: dependencies change rarely, application code changes on every commit.
COPY --from=build --chown=ledger:ledger /workspace/extracted/dependencies/ ./
COPY --from=build --chown=ledger:ledger /workspace/extracted/spring-boot-loader/ ./
COPY --from=build --chown=ledger:ledger /workspace/extracted/snapshot-dependencies/ ./
COPY --from=build --chown=ledger:ledger /workspace/extracted/application/ ./

USER ledger
EXPOSE 8080

# Containers get a memory limit, not a machine: let the JVM size its heap from that limit.
ENV JAVA_TOOL_OPTIONS="-XX:MaxRAMPercentage=75.0 -XX:+ExitOnOutOfMemoryError"

ENTRYPOINT ["java", "-jar", "application.jar"]
