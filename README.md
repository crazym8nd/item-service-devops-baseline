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

Пайплайн `.github/workflows/ci.yml` — стадии как в GitLab-пайплайне:

| Стадия | Джоба | Когда |
|--------|-------|-------|
| quality | `Quality Checks` — hadolint, shellcheck, compose config, jq дашбордов | push/PR |
| build | `Build` — `./gradlew bootJar -x test`, артефакт jar | push/PR |
| tests | `Tests` — `./gradlew test`, артефакт отчётов | после build |
| build-docker-image | `Docker Build` — `docker build` + smoke test (PostgreSQL + app) | после build + tests |
| release | `Push image to GHCR` — публикация образа в GitHub Container Registry | только push в main |
| deploy-development | `Deploy to Development` (имитация) | авто после docker-build |
| deploy-stage | `Deploy to Stage` (имитация, manual) | только `workflow_dispatch` |
| deploy-production | `Deploy to Production` (имитация, manual) | только `workflow_dispatch` |

Дополнительно:
- **Concurrency**: новый пуш отменяет старый запуск (`cancel-in-progress`).
- **Timeout**: у каждой джобы лимит времени — защита от зависших сборок.
- **Smoke test**: CI сам поднимает PostgreSQL + app, ждёт `/actuator/health == UP`, останавливает.
- **GHCR**: образ публикуется как `ghcr.io/crazym8nd/item-service-devops-baseline:{sha}` и `:latest`.

Деплой на stage/production — имитация (echo-шаги с GitHub Environments `development`/`stage`/`production`).
Ручной гейт с approval: Settings → Environments → stage/production → Required reviewers.
Запуск вручную: Actions → CI → Run workflow.

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
| **Branch protection** | main только через PR, без прямых пушей |
| **Spotless / Checkstyle** | Проверка формата Java в CI |
| **Trivy scan** | Сканирование Docker-образа на CVE |
| **Dependabot** | Авто-обновление зависимостей (Gradle, Docker, Actions) |
| **Бекап по расписанию** | Nightly cron + алерт на свободное место на диске |

### P1 — скоро (средняя сложность)

| Практика | Что даёт |
|----------|----------|
| **SonarQube** | Анализ качества кода + coverage gate |
| **Semantic release** | Авто-версионирование + changelog |
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

