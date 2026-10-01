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

pgy_adblock_install_prereq() {
    if ! command -v dnsmasq >/dev/null 2>&1; then
        echo -e "${C_INFO}  Menginstal paket dnsmasq...${C_RESET}"
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -y >/dev/null 2>&1 || true
        apt-get install -y --no-install-recommends dnsmasq >/dev/null 2>&1 || true
    fi
    mkdir -p "$ADBLOCK_DIR" "$ADBLOCK_CONF_DIR"
    touch "$ADBLOCK_CUSTOM_BLACK" "$ADBLOCK_CUSTOM_WHITE"
}

pgy_adblock_update_rules() {
    pgy_adblock_install_prereq
    echo -e "${C_INFO}  Mengunduh database domain iklan & tracker terbaru...${C_RESET}"
    local tmp_rules="/tmp/pgy-adblock-rules.$$"

    # Download raw list from OISD / StevenBlack
    local source_url="https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts"
    curl -fsSL --connect-timeout 10 --max-time 60 "$source_url" -o "$tmp_rules" 2>/dev/null || {
        echo -e "${C_WARN}  Gagal mengunduh rules utama, menggunakan daftar fallback...${C_RESET}"
        cat <<EOF > "$tmp_rules"
0.0.0.0 doubleclick.net
0.0.0.0 googleads.g.doubleclick.net
0.0.0.0 pagead2.googlesyndication.com
0.0.0.0 adservice.google.com
0.0.0.0 ads.pubmatic.com
EOF
    }

    echo -e "${C_INFO}  Menyusun konfigurasi DNS sinkhole...${C_RESET}"
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

    # Convert hosts format to dnsmasq address=/domain/0.0.0.0
    grep -E '^0\.0\.0\.0 ' "$tmp_rules" | awk '{print "address=/"$2"/0.0.0.0"}' >> "$ADBLOCK_CONF" 2>/dev/null || true
    rm -f "$tmp_rules"

    # Add custom blacklist
    if [[ -s "$ADBLOCK_CUSTOM_BLACK" ]]; then
        while IFS= read -r domain; do
            [[ -n "$domain" && ! "$domain" =~ ^# ]] && echo "address=/${domain}/0.0.0.0" >> "$ADBLOCK_CONF"
        done < "$ADBLOCK_CUSTOM_BLACK"
    fi

    # Exclude whitelist if any
    if [[ -s "$ADBLOCK_CUSTOM_WHITE" ]]; then
        while IFS= read -r domain; do
            [[ -n "$domain" && ! "$domain" =~ ^# ]] && sed -i "\|address=/${domain}/0.0.0.0|d" "$ADBLOCK_CONF" 2>/dev/null || true
        done < "$ADBLOCK_CUSTOM_WHITE"
    fi

    echo -e "${C_GREEN}  Database Adblocker berhasil diperbarui.${C_RESET}"
    if pgy_adblock_is_active; then
        systemctl restart dnsmasq >/dev/null 2>&1 || true
    fi
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

pgy_adblock_toggle() {
    if pgy_adblock_is_active; then
        rm -f "$ADBLOCK_CONF"
        systemctl restart dnsmasq >/dev/null 2>&1 || true
        echo -e "${C_WARN}  DNS Adblocker telah Dinonaktifkan.${C_RESET}"
    else
        pgy_adblock_update_rules
        systemctl enable dnsmasq >/dev/null 2>&1 || true
        systemctl restart dnsmasq >/dev/null 2>&1 || true
        echo -e "${C_GREEN}  DNS Adblocker telah Diaktifkan pada port ${ADBLOCK_PORT}.${C_RESET}"
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

pgy_adblock_add_whitelist() {
    local domain="$1"
    [[ -z "$domain" ]] && return 1
    mkdir -p "$ADBLOCK_DIR"
    echo "$domain" >> "$ADBLOCK_CUSTOM_WHITE"
    sort -u -o "$ADBLOCK_CUSTOM_WHITE" "$ADBLOCK_CUSTOM_WHITE"
    pgy_adblock_update_rules
}
