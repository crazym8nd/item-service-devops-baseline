# Build stage
FROM gradle:8.14.3-jdk24-corretto AS build
WORKDIR /app

COPY --chown=gradle:gradle . .

RUN gradle --no-daemon clean build -x test

# Runtime stage
FROM eclipse-temurin:24-jre

RUN apt-get update \
    && apt-get install -y --no-install-recommends curl=8.5.0-2ubuntu10.13 \
    && rm -rf /var/lib/apt/lists/*

RUN groupadd --system --gid 10001 app && useradd --system --uid 10001 --gid app app

WORKDIR /app

COPY --from=build /app/build/libs/*.jar app.jar

USER 10001

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=3 \
    CMD ["curl", "-f", "http://localhost:8080/actuator/health"]

ENTRYPOINT ["java", "-jar", "app.jar"]