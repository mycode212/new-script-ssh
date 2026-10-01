#!/bin/bash
# ============================================================
# Auto Script SSH By : ProgoCloud
# Module: features/adblock.sh - Server-Side DNS Adblocker
# ============================================================

ADBLOCK_DIR="/etc/pgy-adblock"
ADBLOCK_CONF_DIR="/etc/dnsmasq.d"
ADBLOCK_CONF="${ADBLOCK_CONF_DIR}/pgy-adblock.conf"
ADBLOCK_CUSTOM_BLACK="${ADBLOCK_DIR}/custom_blacklist.txt"
ADBLOCK_CUSTOM_WHITE="${ADBLOCK_DIR}/custom_whitelist.txt"
ADBLOCK_PORT=5353

_pgy_adblock_apt_install() {
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y >/dev/null 2>&1 || true
    apt-get install -y --no-install-recommends dnsmasq >/dev/null 2>&1 || true
}

pgy_adblock_install_prereq() {
    if ! command -v dnsmasq >/dev/null 2>&1; then
        if declare -F run_step_with_spinner >/dev/null 2>&1; then
            run_step_with_spinner "Menginstal paket dnsmasq" _pgy_adblock_apt_install
        else
            echo -e "${C_INFO}  Menginstal paket dnsmasq...${C_RESET}"
            _pgy_adblock_apt_install
        fi
    fi
    mkdir -p "$ADBLOCK_DIR" "$ADBLOCK_CONF_DIR"
    touch "$ADBLOCK_CUSTOM_BLACK" "$ADBLOCK_CUSTOM_WHITE"
}

