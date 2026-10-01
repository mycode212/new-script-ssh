#!/bin/bash
# ============================================================
# Auto Script SSH By : ProgoCloud
# Installer / Updater Console
# Repo: https://github.com/mycode212/new-script-ssh
# ============================================================

set -Eeuo pipefail

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    echo -e "\033[0;31m[ERROR] Installer ini harus dijalankan sebagai root (sudo -i / sudo bash install.sh).\033[0m"
    exit 1
fi

if [[ -t 1 ]]; then
    C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
    C_CYAN=$'\033[38;2;0;212;255m'; C_GREEN=$'\033[38;5;46m'
    C_YELLOW=$'\033[38;5;226m'; C_RED=$'\033[38;5;196m'; C_GRAY=$'\033[38;5;245m'
    C_TITLE=$'\033[38;5;39m'; C_WHITE=$'\033[38;5;255m'; C_DANGER=$'\033[38;5;196m'
else
    C_RESET=''; C_BOLD=''; C_DIM=''; C_CYAN=''; C_GREEN=''; C_YELLOW=''; C_RED=''; C_GRAY=''
    C_TITLE=''; C_WHITE=''; C_DANGER=''
fi

REPO_URL="${REPO_URL:-https://github.com/mycode212/new-script-ssh.git}"
REPO_BRANCH="${REPO_BRANCH:-main}"
SOURCE_REPO_DIR="/opt/pgy-source"

TARGET_MENU="/usr/local/bin/menu"
TARGET_PGY="/usr/local/bin/pgy"
TARGET_UPDATE="/usr/local/bin/pgy-update"
TARGET_LICENSE_CHECK="/usr/local/bin/pgy-license-check"
TARGET_BRIDGE="/usr/local/bin/pgy-ws-ssh-bridge.py"
TARGET_LIB_DIR="/usr/local/lib/pgy-ssh-tunnel"
TARGET_OPT_LIB_DIR="/pgy-lib/opt"
DATA_DIR="/etc/pgytunnel"
INSTALL_FLAG="$DATA_DIR/.install"
SSHD_CONFIG="/etc/ssh/sshd_config"
SSHD_DROPIN_DIR="/etc/ssh/sshd_config.d"
SSHD_DROPIN="$SSHD_DROPIN_DIR/pgytunnel.conf"

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd || true)"

# License constants
PGY_LICENSE_STATE_DIR="/var/lib/pgy-license"
PGY_LICENSE_TRUSTED_DEFAULT_API_URL="https://autoscript-license.worker-balancer-mang.workers.dev/api/v1/license/check"
PGY_LICENSE_PORTAL_URL="https://autoscript-license-3xj.pages.dev"

WORK_DIR="$(mktemp -d /tmp/pgy-installer.XXXXXX)"
LOG_FILE="$WORK_DIR/install.log"
OLD_MENU="$WORK_DIR/menu.previous"
OLD_LIB_DIR="$WORK_DIR/lib.previous"
OLD_SSHD_CONFIG="$WORK_DIR/sshd_config.previous"
OLD_SSHD_DROPIN="$WORK_DIR/sshd_dropin.previous"
HAD_OLD_MENU=false
HAD_OLD_LIB=false
HAD_OLD_DROPIN=false
SSH_CHANGED=false
FINISHED=false

BOX_MAX_WIDTH=68
BOX_WIDTH=$BOX_MAX_WIDTH
if [[ -t 1 ]]; then
    terminal_columns=${COLUMNS:-}
    [[ "$terminal_columns" =~ ^[0-9]+$ ]] || terminal_columns=$(tput cols 2>/dev/null || true)
    if [[ "$terminal_columns" =~ ^[0-9]+$ ]]; then
        BOX_WIDTH=$((terminal_columns - 4))
        (( BOX_WIDTH > BOX_MAX_WIDTH )) && BOX_WIDTH=$BOX_MAX_WIDTH
        (( BOX_WIDTH < 30 )) && BOX_WIDTH=30
    fi
fi

# Box UI Helpers
_pgy_strip_ansi() {
    printf '%s' "$1" | sed -E $'s/\033\\[[0-9;]*[a-zA-Z]//g'
}

