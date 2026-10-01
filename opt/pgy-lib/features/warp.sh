#!/bin/bash
# ============================================================
# Auto Script SSH By : ProgoCloud
# Module: features/warp.sh - Cloudflare WARP (wireproxy & wgcf)
# ============================================================

WARP_DIR="/etc/wireproxy"
WARP_CONF="${WARP_DIR}/config.conf"
WARP_SOCKS_PORT=40000
WARP_SYSTEMD_SERVICE="/etc/systemd/system/wireproxy.service"

pgy_warp_arch() {
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64|amd64) echo "amd64" ;;
        aarch64|arm64) echo "arm64" ;;
        armv7l|armhf) echo "arm" ;;
        *) echo "amd64" ;;
    esac
}

pgy_warp_install_binaries() {
    local arch
    arch=$(pgy_warp_arch)
    mkdir -p /tmp/pgy-warp-install /usr/local/bin "$WARP_DIR"

    # 1. Install wireproxy if not present
    if ! command -v wireproxy >/dev/null 2>&1; then
        echo -e "${C_INFO}  Mengunduh binary wireproxy (${arch})...${C_RESET}"
        local wp_url="https://github.com/windtf/wireproxy/releases/download/v1.1.2/wireproxy_linux_${arch}.tar.gz"
        curl -fsSL --connect-timeout 10 --max-time 60 "$wp_url" -o /tmp/pgy-warp-install/wireproxy.tar.gz 2>/dev/null || {
            echo -e "${C_ERR}  Gagal mengunduh wireproxy.${C_RESET}"
            return 1
        }
        tar -xzf /tmp/pgy-warp-install/wireproxy.tar.gz -C /tmp/pgy-warp-install/
        local bin_wp
        bin_wp=$(find /tmp/pgy-warp-install -type f -name wireproxy -print -quit)
        if [[ -n "$bin_wp" && -f "$bin_wp" ]]; then
            install -m 755 "$bin_wp" /usr/local/bin/wireproxy
        fi
    fi

    # 2. Install wgcf if not present
    if ! command -v wgcf >/dev/null 2>&1; then
        echo -e "${C_INFO}  Mengunduh binary wgcf (${arch})...${C_RESET}"
        local wgcf_arch="amd64"
        [[ "$arch" == "arm64" ]] && wgcf_arch="arm64"
        local wgcf_url="https://github.com/ViRb3/wgcf/releases/download/v2.2.23/wgcf_2.2.23_linux_${wgcf_arch}"
        curl -fsSL --connect-timeout 10 --max-time 60 "$wgcf_url" -o /usr/local/bin/wgcf 2>/dev/null || {
            echo -e "${C_ERR}  Gagal mengunduh wgcf.${C_RESET}"
            return 1
        }
        chmod 755 /usr/local/bin/wgcf
    fi

    rm -rf /tmp/pgy-warp-install
    return 0
}

pgy_warp_generate_config() {
    local target_key="${1:-}"
    local wgcf_dir="/etc/wgcf"
    mkdir -p "$wgcf_dir" "$WARP_DIR"
    cd "$wgcf_dir" || return 1

    echo -e "${C_INFO}  Mendaftarkan akun Cloudflare WARP via wgcf...${C_RESET}"
    if [[ ! -f "wgcf-account.toml" ]]; then
        yes | wgcf register >/tmp/wgcf-register.log 2>&1 || true
        if [[ ! -f "wgcf-account.toml" ]]; then
            echo -e "${C_ERR}  Gagal mendaftarkan akun Cloudflare (Rate Limit / Network). Detail:${C_RESET}"
            tail -n 10 /tmp/wgcf-register.log 2>/dev/null || true
            return 1
        fi
    fi

    if [[ -n "$target_key" ]]; then
        echo -e "${C_INFO}  Menerapkan License Key WARP+...${C_RESET}"
        sed -i "s/license_key = .*/license_key = '${target_key}'/" wgcf-account.toml 2>/dev/null || true
        wgcf update >/dev/null 2>&1 || true
    fi

    echo -e "${C_INFO}  Membuat profil WireGuard...${C_RESET}"
    wgcf generate >/tmp/wgcf-generate.log 2>&1 || true

    if [[ ! -f "wgcf-profile.conf" ]]; then
        echo -e "${C_ERR}  Gagal men-generate profil wgcf-profile.conf.${C_RESET}"
        tail -n 10 /tmp/wgcf-generate.log 2>/dev/null || true
        return 1
    fi

    echo -e "${C_INFO}  Menyusun konfigurasi Wireproxy...${C_RESET}"
    cp -f "${wgcf_dir}/wgcf-profile.conf" "${WARP_CONF}"

    # Hapus section Socks/Socks5 lama jika ada dan tambahkan section Socks5 resmi
    local wp_tmp
    wp_tmp="$(mktemp /tmp/wireproxy.XXXXXX)"
    awk '
        BEGIN { drop=0 }
        /^\[(Socks|Socks5)\]$/ { drop=1; next }
        /^\[.*\]$/ { drop=0 }
        drop { next }
        { print }
    ' "$WARP_CONF" > "$wp_tmp"

    cat >> "$wp_tmp" <<EOF

[Socks5]
BindAddress = 127.0.0.1:${WARP_SOCKS_PORT}
EOF

    install -m 600 "$wp_tmp" "$WARP_CONF"
    rm -f "$wp_tmp" /tmp/wgcf-register.log /tmp/wgcf-generate.log
    echo -e "${C_GREEN}  Konfigurasi ${WARP_CONF} berhasil dibuat.${C_RESET}"
    return 0
}

