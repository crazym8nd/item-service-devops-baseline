.PHONY: up down ps logs backup restore restore-valid restore-corrupted

COMPOSE := docker compose
COMPOSE_FILE := docker-compose.yml

up:
	$(COMPOSE) -f $(COMPOSE_FILE) up -d --build

down:
	$(COMPOSE) -f $(COMPOSE_FILE) down

ps:
	$(COMPOSE) -f $(COMPOSE_FILE) ps

logs:
	$(COMPOSE) -f $(COMPOSE_FILE) logs -f

backup:
	./scripts/backup.sh

restore:
	@if [ -z "$(FILE)" ]; then \
		echo "Использование: make restore FILE=backups/<файл>.sql.gz"; \
		echo ""; \
		echo "Доступные бекапы:"; \
		ls -1 backups/*.sql.gz* 2>/dev/null || echo "  (нет)"; \
		exit 1; \
	fi
	./scripts/restore.sh $(FILE)

restore-valid:
	./scripts/restore.sh backups/item_service_20260914_193034.sql.gz

restore-corrupted:
	./scripts/restore.sh backups/backup_corrupted.sql.gz
