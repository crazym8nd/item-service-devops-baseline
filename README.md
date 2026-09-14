# Item Service — DevOps Baseline

REST API (Spring Boot 3.5 + PostgreSQL 17) с observability-стеком (Prometheus, Grafana, Loki, Alloy), алертингом в Telegram и CI через GitHub Actions.

## Требования

- Java 24+
- Gradle 8.14+
- Docker + Docker Compose
- Make (опционально)

## Быстрый старт

```bash
cp .env.example .env   # заполнить TELEGRAM_BOT_TOKEN_GRAFANA (токен бота)
make up                # старт
```

> **Telegram-алерты:** в `monitoring/grafana/provisioning/alerting/contact_points.yml`
> замените плейсхолдер `999999999` на ваш chat id (число в кавычках).
> Chat id хардкодится строкой, т.к. Grafana не подставляет числовой `${TELEGRAM_CHAT_ID}`
> из env корректно (известный баг с 2023 года).

## Команды Makefile

| Команда | Что делает |
|---------|------------|
| `make up` | Запуск полного стека (db + app + observability) |
| `make down` | Остановка |
| `make ps` | Список контейнеров |
| `make logs` | Логи |
| `make backup` | Снять бекап БД |
| `make restore FILE=...` | Восстановить из бекапа |
| `make restore-valid` | Демо: восстановление валидного бекапа |
| `make restore-corrupted` | Демо: восстановление испорченного бекапа (упадёт на checksum) |

## API

| Метод | URL | Описание |
|-------|-----|----------|
| POST  | `/api/items` | Создать item (требуется `name` в JSON body) |

## Мониторинг

| Сервис | URL |
|--------|-----|
| Grafana | http://localhost:3000 (admin/admin) |
| Prometheus | http://localhost:9090 |
| Alloy | http://localhost:12345 |

Datasource'ы и дашборды провижинятся автоматически:

| Дашборд | UID | Что показывает |
|---------|-----|----------------|
| Item Service | `item-service-dashboard` | App up, PG up, Request rate |
| PostgreSQL | `postgres-dashboard` | Connections, DB size, WAL, locks, replication, BGWriter и др. |
| JVM мониторинг | `jvm-dashboard` | HTTP (RPS, latency, errors), JVM memory/GC/threads, HikariCP, Logback, Tomcat sessions, CPU/disk |

## Алертинг

| Rule | Condition | Duration |
|------|-----------|----------|
| App is down | `up{job="app"} == 0` | 5s (evaluation 10s) |
| Database is down | `pg_up{job="postgres"} == 0` | 5s (evaluation 10s) |

Уведомления приходят в Telegram через Grafana Alerting.
Конфигурация: [`monitoring/grafana/provisioning/alerting/`](monitoring/grafana/provisioning/alerting/) — правила (`alert_rules.yml`), contact points (`contact_points.yml`), политики (`policies.yml`).
Креды: `TELEGRAM_BOT_TOKEN_GRAFANA` берётся из `.env` через `${...}`,
chat id захардкожен в `contact_points.yml` (плейсхолдер `999999999` — замените на свой).

## CI/CD (GitHub Actions)

В репозитории два workflow: `ci.yml` проверяет и публикует образ, `cd.yml` разворачивает уже опубликованный образ. CD ничего не пересобирает.

### CI

CI запускается при pull request в `main`, push в `main` и вручную из GitHub Actions.

| Job | Назначение |
|-------|-----------|-------|
| `Quality Checks` | Проверяет Dockerfile через Hadolint, shell-скрипты через ShellCheck, Compose-конфигурацию и JSON-дашборды Grafana |
| `Build` | Собирает JAR командой `./gradlew bootJar -x test` и сохраняет его как артефакт |
| `Tests` | Запускает `./gradlew test`, публикует JUnit-результаты для PR и сохраняет HTML-отчёт |
| `Docker Build & Publish` | Забирает готовый JAR, собирает Docker-образ, запускает его вместе с PostgreSQL и ждёт ответа `UP` от `/actuator/health` |

`Quality Checks`, `Build` и `Tests` выполняются параллельно. `Quality Checks` — информационная проверка: ошибка видна в Actions, но не останавливает build, tests, публикацию образа или merge.

Docker-образ собирается только после успешных `Build` и `Tests`. Gradle внутри Docker-образа не запускается: CI использует JAR, собранный отдельной job.

После push в `main` и успешного smoke test CI публикует проверенный образ в GHCR:

