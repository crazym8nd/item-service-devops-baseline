## 1. Project Scaffolding

- [x] 1.1 Create Gradle Kotlin DSL project structure: `build.gradle.kts` with Spring Boot 3.5.10, Java 24, dependencies (spring-boot-starter-web, spring-boot-starter-data-jpa, spring-boot-starter-actuator, postgresql, flyway-core, spring-boot-starter-validation), `settings.gradle.kts` with project name, generate Gradle wrapper 8.14.3 (версии из reference-проекта)
- [x] 1.2 Create `item-service/src/main/resources/application.yml` with Spring datasource (from env vars `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASSWORD`), JPA `ddl-auto=validate`, Flyway enabled, Actuator health/prometheus exposed
- [x] 1.3 Create `item-service/src/main/resources/db/migration/V001__create_items_table.sql` — `CREATE TABLE items (id BIGSERIAL PRIMARY KEY, name VARCHAR(255) NOT NULL)`
- [x] 1.4 Create `Item` entity (`item-service/src/main/java/com/example/itemservice/`) with `@Entity`, `@Id @GeneratedValue(strategy=GenerationType.IDENTITY)`, `name` with `@NotBlank`, no-arg + all-args constructors, getters/setters
- [x] 1.5 Create `ItemRepository` (Spring Data JPA) — extends `JpaRepository<Item, Long>`
- [x] 1.6 Create `ItemController` with `POST /api/items`: accepts `Item` JSON body, validates via `@Valid`, saves via repository, returns 201 with saved entity (including generated `id`), returns 400 on validation failure
- [x] 1.7 Verify project builds locally: `./gradlew build` succeeds

## 2. Integration Test

- [x] 2.1 Add test dependencies to `build.gradle.kts`: `spring-boot-starter-test`, `org.testcontainers:postgresql:1.19.4`, `org.testcontainers:junit-jupiter:1.19.4` (версия из reference)
- [x] 2.2 Create integration test class with `@SpringBootTest(webEnvironment = RANDOM_PORT)` + `@Testcontainers` + `@Container` PostgreSQL
- [x] 2.3 Configure test `application-test.yml` (or `@DynamicPropertySource`) to point Spring datasource at Testcontainers PostgreSQL
- [x] 2.4 Write test: `POST /api/items` with valid `{"name": "test"}` → assert 201, response contains `id` and `name`
- [x] 2.5 Write test: `POST /api/items` with `{"name": ""}` → assert 400
- [x] 2.6 Run `./gradlew test` — all tests green

## 3. Containerized Deployment

- [x] 3.1 Create `item-service/Dockerfile`: multi-stage — Stage 1: `gradle:8.14.3-jdk24-corretto` builds fat jar with `./gradlew :item-service:bootJar` (BuildKit cache mount `--mount=type=cache,target=/home/gradle/.gradle`); Stage 2: `eclipse-temurin:24-jre`, install `curl` via `apt-get` (в базовом JRE-образе нет ни curl, ни wget — паттерн reference), create non-root user `appuser`, copy jar, `USER appuser`, `ENTRYPOINT ["java", "-jar", "app.jar"]`
- [x] 3.2 Create `.env.example` with variables: `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`, `SPRING_DATASOURCE_USERNAME`, `SPRING_DATASOURCE_PASSWORD`, `SPRING_DATASOURCE_URL=jdbc:postgresql://db:5432/itemdb` (полный URL с именем БД — иначе app не подключится)
- [x] 3.3 Create `docker-compose.yml` with service `db`: `postgres:17-alpine` (мажорная версия 17.6 из reference), env from `.env`, named volume `db_data`, healthcheck (`pg_isready`), `restart: unless-stopped`, `deploy.resources.limits`, `logging: json-file max-size: 10m max-file: 3`
- [x] 3.4 Add service `migrate`: image `flyway/flyway:11` (совместим с Flyway 11.x в Spring Boot 3.5.10), depends on `db`, mounts `item-service/src/main/resources/db/migration:/flyway/sql`, command: `flyway -url=jdbc:postgresql://db:5432/$POSTGRES_DB -user=$POSTGRES_USER -password=$POSTGRES_PASSWORD migrate`, env from `.env`, `restart: "no"`
- [x] 3.5 Add service `app`: builds from `item-service/Dockerfile`, depends on `migrate: condition: service_completed_successfully`, ports `8080:8080`, env from `.env` (datasource URL/user/password), healthcheck (`curl -f http://localhost:8080/actuator/health || exit 1`, `start_period: 60s` — паттерн reference для Java-сервисов), `restart: unless-stopped`, `deploy.resources.limits`, `logging: json-file max-size: 10m max-file: 3`
- [x] 3.6 Create `item-service/.dockerignore`: exclude `.gradle/`, `build/`, `*.class`, `.idea/`, `*.iml` — уменьшает build context и не пускает артефакты сборки в образ
- [x] 3.7 Verify: `docker compose up --build` → all 3 services start, `app` reports healthy, `curl localhost:8080/actuator/health` returns `{"status":"UP"}`

