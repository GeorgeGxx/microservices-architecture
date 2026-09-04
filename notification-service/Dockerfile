# ---- Stage 1: Build & Layer Extraction ----
FROM bellsoft/liberica-openjdk-alpine:21 AS builder

WORKDIR /app

# 1) Parent pom.xml first -> better cache
COPY pom.xml .

# 2) wrapper + module pom.xml
WORKDIR /app/notification-service
COPY ./notification-service/.mvn ./.mvn
COPY ./notification-service/mvnw .
COPY ./notification-service/pom.xml .
RUN chmod +x mvnw

# 3) Dependencies in their own cache layer
RUN --mount=type=cache,target=/root/.m2 \
    ./mvnw dependency:go-offline -B

# 4) Source code + build (single layer that changes per commit)
COPY ./notification-service/src ./src
RUN --mount=type=cache,target=/root/.m2 \
    ./mvnw clean package -DskipTests -B

# 5) Extract Spring Boot layers
WORKDIR /app/notification-service/target
RUN java -Djarmode=layertools -jar *.jar extract --destination /app/extracted

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

USER nonroot

ENTRYPOINT ["java", "-XX:+ExitOnOutOfMemoryError", "-XX:MaxRAMPercentage=75.0", "org.springframework.boot.loader.launch.JarLauncher"]
