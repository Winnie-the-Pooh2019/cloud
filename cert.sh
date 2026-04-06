#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_MAIN="$SCRIPT_DIR/compose.yaml"
COMPOSE_SETUP="$SCRIPT_DIR/compose-setup.yaml"
EMAIL="ivan.duvanov.3@gmail.com"

# ─── Nginx ───────────────────────────────────────────────────────────────────

nginx_stop() {
    echo "Останавливаю nginx..."
    docker compose -f "$COMPOSE_MAIN" stop nginx
}

nginx_start() {
    echo "Запускаю nginx..."
    docker compose -f "$COMPOSE_MAIN" up -d nginx
}

nginx_reload() {
    echo "Перезагружаю nginx..."
    docker compose -f "$COMPOSE_MAIN" exec -T nginx nginx -s reload
}

nginx_setup_start() {
    echo "Запускаю nginx-setup..."
    docker compose -f "$COMPOSE_SETUP" up -d nginx-setup
}

nginx_setup_stop() {
    echo "Останавливаю nginx-setup..."
    docker compose -f "$COMPOSE_SETUP" stop nginx-setup
    docker compose -f "$COMPOSE_SETUP" rm -f nginx-setup
}

# ─── Certbot ─────────────────────────────────────────────────────────────────

cert_exists() {
    local domain="$1"
    local project_name
    project_name=$(grep -E '^name:' "$COMPOSE_MAIN" | head -1 | awk '{print $2}')
    docker run --rm \
        -v "${project_name}_certbot-etc:/etc/letsencrypt" \
        alpine \
        test -f "/etc/letsencrypt/live/$domain/fullchain.pem" 2>/dev/null
}

cert_issue() {
    local domain="$1"
    echo "Выдаю сертификат для $domain..."
    docker compose -f "$COMPOSE_SETUP" run --rm certbot certonly \
        --webroot --webroot-path=/var/www/certbot \
        --email "$EMAIL" \
        --agree-tos --no-eff-email --non-interactive \
        --keep-until-expiring \
        --preferred-challenges http \
        -d "$domain"
}

cert_renew() {
    local domain="$1"
    echo "Обновляю сертификат для $domain..."
    docker compose -f "$COMPOSE_SETUP" run --rm certbot renew \
        --cert-name "$domain"
}

# ─── Команды ─────────────────────────────────────────────────────────────────

cmd_issue() {
    if [ $# -eq 0 ]; then
        echo "Ошибка: укажите домены" >&2
        exit 1
    fi
    local domains=("$@")

    nginx_stop
    nginx_setup_start

    for domain in "${domains[@]}"; do
        cert_issue "$domain"
    done

    nginx_setup_stop
    nginx_start
    nginx_reload
}

cmd_renew() {
    if [ $# -eq 0 ]; then
        echo "Ошибка: укажите домены" >&2
        exit 1
    fi
    local domains=("$@")

    nginx_stop
    nginx_setup_start

    for domain in "${domains[@]}"; do
        cert_renew "$domain"
    done

    nginx_setup_stop
    nginx_start
    nginx_reload
}

cmd_check() {
    if [ $# -eq 0 ]; then
        echo "Ошибка: укажите домены" >&2
        exit 1
    fi
    local domains=("$@")

    local missing=()

    echo ""
    echo "Проверяю сертификаты:"
    for domain in "${domains[@]}"; do
        if cert_exists "$domain"; then
            echo "  ✓ $domain — сертификат найден"
        else
            echo "  ✗ $domain — сертификат отсутствует"
            missing+=("$domain")
        fi
    done

    if [ ${#missing[@]} -eq 0 ]; then
        echo ""
        echo "Все сертификаты на месте"
        return 0
    fi

    echo ""
    echo "Выдаю отсутствующие сертификаты..."

    nginx_stop
    nginx_setup_start

    for domain in "${missing[@]}"; do
        cert_issue "$domain"
    done

    nginx_setup_stop
    nginx_start
    nginx_reload
}

# ─── Точка входа ─────────────────────────────────────────────────────────────

case "${1:-}" in
    issue)
        shift
        cmd_issue "$@"
        ;;
    renew)
        shift
        cmd_renew "$@"
        ;;
    check)
        shift
        cmd_check "$@"
        ;;
    *)
        echo "Использование: $0 <команда> [домен1] [домен2] ..."
        echo ""
        echo "Команды:"
        echo "  issue  домен1 [домен2 ...]  — выдать сертификаты"
        echo "  renew  домен1 [домен2 ...]  — обновить сертификаты"
        echo "  check  домен1 [домен2 ...]  — проверить наличие, выдать если нет"
        exit 1
        ;;
esac
