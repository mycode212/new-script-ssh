#!/bin/bash
# ============================================================
# Auto Script SSH By : ProgoCloud
# Module: menus/main_menu.sh - Interactive Main Dashboard
# ============================================================

preload_dashboard_data() {
    local cache_file="${1:-/tmp/pgy_menu_cache_${UID}_$$.env}"

    # 1. Sync runtime state silently in background
    sync_runtime_components_if_needed >/dev/null 2>&1 || true

    # 2. Live license check
    local lic_blocked=0 lic_reason=""
    if ! pgy_license_guard_preflight "menu" >/dev/null 2>&1; then
        lic_blocked=1
        lic_reason="${PGY_LICENSE_BLOCK_REASON:-}"
    fi

    # 3. Live version & update check against GitHub repo
    local update_avail=false latest_ver=""
    local local_ver
    local_ver="$(get_pgy_installed_version 2>/dev/null || echo "${PGY_SCRIPT_VERSION:-0.0.1}")"
    local remote_ver=""
    remote_ver=$(curl -s --max-time 4 "https://raw.githubusercontent.com/mycode212/new-script-ssh/main/version.txt" 2>/dev/null | tr -d ' \r\n\t')
    if [[ -n "$remote_ver" && "$remote_ver" != "$local_ver" ]]; then
        update_avail=true
        latest_ver="$remote_ver"
    else
        update_avail=false
        latest_ver="$local_ver"
    fi

    # 4. Refresh Dashboard System & Network Cache
    refresh_dashboard_cache >/dev/null 2>&1 || true

    # 5. Write runtime state to cache file
    cat <<EOF > "$cache_file"
PGY_LICENSE_BLOCKED=${lic_blocked}
PGY_LICENSE_BLOCK_REASON=$(printf '%q' "${lic_reason}")
PGY_UPDATE_AVAILABLE=${update_avail}
PGY_LATEST_VERSION=$(printf '%q' "${latest_ver}")
PGY_UPDATE_CHECK_TS=$(date +%s)
DASH_CACHE_TS=${DASH_CACHE_TS:-0}
DASH_CACHE_OS_NAME=$(printf '%q' "${DASH_CACHE_OS_NAME:-Linux}")
DASH_CACHE_UPTIME=$(printf '%q' "${DASH_CACHE_UPTIME:-unknown}")
DASH_CACHE_CPU_LOAD=$(printf '%q' "${DASH_CACHE_CPU_LOAD:-0.00}")
DASH_CACHE_CPU_CORES=${DASH_CACHE_CPU_CORES:-1}
DASH_CACHE_RAM_PCT=$(printf '%q' "${DASH_CACHE_RAM_PCT:-0}")
DASH_CACHE_RAM_USED=$(printf '%q' "${DASH_CACHE_RAM_USED:-0 / 0}")
DASH_CACHE_DISK_PCT=$(printf '%q' "${DASH_CACHE_DISK_PCT:-0}")
DASH_CACHE_TOTAL_USERS=${DASH_CACHE_TOTAL_USERS:-0}
DASH_CACHE_ONLINE_USERS=${DASH_CACHE_ONLINE_USERS:-0}
DASH_CACHE_LOCATION=$(printf '%q' "${DASH_CACHE_LOCATION:-N/A}")
DASH_CACHE_ISP=$(printf '%q' "${DASH_CACHE_ISP:-N/A}")
DASH_CACHE_PUBLIC_IP=$(printf '%q' "${DASH_CACHE_PUBLIC_IP:-N/A}")
DASH_CACHE_DOMAIN=$(printf '%q' "${DASH_CACHE_DOMAIN:-None}")
EOF
}