## 4. Database Backup Script

- [x] 4.1 Create `scripts/backup.sh` with `set -euo pipefail`: read `PGHOST`, `PGPORT`, `PGDATABASE`, `PGUSER`, `PGPASSWORD` from env/`.env` file, set `BACKUP_DIR=backups`, `RETENTION_DAYS=7`
- [x] 4.2 Implement backup creation: `mkdir -p "$BACKUP_DIR"`, set dir permissions `700`, run `pg_dump` piped through `gzip`, write to `$BACKUP_DIR/${PGDATABASE}_$(date +%Y%m%d_%H%M%S).sql.gz`, set file permissions `600`
- [x] 4.3 Implement integrity check: `gzip -t "$file"` to verify archive, then `sha256sum` → write to `$file.sha256`, verify SHA256 roundtrip. If either check fails: log ERROR, exit 1, do not count as valid backup
- [x] 4.4 Implement rotation: after successful backup + integrity check, `find "$BACKUP_DIR" -name "*.sql.gz" -mtime +$RETENTION_DAYS -delete` (plus matching `.sha256`), log count of deleted files
- [x] 4.5 Add logging: timestamped INFO log on success, ERROR log on failure, exit code 0 on success, 1 on any failure. Verify idempotent: running twice in sequence produces same result if DB state unchanged
- [x] 4.6 Create `scripts/restore.sh`: restore from backup — verify SHA256 (`sha256sum -c <file>.sha256`), then `gunzip -c <file> | psql` (env from `.env`), `set -euo pipefail`, usage: `./restore.sh backups/<db>_<timestamp>.sql.gz`

## 5. CI Pipeline (GitHub Actions)

- [x] 5.1 Create `.github/workflows/ci.yml`: trigger on `push` and `pull_request` to `main`, `ubuntu-latest` runner, `concurrency: group: ci-${{ github.ref }}, cancel-in-progress: true`, `permissions: contents: read`, `timeout-minutes: 15`
- [x] 5.2 Add job `build-test`: checkout, setup JDK 24 (`actions/setup-java@v4` with `temurin`, `gradle-wrapper` cache), run `./gradlew build` (which includes tests), upload `build/reports/tests` as artifact on failure
- [x] 5.3 Add job `docker-build`: needs `build-test`, checkout, `docker build -t item-service:test ./item-service/` — no push, no registry interaction. Fail if build fails
- [x] 5.4 Verify by pushing to GitHub (step 7 below) — workflow should show green checkmarks on both jobs

## 6. Observability Stack

