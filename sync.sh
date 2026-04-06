#!/bin/bash

# ─── Настройки ───────────────────────────────────────────────────────────────

SERVER="ivan@duvanoff.su"
REMOTE_PATH="~/new/cloud"
LOCAL_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ─── Синхронизация ────────────────────────────────────────────────────────────

echo "Синхронизирую с $SERVER:$REMOTE_PATH ..."

tar -czf - \
    --exclude='./.git' \
    --exclude='./.idea' \
    --exclude='./*.iml' \
    -C "$LOCAL_PATH" . \
| ssh "$SERVER" "mkdir -p $REMOTE_PATH && tar -xzf - -C $REMOTE_PATH"

echo ""
echo "✓ Готово"
