## Why

Тестовое задание на позицию Junior DevOps-инженера требует показать работу с
Docker/Compose, CI/CD, скриптами резервного копирования и мониторингом с
уведомлениями, а также понимание рисков эксплуатации. Нужен небольшой, но
реалистичный сервис (Spring Boot + PostgreSQL), вокруг которого эти
DevOps-артефакты имеют смысл (реальная схема БД для бэкапа, реальный
`/actuator/health` и метрики для мониторинга), и который умещается в
заявленный лимит ~4 часов без переусложнения (без
Kafka/шардирования/Kubernetes).

## What Changes

- Добавлено Spring Boot приложение `item-service` (Java 24, Gradle Kotlin DSL,
  версии стека — Spring Boot 3.5.10, Gradle 8.14.3 — взяты из проверенного
  reference-проекта)
  с одной сущностью `Item{id, name}`, одним REST-эндпоинтом `POST /api/items`,
  схемой БД через Flyway-миграции (`ddl-auto=validate`), Actuator
  (`/actuator/health` с реальной проверкой соединения с PostgreSQL,
  `/actuator/prometheus` через Micrometer).
- Добавлен один интеграционный тест на Testcontainers (реальный Postgres в
  контейнере): контекст поднимается, валидный POST создаёт сущность (201),
  пустой `name` отклоняется (400).
- Добавлен multi-stage `Dockerfile` (build на JDK, runtime на JRE
  `eclipse-temurin:24-jre`, non-root user).
- Добавлен `docker-compose.yml` с тремя сервисами: `db` (postgres, healthcheck),
  `migrate` (run-once Flyway-контейнер, накатывает схему и завершается),
  `app` (стартует только после успешного завершения `migrate`).
- Добавлен `.github/workflows/ci.yml`: build → test (включая Testcontainers,
  Docker доступен в GH Actions из коробки) → `docker build` образа приложения
  (без push в registry; push в GHCR документирован в README как опциональный
  шаг).
- Добавлен `scripts/backup.sh`: `pg_dump` → gzip → SHA256-контроль
  целостности → ротация бэкапов старше 7 дней → права доступа 600/700 →
  секреты из `.env` → структурированное логирование и осмысленные коды
  возврата.
- Добавлен `docker-compose.observability.yml`: Prometheus (скрейпит
  `/actuator/prometheus` приложения и `postgres-exporter`), Grafana
  (provisioned datasource + дашборд + два Alert Rule — `app-down` на
  `up{job="app"} == 0 for 1m` и `db-down` на `pg_up{job="postgres"} == 0
  for 1m` → Telegram Contact Point), Grafana Alloy (сбор stdout-логов
  контейнеров `app`/`db`/`migrate` в Loki), Loki (хранилище логов).
  Поднимается отдельной командой, не мешает базовому стеку. Мониторинг и
  алертинг полностью строятся на двух прямых экспортерах
  (actuator/prometheus + postgres_exporter) — без самописного скрипта
  проверки здоровья (см. `design.md`).
- Добавлен `README.md`: инструкция запуска (база + observability), описание
  принятых решений, TODO для продакшена (TLS к БД, шифрование бэкапов,
  offsite-хранение, инкрементальные бэкапы, push образа в GHCR, HashiCorp
  Vault для секретов — `spring-cloud-vault-config` + KV v2 + AppRole) и
  явный раздел рисков.

## Capabilities

### New Capabilities
- `item-service`: Spring Boot REST-сервис с сущностью Item, схемой БД через
  Flyway и Actuator health/metrics endpoints.
- `containerized-deployment`: Dockerfile и оркестрация docker-compose
  (db → migrate → app) для локального/тестового запуска.
- `ci-pipeline`: GitHub Actions пайплайн (build, test, сборка Docker-образа).
- `db-backup`: скрипт резервного копирования PostgreSQL с ротацией и
  проверкой целостности.
- `observability-stack`: стек Prometheus + Grafana + Loki + Alloy +
  postgres_exporter с алертингом в Telegram по метрикам доступности
  приложения и БД.

### Modified Capabilities
_(нет — репозиторий пустой, все капабилити новые)_

## Impact

- Новый Java/Gradle проект `item-service/` (код, тесты, Dockerfile).
- Новые файлы инфраструктуры в корне репозитория: `docker-compose.yml`,
  `docker-compose.observability.yml`, `.env.example`, `.gitignore`.
- Новая CI-конфигурация `.github/workflows/ci.yml` (GitHub Actions,
  без внешних секретов/permissions).
- Новые операционные скрипты `scripts/backup.sh`, `scripts/lib/common.sh`.
- Новая директория `observability/` с конфигурацией Prometheus, Grafana
  provisioning и Alloy.
- Внешние зависимости: Docker Engine + Docker Compose v2 на машине запуска;
  для Telegram-алертинга — Telegram Bot Token (создаётся через `@BotFather`,
  описано в README).