_pgy_w() {
    local clean
    clean=$(_pgy_strip_ansi "$1")
    printf '%d' "${#clean}"
}

_pgy_fit() {
    local text="$1" max_width="$2"
    if (( ${#text} > max_width )); then
        printf '%s' "${text:0:max_width}"
    else
        printf '%s' "$text"
    fi
}

pgy_box_top() {
    local color="${1:-$C_CYAN}"
    printf "  %s╔" "$color"
    printf '═%.0s' $(seq 1 "$BOX_WIDTH")
    printf "╗%s\n" "$C_RESET"
}

pgy_box_bot() {
    local color="${1:-$C_CYAN}"
    printf "  %s╚" "$color"
    printf '═%.0s' $(seq 1 "$BOX_WIDTH")
    printf "╝%s\n" "$C_RESET"
}

pgy_box_divider() {
    local color="${1:-$C_CYAN}"
    printf "  %s╟" "$color"
    printf '─%.0s' $(seq 1 "$BOX_WIDTH")
    printf "╢%s\n" "$C_RESET"
}

pgy_box_header() {
    local title="$1" color="${2:-$C_CYAN}"
    local title_clean title_content
    title_clean=$(_pgy_fit "$title" "$BOX_WIDTH")
    title_content="${color}${C_BOLD}${title_clean}${C_RESET}"
    local pad=$(( (BOX_WIDTH - ${#title_clean}) / 2 ))
    (( pad < 0 )) && pad=0
    local lpad="" rpad=""
    (( pad > 0 )) && printf -v lpad "%${pad}s" ""
    local rpad_len=$(( BOX_WIDTH - ${#title_clean} - pad ))
    (( rpad_len < 0 )) && rpad_len=0
    (( rpad_len > 0 )) && printf -v rpad "%${rpad_len}s" ""
    printf "  ${color}║${C_RESET}%s%s%s${color}║${C_RESET}\n" "$lpad" "$title_content" "$rpad"
}

pgy_row() {
    local content="$1" color="${2:-$C_CYAN}"
    local max_inner=$(( BOX_WIDTH - 2 ))
    local clean cw
    clean=$(_pgy_strip_ansi "$content")
    cw=${#clean}
    if (( cw > max_inner )); then
        local raw_diff=$(( cw - max_inner ))
        # If too long, truncate string safely
        clean="${clean:0:$max_inner}"
        content="${clean}"
        cw=${#clean}
    fi
    local pad=$(( max_inner - cw ))
    local spaces=""
    if (( pad > 0 )); then
        printf -v spaces "%${pad}s" ""
    fi
    printf "  ${color}║${C_RESET} %s%s ${color}║${C_RESET}\n" "$content" "$spaces"
}

# ============================================================
# TAHAP 1: VALIDASI LISENSI PERTAMA KALI (LANGSUNG CEK & BLOKIR)
# ============================================================
check_license_before_all() {
    # Pastikan curl dan ca-certificates terpasang untuk pemeriksaan
    if ! command -v curl >/dev/null 2>&1 || ! command -v python3 >/dev/null 2>&1; then
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -y >/dev/null 2>&1 || true
        apt-get install -y --no-install-recommends curl ca-certificates python3 >/dev/null 2>&1 || true
    fi

    local pub_ip=""
    pub_ip=$(curl -4 -s --max-time 5 https://api.ipify.org 2>/dev/null || curl -4 -s --max-time 5 https://ipv4.icanhazip.com 2>/dev/null || curl -4 -s --max-time 5 https://ifconfig.me/ip 2>/dev/null || true)

    local payload
    payload=$(printf '{"public_ipv4":"%s","stage":"install","product":"progocloud-ssh"}' "$pub_ip")

    local api_raw http_code json_body
    set +e
    api_raw=$(curl -4 -s -w "\n%{http_code}" --max-time 10 \
        -X POST "$PGY_LICENSE_TRUSTED_DEFAULT_API_URL" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        -H "User-Agent: pgy-installer/1.0" \
        -d "$payload" 2>&1)
    set -e

    http_code=$(echo "$api_raw" | tail -n1)
    json_body=$(echo "$api_raw" | sed '$d')

    local allowed="false" lic_status="denied" lic_reason="" lic_ip="$pub_ip"

    if [[ "$http_code" == "200" && -n "$json_body" ]]; then
        local eval_res
        eval_res=$(python3 -c "
import json, sys
try:
    d = json.loads(sys.argv[1])
    raw_status = str(d.get('status', '')).strip().lower()
    reason = str(d.get('reason', '') or d.get('revoke_reason', '') or d.get('message', ''))
    
    # Determine allowed status
    allowed = False
    for k in ('allowed', 'active', 'is_active', 'valid', 'success'):
        v = d.get(k)
        if v is True or str(v).lower() in ('true', '1', 'yes'):
            allowed = True
            break
            
    if not allowed and raw_status in ('active', 'allowed', 'valid', 'ok', 'success', 'allow', 'cache-allow'):
        allowed = True
    elif not allowed:
        r_low = reason.lower()
        if ('ip aktif' in r_low or 'aktif' in r_low or 'active' in r_low) and not any(
            neg in r_low for neg in ('tidak', 'belum', 'not', 'expired', 'revoked', 'blocked', 'gagal')
        ):
            allowed = True

    status = raw_status if raw_status in ('active', 'allowed', 'valid', 'ok') else ('allowed' if allowed else 'denied')
    allowed_str = 'true' if allowed else 'false'
    ret_ip = str(d.get('public_ip', '') or sys.argv[2])
    print(f'{status}|{allowed_str}|{reason}|{ret_ip}')
except Exception as e:
    print(f'error|false|{e}|{sys.argv[2]}')
" "$json_body" "$pub_ip" 2>/dev/null || echo "denied|false|Respons API tidak valid|$pub_ip")

        IFS='|' read -r lic_status allowed lic_reason lic_ip <<< "$eval_res"
    else
        lic_status="denied"
        allowed="false"
        if [[ -n "$json_body" ]]; then
            lic_reason=$(python3 -c "import json, sys; d=json.loads(sys.argv[1]); print(d.get('reason','') or d.get('message',''))" "$json_body" 2>/dev/null || echo "$json_body")
        fi
        [[ -n "$lic_reason" ]] || lic_reason="Koneksi API gagal (HTTP ${http_code:-0})"
    fi

    if [[ "$allowed" != "true" ]]; then
        [[ -n "$lic_ip" ]] || lic_ip="$pub_ip"
        [[ -n "$lic_reason" ]] || lic_reason="IP belum terdaftar aktif"

        [[ -t 1 ]] && clear || true
        echo
        pgy_box_top "$C_DANGER"
        pgy_box_header "PROGOCLOUD LICENSE GUARD" "$C_DANGER"
        pgy_box_divider "$C_DANGER"
        pgy_row "$(printf "${C_RED}${C_BOLD}[AKSES DITOLAK] Lisensi VPS Tidak Aktif / Belum Terdaftar${C_RESET}")" "$C_DANGER"
        pgy_box_divider "$C_DANGER"
        pgy_row "$(printf "${C_GRAY}IP VPS :${C_RESET} ${C_WHITE}%s${C_RESET}" "${lic_ip:-N/A}")" "$C_DANGER"
        pgy_box_divider "$C_DANGER"
        pgy_row "$(printf "${C_YELLOW}[license] %s: %s${C_RESET}" "${lic_status:-denied}" "${lic_reason}")" "$C_DANGER"
        pgy_row "$(printf "${C_YELLOW}Tindakan : Daftarkan IP di portal lisensi${C_RESET}")" "$C_DANGER"
        pgy_row "$(printf "${C_YELLOW}Portal   : %s${C_RESET}" "$PGY_LICENSE_PORTAL_URL")" "$C_DANGER"
        pgy_box_divider "$C_DANGER"
        pgy_row "$(printf "${C_WHITE}Untuk aktivasi atau perpanjangan lisensi, hubungi:${C_RESET}")" "$C_DANGER"
        pgy_row "$(printf "${C_CYAN}Telegram :${C_RESET} ${C_WHITE}https://t.me/progocloud${C_RESET}")" "$C_DANGER"
        pgy_row "$(printf "${C_CYAN}Website  :${C_RESET} ${C_WHITE}%s${C_RESET}" "$PGY_LICENSE_PORTAL_URL")" "$C_DANGER"
        pgy_box_bot "$C_DANGER"
        echo
        echo -e "  ${C_RED}[ERROR] Proses instalasi dihentikan karena IP VPS belum terdaftar aktif di ProgoCloud.${C_RESET}\n"
        exit 1
    fi
}

# Jalankan pengecekan lisensi langsung sebelum proses instalasi apapun
check_license_before_all

# ============================================================
# TAHAP 2: PROSES INSTALASI MODULAR
# ============================================================

MODE="install"
if [[ -x "$TARGET_MENU" || -f "$INSTALL_FLAG" || -f "$DATA_DIR/users.db" || -f "$DATA_DIR/banners_enabled" ]]; then
    MODE="update"
fi
[[ -f "$TARGET_MENU" ]] && HAD_OLD_MENU=true
[[ -d "$TARGET_LIB_DIR" ]] && HAD_OLD_LIB=true
[[ -f "$SSHD_DROPIN" ]] && HAD_OLD_DROPIN=true

cleanup() {
    rm -rf "$WORK_DIR" 2>/dev/null || true
}

restart_ssh() {
    if command -v systemctl >/dev/null 2>&1; then
        systemctl restart sshd >/dev/null 2>&1 || systemctl restart ssh >/dev/null 2>&1
    elif command -v service >/dev/null 2>&1; then
        service sshd restart >/dev/null 2>&1 || service ssh restart >/dev/null 2>&1
    elif command -v rc-service >/dev/null 2>&1; then
        rc-service sshd restart >/dev/null 2>&1 || rc-service ssh restart >/dev/null 2>&1
    elif [[ -x /etc/init.d/sshd ]]; then
        /etc/init.d/sshd restart >/dev/null 2>&1
    elif [[ -x /etc/init.d/ssh ]]; then
        /etc/init.d/ssh restart >/dev/null 2>&1
    else
        return 1
    fi
}

rollback() {
    $FINISHED && return 0

    if $HAD_OLD_MENU && [[ -f "$OLD_MENU" ]]; then
        install -m 755 "$OLD_MENU" "$TARGET_MENU" 2>/dev/null || true
    elif ! $HAD_OLD_MENU; then
        rm -f "$TARGET_MENU" 2>/dev/null || true
    fi

    if $HAD_OLD_LIB && [[ -d "$OLD_LIB_DIR" ]]; then
        rm -rf "$TARGET_LIB_DIR" 2>/dev/null || true
        cp -a "$OLD_LIB_DIR" "$TARGET_LIB_DIR" 2>/dev/null || true
    elif ! $HAD_OLD_LIB; then
        rm -rf "$TARGET_LIB_DIR" 2>/dev/null || true
    fi

    if $SSH_CHANGED && [[ -f "$OLD_SSHD_CONFIG" ]]; then
        cp "$OLD_SSHD_CONFIG" "$SSHD_CONFIG" 2>/dev/null || true
        if $HAD_OLD_DROPIN; then
            cp "$OLD_SSHD_DROPIN" "$SSHD_DROPIN" 2>/dev/null || true
        else
            rm -f "$SSHD_DROPIN" 2>/dev/null || true
        fi
        restart_ssh >/dev/null 2>&1 || true
    fi
}

on_exit() {
    local rc=$?
    if (( rc != 0 )); then
        rollback
        echo
        echo -e "  ${C_RED}${C_BOLD}Instalasi tidak dapat diselesaikan.${C_RESET}"
        echo -e "  ${C_GRAY}Data dan konfigurasi sebelumnya tetap dipertahankan.${C_RESET}"
        if [[ -s "$LOG_FILE" ]]; then
            echo
            echo -e "  ${C_YELLOW}Log detail kegagalan:${C_RESET}"
            tail -n 15 "$LOG_FILE" | sed 's/^/  /'
        fi
    fi
    cleanup
    exit "$rc"
}
trap on_exit EXIT

print_centered_line() {
    local clean_text=$1 styled_text=$2 left right
    if (( ${#clean_text} > BOX_WIDTH )); then
        clean_text="${clean_text:0:BOX_WIDTH}"
        styled_text="$clean_text"
    fi
    left=$(( (BOX_WIDTH - ${#clean_text}) / 2 ))
    (( left < 0 )) && left=0
    right=$((BOX_WIDTH - ${#clean_text} - left))
    (( right < 0 )) && right=0
    printf "  ${C_CYAN}║${C_RESET}%*s%s%*s${C_CYAN}║${C_RESET}\n" \
        "$left" "" "$styled_text" "$right" ""
}

show_header() {
    [[ -t 1 ]] && clear || true
    echo
    printf "  %s╔" "$C_CYAN"
    printf '═%.0s' $(seq 1 "$BOX_WIDTH")
    printf "╗%s\n" "$C_RESET"
    print_centered_line "Auto Script SSH By : ProgoCloud" "${C_CYAN}${C_BOLD}Auto Script SSH By : ProgoCloud${C_RESET}"
    print_centered_line "ProgoCloud Premium Tunneling Engine" "${C_GRAY}ProgoCloud Premium Tunneling Engine${C_RESET}"
    printf "  %s╚" "$C_CYAN"
    printf '═%.0s' $(seq 1 "$BOX_WIDTH")
    printf "╝%s\n" "$C_RESET"
    echo
    if [[ "$MODE" == "update" ]]; then
        echo -e "  ${C_YELLOW}${C_BOLD}● MODE PEMBARUAN (UPDATE)${C_RESET}"
        echo -e "  ${C_DIM}  Instalasi terdeteksi • seluruh akun dan data tetap aman${C_RESET}"
    else
        echo -e "  ${C_GREEN}${C_BOLD}● MODE INSTALASI BARU${C_RESET}"
        echo -e "  ${C_DIM}  Menyiapkan instalasi ProgoCloud SSH Tunnel${C_RESET}"
    fi
    echo
}

TOTAL_STEPS=5
CURRENT_STEP=0
CURRENT_PERCENT=0
ANIMATION_TICKS=20

draw_live_progress() {
    local percent=$1 label=$2 spinner=${3:-} width=28 filled empty fill_bar="" empty_bar=""
    filled=$((percent * width / 100))
    empty=$((width - filled))
    (( filled > 0 )) && printf -v fill_bar '%*s' "$filled" '' && fill_bar=${fill_bar// /█}
    if (( empty > 0 )); then
        printf -v empty_bar '%*s' "$empty" ''
        empty_bar=${empty_bar// /░}
    fi
    printf '\r\033[2K  %s[%s%s%s%s]%s %s%3d%%%s  %s%s%s' \
        "$C_CYAN" "$fill_bar" "$C_GRAY" "$empty_bar" "$C_CYAN" "$C_RESET" \
        "$C_BOLD" "$percent" "$C_RESET" "$label" "$spinner" "$C_RESET"
}

run_step() {
    local label=$1 target_percent=$2
    shift 2
    local job_pid tick percent spinner_index=0
    local -a spinners=(' ◐' ' ◓' ' ◑' ' ◒')
    CURRENT_STEP=$((CURRENT_STEP + 1))

    if [[ ! -t 1 ]]; then
        printf '  [%d/%d] %-30s' "$CURRENT_STEP" "$TOTAL_STEPS" "$label"
        if "$@" >>"$LOG_FILE" 2>&1; then
            echo " [OK]"
            CURRENT_PERCENT=$target_percent
            return 0
        fi
        echo " [FAIL]"
        return 1
    fi

    "$@" >>"$LOG_FILE" 2>&1 &
    job_pid=$!
    for ((tick=1; tick<=ANIMATION_TICKS; tick++)); do
        percent=$((CURRENT_PERCENT + (target_percent - CURRENT_PERCENT) * tick / ANIMATION_TICKS))
        (( percent >= target_percent )) && percent=$((target_percent - 1))
        draw_live_progress "$percent" "$label" "${spinners[$spinner_index]}"
        spinner_index=$(((spinner_index + 1) % ${#spinners[@]}))
        sleep 0.08
    done
    while kill -0 "$job_pid" 2>/dev/null; do
        draw_live_progress "$((target_percent - 1))" "$label" "${spinners[$spinner_index]}"
        spinner_index=$(((spinner_index + 1) % ${#spinners[@]}))
        sleep 0.08
    done

    if wait "$job_pid"; then
        printf '\r\033[2K  %s✓%s %s\n' "$C_GREEN" "$C_RESET" "$label"
        CURRENT_PERCENT=$target_percent
        return 0
    fi
    printf '\r\033[2K  %s✗%s %s\n' "$C_RED" "$C_RESET" "$label"
    return 1
}

prepare_source_environment() {
    local missing=()
    for cmd in python3 git curl bash tar iptables; do
        command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
    done
    if (( ${#missing[@]} > 0 )); then
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -y >/dev/null 2>&1 || true
        apt-get install -y --no-install-recommends "${missing[@]}" ca-certificates >/dev/null 2>&1 || true
    fi

    if [[ -n "$SCRIPT_DIR" && -d "$SCRIPT_DIR/opt/pgy-lib" && -f "$SCRIPT_DIR/menu.sh" ]]; then
        SOURCE_REPO_DIR="$SCRIPT_DIR"
        return 0
    fi

    mkdir -p "$(dirname "$SOURCE_REPO_DIR")"
    if [[ -d "${SOURCE_REPO_DIR}/.git" ]]; then
        git -C "${SOURCE_REPO_DIR}" fetch --depth=1 origin "${REPO_BRANCH}" >/dev/null 2>&1 || true
        git -C "${SOURCE_REPO_DIR}" reset --hard "origin/${REPO_BRANCH}" >/dev/null 2>&1 || true
    else
        rm -rf "${SOURCE_REPO_DIR}"
        git clone --depth=1 -b "${REPO_BRANCH}" "${REPO_URL}" "${SOURCE_REPO_DIR}" >/dev/null 2>&1 || {
            echo "[ERROR] Gagal mengkloning repository: ${REPO_URL}" >&2
            return 1
        }
    fi
}

backup_current_state() {
    if [[ -f "$TARGET_MENU" ]]; then
        cp "$TARGET_MENU" "$OLD_MENU"
    fi
    if [[ -d "$TARGET_LIB_DIR" ]]; then
        cp -a "$TARGET_LIB_DIR" "$OLD_LIB_DIR"
    fi
    [[ -f "$SSHD_CONFIG" ]] || return 1
    cp "$SSHD_CONFIG" "$OLD_SSHD_CONFIG"
    if [[ -f "$SSHD_DROPIN" ]]; then
        cp "$SSHD_DROPIN" "$OLD_SSHD_DROPIN"
    fi
}

install_core() {
    install -d -m 755 "$TARGET_LIB_DIR" "$TARGET_OPT_LIB_DIR" "$DATA_DIR"

    if [[ -d "${SOURCE_REPO_DIR}/opt/pgy-lib" ]]; then
        cp -a "${SOURCE_REPO_DIR}/opt/pgy-lib/." "${TARGET_OPT_LIB_DIR}/"
        cp -a "${SOURCE_REPO_DIR}/opt/pgy-lib/." "${TARGET_LIB_DIR}/"
    fi

    if [[ -f "${SOURCE_REPO_DIR}/version.txt" ]]; then
        install -m 644 "${SOURCE_REPO_DIR}/version.txt" "${TARGET_OPT_LIB_DIR}/version.txt"
        install -m 644 "${SOURCE_REPO_DIR}/version.txt" "${TARGET_LIB_DIR}/version.txt"
        install -m 644 "${SOURCE_REPO_DIR}/version.txt" "${DATA_DIR}/version.txt"
    fi

    install -m 755 "${SOURCE_REPO_DIR}/menu.sh" "$TARGET_MENU"
    install -m 755 "${SOURCE_REPO_DIR}/menu.sh" "$TARGET_PGY"

    if [[ -f "${SOURCE_REPO_DIR}/opt/pgy-lib/bin/pgy-license-check" ]]; then
        install -m 755 "${SOURCE_REPO_DIR}/opt/pgy-lib/bin/pgy-license-check" "$TARGET_LICENSE_CHECK"
    fi

    if [[ -f "${SOURCE_REPO_DIR}/pgy_ws_ssh_bridge.py" ]]; then
        install -m 755 "${SOURCE_REPO_DIR}/pgy_ws_ssh_bridge.py" "$TARGET_BRIDGE"
    fi

    for item in openvpn_module.sh pgy_openvpn_gateway.py pgy_openvpn_portal.py pgy_ssh_auth_session.py pgy_openvpn_runtime.py pgy_ws_ssh_bridge.py; do
        if [[ -f "${SOURCE_REPO_DIR}/${item}" ]]; then
            install -m 755 "${SOURCE_REPO_DIR}/${item}" "${TARGET_LIB_DIR}/${item}"
            install -m 755 "${SOURCE_REPO_DIR}/${item}" "${TARGET_OPT_LIB_DIR}/${item}"
        fi
    done

    cat <<'EOF' > "$TARGET_UPDATE"
#!/bin/bash
/usr/local/bin/menu --update-script "$@"
EOF
    chmod 755 "$TARGET_UPDATE"
}

configure_ssh() {
    local sshd_bin
    sshd_bin="$(command -v sshd 2>/dev/null || true)"
    [[ -n "$sshd_bin" ]] || sshd_bin="/usr/sbin/sshd"
    [[ -x "$sshd_bin" ]] || return 1

    mkdir -p "$SSHD_DROPIN_DIR"
    sed -i \
        -e 's/^[[:space:]]*AddressFamily[[:space:]]\+any[[:space:]]*$/# ProgoCloud disabled: AddressFamily any/' \
        -e 's/^[[:space:]]*ListenAddress[[:space:]]\+::[[:space:]]*$/# ProgoCloud disabled: ListenAddress ::/' \
        "$SSHD_CONFIG"

    if ! grep -qE '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/\*\.conf' "$SSHD_CONFIG" 2>/dev/null; then
        printf '\n# ProgoCloud SSH drop-ins\nInclude /etc/ssh/sshd_config.d/*.conf\n' >> "$SSHD_CONFIG"
    fi

    cat > "$SSHD_DROPIN" <<'EOF'
# Auto Script SSH By : ProgoCloud
Port 22
DebianBanner no
VersionAddendum By: ProgoCloud
AddressFamily inet
ListenAddress 0.0.0.0
PermitRootLogin yes
PasswordAuthentication yes
KbdInteractiveAuthentication yes
ChallengeResponseAuthentication yes
UsePAM yes
X11Forwarding yes
PrintMotd no
AcceptEnv LANG LC_*
ClientAliveInterval 30
ClientAliveCountMax 3
UseDNS no
LoginGraceTime 60
MaxStartups 30:30:100
TCPKeepAlive yes
PermitTunnel yes
AllowTcpForwarding yes
GatewayPorts yes
Banner /etc/pgytunnel/bannerssh
EOF
    chmod 600 "$SSHD_DROPIN"
    "$sshd_bin" -t
}

sync_runtime() {
    if [[ "$MODE" == "update" ]]; then
        bash "$TARGET_MENU" --update-setup
    else
        bash "$TARGET_MENU" --install-setup
    fi
}

finish_setup() {
    restart_ssh || true
    mkdir -p "$(dirname "$INSTALL_FLAG")"
    touch "$INSTALL_FLAG"
}

refresh_and_finish() {
    sync_runtime
    finish_setup
}

# Mulai instalasi jika lisensi telah tervalidasi
show_header
run_step "Menyiapkan Berkas Source Repo" 25 prepare_source_environment
run_step "Membuat Backup Konfigurasi" 50 backup_current_state
run_step "Memasang Modul /pgy-lib" 75 install_core
SSH_CHANGED=true
run_step "Optimasi Konfigurasi SSH" 90 configure_ssh
run_step "Memulai Layanan & Runtime" 100 refresh_and_finish

FINISHED=true
echo
draw_live_progress 100 "Selesai" ""
echo
echo
if [[ "$MODE" == "update" ]]; then
    echo -e "  ${C_GREEN}${C_BOLD}✓ PEMBARUAN BERHASIL${C_RESET}"
    echo -e "  ${C_GRAY}  Seluruh akun dan konfigurasi tersimpan aman.${C_RESET}"
else
    echo -e "  ${C_GREEN}${C_BOLD}✓ INSTALASI BERHASIL${C_RESET}"
fi
echo -e "  ${C_CYAN}  Jalankan menu panel: ${C_BOLD}menu${C_RESET} atau ${C_BOLD}pgy${C_RESET}"
echo -e "  ${C_CYAN}  Update script: ${C_BOLD}pgy-update${C_RESET}"
echo
