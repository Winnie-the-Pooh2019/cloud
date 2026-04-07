#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVS_DIR="$SCRIPT_DIR/servs"
NGINX_CONF="$SCRIPT_DIR/nginx/prod/conf.d"
NGINX_SETUP="$SCRIPT_DIR/nginx/setup/conf.d"

PROJECT_NAME="cloud"

# ─── Утилиты ────────────────────────────────────────────────────────────────

find_compose_file() {
    local service_dir="$1"
    local service_name="$2"

    if [ -f "$service_dir/compose.yaml" ]; then
        echo "$service_dir/compose.yaml"
    elif [ -f "$service_dir/$service_name.yaml" ]; then
        echo "$service_dir/$service_name.yaml"
    else
        find "$service_dir" -maxdepth 1 -name "*.yaml" | head -1
    fi
}

get_available_services() {
    find "$SERVS_DIR" -mindepth 1 -maxdepth 1 -type d | xargs -I{} basename {} | sort
}

is_service_running() {
    local service_name="$1"
    [ -f "$NGINX_CONF/$service_name.conf" ]
}

#is_service_running() {
#    local service_name="$1"
#    local service_dir="$SERVS_DIR/$service_name"
#    [ -d "$service_dir" ] || return 1
#    local compose_file
#    compose_file=$(find_compose_file "$service_dir" "$service_name")
#    [ -z "$compose_file" ] && return 1
#    docker compose -f "$compose_file" ps --status running --quiet 2>/dev/null | grep -q .
#}


is_nginx_running() {
    docker compose -f "$SCRIPT_DIR/compose.yaml" ps --status running --quiet nginx 2>/dev/null | grep -q .
}

reload_nginx() {
    if is_nginx_running; then
        docker compose -f "$SCRIPT_DIR/compose.yaml" exec -T nginx nginx -s reload
        echo "  ✓ nginx перезагружен"
    else
        echo "  ⚠ nginx не запущен, пропускаю перезагрузку"
    fi
}

cmd_nginx() {
    local action="${1:-}"
    case "$action" in
        start)
            echo "Запускаю nginx..."
            docker compose -f "$SCRIPT_DIR/compose.yaml" up -d
            echo "nginx запущен"
            ;;
        stop)
            echo "Останавливаю nginx..."
            docker compose -f "$SCRIPT_DIR/compose.yaml" stop nginx
            echo "nginx остановлен"
            ;;
        down)
            echo "Удаляю nginx..."
            docker compose -f "$SCRIPT_DIR/compose.yaml" down
            echo "nginx удалён"
            ;;
        reload)
            reload_nginx
            ;;
        *)
            echo "Использование: $0 nginx [start|stop|down|reload]"
            return 1
            ;;
    esac
}

# ─── Справка ────────────────────────────────────────────────────────────────

cmd_help() {
    echo ""
    echo "Использование: $(basename "$0") <команда> [аргументы]"
    echo ""
    echo "Управление сервисами:"
    echo "  start <сервис...>   Запустить один или несколько сервисов"
    echo "  start --all         Запустить все сервисы"
    echo "  stop  <сервис...>   Остановить один или несколько сервисов"
    echo "  stop  --all         Остановить все сервисы"
    echo "  down  <сервис...>   Остановить и удалить контейнеры сервиса"
    echo "  down  --all         Остановить и удалить все сервисы"
    echo ""
    echo "Управление nginx:"
    echo "  nginx start         Запустить nginx"
    echo "  nginx stop          Остановить nginx"
    echo "  nginx down          Остановить и удалить контейнер nginx"
    echo "  nginx reload        Перезагрузить конфигурацию nginx"
    echo ""
    echo "Информация:"
    echo "  status              Статус всех сервисов и nginx"
    echo "  list                Список доступных сервисов"
    echo "  help                Показать эту справку"
    echo ""
    echo "Без аргументов запускается интерактивное меню."
    echo ""
}

# ─── Команды ────────────────────────────────────────────────────────────────

