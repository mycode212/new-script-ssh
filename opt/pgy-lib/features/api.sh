#!/bin/bash
# ============================================================
# Auto Script SSH By : ProgoCloud
# Module: features/api.sh - ProgoCloud REST API Service Controller
# ============================================================

PGY_API_CONFIG_DIR="/etc/pgytunnel/db"
PGY_API_CONFIG_FILE="/etc/pgytunnel/db/api_config.conf"
PGY_API_SERVICE_FILE="/etc/systemd/system/pgy-api.service"
PGY_API_PYTHON_BIN="/usr/local/bin/pgy_api_service.py"

pgy_api_init_config() {
    mkdir -p "$PGY_API_CONFIG_DIR"
    if [[ ! -f "$PGY_API_CONFIG_FILE" ]]; then
        local initial_key
        initial_key="pgy_sec_$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 24)"
        cat > "$PGY_API_CONFIG_FILE" <<EOF
# ProgoCloud REST API Daemon Configuration
API_ENABLED=1
API_PORT=8780
API_KEY=${initial_key}
ALLOWED_IPS=ALL
RATE_LIMIT=60
EOF
        chmod 600 "$PGY_API_CONFIG_FILE"
    fi
}

pgy_api_get_config_val() {
    local key="$1" default_val="${2:-}"
    pgy_api_init_config
    local val
    val=$(grep "^${key}=" "$PGY_API_CONFIG_FILE" 2>/dev/null | cut -d'=' -f2- | tr -d '"'\'' ')
    echo "${val:-$default_val}"
}

pgy_api_set_config_val() {
    local key="$1" value="$2"
    pgy_api_init_config
    if grep -q "^${key}=" "$PGY_API_CONFIG_FILE" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${value}|" "$PGY_API_CONFIG_FILE"
    else
        echo "${key}=${value}" >> "$PGY_API_CONFIG_FILE"
    fi
}

pgy_api_install_service() {
    pgy_api_init_config

    local py_src=""
    if [[ -f "${PGY_SOURCE_DIR:-.}/pgy_api_service.py" && "${PGY_SOURCE_DIR:-.}/pgy_api_service.py" != "$PGY_API_PYTHON_BIN" ]]; then
        py_src="${PGY_SOURCE_DIR:-.}/pgy_api_service.py"
    elif [[ -f "/usr/local/lib/pgy-ssh-tunnel/pgy_api_service.py" && "/usr/local/lib/pgy-ssh-tunnel/pgy_api_service.py" != "$PGY_API_PYTHON_BIN" ]]; then
        py_src="/usr/local/lib/pgy-ssh-tunnel/pgy_api_service.py"
    elif [[ -f "/opt/pgy-lib/pgy_api_service.py" && "/opt/pgy-lib/pgy_api_service.py" != "$PGY_API_PYTHON_BIN" ]]; then
        py_src="/opt/pgy-lib/pgy_api_service.py"
    fi

    if [[ -n "$py_src" && -f "$py_src" ]]; then
        install -m 755 "$py_src" "$PGY_API_PYTHON_BIN" 2>/dev/null || true
    elif [[ -f "$PGY_API_PYTHON_BIN" ]]; then
        chmod 755 "$PGY_API_PYTHON_BIN" 2>/dev/null || true
    fi

    cat > "$PGY_API_SERVICE_FILE" <<EOF
[Unit]
Description=ProgoCloud REST API Daemon
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/pgytunnel
ExecStart=/usr/bin/python3 ${PGY_API_PYTHON_BIN}
Restart=always
RestartSec=3
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload 2>/dev/null || true
}

pgy_api_service_status() {
    if systemctl is-active --quiet pgy-api 2>/dev/null; then
        echo "active"
    elif systemctl is-enabled --quiet pgy-api 2>/dev/null; then
        echo "stopped"
    else
        echo "disabled"
    fi
}

pgy_api_start() {
    pgy_api_install_service
    systemctl enable pgy-api >/dev/null 2>&1 || true
    systemctl restart pgy-api >/dev/null 2>&1 || true
    pgy_api_set_config_val "API_ENABLED" "1"
}

pgy_api_stop() {
    systemctl stop pgy-api >/dev/null 2>&1 || true
    pgy_api_set_config_val "API_ENABLED" "0"
}

pgy_api_restart() {
    pgy_api_install_service
    systemctl restart pgy-api >/dev/null 2>&1 || true
}

pgy_api_regenerate_key() {
    local new_key
    new_key="pgy_sec_$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 24)"
    pgy_api_set_config_val "API_KEY" "$new_key"
    pgy_api_restart
    echo "$new_key"
}

pgy_api_set_port() {
    local new_port="$1"
    if [[ ! "$new_port" =~ ^[0-9]+$ ]] || (( new_port < 1024 || new_port > 65535 )); then
        return 1
    fi
    pgy_api_set_config_val "API_PORT" "$new_port"
    pgy_api_restart
    return 0
}

pgy_api_set_allowed_ips() {
    local ips="$1"
    [[ -z "$ips" ]] && ips="ALL"
    pgy_api_set_config_val "ALLOWED_IPS" "$ips"
    pgy_api_restart
}

pgy_api_test_local() {
    local port key
    port=$(pgy_api_get_config_val "API_PORT" "8780")
    key=$(pgy_api_get_config_val "API_KEY" "")
    
    local res
    res=$(curl -fsSL -H "X-API-Key: $key" --max-time 3 "http://127.0.0.1:${port}/api/v1/system/status" 2>/dev/null)
    if [[ -n "$res" ]] && [[ "$res" == *"\"success\": true"* || "$res" == *"\"success\":true"* ]]; then
        return 0
    fi
    return 1
}
