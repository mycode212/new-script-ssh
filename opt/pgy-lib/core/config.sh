#!/bin/bash
# ============================================================
# Auto Script SSH By : ProgoCloud
# Module: core/config.sh - Global configuration paths and ports
# ============================================================

PGY_HEADER_BRAND="Auto Script SSH By : ProgoCloud"
PGY_VERSION_TAG="v2.1.0 ProgoCloud Edition"

DB_DIR="/etc/pgytunnel"
DB_FILE="$DB_DIR/users.db"
PGY_MENU_BINARY="${PGY_MENU_BINARY:-/usr/local/bin/menu}"
TDZ_MENU_BINARY="${TDZ_MENU_BINARY:-$PGY_MENU_BINARY}"
MANUAL_LOCK_FILE="$DB_DIR/manual-locks.db"
MANUAL_LOCK_MUTEX="$DB_DIR/.manual-locks.lock"
INSTALL_FLAG_FILE="$DB_DIR/.install"

BADVPN_SERVICE_FILE="/etc/systemd/system/badvpn.service"
BADVPN_BUILD_DIR="/root/badvpn-build"
HAPROXY_CONFIG="/etc/haproxy/haproxy.cfg"
NGINX_CONFIG_FILE="/etc/nginx/sites-available/default"

SSL_CERT_DIR="/etc/pgytunnel/ssl"
PGY_SSL_CERT_FILE="$SSL_CERT_DIR/pgytunnel.pem"
TDZ_SSL_CERT_FILE="$PGY_SSL_CERT_FILE"
SSL_CERT_CHAIN_FILE="$SSL_CERT_DIR/pgytunnel.crt"
SSL_CERT_KEY_FILE="$SSL_CERT_DIR/pgytunnel.key"

EDGE_CERT_INFO_FILE="$DB_DIR/edge_cert.conf"
NGINX_PORTS_FILE="$DB_DIR/nginx_ports.conf"
EDGE_PORT_SETTINGS_FILE="$DB_DIR/edge_ports.conf"

DEFAULT_EDGE_PUBLIC_HTTP_PORT="2080"
DEFAULT_EDGE_PUBLIC_TLS_PORT="442"
EDGE_PUBLIC_HTTP_PORT="$DEFAULT_EDGE_PUBLIC_HTTP_PORT"
EDGE_PUBLIC_TLS_PORT="$DEFAULT_EDGE_PUBLIC_TLS_PORT"
NGINX_INTERNAL_HTTP_PORT="8770"
NGINX_INTERNAL_TLS_PORT="8771"
HAPROXY_INTERNAL_DECRYPT_PORT="10443"

# WebSocket-to-SSH bridge
WS_SSH_BRIDGE_SCRIPT="/usr/local/bin/pgy-ws-ssh-bridge.py"
WS_SSH_BRIDGE_SERVICE="/etc/systemd/system/pgy-ws-ssh-bridge.service"
WS_SSH_BRIDGE_PORT="8890"

SSH_BANNER_FILE="/etc/pgytunnel/bannerssh"
BANNER_IDENTITY_CONF="$DB_DIR/banner_identity.conf"
DEFAULT_BANNER_ADMIN_USERNAME="ProgoCloud"
DEFAULT_BANNER_CHANNEL_USERNAME="progocloud"

DNSTT_SERVICE_FILE="/etc/systemd/system/dnstt.service"
DNSTT_BINARY="/usr/local/bin/dnstt-server"
DNSTT_KEYS_DIR="/etc/pgytunnel/dnstt"
DNSTT_CONFIG_FILE="$DB_DIR/dnstt_info.conf"
DNSTT_RESOLVER_STATE_FILE="$DNSTT_KEYS_DIR/resolver.state"
DNSTT_RESOLV_BACKUP="$DNSTT_KEYS_DIR/resolv.conf.before"
PGY_RESOLV_CONF="${PGY_RESOLV_CONF:-/etc/resolv.conf}"
TDZ_RESOLV_CONF="${TDZ_RESOLV_CONF:-$PGY_RESOLV_CONF}"
PGY_RESOLVED_STUB="${PGY_RESOLVED_STUB:-/run/systemd/resolve/stub-resolv.conf}"
TDZ_RESOLVED_STUB="${TDZ_RESOLVED_STUB:-$PGY_RESOLVED_STUB}"

