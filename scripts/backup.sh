#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BACKUP_DIR="$PROJECT_DIR/backups"

# Подтягиваем переменные из .env
if [ -f "$PROJECT_DIR/.env" ]; then
    set -a
    # shellcheck disable=SC1091
    source "$PROJECT_DIR/.env"
    set +a
fi

POSTGRES_USER="${POSTGRES_USER:-postgres}"
POSTGRES_DB="${POSTGRES_DB:-item_service}"
CONTAINER_NAME="db"
BACKUP_PASSPHRASE="${BACKUP_PASSPHRASE:-}"
BACKUP_RETENTION="${BACKUP_RETENTION:-7}"

if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
    echo "✗ Контейнер '$CONTAINER_NAME' не запущен."
    echo "  Запустите стек: make up"
    exit 1
fi

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/${POSTGRES_DB}_${TIMESTAMP}.sql.gz"

mkdir -p "$BACKUP_DIR"

echo "Создаю бекап $POSTGRES_DB из контейнера $CONTAINER_NAME..."

# --clean --if-exists: restore перезапишет существующие таблицы
docker exec "$CONTAINER_NAME" \
    pg_dump --clean --if-exists -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
    | gzip > "$BACKUP_FILE"

if ! gzip -t "$BACKUP_FILE" 2>/dev/null; then
    echo "✗ Проверка бекапа не пройдена!"
    rm -f "$BACKUP_FILE"
    exit 1
fi

# Если задан BACKUP_PASSPHRASE — шифруем (AES-256-CBC + PBKDF2)
if [ -n "$BACKUP_PASSPHRASE" ]; then
    ENCRYPTED_FILE="${BACKUP_FILE}.enc"
    openssl enc -aes-256-cbc -pbkdf2 -salt -pass "env:BACKUP_PASSPHRASE" \
        -in "$BACKUP_FILE" -out "$ENCRYPTED_FILE"
    rm -f "$BACKUP_FILE"
    BACKUP_FILE="$ENCRYPTED_FILE"
    echo "✓ Зашифровано (AES-256-CBC, PBKDF2)"
fi

# SHA-256 — restore сверяет по ней целостность
sha256sum "$BACKUP_FILE" > "${BACKUP_FILE}.sha256"

# Оставляем последние N бекапов, остальные удаляем
find "$BACKUP_DIR" -maxdepth 1 -type f -name "${POSTGRES_DB}_*.sql.gz*" -exec ls -1t {} + 2>/dev/null \
    | tail -n +$((BACKUP_RETENTION + 1)) \
    | while IFS= read -r old; do
        rm -f "$old" "${old}.sha256"
        echo "Удалён старый бекап: $old"
    done

FILE_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
echo "✓ Бекап создан: $BACKUP_FILE ($FILE_SIZE)"
echo "✓ Контрольная сумма: ${BACKUP_FILE}.sha256"
echo "✓ Храню последние $BACKUP_RETENTION бекапов"