- `ghcr.io/crazym8nd/item-service-devops-baseline:latest`;
- `ghcr.io/crazym8nd/item-service-devops-baseline:sha-<полный SHA коммита>`.

Для pull request и ручного запуска образ может быть собран и проверен, но в GHCR он не публикуется. Новый push в ту же ветку отменяет незавершённый CI-run. JAR и HTML-отчёт тестов хранятся в Actions 7 дней.

GitHub Actions и Docker-образы закреплены полными SHA/digest, поэтому повторная сборка использует те же внешние зависимости.

### CD

CD использует только образы, опубликованные в GHCR. Перед simulated-deploy он проверяет тег и получает immutable-ссылку на digest:

```text
ghcr.io/crazym8nd/item-service-devops-baseline@sha256:<digest>
```

| Окружение | Запуск | Образ |
|-------|-------|-------------|
| `development` | Автоматически после успешного CI на `main` | `sha-<SHA коммита>`, разрешённый в digest |
| `stage` | Вручную: **Actions → CD → Run workflow** | `sha-<SHA>` или `vX.Y.Z`, разрешённый в digest |
| `production` | Вручную: **Actions → CD → Run workflow** | `sha-<SHA>` или `vX.Y.Z`, разрешённый в digest |

Для ручного запуска `image_tag` обязателен. Workflow принимает только `sha-<40 lowercase hex>` и `vX.Y.Z`; `latest` и произвольные значения отклоняет.

У каждого окружения своя concurrency-группа. Уже запущенный деплой не отменяется следующим запуском.

Сейчас deploy-jobs выполняют `echo`. Для `stage` и `production` можно настроить ручное подтверждение: **Settings → Environments → `<environment>` → Required reviewers**.

> Один ручной запуск CD создаёт jobs для `stage` и `production`. Для строго последовательного promotion-flow, где production доступен только после stage, нужно отдельно изменить workflow.

### Правила для `main`

Ruleset `merge-request` защищает `main`:

- прямые push, force push и удаление ветки запрещены;
- изменения попадают в `main` только через pull request;
- перед merge нужен один approval;
- ветка должна быть актуальна относительно `main`;
- перед merge обязательны успешные checks: `Build`, `Tests`, `Docker Build & Publish`.

`Quality Checks` в ruleset не входит и merge не блокирует. После merge CI публикует smoke-tested образ, а CD автоматически разворачивает этот же образ в `development`.

### Релизные теги

Сейчас CI публикует `latest` и `sha-<commit>`. Ручной CD уже принимает `vX.Y.Z`, но CI ещё не запускается по Git-тегам и не публикует образы с семверным тегом.

Целевой release-flow добавлен в roadmap: Semantic release создаёт Git tag `vX.Y.Z`, CI публикует образ с тем же тегом в GHCR, затем CD разворачивает его immutable digest на stage или production. До этого для stage и production используйте опубликованный тег `sha-<SHA коммита>`.

## Архитектурные решения

| Решение | Почему |
|---------|--------|
| **Flyway как одноразовый контейнер** (`migrate`) | Миграции гоняет отдельный контейнер до старта приложения (`depends_on: service_completed_successfully`). Порядок детерминированный: app не стартует, пока схема не готова. Миграции при старте app размазывают ответственность и усложняют отладку |
| **Прямые экспортеры вместо blackbox** | Метрики приложения — `actuator/prometheus` (JVM, HikariCP, HTTP), БД — `postgres_exporter` (connections, WAL, locks, replication). Готовые экспортеры дают глубокие метрики, blackbox — только up/down |
| **`.env` вместо Vault** | Локальный стек: секреты в `.env` (в `.gitignore`). Vault — для прода, см. Production TODOs |

## Production TODOs

| Практика | Что это и зачем |
|----------|-----------------|
| **Vault integration** | Секреты (пароли БД, токены) в HashiCorp Vault вместо `.env`: централизованное хранение, ротация, аудит доступа |
| **Encrypted backups** | Уже есть: `BACKUP_PASSPHRASE` → AES-256-CBC (PBKDF2). В проде — ключи в KMS и их ротация |
| **TLS for DB** | Шифрование соединения app↔db (SSL-сертификаты) — защита трафика внутри сети |
| **Streaming replication** | Реплика БД (hot standby): отказоустойчивость и read-scaling |
| **Incremental backups** | Инкрементальные бекапы: только изменения с последнего полного бекапа — меньше места и времени на создание |
| **WAL archiving** | Непрерывное архивирование WAL → point-in-time recovery (восстановление на любой момент времени) |

