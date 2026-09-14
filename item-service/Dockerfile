#   CI:   "Build" job -> ./gradlew bootJar -> artifact -> "Docker Build & Publish"
#   local: ./gradlew bootJar  (then: docker build .)
FROM eclipse-temurin:24-jre

RUN apt-get update \
    && apt-get install -y --no-install-recommends curl=8.5.0-2ubuntu10.13 \
    && groupadd --system --gid 10001 app \
    && useradd --system --no-log-init --uid 10001 --gid app app \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY build/libs/*.jar app.jar

USER 10001

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=3 \
    CMD ["curl", "-f", "http://localhost:8080/actuator/health"]

ENTRYPOINT ["java", "-jar", "app.jar"]
