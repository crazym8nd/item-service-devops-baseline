# ci-pipeline Specification

## Purpose
Автоматическая проверка на каждом push/PR, что проект собирается, тесты
проходят и Docker-образ приложения успешно строится. Ветка `main` защищена:
изменения попадают в неё только через одобренный pull request. После успешного
smoke test коммита, попавшего в `main`, образ публикуется в GHCR.

## Requirements

### Requirement: Пайплайн запускается на push и pull request
Система CI SHALL запускать workflow на событиях `push` и `pull_request` для
основной ветки, используя `ubuntu-latest` runner.

### Requirement: Публикация требует защищённую основную ветку
Ветка `main` SHALL быть защищена правилами GitHub: прямые push запрещены,
слияние возможно только через pull request с обязательным approve и успешными
CI-проверками. Поэтому `push` в `main` является результатом слияния
одобренного pull request.

#### Scenario: Push в ветку
- **WHEN** выполняется push коммита в отслеживаемую ветку
- **THEN** GitHub Actions запускает workflow `ci.yml`

### Requirement: Пайплайн собирает проект и запускает тесты
Пайплайн SHALL выполнять сборку Gradle-проекта и запуск тестового набора,
включая интеграционный тест на Testcontainers, без внешних секретов.

#### Scenario: Успешная сборка и тесты
- **WHEN** код компилируется без ошибок и интеграционный тест на
  Testcontainers проходит (Docker доступен в среде выполнения runner'а из
  коробки)
- **THEN** шаги `build` и `test` пайплайна завершаются с успехом, отчёт о
  тестах доступен как артефакт workflow

#### Scenario: Провал теста останавливает пайплайн
- **WHEN** один из тестов завершается с ошибкой
- **THEN** workflow помечается как failed и последующий шаг сборки
  Docker-образа не выполняется

### Requirement: Пайплайн проверяет и публикует Docker-образ
Пайплайн SHALL после успешных build и test один раз выполнять `docker build`
образа приложения по `Dockerfile` из `item-service/` и запускать smoke test
этого же локального образа с PostgreSQL. При `push` в `main` workflow SHALL
проставлять проверенному образу теги `latest` и полный SHA коммита и
публиковать именно его в GHCR. Для `pull_request` и `workflow_dispatch`
публикация образа не выполняется.

#### Scenario: Образ собирается и проходит smoke test
- **WHEN** предыдущие шаги (build, test) завершились успешно
- **THEN** шаг сборки образа выполняет `docker build`, запускает этот образ с
  PostgreSQL и завершается с кодом 0, когда `/actuator/health` возвращает
  статус `UP`

#### Scenario: Проверенный образ публикуется после merge одобренного PR
- **WHEN** одобренный pull request успешно слит в защищённую ветку `main` и
  smoke test его commit успешно завершился
- **THEN** workflow публикует smoke-tested образ в GHCR с тегами `latest` и
  полным SHA коммита, без повторной сборки образа

#### Scenario: Образ не публикуется вне push в main
- **WHEN** workflow запущен по `pull_request` или `workflow_dispatch`
- **THEN** Docker-образ может быть собран и проверен, но `docker push` в GHCR
  не выполняется