main_menu() {
    local cache_file="/tmp/pgy_menu_cache_${UID}_$$.env"

    # Show animated loading spinner on initial launch
    if [[ -t 1 && "${PGY_MENU_LOADED:-false}" != "true" ]]; then
        PGY_MENU_LOADED=true
        printf '\033[?25l' 2>/dev/null || true
        (
            preload_dashboard_data "$cache_file"
        ) >/dev/null 2>&1 &
        local load_pid=$!
        local -a frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
        local f_idx=0
        while kill -0 "$load_pid" 2>/dev/null; do
            printf '\r\033[2K  \033[38;2;0;212;255m%s\033[0m \033[1;37mMemuat Konten & Memeriksa Pembaruan...\033[0m' "${frames[$f_idx]}"
            f_idx=$(( (f_idx + 1) % ${#frames[@]} ))
            sleep 0.08
        done
        wait "$load_pid" 2>/dev/null || true
        printf '\r\033[2K\033[?25h' 2>/dev/null || true
        if [[ -f "$cache_file" ]]; then
            # shellcheck source=/dev/null
            source "$cache_file"
            rm -f "$cache_file" 2>/dev/null || true
        fi
    fi

    while true; do
        export UNINSTALL_MODE="interactive"

        # Check License before rendering main menu
        if [[ "${PGY_LICENSE_BLOCKED:-0}" -ne 0 ]]; then
            pgy_display_license_block_screen
            echo
            read -r -p "$(echo -e ${C_PROMPT}"  Tekan [Enter] untuk cek ulang atau [Ctrl+C] untuk keluar... "${C_RESET})" || exit 0
            PGY_MENU_LOADED=false
            continue
        fi

        show_banner
        show_script_update_box_if_available 2>/dev/null || true

        # ── Refresh caches ─────────────────────────────────────────────
        refresh_dashboard_cache 2>/dev/null || true

        # ── Service status pills (● = running, ○ = stopped) ───────────
        local pill_haprx="${C_STATUS_I}○${C_RESET}"  pill_nginx="${C_STATUS_I}○${C_RESET}"
        local pill_ws="${C_STATUS_I}○${C_RESET}"     pill_badvpn="${C_STATUS_I}○${C_RESET}"
        local pill_dnstt="${C_STATUS_I}○${C_RESET}"
        if systemctl is-active --quiet haproxy 2>/dev/null; then pill_haprx="${C_STATUS_A}●${C_RESET}"; fi
        if systemctl is-active --quiet nginx 2>/dev/null; then pill_nginx="${C_STATUS_A}●${C_RESET}"; fi
        if systemctl is-active --quiet pgy-ws-ssh-bridge 2>/dev/null; then pill_ws="${C_STATUS_A}●${C_RESET}"; fi
        if systemctl is-active --quiet badvpn 2>/dev/null; then pill_badvpn="${C_STATUS_A}●${C_RESET}"; fi
        if systemctl is-active --quiet dnstt 2>/dev/null; then pill_dnstt="${C_STATUS_A}●${C_RESET}"; fi

        # ── SECTION 1: SERVER PROFILE ──
        local _cpu_core_word="CORE"
        if [[ "${DASH_CACHE_CPU_CORES:-1}" -gt 1 ]]; then
            _cpu_core_word="CORES"
        fi
        local _cpu_pct
        _cpu_pct=$(compute_cpu_pct 2>/dev/null || echo 0)
        local _cpu_val="${_cpu_pct}% (${DASH_CACHE_CPU_CORES:-1} ${_cpu_core_word})"
        local _ram_val="${DASH_CACHE_RAM_PCT:-0}% (${DASH_CACHE_RAM_USED:-0 / 0})"
        echo
        pgy_box_top
        pgy_box_header "SERVER PROFILE"
        pgy_box_divider
        pgy_kv2 "LOC"    "${DASH_CACHE_LOCATION:0:22}"  "IP"     "${DASH_CACHE_PUBLIC_IP:0:24}"
        pgy_kv2 "ISP"    "${DASH_CACHE_ISP:0:22}"       "DOMAIN" "${DASH_CACHE_DOMAIN:0:24}"
        pgy_box_divider
        pgy_kv2 "OS"     "${DASH_CACHE_OS_NAME:0:22}"   "UPTIME" "${DASH_CACHE_UPTIME:0:24}"
        pgy_kv2 "CPU"    "${_cpu_val:0:22}"             "RAM"    "${_ram_val:0:24}"
        pgy_box_divider
        pgy_kv2 "ACCT"   "${DASH_CACHE_TOTAL_USERS} total" "ONLINE" "${DASH_CACHE_ONLINE_USERS} now"
        pgy_box_bot

        # ── SECTION 2: SERVICE STATUS (live pills) ────────────────────
        echo
        pgy_box_top
        pgy_box_header "SERVICE STATUS"
        pgy_box_divider
        pgy_row "${pill_haprx} HAProxy ${EDGE_PUBLIC_HTTP_PORT}/${EDGE_PUBLIC_TLS_PORT}   ${pill_nginx} Nginx ${NGINX_INTERNAL_TLS_PORT}   ${pill_ws} WS-Bridge ${WS_SSH_BRIDGE_PORT}"
        pgy_box_bot

        # ── SECTION 3: USER MANAGEMENT ────────────────────────────────
        echo
        pgy_box_top
        pgy_box_header "USER MANAGEMENT"
        pgy_box_divider
        pgy_menu2 "[ 1]" "Create User"      "[ 7]" "List Users"
        pgy_menu2 "[ 2]" "Delete User"      "[ 8]" "Client Config"
        pgy_menu2 "[ 3]" "Renew Account"    "[ 9]" "Create Trial"
        pgy_menu2 "[ 4]" "Lock User"        "[10]" "Trial Accounts"
        pgy_menu2 "[ 5]" "Unlock Account"   "[11]" "Bandwidth Usage"
        pgy_menu2 "[ 6]" "Edit Details"     "[12]" "Bulk Create"
        pgy_box_bot

        # ── SECTION 4: VPN & PROTOCOLS ────────────────────────────────
        echo
        pgy_box_top
        pgy_box_header "VPN & PROTOCOLS"
        pgy_box_divider
        pgy_menu2 "[13]" "Protocol Manager" "[15]" "Block Torrent"
        pgy_menu2 "[14]" "Port Management"  "[16]" "Traffic Monitor"
        pgy_box_bot

        # ── SECTION 5: SYSTEM & MAINTENANCE ───────────────────────────
        echo
        pgy_box_top
        pgy_box_header "SYSTEM & MAINTENANCE"
        pgy_box_divider
        pgy_menu2 "[17]" "Domain & SSL Cert" "[21]" "Restore Data"
        pgy_menu2 "[18]" "SSH Banner"        "[22]" "Cleanup Expired"
        pgy_menu2 "[19]" "Auto-Reboot Task"  "[23]" "Update Script"
        pgy_menu2 "[20]" "Backup Data"       "[24]" "Status Lisensi"
        pgy_box_bot

        # ── SECTION 6: DANGER ZONE (red) ──────────────────────────────
        echo
        pgy_box_top "$C_DANGER"
        pgy_box_header "DANGER ZONE" "$C_DANGER" "$C_DANGER"
        pgy_box_divider "$C_DANGER"
        pgy_menu2 "[99]" "Uninstall Script" "[ 0]" "Exit" "$C_DANGER"
        pgy_box_bot "$C_DANGER"

        echo
        if ! read -r -p "$(echo -e ${C_PROMPT}"  Pilih opsi [0-24/99]: "${C_RESET})" choice; then
            echo
            exit 0
        fi
        case $choice in
            1) pgy_run_action create_user ;;
            2) pgy_run_action delete_user ;;
            3) pgy_run_action renew_user ;;
            4) pgy_run_action lock_user ;;
            5) pgy_run_action unlock_user ;;
            6) pgy_run_action edit_user ;;
            7) pgy_run_action list_users ;;
            8) pgy_run_action client_config_menu ;;
            9) pgy_run_action create_trial_account ;;
            10) pgy_run_action list_trial_accounts ;;
            11) pgy_run_action view_user_bandwidth ;;
            12) pgy_run_action bulk_create_users ;;

            13) protocol_menu ;;
            14) edge_public_port_menu ;;
            15) torrent_block_menu ;;
            16) traffic_monitor_menu ;;

            17) pgy_run_action domain_cert_menu ;;
            18) ssh_banner_menu ;;
            19) auto_reboot_menu ;;
            20) backup_data_menu ;;
            21) pgy_run_action restore_user_data ;;
            22) pgy_run_action cleanup_expired ;;
            23) pgy_run_action update_script ;;
            24) pgy_run_action pgy_license_show_status ;;

            99) uninstall_script ;;
            0) exit 0 ;;
            *) invalid_option ;;
        esac
    done
}

pgy_license_show_status() {
    pgy_screen_title "STATUS LISENSI" "Informasi lisensi VPS ProgoCloud"
    local license_bin
    license_bin="$(pgy_license_guard_bin_path)"
    if [[ -x "${license_bin}" ]]; then
        "${license_bin}" status
    else
        python3 "${PGY_LIB_DIR}/pgy-license-check" status 2>/dev/null || python3 "/pgy-lib/opt/bin/pgy-license-check" status 2>/dev/null || echo "Informasi lisensi tidak tersedia."
    fi
}
