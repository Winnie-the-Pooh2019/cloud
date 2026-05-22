#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVS_DIR="$SCRIPT_DIR/servs"

[ -f "$SCRIPT_DIR/.env" ] && . "$SCRIPT_DIR/.env"

PROJECT_NAME="cloud"
START_BUILD=false
MODE="prod"   # prod | internal

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

get_nginx_network_name() {
    echo "${COMMON_NAME}_nginx-network"
}

ensure_nginx_network() {
    local net
    net=$(get_nginx_network_name)
    if ! docker network inspect "$net" >/dev/null 2>&1; then
        echo "  ⤴ создаю сеть '$net'..."
        docker network create "$net" >/dev/null
        echo "  ✓ сеть '$net' создана"
    fi
}

# ─── Режимо-зависимые функции ────────────────────────────────────────────────

get_nginx_conf_dir() {
    if [ "$MODE" = "internal" ]; then
        echo "$SCRIPT_DIR/nginx/internal/conf.d"
    else
        echo "$SCRIPT_DIR/nginx/prod/conf.d"
    fi
}

get_nginx_setup_dir() {
    echo "$SCRIPT_DIR/nginx/setup/conf.d"
}

get_root_compose() {
    if [ "$MODE" = "internal" ]; then
        echo "$SCRIPT_DIR/compose-internal.yaml"
    else
        echo "$SCRIPT_DIR/compose.yaml"
    fi
}

get_nginx_container() {
    if [ "$MODE" = "internal" ]; then
        echo "nginx-internal"
    else
        echo "nginx"
    fi
}

is_service_running() {
    local service_name="$1"
    [ -f "$(get_nginx_conf_dir)/$service_name.conf" ]
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
    local container
    container=$(get_nginx_container)
    docker compose -f "$(get_root_compose)" ps --status running --quiet "$container" 2>/dev/null | grep -q .
}

reload_nginx() {
    if is_nginx_running; then
        local container
        container=$(get_nginx_container)
        docker compose -f "$(get_root_compose)" exec -T "$container" nginx -s reload
        echo "  ✓ nginx перезагружен"
    else
        echo "  ⚠ nginx не запущен, пропускаю перезагрузку"
    fi
}

cmd_nginx() {
    local action="${1:-}"
    local root_compose
    root_compose=$(get_root_compose)
    local container
    container=$(get_nginx_container)
    case "$action" in
        start)
            ensure_nginx_network
            echo "Запускаю nginx..."
            docker compose -f "$root_compose" up -d
            echo "nginx запущен"
            ;;
        stop)
            echo "Останавливаю nginx..."
            docker compose -f "$root_compose" stop "$container"
            echo "nginx остановлен"
            ;;
        down)
            echo "Удаляю nginx..."
            docker compose -f "$root_compose" down
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
    echo "Управление сервисами (prod-режим, HTTPS + домен):"
    echo "  start <сервис...>              Запустить один или несколько сервисов"
    echo "  start --all                    Запустить все сервисы"
    echo "  start --build <сервис...>      Пересобрать образы и запустить"
    echo "  start --build --all            Пересобрать образы и запустить все"
    echo "  stop  <сервис...>              Остановить один или несколько сервисов"
    echo "  stop  --all                    Остановить все сервисы"
    echo "  down  <сервис...>              Остановить и удалить контейнеры сервиса"
    echo "  down  --all                    Остановить и удалить все сервисы"
    echo ""
    echo "Internal-режим (HTTP, без SSL, path-роутинг по одному IP):"
    echo "  internal start [--build] <сервис...>   Запустить в internal-режиме"
    echo "  internal start [--build] --all         Запустить все"
    echo "  internal stop  <сервис...>             Остановить"
    echo "  internal down  <сервис...>             Удалить контейнеры"
    echo "  internal nginx start|stop|down|reload  Управление internal nginx"
    echo "  internal status                        Статус сервисов в internal"
    echo "  internal list                          Список сервисов"
    echo "  Конфиги сервиса: servs/<name>/internal/nginx.conf и internal/.env"
    echo ""
    echo "Управление nginx (prod):"
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
    echo "Без аргументов запускается интерактивное меню (prod-режим)."
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
    local mode_label="prod"
    [ "$MODE" = "internal" ] && mode_label="internal"
    echo ""
    echo "Статус сервисов [$mode_label]:"
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

    ensure_nginx_network

    # Выбор nginx-конфига: internal/ имеет приоритет в internal-режиме
    local nginx_src="$service_dir/nginx.conf"
    local env_src="$service_dir/.env"
    if [ "$MODE" = "internal" ]; then
        [ -f "$service_dir/internal/nginx.conf" ] && nginx_src="$service_dir/internal/nginx.conf"
        [ -f "$service_dir/internal/.env" ] && env_src="$service_dir/internal/.env"
    fi

    local nginx_conf_dir
    nginx_conf_dir=$(get_nginx_conf_dir)

    if [ -f "$nginx_src" ]; then
        cp "$nginx_src" "$nginx_conf_dir/$service_name.conf"
        echo "  ✓ nginx.conf скопирован"
    fi

    # acme.conf — только в prod-режиме
    if [ "$MODE" = "prod" ] && [ -f "$service_dir/acme.conf" ]; then
        cp "$service_dir/acme.conf" "$(get_nginx_setup_dir)/$service_name.conf"
        echo "  ✓ acme.conf скопирован"
    fi

    local env_arg=()
    [ -f "$env_src" ] && env_arg=(--env-file "$env_src")

    local up_args=(-d --remove-orphans)
    [ "$START_BUILD" = true ] && up_args+=(--build)

    if ! docker compose -f "$compose_file" "${env_arg[@]}" up "${up_args[@]}"; then
        rm -f "$nginx_conf_dir/$service_name.conf"
        rm -f "$(get_nginx_setup_dir)/$service_name.conf"
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

    local env_src="$service_dir/.env"
    [ "$MODE" = "internal" ] && [ -f "$service_dir/internal/.env" ] && env_src="$service_dir/internal/.env"

    local env_arg=()
    [ -f "$env_src" ] && env_arg=(--env-file "$env_src")

    docker compose -f "$compose_file" "${env_arg[@]}" stop

    local nginx_conf_dir
    nginx_conf_dir=$(get_nginx_conf_dir)
    rm -f "$nginx_conf_dir/$service_name.conf"
    echo "  ✓ nginx.conf удалён"

    if [ "$MODE" = "prod" ]; then
        rm -f "$(get_nginx_setup_dir)/$service_name.conf"
        echo "  ✓ acme.conf удалён"
    fi

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

    local env_src="$service_dir/.env"
    [ "$MODE" = "internal" ] && [ -f "$service_dir/internal/.env" ] && env_src="$service_dir/internal/.env"

    local env_arg=()
    [ -f "$env_src" ] && env_arg=(--env-file "$env_src")

    docker compose -f "$compose_file" "${env_arg[@]}" down --remove-orphans

    local nginx_conf_dir
    nginx_conf_dir=$(get_nginx_conf_dir)
    rm -f "$nginx_conf_dir/$service_name.conf"
    echo "  ✓ nginx.conf удалён"

    if [ "$MODE" = "prod" ]; then
        rm -f "$(get_nginx_setup_dir)/$service_name.conf"
        echo "  ✓ acme.conf удалён"
    fi

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