# Legacy paths
LEGACY_UDP_DIR="${LEGACY_UDP_DIR:-/root/udp}"
LEGACY_UDP_SERVICE="${LEGACY_UDP_SERVICE:-/etc/systemd/system/udp-custom.service}"
LEGACY_UDPGW_BINARY="${LEGACY_UDPGW_BINARY:-/usr/local/bin/udpgw}"
LEGACY_UDPGW_SERVICE="${LEGACY_UDPGW_SERVICE:-/etc/systemd/system/udpgw.service}"
LEGACY_PROXY_BINARY="${LEGACY_PROXY_BINARY:-/usr/local/bin/pgyproxy}"
LEGACY_PROXY_SERVICE="${LEGACY_PROXY_SERVICE:-/etc/systemd/system/pgyproxy.service}"
LEGACY_PROXY_CONFIG="${LEGACY_PROXY_CONFIG:-$DB_DIR/pgyproxy_config.conf}"

LIMITER_SCRIPT="/usr/local/bin/pgytunnel-limiter.sh"
LIMITER_SERVICE="/etc/systemd/system/pgytunnel-limiter.service"
BANDWIDTH_DIR="$DB_DIR/bandwidth"
BANDWIDTH_SCRIPT="/usr/local/bin/pgytunnel-bandwidth.sh"
BANDWIDTH_SERVICE="/etc/systemd/system/pgytunnel-bandwidth.service"
LEGACY_BANDWIDTH_DIR="/usr/local/bin/pgytunnel-bandwidth"
TRIAL_CLEANUP_SCRIPT="/usr/local/bin/pgytunnel-trial-cleanup.sh"
LOGIN_INFO_SCRIPT="/usr/local/bin/pgytunnel-login-info.sh"
SSHD_PGY_CONFIG="/etc/ssh/sshd_config.d/pgytunnel.conf"
SSHD_TDZ_CONFIG="$SSHD_PGY_CONFIG"

AUTO_BACKUP_CONF="/etc/pgytunnel-auto-backup-bot.conf"
AUTO_BACKUP_SCRIPT="/usr/local/bin/pgytunnel-auto-backup-bot.sh"
AUTO_BACKUP_DIR="/root/pgytunnel-auto-backups"
AUTO_BACKUP_LOG="/var/log/pgytunnel-auto-backup.log"
AUTO_BACKUP_LAST_FILE="$AUTO_BACKUP_DIR/last-backup.tar.gz"
AUTO_BACKUP_PM2_NAME="pgy-auto-backup-bot"
AUTO_REBOOT_CRON_TAG="# pgytunnel-managed-auto-reboot"

PGY_PACKAGE_LOG="${PGY_PACKAGE_LOG:-/var/log/pgy-package-setup.log}"
TDZ_PACKAGE_LOG="$PGY_PACKAGE_LOG"
PGY_CERTIFICATE_LOG="${PGY_CERTIFICATE_LOG:-/var/log/pgy-certificate-setup.log}"
TDZ_CERTIFICATE_LOG="$PGY_CERTIFICATE_LOG"
PGY_SERVICE_LOG="${PGY_SERVICE_LOG:-/var/log/pgy-service-setup.log}"
TDZ_SERVICE_LOG="$PGY_SERVICE_LOG"
PGY_UNINSTALL_LOG="${PGY_UNINSTALL_LOG:-/var/log/pgy-uninstall.log}"
TDZ_UNINSTALL_LOG="$PGY_UNINSTALL_LOG"

