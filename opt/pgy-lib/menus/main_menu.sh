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
    remote_ver=$(curl -s --max-time 4 "${REPO_URL}/version.txt" 2>/dev/null | tr -d ' \r\n\t')
    if [[ -n "$remote_ver" ]] && pgy_is_newer_version "$remote_ver" "$local_ver"; then
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
DASH_CACHE_VMESS_USERS=${DASH_CACHE_VMESS_USERS:-0}
DASH_CACHE_VLESS_USERS=${DASH_CACHE_VLESS_USERS:-0}
DASH_CACHE_TROJAN_USERS=${DASH_CACHE_TROJAN_USERS:-0}
DASH_CACHE_SSWS_USERS=${DASH_CACHE_SSWS_USERS:-0}
DASH_CACHE_SSH_USERS=${DASH_CACHE_SSH_USERS:-0}
DASH_CACHE_BW_TODAY=$(printf '%q' "${DASH_CACHE_BW_TODAY:-0.00 GiB}")
DASH_CACHE_BW_YESTERDAY=$(printf '%q' "${DASH_CACHE_BW_YESTERDAY:-0.00 GiB}")
DASH_CACHE_BW_MONTH=$(printf '%q' "${DASH_CACHE_BW_MONTH:-0.00 GiB}")
DASH_CACHE_BW_TOTAL=$(printf '%q' "${DASH_CACHE_BW_TOTAL:-0.00 GiB}")
DASH_CACHE_LOCATION=$(printf '%q' "${DASH_CACHE_LOCATION:-N/A}")
DASH_CACHE_ISP=$(printf '%q' "${DASH_CACHE_ISP:-N/A}")
DASH_CACHE_PUBLIC_IP=$(printf '%q' "${DASH_CACHE_PUBLIC_IP:-N/A}")
DASH_CACHE_DOMAIN=$(printf '%q' "${DASH_CACHE_DOMAIN:-None}")
EOF
}

