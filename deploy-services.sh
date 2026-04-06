#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOMAINS_FILE="$SCRIPT_DIR/domains.txt"

# ─── Остановка всех сервисов ─────────────────────────────────────────────────

echo "=== Останавливаю сервисы ==="
"$SCRIPT_DIR/manage.sh" down --all

# ─── Запуск nginx ────────────────────────────────────────────────────────────

#echo "=== Запускаю Nginx ==="
#docker compose -f ./compose.yaml up -d

# ─── Сертификаты ─────────────────────────────────────────────────────────────

echo ""
echo "=== Проверяю сертификаты ==="
if [ ! -f "$DOMAINS_FILE" ]; then
    echo "Ошибка: не найден $DOMAINS_FILE" >&2
    exit 1
fi

mapfile -t domains < <(grep -v '^\s*$' "$DOMAINS_FILE" | tr -d '\r')
"$SCRIPT_DIR/cert.sh" check "${domains[@]}"

# ─── Запуск всех сервисов ────────────────────────────────────────────────────

echo ""
echo "=== Запускаю сервисы ==="
"$SCRIPT_DIR/manage.sh" start --all

# ─── Крон задача ─────────────────────────────────────────────────────────────

echo ""
echo "=== Настраиваю крон ==="
CRON_CMD="0 9 * * 1 tr -d '\r' < $DOMAINS_FILE | xargs $SCRIPT_DIR/cert.sh renew >> /var/log/cert-renew.log 2>&1"
(crontab -l 2>/dev/null | grep -v "cert.sh"; echo "$CRON_CMD") | crontab -
echo "  ✓ Задача добавлена: cert.sh renew каждый понедельник в 9:00"

echo ""
echo "=== Деплой завершён ==="
