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
else
    C_RESET=''; C_BOLD=''; C_DIM=''; C_CYAN=''; C_GREEN=''; C_YELLOW=''; C_RED=''; C_GRAY=''
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

MODE="install"
if [[ -x "$TARGET_MENU" || -f "$INSTALL_FLAG" || -f "$DATA_DIR/users.db" || -f "$DATA_DIR/banners_enabled" ]]; then
    MODE="update"
fi
[[ -f "$TARGET_MENU" ]] && HAD_OLD_MENU=true
[[ -d "$TARGET_LIB_DIR" ]] && HAD_OLD_LIB=true
[[ -f "$SSHD_DROPIN" ]] && HAD_OLD_DROPIN=true

BOX_MAX_WIDTH=64
BOX_WIDTH=$BOX_MAX_WIDTH
if [[ -t 1 ]]; then
    terminal_columns=${COLUMNS:-}
    [[ "$terminal_columns" =~ ^[0-9]+$ ]] || terminal_columns=$(tput cols 2>/dev/null || true)
    if [[ "$terminal_columns" =~ ^[0-9]+$ ]]; then
        BOX_WIDTH=$((terminal_columns - 4))
        (( BOX_WIDTH > BOX_MAX_WIDTH )) && BOX_WIDTH=$BOX_MAX_WIDTH
        (( BOX_WIDTH < 24 )) && BOX_WIDTH=24
    fi
fi

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
            echo -e "  ${C_YELLOW}Log detail kegagalan (15 baris terakhir):${C_RESET}"
            echo -e "  ------------------------------------------------------------"
            tail -n 15 "$LOG_FILE" | sed 's/^/  /'
            echo -e "  ------------------------------------------------------------"
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

TOTAL_STEPS=6
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

# 1. Menyiapkan Dependensi & Source Repo
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

    # Cek apakah script dijalankan langsung di dalam folder repo lokal yang lengkap
    if [[ -n "$SCRIPT_DIR" && -d "$SCRIPT_DIR/opt/pgy-lib" && -f "$SCRIPT_DIR/menu.sh" ]]; then
        SOURCE_REPO_DIR="$SCRIPT_DIR"
        return 0
    fi

    # Jika via curl / pipe, clone atau update repo ke /opt/pgy-source
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

    [[ -d "${SOURCE_REPO_DIR}/opt/pgy-lib" && -f "${SOURCE_REPO_DIR}/menu.sh" ]] || {
        echo "[ERROR] Struktur berkas repositori tidak lengkap di ${SOURCE_REPO_DIR}" >&2
        return 1
    }
}

# 2. Validasi Lisensi IP VPS (Ketat)
run_license_preflight() {
    mkdir -p "${PGY_LICENSE_STATE_DIR}" "${DATA_DIR}/license"
    local lic_bin="${SOURCE_REPO_DIR}/opt/pgy-lib/bin/pgy-license-check"
    
    if [[ ! -f "$lic_bin" ]]; then
        lic_bin="$TARGET_LICENSE_CHECK"
    fi

    if [[ ! -f "$lic_bin" ]]; then
        echo "[ERROR] Binary pgy-license-check tidak ditemukan di ${lic_bin}." >&2
        return 1
    fi

    chmod +x "$lic_bin" 2>/dev/null || true

    # Eksekusi pengecekan lisensi via python3
    local lic_output lic_status
    if ! lic_output=$(python3 "$lic_bin" check --stage install --allow-disabled=false 2>&1); then
        lic_status=$?
        echo "$lic_output" >> "$LOG_FILE" 2>&1 || true
        echo -e "\n\033[0;31m[AKSES DITOLAK] Lisensi VPS Tidak Aktif / Belum Terdaftar!\033[0m" >&2
        echo -e "\033[1;33m$lic_output\033[0m" >&2
        echo -e "\033[0;36mSilakan daftarkan IP VPS Anda di: ${PGY_LICENSE_PORTAL_URL} atau hubungi https://t.me/progocloud\033[0m\n" >&2
        return "$lic_status"
    fi
    return 0
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

    # Salin pustaka modular ke /pgy-lib/opt dan /usr/local/lib/pgy-ssh-tunnel
    if [[ -d "${SOURCE_REPO_DIR}/opt/pgy-lib" ]]; then
        cp -a "${SOURCE_REPO_DIR}/opt/pgy-lib/." "${TARGET_OPT_LIB_DIR}/"
        cp -a "${SOURCE_REPO_DIR}/opt/pgy-lib/." "${TARGET_LIB_DIR}/"
    fi

    # Pasang executable binaries
    install -m 755 "${SOURCE_REPO_DIR}/menu.sh" "$TARGET_MENU"
    install -m 755 "${SOURCE_REPO_DIR}/menu.sh" "$TARGET_PGY"

    if [[ -f "${SOURCE_REPO_DIR}/opt/pgy-lib/bin/pgy-license-check" ]]; then
        install -m 755 "${SOURCE_REPO_DIR}/opt/pgy-lib/bin/pgy-license-check" "$TARGET_LICENSE_CHECK"
    fi

    if [[ -f "${SOURCE_REPO_DIR}/pgy_ws_ssh_bridge.py" ]]; then
        install -m 755 "${SOURCE_REPO_DIR}/pgy_ws_ssh_bridge.py" "$TARGET_BRIDGE"
    fi

    # Salin helper scripts
    for item in openvpn_module.sh pgy_openvpn_gateway.py pgy_openvpn_portal.py pgy_ssh_auth_session.py pgy_openvpn_runtime.py pgy_ws_ssh_bridge.py; do
        if [[ -f "${SOURCE_REPO_DIR}/${item}" ]]; then
            install -m 755 "${SOURCE_REPO_DIR}/${item}" "${TARGET_LIB_DIR}/${item}"
            install -m 755 "${SOURCE_REPO_DIR}/${item}" "${TARGET_OPT_LIB_DIR}/${item}"
        fi
    done

    # Buat shortcut updater pgy-update
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

show_header
run_step "Menyiapkan Berkas Source Repo" 20 prepare_source_environment
run_step "Validasi Lisensi IP VPS" 40 run_license_preflight
run_step "Membuat Backup Konfigurasi" 55 backup_current_state
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
