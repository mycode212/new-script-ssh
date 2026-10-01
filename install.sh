#!/bin/bash
# ============================================================
# Auto Script SSH By : ProgoCloud
# Installer / Updater Console
# Repo: https://github.com/mycode212/autoscript
# ============================================================

set -Eeuo pipefail

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    echo "Error: Installer ini harus dijalankan sebagai root (sudo bash install.sh)."
    exit 1
fi

if [[ -t 1 ]]; then
    C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
    C_CYAN=$'\033[38;2;0;212;255m'; C_GREEN=$'\033[38;5;46m'
    C_YELLOW=$'\033[38;5;226m'; C_RED=$'\033[38;5;196m'; C_GRAY=$'\033[38;5;245m'
else
    C_RESET=''; C_BOLD=''; C_DIM=''; C_CYAN=''; C_GREEN=''; C_YELLOW=''; C_RED=''; C_GRAY=''
fi

TARGET_MENU="/usr/local/bin/menu"
TARGET_PGY="/usr/local/bin/pgy"
TARGET_UPDATE="/usr/local/bin/pgy-update"
TARGET_LICENSE_CHECK="/usr/local/bin/pgy-license-check"
TARGET_BRIDGE="/usr/local/bin/pgy-ws-ssh-bridge.py"
TARGET_LIB_DIR="/usr/local/lib/pgy-ssh-tunnel"
TARGET_OPT_LIB_DIR="/pgy-lib/opt"
TARGET_OVPN_MODULE="$TARGET_LIB_DIR/openvpn_module.sh"
TARGET_OVPN_GATEWAY="$TARGET_LIB_DIR/pgy_openvpn_gateway.py"
TARGET_OVPN_PORTAL="$TARGET_LIB_DIR/pgy_openvpn_portal.py"
TARGET_OVPN_RUNTIME="$TARGET_LIB_DIR/pgy_openvpn_runtime.py"
TARGET_SSH_AUTH_SESSION="$TARGET_LIB_DIR/pgy_ssh_auth_session.py"
DATA_DIR="/etc/pgytunnel"
INSTALL_FLAG="$DATA_DIR/.install"
SSHD_CONFIG="/etc/ssh/sshd_config"
SSHD_DROPIN_DIR="/etc/ssh/sshd_config.d"
SSHD_DROPIN="$SSHD_DROPIN_DIR/pgytunnel.conf"
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd || true)"

# License constants
PGY_LICENSE_STATE_DIR="/var/lib/pgy-license"
PGY_LICENSE_TRUSTED_DEFAULT_API_URL="https://autoscript-license.worker-balancer-mang.workers.dev/api/v1/license/check"

WORK_DIR="$(mktemp -d /tmp/pgy-installer.XXXXXX)"
LOG_FILE="$WORK_DIR/install.log"
PAYLOAD_MENU="$WORK_DIR/menu.sh"
PAYLOAD_BRIDGE="$WORK_DIR/pgy_ws_ssh_bridge.py"
PAYLOAD_OVPN_MODULE="$WORK_DIR/openvpn_module.sh"
PAYLOAD_OVPN_GATEWAY="$WORK_DIR/pgy_openvpn_gateway.py"
PAYLOAD_OVPN_PORTAL="$WORK_DIR/pgy_openvpn_portal.py"
PAYLOAD_OVPN_RUNTIME="$WORK_DIR/pgy_openvpn_runtime.py"
PAYLOAD_SSH_AUTH_SESSION="$WORK_DIR/pgy_ssh_auth_session.py"
PAYLOAD_LICENSE_CHECK="$WORK_DIR/pgy-license-check"

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
if [[ -x "$TARGET_MENU" || -f "$INSTALL_FLAG" || -f "$DATA_DIR/users.db" ||
      -f "$DATA_DIR/banners_enabled" ]]; then
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
    rm -rf "$WORK_DIR"
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

# License check before installation
run_license_preflight() {
    mkdir -p "${PGY_LICENSE_STATE_DIR}" "${DATA_DIR}/license"
    local lic_bin="${SCRIPT_DIR}/opt/pgy-lib/bin/pgy-license-check"
    if [[ ! -f "$lic_bin" ]]; then
        lic_bin="$TARGET_LICENSE_CHECK"
    fi
    if [[ -f "$lic_bin" ]]; then
        chmod +x "$lic_bin" 2>/dev/null || true
        python3 "$lic_bin" check --stage install --allow-disabled=false
    else
        return 0
    fi
}