## Roadmap

Что уже есть — выше. Что добавлять дальше, по приоритету:

### P0 — ближайшее (низкая сложность, быстрый эффект)

| Практика | Что даёт |
|----------|----------|
| **Environments + approval** | Ручной гейт на stage/prod (Required reviewers) |
| **Branch protection** | Настроено: `main` только через одобренный PR, без прямых push |
| **Spotless / Checkstyle** | Проверка формата Java в CI |
| **Trivy scan** | Сканирование Docker-образа на CVE |
| **Dependabot** | Авто-обновление зависимостей (Gradle, Docker, Actions) |
| **Бекап по расписанию** | Nightly cron + алерт на свободное место на диске |

### P1 — скоро (средняя сложность)

| Практика | Что даёт |
|----------|----------|
| **SonarQube** | Анализ качества кода + coverage gate |
| **Semantic release + release-tag CI/CD** | Авто-версионирование + changelog; Git tag `vX.Y.Z` запускает CI, публикует одноимённый образ в GHCR, после чего CD разворачивает его immutable digest на stage/prod |
| **Sentry release** | Трекинг релизов в Sentry |
| **Реальный деплой** | Деплойный репозиторий + registry + dispatch |
| **Restore drills** | Регулярное восстановление из бекапа в тестовую БД |

### P2 — потом (большая сложность)

| Практика | Что даёт |
|----------|----------|
| **K8s/Helm** | Раскатка в кластер вместо Docker Compose |
| **Terraform** | Инфраструктура как код |
| **Multi-arch сборка** | Образы amd64 + arm64 |
| **SBOM + cosign** | Манифест зависимостей + подпись образов |
| **OpenTelemetry** | Сквозная трассировка |
| **Zero-downtime деплой** | Blue-green / rolling |

## Backup / Restore

```bash
make backup                              # Дамп → backups/
make restore FILE=backups/xxx.sql.gz     # Восстановление
```

Что делает `backup.sh`:
- `pg_dump --clean --if-exists` из контейнера `db` → `backups/item_service_<timestamp>.sql.gz`
- **Шифрование** AES-256-CBC (PBKDF2), если задан `BACKUP_PASSPHRASE` в `.env` → файл `.sql.gz.enc`
- **SHA-256 checksum** рядом с архивом (`.sha256`)
- **Retention**: хранит последние `BACKUP_RETENTION` (по умолчанию 7) бекапов, старые удаляет

Что делает `restore.sh`:
- **Проверяет SHA-256** перед восстановлением — при несовпадении отказывается (защита от повреждения/подмены)
- Расшифровывает `.enc` (нужен `BACKUP_PASSPHRASE`)
- Восстанавливает в БД через `psql` (перезаписывает существующие объекты)

### Демо: валидный vs испорченный бекап

В `backups/` лежат два демо-файла:

| Файл | Что это |
|------|---------|
| `item_service_20260914_193034.sql.gz` | Валидный бекап (5 записей в `items`) |
| `backup_corrupted.sql.gz` | Тот же бекап, но в конец дописаны байты, а checksum оставлен от оригинала |

```bash
make restore-valid       # ✓ Контрольная сумма совпадает → restore проходит
make restore-corrupted   # ✗ Контрольная сумма не совпадает → restore отказывается
```

Испорченный бекап имитирует повреждение/подмену файла: `restore.sh` ловит
несовпадение SHA-256 и не трогает БД.

### Продакшен-практики (на будущее)

Локальные скрипты — это база. В проде бекапы живут по-другому:

| Практика | Что делать |
|----------|-----------|
| **Расписание** | Бекап по cron / CI scheduled job (например, nightly в 02:00) |
| **Мониторинг диска** | Алерт на свободное место на диске с бекапами (Prometheus `node_filesystem_avail_bytes` + alert, или Grafana Cloud) — бекап, которому некуда писаться, молча умирает |
| **Мониторинг бекапа** | Метрика/алерт «последний успешный бекап старше N часов» (blackbox-проверка файла + mtime) |
| **3-2-1 правило** | 3 копии, 2 разных носителя, 1 вне площадки (S3/объектное хранилище) |
| **Restore drills** | Регулярно (раз в месяц) восстанавливать бекап в тестовую БД — бекап, который ни разу не восстанавливали, это не бекап |
| **Ротация ключей** | Периодически менять `BACKUP_PASSPHRASE` |
| **Проверка целостности** | Периодически прогонять `sha256sum -c` по всем бекапам (detect bit rot) |