pgy_warp_install_service() {
    cat <<EOF > "$WARP_SYSTEMD_SERVICE"
[Unit]
Description=ProgoCloud Cloudflare WARP Wireproxy SOCKS5 Service
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/wireproxy -c ${WARP_CONF}
Restart=always
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload >/dev/null 2>&1 || true
    systemctl enable wireproxy.service >/dev/null 2>&1 || true
    systemctl restart wireproxy.service >/dev/null 2>&1 || true
    sleep 1.5

    if ! systemctl is-active --quiet wireproxy.service; then
        echo -e "${C_ERR}  wireproxy.service gagal berjalan. Log systemd:${C_RESET}"
        journalctl -u wireproxy.service -n 15 --no-pager 2>/dev/null || true
        return 1
    fi
    return 0
}

pgy_warp_is_active() {
    systemctl is-active --quiet wireproxy.service 2>/dev/null
}

pgy_warp_get_status() {
    if ! pgy_warp_is_active; then
        echo "Inactive"
        return
    fi
    local trace
    trace=$(curl -s --socks5-hostname "127.0.0.1:${WARP_SOCKS_PORT}" --connect-timeout 4 --max-time 6 "https://www.cloudflare.com/cdn-cgi/trace" 2>/dev/null || true)
    local warp_stat
    warp_stat=$(echo "$trace" | grep '^warp=' | cut -d= -f2)
    case "$warp_stat" in
        plus) echo "Active (WARP+)" ;;
        on) echo "Active (Free)" ;;
        *) echo "Active" ;;
    esac
}

pgy_warp_test_unlock() {
    echo -e "${C_TITLE}  --- HASIL UJI UNLOCK STREAMING & AI VIA WARP ---${C_RESET}"
    echo
    local socks="socks5h://127.0.0.1:${WARP_SOCKS_PORT}"

    # 1. Test Cloudflare Trace
    echo -ne "  [1] Cloudflare Edge Routing : "
    local trace ip_loc warp_mode
    trace=$(curl -s -x "$socks" --connect-timeout 5 --max-time 8 "https://www.cloudflare.com/cdn-cgi/trace" 2>/dev/null || true)
    if [[ -n "$trace" ]]; then
        ip_loc=$(echo "$trace" | grep '^loc=' | cut -d= -f2)
        warp_mode=$(echo "$trace" | grep '^warp=' | cut -d= -f2)
        echo -e "${C_GREEN}TERHUBUNG (Loc: ${ip_loc}, Mode: ${warp_mode})${C_RESET}"
    else
        echo -e "${C_RED}GAGAL TERHUBUNG${C_RESET}"
    fi

    # 2. Test Netflix
    echo -ne "  [2] Netflix Streaming       : "
    local nf_code
    nf_code=$(curl -s -o /dev/null -w "%{http_code}" -x "$socks" --connect-timeout 5 --max-time 10 "https://www.netflix.com/title/80018499" 2>/dev/null || echo "000")
    if [[ "$nf_code" == "200" ]]; then
        echo -e "${C_GREEN}UNLOCKED / BEBAS BLOKIR (HTTP 200)${C_RESET}"
    elif [[ "$nf_code" == "403" || "$nf_code" == "404" ]]; then
        echo -e "${C_YELLOW}TERBATAS (HTTP ${nf_code})${C_RESET}"
    else
        echo -e "${C_RED}TIMEOUT / ERROR (${nf_code})${C_RESET}"
    fi

    # 3. Test OpenAI / ChatGPT
    echo -ne "  [3] OpenAI / ChatGPT Access : "
    local ai_code
    ai_code=$(curl -s -o /dev/null -w "%{http_code}" -x "$socks" --connect-timeout 5 --max-time 10 "https://chatgpt.com" 2>/dev/null || echo "000")
    if [[ "$ai_code" == "200" || "$ai_code" == "301" || "$ai_code" == "302" || "$ai_code" == "403" && "$ai_code" != "1020" ]]; then
        echo -e "${C_GREEN}LOLOS (HTTP ${ai_code})${C_RESET}"
    else
        echo -e "${C_RED}TERBLOKIR (HTTP ${ai_code})${C_RESET}"
    fi
    echo
}

pgy_warp_toggle_service() {
    if pgy_warp_is_active; then
        systemctl stop wireproxy.service >/dev/null 2>&1 || true
        systemctl disable wireproxy.service >/dev/null 2>&1 || true
        echo -e "${C_WARN}  Service Cloudflare WARP telah Dinonaktifkan.${C_RESET}"
    else
        if [[ ! -f "$WARP_CONF" ]]; then
            pgy_warp_install_binaries || return 1
            pgy_warp_generate_config "" || return 1
            pgy_warp_install_service || return 1
        else
            systemctl enable wireproxy.service >/dev/null 2>&1 || true
            systemctl start wireproxy.service >/dev/null 2>&1 || true
        fi
        echo -e "${C_GREEN}  Service Cloudflare WARP telah Diaktifkan (SOCKS5 127.0.0.1:${WARP_SOCKS_PORT}).${C_RESET}"
    fi
}
