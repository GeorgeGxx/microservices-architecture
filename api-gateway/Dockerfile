# Stage 1: Build & Layer Extraction
FROM bellsoft/liberica-openjdk-alpine:21 AS builder

WORKDIR /app

COPY pom.xml .
COPY ./api-gateway/pom.xml ./api-gateway/pom.xml
COPY ./api-gateway/.mvn ./api-gateway/.mvn
COPY ./api-gateway/mvnw ./api-gateway/mvnw
COPY ./api-gateway/src ./api-gateway/src

WORKDIR /app/api-gateway
RUN chmod +x mvnw && ./mvnw clean package -DskipTests -B

WORKDIR /app/api-gateway/target
RUN java -Djarmode=layertools -jar *.jar extract --destination /app/extracted

# Stage 2: Secure Distroless Runtime
FROM gcr.io/distroless/java21-debian13:nonroot

WORKDIR /app

# Copy layers at a granular level with non-root permissions.
COPY --from=builder --chown=nonroot:nonroot /app/extracted/dependencies/ ./
COPY --from=builder --chown=nonroot:nonroot /app/extracted/spring-boot-loader/ ./
COPY --from=builder --chown=nonroot:nonroot /app/extracted/snapshot-dependencies/ ./
COPY --from=builder --chown=nonroot:nonroot /app/extracted/application/ ./

# Expose the port the app runs on
EXPOSE 8080

# Ensure non-root user
USER nonroot

# Command to run the application using Spring Boot JarLauncher
ENTRYPOINT ["java", "-XX:+ExitOnOutOfMemoryError", "-XX:MaxRAMPercentage=75.0", "org.springframework.boot.loader.launch.JarLauncher"]