cmd_list() {
    echo ""
    echo "Доступные сервисы:"
    while IFS= read -r service; do
        echo "  - $service"
    done < <(get_available_services)
}

cmd_status() {
    echo ""
    echo "Статус сервисов:"
    if is_nginx_running; then
        echo "  ● nginx  [запущен]"
    else
        echo "  ○ nginx  [остановлен]"
    fi
    while IFS= read -r service; do
        if is_service_running "$service"; then
            echo "  ● $service  [запущен]"
        else
            echo "  ○ $service  [остановлен]"
        fi
    done < <(get_available_services)
}

cmd_start() {
    local service_name="$1"
    local service_dir="$SERVS_DIR/$service_name"

    if [ ! -d "$service_dir" ]; then
        echo "Ошибка: сервис '$service_name' не найден в $SERVS_DIR"
        return 1
    fi

    if is_service_running "$service_name"; then
        echo "Сервис '$service_name' уже запущен"
        return 0
    fi

    local compose_file
    compose_file=$(find_compose_file "$service_dir" "$service_name")

    if [ -z "$compose_file" ]; then
        echo "Ошибка: compose-файл не найден в $service_dir"
        return 1
    fi

    echo "Запускаю '$service_name'..."

    if [ -f "$service_dir/nginx.conf" ]; then
        cp "$service_dir/nginx.conf" "$NGINX_CONF/$service_name.conf"
        echo "  ✓ nginx.conf скопирован"
    fi

    if [ -f "$service_dir/acme.conf" ]; then
        cp "$service_dir/acme.conf" "$NGINX_SETUP/$service_name.conf"
        echo "  ✓ acme.conf скопирован"
    fi

    local env_arg=()
    [ -f "$service_dir/.env" ] && env_arg=(--env-file "$service_dir/.env")

    if ! docker compose -f "$compose_file" "${env_arg[@]}" up -d --remove-orphans ; then
        rm -f "$NGINX_CONF/$service_name.conf"
        rm -f "$NGINX_SETUP/$service_name.conf"
        echo "Ошибка запуска '$service_name', конфиги откатаны"
        return 1
    fi

    reload_nginx
    echo "Сервис '$service_name' запущен"
}

cmd_stop() {
    local service_name="$1"
    local service_dir="$SERVS_DIR/$service_name"

    if [ ! -d "$service_dir" ]; then
        echo "Ошибка: сервис '$service_name' не найден в $SERVS_DIR"
        return 1
    fi

    if ! is_service_running "$service_name"; then
        echo "Сервис '$service_name' не запущен"
        return 0
    fi

    local compose_file
    compose_file=$(find_compose_file "$service_dir" "$service_name")

    echo "Останавливаю '$service_name'..."

    local env_arg=()
    [ -f "$service_dir/.env" ] && env_arg=(--env-file "$service_dir/.env")

    docker compose -f "$compose_file" "${env_arg[@]}" stop

    rm -f "$NGINX_CONF/$service_name.conf"
    echo "  ✓ nginx.conf удалён"

    rm -f "$NGINX_SETUP/$service_name.conf"
    echo "  ✓ acme.conf удалён"

    reload_nginx
    echo "Сервис '$service_name' остановлен"
}

cmd_down() {
    local service_name="$1"
    local service_dir="$SERVS_DIR/$service_name"

    if [ ! -d "$service_dir" ]; then
        echo "Ошибка: сервис '$service_name' не найден в $SERVS_DIR"
        return 1
    fi

    local compose_file
    compose_file=$(find_compose_file "$service_dir" "$service_name")

    if is_service_running "$service_name"; then
        echo "Удаляю контейнеры '$service_name'..."
    else
        echo "Сервис '$service_name' не запущен, выполняю down для очистки..."
    fi

    local env_arg=()
    [ -f "$service_dir/.env" ] && env_arg=(--env-file "$service_dir/.env")

    docker compose -f "$compose_file" "${env_arg[@]}" down --remove-orphans

    rm -f "$NGINX_CONF/$service_name.conf"
    echo "  ✓ nginx.conf удалён"

    rm -f "$NGINX_SETUP/$service_name.conf"
    echo "  ✓ acme.conf удалён"

    reload_nginx
    echo "Сервис '$service_name' удалён"
}