main_menu() {
    local cache_file="/tmp/pgy_menu_cache_${UID}_$$.env"

    # Show Header Banner FIRST, then display the spinner below it
    if [[ -t 1 && "${PGY_MENU_LOADED:-false}" != "true" ]]; then
        PGY_MENU_LOADED=true
        show_banner
        echo
        printf '\033[?25l' 2>/dev/null || true
        (
            preload_dashboard_data "$cache_file"
        ) >/dev/null 2>&1 &
        local load_pid=$!
        local -a frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
        local f_idx=0
        while kill -0 "$load_pid" 2>/dev/null; do
            printf '\r\033[2K  \033[38;2;0;212;255m%s\033[0m \033[1;37mSedang Memuat Konten...\033[0m' "${frames[$f_idx]}"
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
        pgy_box_bot

        # ── SECTION 2: BANDWIDTH USAGE ──
        echo
        pgy_box_top
        pgy_box_header "BANDWIDTH USAGE"
        pgy_box_divider
        pgy_kv2 "TODAY"  "${DASH_CACHE_BW_TODAY:-0.00 GiB}"  "YESTERDAY" "${DASH_CACHE_BW_YESTERDAY:-0.00 GiB}"
        pgy_kv2 "MONTH"  "${DASH_CACHE_BW_MONTH:-0.00 GiB}"  "TOTAL"     "${DASH_CACHE_BW_TOTAL:-0.00 GiB}"
        pgy_box_bot

        # ── SECTION 3: USER & TRAFFIC STATS ──
        echo
        pgy_box_top
        pgy_box_header "USER & TRAFFIC STATS"
        pgy_box_divider
        pgy_kv2 "VMESS"  "${DASH_CACHE_VMESS_USERS:-0} users"  "VLESS"  "${DASH_CACHE_VLESS_USERS:-0} users"
        pgy_kv2 "TROJAN" "${DASH_CACHE_TROJAN_USERS:-0} users" "SSH/WS" "${DASH_CACHE_SSH_USERS:-0} users"
        pgy_box_divider
        pgy_kv2 "TOTAL"  "${DASH_CACHE_TOTAL_USERS:-0} accounts" "ONLINE" "${DASH_CACHE_ONLINE_USERS:-0} sessions"
        pgy_box_bot

        # ── SECTION 4: SERVICE STATUS (live indicators) ───────────────
        local act_xray=false act_nginx=false act_haprx=false act_ws=false
        local act_badvpn=false act_warp=false act_dnstt=false act_adblock=false
        if systemctl is-active --quiet xray 2>/dev/null; then act_xray=true; fi
        if systemctl is-active --quiet nginx 2>/dev/null; then act_nginx=true; fi
        if systemctl is-active --quiet haproxy 2>/dev/null; then act_haprx=true; fi
        if systemctl is-active --quiet pgy-ws-ssh-bridge 2>/dev/null; then act_ws=true; fi
        if systemctl is-active --quiet badvpn 2>/dev/null; then act_badvpn=true; fi
        if systemctl is-active --quiet wireproxy 2>/dev/null || systemctl is-active --quiet warp-svc 2>/dev/null; then act_warp=true; fi
        if systemctl is-active --quiet dnstt 2>/dev/null || systemctl is-active --quiet dnstt.service 2>/dev/null; then act_dnstt=true; fi
        if systemctl is-active --quiet dnsmasq 2>/dev/null || systemctl is-active --quiet pgy-adblock 2>/dev/null; then act_adblock=true; fi

        echo
        pgy_box_top
        pgy_box_header "SERVICE STATUS"
        pgy_box_divider
        pgy_svc2 "XRAY" "$act_xray" "NGINX" "$act_nginx"
        pgy_svc2 "HAPROXY" "$act_haprx" "SSH WS" "$act_ws"
        pgy_svc2 "BADVPN" "$act_badvpn" "WARP" "$act_warp"
        pgy_svc2 "SLOWDNS" "$act_dnstt" "ADBLOCK" "$act_adblock"
        pgy_box_bot

        # ── SECTION 5: USER MANAGEMENT ────────────────────────────────
        echo
        pgy_box_top
        pgy_box_header "USER MANAGEMENT"
        pgy_box_divider
        pgy_menu2 "[ 1]" "SSH User Manager" "[ 2]" "XRay User Manager"
        pgy_box_bot

        # ── SECTION 6: VPN & PROTOCOLS ────────────────────────────────
        echo
        pgy_box_top
        pgy_box_header "VPN & PROTOCOLS"
        pgy_box_divider
        pgy_menu2 "[ 3]" "Protocol & VPN Manager" "[ 5]" "Server-Side Adblocker"
        pgy_menu2 "[ 4]" "Port Management"        "[ 6]" "Traffic & Torrent Block"
        pgy_box_bot

        # ── SECTION 5: SYSTEM & MAINTENANCE ───────────────────────────
        echo
        pgy_box_top
        pgy_box_header "SYSTEM & MAINTENANCE"
        pgy_box_divider
        pgy_menu2 "[ 7]" "Domain & SSL Cert" "[11]" "Restore Data"
        pgy_menu2 "[ 8]" "SSH Banner"        "[12]" "Cleanup Expired"
        pgy_menu2 "[ 9]" "Auto-Reboot Task"  "[13]" "Update Script"
        pgy_menu2 "[10]" "Backup Data"       "[14]" "Status Lisensi"
        pgy_box_bot

        # ── SECTION 6: DANGER ZONE (red) ──────────────────────────────
        echo
        pgy_box_top "$C_DANGER"
        pgy_box_header "DANGER ZONE" "$C_DANGER" "$C_DANGER"
        pgy_box_divider "$C_DANGER"
        pgy_menu2 "[99]" "Uninstall Script" "[ 0]" "Exit" "$C_DANGER"
        pgy_box_bot "$C_DANGER"

        echo
        if ! read -r -p "$(echo -e ${C_PROMPT}"  Pilih opsi [0-14/99]: "${C_RESET})" choice; then
            echo
            exit 0
        fi
        case $choice in
            1) ssh_user_management_menu ;;
            2) xray_user_management_menu ;;

            3) protocol_menu ;;
            4) edge_public_port_menu ;;
            5) adblock_management_menu ;;
            6) traffic_monitor_menu ;;

            7) pgy_run_action domain_cert_menu ;;
            8) ssh_banner_menu ;;
            9) auto_reboot_menu ;;
            10) backup_data_menu ;;
            11) pgy_run_action restore_user_data ;;
            12) pgy_run_action cleanup_expired ;;
            13) pgy_run_action update_script ;;
            14) pgy_run_action pgy_license_show_status ;;

            99) uninstall_script ;;
            0) exit 0 ;;
            *) invalid_option ;;
        esac
    done
}
