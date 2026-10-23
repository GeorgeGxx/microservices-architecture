# ---- Stage 1: Build & Layer Extraction ----
FROM bellsoft/liberica-openjdk-alpine:21 AS builder

WORKDIR /app

# Mitigate CVE-2026-91403 (eMudhra intermediate CA compromise in OpenJDK <= 21.0.13)
COPY ./devsecops/compliance/java-security/blocked.certs /app/security/blocked.certs
RUN cp /app/security/blocked.certs "$JAVA_HOME/lib/security/blocked.certs"

COPY ./orders-service/docker/HttpHealthcheck.java /app/healthcheck-src/HttpHealthcheck.java
RUN mkdir -p /app/healthcheck && javac --release 21 -d /app/healthcheck /app/healthcheck-src/HttpHealthcheck.java

# 1) Parent pom.xml first -> better cache
COPY pom.xml .

# 2) wrapper + module pom.xml
WORKDIR /app/orders-service
COPY ./orders-service/.mvn ./.mvn
COPY ./orders-service/mvnw .
COPY ./orders-service/pom.xml .
RUN chmod +x mvnw

# 3) Dependencies in their own cache layer
RUN --mount=type=cache,target=/root/.m2 \
    ./mvnw dependency:go-offline -B

# 4) Source code + build (single layer that changes per commit)
COPY ./orders-service/src ./src
RUN --mount=type=cache,target=/root/.m2 \
    ./mvnw package -T 1C -DskipTests -Dmaven.javadoc.skip=true -B

# 5) Extract Spring Boot layers
WORKDIR /app/orders-service/target
RUN cp $(ls *.jar | grep -v -e '.original' -e 'sources' -e 'javadoc' | head -n1) application.jar
RUN java -Djarmode=tools -jar application.jar extract --layers --destination /app/extracted

# ---- Stage 2: Secure Distroless Runtime (non-root) ----
FROM gcr.io/distroless/java21-debian13:nonroot

WORKDIR /app

# The 4 Spring Boot layers in a single COPY instruction (1 layer instead of 4)
COPY --from=builder --chown=nonroot:nonroot \
    /app/extracted/dependencies/ \
    /app/extracted/spring-boot-loader/ \
    /app/extracted/snapshot-dependencies/ \
    /app/extracted/application/ \
    ./

COPY --from=builder --chown=nonroot:nonroot /app/healthcheck/ /app/healthcheck/
COPY --from=builder --chown=nonroot:nonroot /app/security/blocked.certs /usr/lib/jvm/temurin-21-jre-amd64/lib/security/blocked.certs
COPY --from=builder --chown=nonroot:nonroot /app/security/blocked.certs /usr/lib/jvm/temurin-21-jre-arm64/lib/security/blocked.certs

USER nonroot

HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 CMD ["java", "-cp", "/app/healthcheck", "HttpHealthcheck", "http://127.0.0.1:8003/actuator/orders/health"]

ENTRYPOINT ["java", "-XX:+UseContainerSupport", "-XX:+ExitOnOutOfMemoryError", "-XX:MaxRAMPercentage=75.0", "-Djava.security.egd=file:/dev/./urandom", "-Dcom.sun.net.ssl.checkRevocation=true", "-Dcom.sun.security.enableCRLDP=true", "-jar", "application.jar"]