_pgy_adblock_download_and_compile() {
    local tmp_rules="/tmp/pgy-adblock-rules.$$"
    local source_url="https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts"
    curl -fsSL --connect-timeout 10 --max-time 60 "$source_url" -o "$tmp_rules" 2>/dev/null || {
        cat <<EOF > "$tmp_rules"
0.0.0.0 doubleclick.net
0.0.0.0 googleads.g.doubleclick.net
0.0.0.0 pagead2.googlesyndication.com
0.0.0.0 adservice.google.com
0.0.0.0 ads.pubmatic.com
EOF
    }

    cat <<EOF > "$ADBLOCK_CONF"
# ProgoCloud Server-Side Adblock DNS Resolver
port=${ADBLOCK_PORT}
listen-address=127.0.0.1
bind-interfaces
server=1.1.1.1
server=8.8.8.8
no-resolv
log-async

EOF

    grep -E '^0\.0\.0\.0 ' "$tmp_rules" | awk '{print "address=/"$2"/0.0.0.0"}' >> "$ADBLOCK_CONF" 2>/dev/null || true
    rm -f "$tmp_rules"

    if [[ -s "$ADBLOCK_CUSTOM_BLACK" ]]; then
        while IFS= read -r domain; do
            [[ -n "$domain" && ! "$domain" =~ ^# ]] && echo "address=/${domain}/0.0.0.0" >> "$ADBLOCK_CONF"
        done < "$ADBLOCK_CUSTOM_BLACK"
    fi

    if [[ -s "$ADBLOCK_CUSTOM_WHITE" ]]; then
        while IFS= read -r domain; do
            [[ -n "$domain" && ! "$domain" =~ ^# ]] && sed -i "\|address=/${domain}/0.0.0.0|d" "$ADBLOCK_CONF" 2>/dev/null || true
        done < "$ADBLOCK_CUSTOM_WHITE"
    fi
}

pgy_adblock_update_rules() {
    pgy_adblock_install_prereq
    if declare -F run_step_with_spinner >/dev/null 2>&1; then
        run_step_with_spinner "Mengunduh & menyusun database Adblocker" _pgy_adblock_download_and_compile
    else
        echo -e "${C_INFO}  Mengunduh database domain iklan & tracker terbaru...${C_RESET}"
        _pgy_adblock_download_and_compile
    fi

    if pgy_adblock_is_active; then
        systemctl restart dnsmasq >/dev/null 2>&1 || true
    fi
    if declare -F pgy_xray_sync_users_to_config >/dev/null 2>&1; then
        pgy_xray_sync_users_to_config >/dev/null 2>&1 || true
    fi
    echo -e "${C_GREEN}  Database Adblocker berhasil diperbarui (dnsmasq & XRay).${C_RESET}"
}

pgy_adblock_is_active() {
    systemctl is-active --quiet dnsmasq 2>/dev/null && [[ -f "$ADBLOCK_CONF" ]]
}

pgy_adblock_get_status() {
    if pgy_adblock_is_active; then
        local count=0
        count=$(grep -c '^address=' "$ADBLOCK_CONF" 2>/dev/null || echo 0)
        echo "Active (${count} domain terblokir)"
    else
        echo "Inactive"
    fi
}

pgy_adblock_apply_firewall() {
    # 1. Redirect inbound DNS queries from tun interfaces (OpenVPN / BadVPN / Tunnels)
    iptables -t nat -C PREROUTING -p udp --dport 53 -j REDIRECT --to-ports ${ADBLOCK_PORT} 2>/dev/null || \
        iptables -t nat -A PREROUTING -p udp --dport 53 -j REDIRECT --to-ports ${ADBLOCK_PORT} 2>/dev/null || true
    iptables -t nat -C PREROUTING -p tcp --dport 53 -j REDIRECT --to-ports ${ADBLOCK_PORT} 2>/dev/null || \
        iptables -t nat -A PREROUTING -p tcp --dport 53 -j REDIRECT --to-ports ${ADBLOCK_PORT} 2>/dev/null || true

    # 2. Redirect outbound DNS queries from SSH tunnel users (Group & UID-based)
    for grp in pgyusers tdzusers; do
        if getent group "$grp" >/dev/null 2>&1; then
            iptables -t nat -C OUTPUT -p udp --dport 53 -m owner --gid-owner "$grp" -j REDIRECT --to-ports ${ADBLOCK_PORT} 2>/dev/null || \
                iptables -t nat -A OUTPUT -p udp --dport 53 -m owner --gid-owner "$grp" -j REDIRECT --to-ports ${ADBLOCK_PORT} 2>/dev/null || true
            iptables -t nat -C OUTPUT -p tcp --dport 53 -m owner --gid-owner "$grp" -j REDIRECT --to-ports ${ADBLOCK_PORT} 2>/dev/null || \
                iptables -t nat -A OUTPUT -p tcp --dport 53 -m owner --gid-owner "$grp" -j REDIRECT --to-ports ${ADBLOCK_PORT} 2>/dev/null || true
        fi
    done

    local db_path="${DB_FILE:-/etc/pgytunnel/users.db}"
    if [[ -s "$db_path" ]]; then
        while IFS=: read -r u_name _rest; do
            [[ -z "$u_name" || "$u_name" =~ ^# ]] && continue
            local u_uid
            u_uid=$(id -u "$u_name" 2>/dev/null || true)
            if [[ -n "$u_uid" && "$u_uid" =~ ^[0-9]+$ ]]; then
                iptables -t nat -C OUTPUT -p udp --dport 53 -m owner --uid-owner "$u_uid" -j REDIRECT --to-ports ${ADBLOCK_PORT} 2>/dev/null || \
                    iptables -t nat -A OUTPUT -p udp --dport 53 -m owner --uid-owner "$u_uid" -j REDIRECT --to-ports ${ADBLOCK_PORT} 2>/dev/null || true
                iptables -t nat -C OUTPUT -p tcp --dport 53 -m owner --uid-owner "$u_uid" -j REDIRECT --to-ports ${ADBLOCK_PORT} 2>/dev/null || \
                    iptables -t nat -A OUTPUT -p tcp --dport 53 -m owner --uid-owner "$u_uid" -j REDIRECT --to-ports ${ADBLOCK_PORT} 2>/dev/null || true
            fi
        done < "$db_path"
    fi
}

pgy_adblock_remove_firewall() {
    iptables -t nat -D PREROUTING -p udp --dport 53 -j REDIRECT --to-ports ${ADBLOCK_PORT} 2>/dev/null || true
    iptables -t nat -D PREROUTING -p tcp --dport 53 -j REDIRECT --to-ports ${ADBLOCK_PORT} 2>/dev/null || true

    for grp in pgyusers tdzusers; do
        if getent group "$grp" >/dev/null 2>&1; then
            iptables -t nat -D OUTPUT -p udp --dport 53 -m owner --gid-owner "$grp" -j REDIRECT --to-ports ${ADBLOCK_PORT} 2>/dev/null || true
            iptables -t nat -D OUTPUT -p tcp --dport 53 -m owner --gid-owner "$grp" -j REDIRECT --to-ports ${ADBLOCK_PORT} 2>/dev/null || true
        fi
    done

    local db_path="${DB_FILE:-/etc/pgytunnel/users.db}"
    if [[ -s "$db_path" ]]; then
        while IFS=: read -r u_name _rest; do
            [[ -z "$u_name" || "$u_name" =~ ^# ]] && continue
            local u_uid
            u_uid=$(id -u "$u_name" 2>/dev/null || true)
            if [[ -n "$u_uid" && "$u_uid" =~ ^[0-9]+$ ]]; then
                iptables -t nat -D OUTPUT -p udp --dport 53 -m owner --uid-owner "$u_uid" -j REDIRECT --to-ports ${ADBLOCK_PORT} 2>/dev/null || true
                iptables -t nat -D OUTPUT -p tcp --dport 53 -m owner --uid-owner "$u_uid" -j REDIRECT --to-ports ${ADBLOCK_PORT} 2>/dev/null || true
            fi
        done < "$db_path"
    fi
}

pgy_adblock_toggle() {
    if pgy_adblock_is_active; then
        pgy_adblock_remove_firewall
        rm -f "$ADBLOCK_CONF"
        systemctl restart dnsmasq >/dev/null 2>&1 || true
        echo -e "${C_WARN}  DNS Adblocker telah Dinonaktifkan (XRay & SSH).${C_RESET}"
    else
        pgy_adblock_update_rules
        systemctl enable dnsmasq >/dev/null 2>&1 || true
        systemctl restart dnsmasq >/dev/null 2>&1 || true
        pgy_adblock_apply_firewall
        echo -e "${C_GREEN}  DNS Adblocker telah Diaktifkan untuk XRay & SSH pada port ${ADBLOCK_PORT}.${C_RESET}"
    fi
}

pgy_adblock_add_blacklist() {
    local domain="$1"
    [[ -z "$domain" ]] && return 1
    mkdir -p "$ADBLOCK_DIR"
    echo "$domain" >> "$ADBLOCK_CUSTOM_BLACK"
    sort -u -o "$ADBLOCK_CUSTOM_BLACK" "$ADBLOCK_CUSTOM_BLACK"
    pgy_adblock_update_rules
}

pgy_adblock_del_blacklist() {
    local domain="$1"
    [[ -z "$domain" || ! -f "$ADBLOCK_CUSTOM_BLACK" ]] && return 1
    sed -i "\|^${domain}$|d" "$ADBLOCK_CUSTOM_BLACK" 2>/dev/null || true
    pgy_adblock_update_rules
}

pgy_adblock_add_whitelist() {
    local domain="$1"
    [[ -z "$domain" ]] && return 1
    mkdir -p "$ADBLOCK_DIR"
    echo "$domain" >> "$ADBLOCK_CUSTOM_WHITE"
    sort -u -o "$ADBLOCK_CUSTOM_WHITE" "$ADBLOCK_CUSTOM_WHITE"
    pgy_adblock_update_rules
}

pgy_adblock_del_whitelist() {
    local domain="$1"
    [[ -z "$domain" || ! -f "$ADBLOCK_CUSTOM_WHITE" ]] && return 1
    sed -i "\|^${domain}$|d" "$ADBLOCK_CUSTOM_WHITE" 2>/dev/null || true
    pgy_adblock_update_rules
}
