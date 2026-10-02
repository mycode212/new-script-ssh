#!/bin/bash
# ============================================================
# Auto Script SSH By : ProgoCloud
# Module: features/cftunnel.sh - Cloudflare Tunnel (cloudflared) Controller
# ============================================================

PGY_CFTUNNEL_BIN="/usr/local/bin/cloudflared"
PGY_CFTUNNEL_CONFIG_FILE="/etc/pgytunnel/cf_tunnel.conf"
PGY_CFTUNNEL_SERVICE_NAME="cloudflared"

pgy_cftunnel_arch() {
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64|amd64) echo "amd64" ;;
        aarch64|arm64) echo "arm64" ;;
        armv7l|armhf) echo "arm" ;;
        i386|i686) echo "386" ;;
        *) echo "amd64" ;;
    esac
}

pgy_cftunnel_init_config() {
    mkdir -p "/etc/pgytunnel"
    if [[ ! -f "$PGY_CFTUNNEL_CONFIG_FILE" ]]; then
        cat > "$PGY_CFTUNNEL_CONFIG_FILE" <<EOF
# Cloudflare Tunnel Configuration
CF_TUNNEL_ENABLED=0
CF_TUNNEL_TOKEN=
CF_TUNNEL_VPN_DOMAIN=
CF_TUNNEL_API_DOMAIN=
EOF
        chmod 600 "$PGY_CFTUNNEL_CONFIG_FILE"
    fi
}

pgy_cftunnel_get_config_val() {
    local key="$1" default_val="${2:-}"
    pgy_cftunnel_init_config
    local val
    val=$(grep "^${key}=" "$PGY_CFTUNNEL_CONFIG_FILE" 2>/dev/null | cut -d'=' -f2- | tr -d '"'\'' ')
    echo "${val:-$default_val}"
}

pgy_cftunnel_set_config_val() {
    local key="$1" value="$2"
    pgy_cftunnel_init_config
    if grep -q "^${key}=" "$PGY_CFTUNNEL_CONFIG_FILE" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${value}|" "$PGY_CFTUNNEL_CONFIG_FILE"
    else
        echo "${key}=${value}" >> "$PGY_CFTUNNEL_CONFIG_FILE"
    fi
}

pgy_cftunnel_ensure_binary() {
    if [[ -x "$PGY_CFTUNNEL_BIN" ]]; then
        return 0
    fi
    if command -v cloudflared >/dev/null 2>&1; then
        PGY_CFTUNNEL_BIN="$(command -v cloudflared)"
        return 0
    fi

    local arch url tmp_bin="/tmp/cloudflared_download"
    arch=$(pgy_cftunnel_arch)
    url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${arch}"

    if curl -fsSL --connect-timeout 10 --max-time 60 "$url" -o "$tmp_bin" 2>/dev/null; then
        install -m 755 "$tmp_bin" "$PGY_CFTUNNEL_BIN" 2>/dev/null || true
        rm -f "$tmp_bin"
        return 0
    fi

    # Fallback to deb package
    local deb_url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${arch}.deb"
    if curl -fsSL --connect-timeout 10 --max-time 60 "$deb_url" -o "/tmp/cloudflared.deb" 2>/dev/null; then
        dpkg -i "/tmp/cloudflared.deb" >/dev/null 2>&1 || true
        rm -f "/tmp/cloudflared.deb"
        if command -v cloudflared >/dev/null 2>&1; then
            return 0
        fi
    fi

    return 1
}

pgy_cftunnel_service_status() {
    if systemctl is-active --quiet "$PGY_CFTUNNEL_SERVICE_NAME" 2>/dev/null; then
        echo "active"
    elif systemctl is-enabled --quiet "$PGY_CFTUNNEL_SERVICE_NAME" 2>/dev/null; then
        echo "stopped"
    else
        echo "disabled"
    fi
}

pgy_cftunnel_install_service_token() {
    local token="$1"
    [[ -z "$token" ]] && return 1

    pgy_cftunnel_ensure_binary || return 1
    pgy_cftunnel_init_config

    # Stop old service if exists
    systemctl stop "$PGY_CFTUNNEL_SERVICE_NAME" >/dev/null 2>&1 || true
    "$PGY_CFTUNNEL_BIN" service uninstall >/dev/null 2>&1 || true

    # Install systemd service with token
    if "$PGY_CFTUNNEL_BIN" service install "$token" >/dev/null 2>&1; then
        systemctl daemon-reload >/dev/null 2>&1 || true
        systemctl enable "$PGY_CFTUNNEL_SERVICE_NAME" >/dev/null 2>&1 || true
        systemctl restart "$PGY_CFTUNNEL_SERVICE_NAME" >/dev/null 2>&1 || true
        pgy_cftunnel_set_config_val "CF_TUNNEL_ENABLED" "1"
        pgy_cftunnel_set_config_val "CF_TUNNEL_TOKEN" "$token"
        return 0
    fi
    return 1
}

pgy_cftunnel_start() {
    pgy_cftunnel_ensure_binary || return 1
    systemctl enable "$PGY_CFTUNNEL_SERVICE_NAME" >/dev/null 2>&1 || true
    systemctl restart "$PGY_CFTUNNEL_SERVICE_NAME" >/dev/null 2>&1 || true
    pgy_cftunnel_set_config_val "CF_TUNNEL_ENABLED" "1"
}

pgy_cftunnel_stop() {
    systemctl stop "$PGY_CFTUNNEL_SERVICE_NAME" >/dev/null 2>&1 || true
    pgy_cftunnel_set_config_val "CF_TUNNEL_ENABLED" "0"
}

pgy_cftunnel_restart() {
    systemctl restart "$PGY_CFTUNNEL_SERVICE_NAME" >/dev/null 2>&1 || true
}

pgy_cftunnel_uninstall() {
    systemctl stop "$PGY_CFTUNNEL_SERVICE_NAME" >/dev/null 2>&1 || true
    if command -v cloudflared >/dev/null 2>&1; then
        cloudflared service uninstall >/dev/null 2>&1 || true
    elif [[ -x "$PGY_CFTUNNEL_BIN" ]]; then
        "$PGY_CFTUNNEL_BIN" service uninstall >/dev/null 2>&1 || true
    fi
    rm -f "$PGY_CFTUNNEL_BIN" "$PGY_CFTUNNEL_CONFIG_FILE"
    rm -f "/etc/systemd/system/cloudflared.service"
    systemctl daemon-reload >/dev/null 2>&1 || true
}