# ─── Интерактивное меню (prod) ───────────────────────────────────────────────

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

menu_start_build() {
    START_BUILD=true
    menu_start
    START_BUILD=false
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
        echo "  4) Запустить сервис (с пересборкой)"
        echo "  5) Остановить сервис"
        echo "  6) Down сервис"
        echo "  7) Запустить nginx"
        echo "  8) Остановить nginx"
        echo "  9) Перезагрузить nginx"
        echo "  0) Выход"
        echo ""
        read -rp "Выберите действие: " choice

        case "$choice" in
            1) cmd_list ;;
            2) cmd_status ;;
            3) menu_start ;;
            4) menu_start_build ;;
            5) menu_stop ;;
            6) menu_down ;;
            7) cmd_nginx start ;;
            8) cmd_nginx stop ;;
            9) cmd_nginx reload ;;
            0) exit 0 ;;
            *) echo "Неверный выбор" ;;
        esac
    done
}

# ─── Точка входа ─────────────────────────────────────────────────────────────

case "${1:-}" in
    start)
        shift
        args=()
        for arg in "$@"; do
            if [ "$arg" = "--build" ]; then
                START_BUILD=true
            else
                args+=("$arg")
            fi
        done
        set -- "${args[@]}"

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
    internal)
        shift
        MODE="internal"
        case "${1:-}" in
            start)
                shift
                args=()
                for arg in "$@"; do
                    if [ "$arg" = "--build" ]; then
                        START_BUILD=true
                    else
                        args+=("$arg")
                    fi
                done
                set -- "${args[@]}"

                if [ "${1:-}" = "--all" ]; then
                    run_for_all cmd_start
                else
                    for s in "$@"; do cmd_start "$s"; done
                fi
                ;;
            stop)
                shift
                if [ "${1:-}" = "--all" ]; then run_for_all cmd_stop
                else for s in "$@"; do cmd_stop "$s"; done; fi
                ;;
            down)
                shift
                if [ "${1:-}" = "--all" ]; then run_for_all cmd_down
                else for s in "$@"; do cmd_down "$s"; done; fi
                ;;
            nginx)  shift; cmd_nginx "$@" ;;
            status) cmd_status ;;
            list)   cmd_list ;;
            "")
                echo "Использование: $0 internal {start|stop|down|nginx|status|list} ..."
                echo "Запустите '$(basename "$0") help' для справки."
                exit 1
                ;;
            *)
                echo "Неизвестная подкоманда: '$1'"
                echo "Использование: $0 internal {start|stop|down|nginx|status|list} ..."
                exit 1
                ;;
        esac
        ;;
    "")     show_menu ;;
    *)
        echo "Неизвестная команда: '$1'"
        echo "Запустите '$(basename "$0") help' для справки."
        exit 1
        ;;
esac