FIREWALL_STATE_FILE="$DB_DIR/firewall-rules.db"
PGY_LIB_DIR="/usr/local/lib/pgy-ssh-tunnel"
TDZ_LIB_DIR="$PGY_LIB_DIR"
PGY_OPT_LIB_DIR="/pgy-lib/opt"
SSH_AUTH_SESSION_HELPER="$PGY_LIB_DIR/pgy_ssh_auth_session.py"
SSH_AUTH_SESSION_DIR="/run/pgytunnel/ssh-auth-sessions"
SSH_PAM_CONFIG="/etc/pam.d/sshd"
SSH_PAM_HOOK_BEGIN="# Auto Script SSH By : ProgoCloud post-auth session banner - begin"
SSH_PAM_HOOK_END="# Auto Script SSH By : ProgoCloud post-auth session banner - end"
SSH_PAM_AUTH_GUARD_BEGIN="# Auto Script SSH By : ProgoCloud denied-account retry guard - begin"
SSH_PAM_AUTH_GUARD_END="# Auto Script SSH By : ProgoCloud denied-account retry guard - end"

# License config
PGY_LICENSE_STATE_DIR="/var/lib/pgy-license"
PGY_LICENSE_STATE_FILE="$PGY_LICENSE_STATE_DIR/state.json"
PGY_LICENSE_CACHE_FILE="$PGY_LICENSE_STATE_DIR/cache.json"
PGY_LICENSE_DEFAULT_API_URL="https://autoscript-license.worker-balancer-mang.workers.dev/api/v1/license/check"
PGY_LICENSE_BIN="/usr/local/bin/pgy-license-check"

# Helper check ports
pgy_is_valid_port_number() {
    local port="$1"
    [[ "$port" =~ ^[0-9]+$ ]] && (( port >= 1 && port <= 65535 ))
}
tdz_is_valid_port_number() { pgy_is_valid_port_number "$@"; }

pgy_is_reserved_edge_port() {
    local port="$1"
    case "$port" in
        22|"$NGINX_INTERNAL_HTTP_PORT"|"$NGINX_INTERNAL_TLS_PORT"|"$HAPROXY_INTERNAL_DECRYPT_PORT"|"$WS_SSH_BRIDGE_PORT") return 0 ;;
        *) return 1 ;;
    esac
}
tdz_is_reserved_edge_port() { pgy_is_reserved_edge_port "$@"; }

load_edge_port_settings() {
    local saved_http="" saved_tls=""
    [[ -r "$EDGE_PORT_SETTINGS_FILE" ]] || return 0
    saved_http=$(awk -F= '$1 == "EDGE_PUBLIC_HTTP_PORT" {print $2}' "$EDGE_PORT_SETTINGS_FILE" 2>/dev/null | tail -n 1 | tr -d '\r')
    saved_tls=$(awk -F= '$1 == "EDGE_PUBLIC_TLS_PORT" {print $2}' "$EDGE_PORT_SETTINGS_FILE" 2>/dev/null | tail -n 1 | tr -d '\r')

    if pgy_is_valid_port_number "$saved_http" &&
       pgy_is_valid_port_number "$saved_tls" &&
       ! pgy_is_reserved_edge_port "$saved_http" &&
       ! pgy_is_reserved_edge_port "$saved_tls" &&
       [[ "$saved_http" != "$saved_tls" ]]; then
        EDGE_PUBLIC_HTTP_PORT="$saved_http"
        EDGE_PUBLIC_TLS_PORT="$saved_tls"
    fi
}

save_edge_port_settings() {
    mkdir -p "$DB_DIR"
    {
        echo "EDGE_PUBLIC_HTTP_PORT=$EDGE_PUBLIC_HTTP_PORT"
        echo "EDGE_PUBLIC_TLS_PORT=$EDGE_PUBLIC_TLS_PORT"
    } > "$EDGE_PORT_SETTINGS_FILE"
}