# ─── Обработка --all ─────────────────────────────────────────────────────────

run_for_all() {
    local cmd="$1"
    local services=()
    while IFS= read -r service; do
        services+=("$service")
    done < <(get_available_services)
    for service in "${services[@]}"; do
        "$cmd" "$service"
    done
}

# ─── Интерактивное меню ──────────────────────────────────────────────────────

menu_pick_service() {
    local prompt="$1"
    shift
    local services=("$@")

    if [ ${#services[@]} -eq 0 ]; then
        echo "Нет доступных сервисов" > /dev/tty
        return 1
    fi

    echo "" > /dev/tty
    for i in "${!services[@]}"; do
        echo "  $((i+1))) ${services[$i]}" > /dev/tty
    done
    echo "" > /dev/tty
    read -rp "$prompt: " choice < /dev/tty

    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#services[@]} ]; then
        echo "Неверный выбор" > /dev/tty
        return 1
    fi

    echo "${services[$((choice-1))]}"
}

menu_start() {
    local stopped=()
    while IFS= read -r service; do
        is_service_running "$service" || stopped+=("$service")
    done < <(get_available_services)

    local chosen
    chosen=$(menu_pick_service "Выберите сервис для запуска" "${stopped[@]}") || return
    cmd_start "$chosen"
}

menu_stop() {
    local running=()
    while IFS= read -r service; do
        is_service_running "$service" && running+=("$service")
    done < <(get_available_services)

    local chosen
    chosen=$(menu_pick_service "Выберите сервис для остановки" "${running[@]}") || return
    cmd_stop "$chosen"
}

menu_down() {
    local all=()
    while IFS= read -r service; do
        all+=("$service")
    done < <(get_available_services)

    local chosen
    chosen=$(menu_pick_service "Выберите сервис для down" "${all[@]}") || return
    cmd_down "$chosen"
}

show_menu() {
    while true; do
        echo ""
        echo "=== Cloud Service Manager ==="
        echo "  1) Доступные сервисы"
        echo "  2) Статус сервисов"
        echo "  3) Запустить сервис"
        echo "  4) Остановить сервис"
        echo "  5) Down сервис"
        echo "  6) Запустить nginx"
        echo "  7) Остановить nginx"
        echo "  8) Перезагрузить nginx"
        echo "  0) Выход"
        echo ""
        read -rp "Выберите действие: " choice

        case "$choice" in
            1) cmd_list ;;
            2) cmd_status ;;
            3) menu_start ;;
            4) menu_stop ;;
            5) menu_down ;;
            6) cmd_nginx start ;;
            7) cmd_nginx stop ;;
            8) cmd_nginx reload ;;
            0) exit 0 ;;
            *) echo "Неверный выбор" ;;
        esac
    done
}

# ─── Точка входа ─────────────────────────────────────────────────────────────

case "${1:-}" in
    start)
        shift
        if [ "${1:-}" = "--all" ]; then
            run_for_all cmd_start
        else
            for service in "$@"; do cmd_start "$service"; done
        fi
        ;;
    stop)
        shift
        if [ "${1:-}" = "--all" ]; then
            run_for_all cmd_stop
        else
            for service in "$@"; do cmd_stop "$service"; done
        fi
        ;;
    down)
        shift
        if [ "${1:-}" = "--all" ]; then
            run_for_all cmd_down
        else
            for service in "$@"; do cmd_down "$service"; done
        fi
        ;;
    nginx)  shift; cmd_nginx "$@" ;;
    status) cmd_status ;;
    list)   cmd_list ;;
    help)   cmd_help ;;
    "")     show_menu ;;
    *)
        echo "Неизвестная команда: '$1'"
        echo "Запустите '$(basename "$0") help' для справки."
        exit 1
        ;;
esac