- [x] 6.1 Create `docker-compose.observability.yml` with service `prometheus`: `prom/prometheus:v3.7.1` (версия из reference), mounts `monitoring/prometheus.yml`, depends on `app`, healthcheck (`wget --spider http://localhost:9090/-/healthy`), `restart: unless-stopped`, `deploy.resources.limits`, `logging: json-file max-size: 10m max-file: 3`
- [x] 6.2 Create `monitoring/prometheus.yml`: scrape config for `job_name: "app"` (`static_configs: [{ targets: ["app:8080"] }], metrics_path: "/actuator/prometheus", scrape_interval: 15s`) and `job_name: "postgres"` (`static_configs: [{ targets: ["postgres-exporter:9187"] }]`)
- [x] 6.3 Add service `postgres-exporter`: `prometheuscommunity/postgres-exporter:v0.18.1` (версия из reference), env `DATA_SOURCE_NAME=postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@db:5432/${POSTGRES_DB}?sslmode=disable`, depends on `db` healthy, healthcheck `wget --spider http://localhost:9187/metrics` (pattern from reference repo)
- [x] 6.4 Add service `grafana`: `grafana/grafana:12.3.1` (версия из reference), depends on `prometheus` and `loki`, mounts `monitoring/grafana/provisioning/` (datasources + dashboards YAML), port `3000`, env `GF_SECURITY_ADMIN_USER`/`GF_SECURITY_ADMIN_PASSWORD` from `.env` (паттерн reference), `restart: unless-stopped`, `deploy.resources.limits`, `logging: json-file max-size: 10m max-file: 3`
- [x] 6.5 Create `monitoring/grafana/provisioning/datasources/datasources.yml`: auto-provision Prometheus and Loki datasources
- [x] 6.6 Create `monitoring/grafana/provisioning/dashboards/dashboards.yml`: point to `/var/lib/grafana/dashboards/`, create `monitoring/grafana/dashboards/app.json` with panels: `up{job="app"}` gauge, `pg_up{job="postgres"}` gauge, request rate panel
- [x] 6.7 Add service `loki`: `grafana/loki:3.6.3` (версия из reference), port `3100`
- [x] 6.8 Add service `alloy`: `grafana/alloy:v1.12.2` (версия из reference), mounts `monitoring/alloy/config.alloy`, volumes `/var/run/docker.sock:/var/run/docker.sock` + `/var/lib/docker/containers:/var/lib/docker/containers` (паттерн reference) — collect Docker container logs (stdout/stderr from `app`, `db`, `migrate`) and push to Loki
- [x] 6.9 Create `monitoring/alloy/config.alloy` with `discovery.docker` + `loki.write` pipeline
- [x] 6.10 Create `monitoring/grafana/provisioning/alerting/alert_rules.yml`: two Grafana Alert Rules — `app-down` (`up{job="app"} == 0 for 1m`) and `db-down` (`pg_up{job="postgres"} == 0 for 1m`), both send to Telegram Contact Point
- [x] 6.11 Create `monitoring/grafana/provisioning/alerting/contact_points.yml`: Telegram Contact Point with `BOT_TOKEN` and `CHAT_ID` from env vars (provisioned as placeholders, user fills in Grafana UI or env)
- [x] 6.12 Verify: `docker compose -f docker-compose.yml -f docker-compose.observability.yml up` → all services start, Grafana accessible on `localhost:3000`, datasource auto-provisioned, dashboard shows `up{job="app"}` = 1 and `pg_up{job="postgres"}` = 1

## 7. Documentation & GitHub Publish

- [x] 7.1 Create `README.md`: project overview, architecture diagram (text), prerequisites (Java 24, Docker, Docker Compose), quick start (`.env` → `docker compose up`), each component explained
- [x] 7.2 README section: architectural decisions and trade-offs (why Flyway run-once container, why no self-written healthcheck script — monitoring and alerting on two direct exporters (actuator/prometheus + postgres_exporter) with Grafana Alerting, why direct exporters instead of blackbox exporter, why single POST endpoint, why `.env` not Vault)
- [x] 7.3 README section: production TODOs (Vault integration, encrypted backups, TLS for DB, streaming replication, full CRUD, WAL archiving) with brief explanation of what each would involve
- [x] 7.4 Create `.gitignore`: `.env`, `build/`, `*.class`, `backups/`, `logs/`, `.gradle/`, `item-service/build/`
- [x] 7.5 Commit all files, create GitHub repo via `gh repo create crazym8nd/item-service-devops-baseline --private --source=. --remote=origin`, push to `main`
- [x] 7.6 Verify CI: `gh run list --workflow=ci.yml --limit 1` → status `completed`, conclusion `success`. If failed: read logs (`gh run view <id> --log-failed`), fix, re-push, re-verify
- [x] 7.7 Report to user: repo URL, green CI link, summary of what was built
