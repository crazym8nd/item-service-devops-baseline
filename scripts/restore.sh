#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

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

if [ $# -lt 1 ]; then
    echo "Использование: $0 <файл_бекапа.sql.gz[.enc]>"
    echo ""
    echo "Доступные бекапы:"
    ls -1 "$PROJECT_DIR/backups/"*.sql.gz* 2>/dev/null || echo "  (нет)"
    exit 1
fi

BACKUP_FILE="$1"

if [ ! -f "$BACKUP_FILE" ]; then
    echo "✗ Файл не найден: $BACKUP_FILE"
    exit 1
fi

# Сверяем SHA-256 до того, как трогать БД
CHECKSUM_FILE="${BACKUP_FILE}.sha256"
if [ -f "$CHECKSUM_FILE" ]; then
    if ! (cd "$(dirname "$BACKUP_FILE")" && sha256sum -c "$(basename "$CHECKSUM_FILE")" --quiet); then
        echo "✗ Контрольная сумма не совпадает! Бекап повреждён или подменён."
        echo "  Восстановление отменено."
        exit 1
    fi
    echo "✓ Контрольная сумма совпадает"
else
    echo "⚠ Файл контрольной суммы не найден ($CHECKSUM_FILE) — проверка целостности пропущена"
fi

if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
    echo "✗ Контейнер '$CONTAINER_NAME' не запущен."
    echo "  Запустите стек: make up"
    exit 1
fi

# Расшифровываем, если бекап .enc
RESTORE_SOURCE="$BACKUP_FILE"
if [[ "$BACKUP_FILE" == *.enc ]]; then
    if [ -z "$BACKUP_PASSPHRASE" ]; then
        echo "✗ Файл зашифрован, но BACKUP_PASSPHRASE не задан в .env"
        exit 1
    fi
    DECRYPTED="${BACKUP_FILE%.enc}"
    openssl enc -d -aes-256-cbc -pbkdf2 -pass "env:BACKUP_PASSPHRASE" \
        -in "$BACKUP_FILE" -out "$DECRYPTED"
    RESTORE_SOURCE="$DECRYPTED"
    echo "✓ Расшифровано (AES-256-CBC, PBKDF2)"
fi

if ! gzip -t "$RESTORE_SOURCE" 2>/dev/null; then
    echo "✗ Некорректный gzip-файл: $RESTORE_SOURCE"
    if [ -n "${DECRYPTED:-}" ] && [ -f "$DECRYPTED" ]; then
        rm -f "$DECRYPTED"
    fi
    exit 1
fi

echo "Восстанавливаю $BACKUP_FILE в $POSTGRES_DB..."

gunzip -c "$RESTORE_SOURCE" | docker exec -i "$CONTAINER_NAME" \
    psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -q

# Подчищаем временный расшифрованный файл
if [ -n "${DECRYPTED:-}" ] && [ -f "$DECRYPTED" ]; then
    rm -f "$DECRYPTED"
fi

echo "✓ Восстановление завершено."