prepare_payload() {
    # Check dependencies
    local missing=()
    for cmd in python3 curl bash tar iptables; do
        command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
    done
    if (( ${#missing[@]} > 0 )); then
        apt-get update -y >/dev/null 2>&1 || true
        apt-get install -y "${missing[@]}" >/dev/null 2>&1 || true
    fi

    if [[ -n "$SCRIPT_DIR" && -f "$SCRIPT_DIR/menu.sh" ]]; then
        cp "$SCRIPT_DIR/menu.sh" "$PAYLOAD_MENU"
    fi
    [[ -s "$PAYLOAD_MENU" ]] && bash -n "$PAYLOAD_MENU"

    if [[ -n "$SCRIPT_DIR" && -f "$SCRIPT_DIR/pgy_ws_ssh_bridge.py" ]]; then
        cp "$SCRIPT_DIR/pgy_ws_ssh_bridge.py" "$PAYLOAD_BRIDGE"
    fi

    if [[ -n "$SCRIPT_DIR" && -f "$SCRIPT_DIR/opt/pgy-lib/bin/pgy-license-check" ]]; then
        cp "$SCRIPT_DIR/opt/pgy-lib/bin/pgy-license-check" "$PAYLOAD_LICENSE_CHECK"
    fi

    local source_file payload_file
    while IFS='|' read -r source_file payload_file; do
        if [[ -n "$SCRIPT_DIR" && -f "$SCRIPT_DIR/$source_file" ]]; then
            cp "$SCRIPT_DIR/$source_file" "$payload_file"
        fi
        [[ -s "$payload_file" ]] || return 1
    done <<EOF
openvpn_module.sh|$PAYLOAD_OVPN_MODULE
pgy_openvpn_gateway.py|$PAYLOAD_OVPN_GATEWAY
pgy_openvpn_portal.py|$PAYLOAD_OVPN_PORTAL
pgy_openvpn_runtime.py|$PAYLOAD_OVPN_RUNTIME
pgy_ssh_auth_session.py|$PAYLOAD_SSH_AUTH_SESSION
EOF
    bash -n "$PAYLOAD_OVPN_MODULE"
    if command -v python3 >/dev/null 2>&1; then
        PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile \
            "$PAYLOAD_OVPN_GATEWAY" "$PAYLOAD_OVPN_PORTAL" "$PAYLOAD_OVPN_RUNTIME" \
            "$PAYLOAD_SSH_AUTH_SESSION"
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

    # Install modular library to /pgy-lib/opt and /usr/local/lib/pgy-ssh-tunnel
    if [[ -d "${SCRIPT_DIR}/opt/pgy-lib" ]]; then
        cp -a "${SCRIPT_DIR}/opt/pgy-lib/." "${TARGET_OPT_LIB_DIR}/"
        cp -a "${SCRIPT_DIR}/opt/pgy-lib/." "${TARGET_LIB_DIR}/"
    fi

    install -m 755 "$PAYLOAD_MENU" "$TARGET_MENU"
    install -m 755 "$PAYLOAD_MENU" "$TARGET_PGY"

    if [[ -s "$PAYLOAD_BRIDGE" ]]; then
        install -m 755 "$PAYLOAD_BRIDGE" "$TARGET_BRIDGE"
    fi

    if [[ -s "$PAYLOAD_LICENSE_CHECK" ]]; then
        install -m 755 "$PAYLOAD_LICENSE_CHECK" "$TARGET_LICENSE_CHECK"
    fi

    install -m 644 "$PAYLOAD_OVPN_MODULE" "$TARGET_OVPN_MODULE"
    install -m 644 "$PAYLOAD_OVPN_MODULE" "$TARGET_OPT_LIB_DIR/openvpn_module.sh"
    install -m 755 "$PAYLOAD_OVPN_GATEWAY" "$TARGET_OVPN_GATEWAY"
    install -m 755 "$PAYLOAD_OVPN_GATEWAY" "$TARGET_OPT_LIB_DIR/pgy_openvpn_gateway.py"
    install -m 755 "$PAYLOAD_OVPN_PORTAL" "$TARGET_OVPN_PORTAL"
    install -m 755 "$PAYLOAD_OVPN_PORTAL" "$TARGET_OPT_LIB_DIR/pgy_openvpn_portal.py"
    install -m 755 "$PAYLOAD_SSH_AUTH_SESSION" "$TARGET_SSH_AUTH_SESSION"
    install -m 755 "$PAYLOAD_SSH_AUTH_SESSION" "$TARGET_OPT_LIB_DIR/pgy_ssh_auth_session.py"
    install -m 755 "$PAYLOAD_OVPN_RUNTIME" "$TARGET_OVPN_RUNTIME"
    install -m 755 "$PAYLOAD_OVPN_RUNTIME" "$TARGET_OPT_LIB_DIR/pgy_openvpn_runtime.py"

    # Install updater command
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
run_step "Validasi Lisensi IP VPS" 15 run_license_preflight
run_step "Menyiapkan Berkas Modular" 35 prepare_payload
run_step "Membuat Backup Konfigurasi" 50 backup_current_state
run_step "Memasang Modul /pgy-lib" 70 install_core
SSH_CHANGED=true
run_step "Optimasi Konfigurasi SSH" 85 configure_ssh
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
