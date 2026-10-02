#!/bin/bash
# ============================================================
# Auto Script SSH By : ProgoCloud
# Module: features/uninstall.sh - Initial setup & clean uninstall
# ============================================================

initial_setup() {
    echo -e "${C_BLUE}Preparing PGY SSH TUNNEL...${C_RESET}"
    check_environment
    
    ensure_pgytunnel_dirs
    ensure_pgytunnel_system_group
    migrate_legacy_shadow_locks || {
        echo -e "${C_YELLOW}[WARNING] Could not migrate legacy account lock reasons.${C_RESET}"
    }
    
    echo -e "${C_BLUE}Configuring secure access...${C_RESET}"
    harden_sshd_for_tunnel_stability

    echo -e "${C_BLUE}Configuring account services...${C_RESET}"
    setup_limiter_service
    setup_ssh_auth_session_hook || {
        echo -e "${C_YELLOW}[WARNING] Could not install the authenticated SSH session hook.${C_RESET}"
    }
    
    echo -e "${C_BLUE}Preparing usage services...${C_RESET}"
    setup_bandwidth_service
    
    echo -e "${C_BLUE}Finalizing account services...${C_RESET}"
    setup_trial_cleanup_script

    if declare -F pgy_openvpn_refresh_runtime >/dev/null 2>&1 && pgy_openvpn_is_installed; then
        echo -e "${C_BLUE}Refreshing optional services...${C_RESET}"
        pgy_openvpn_refresh_runtime || {
            echo -e "${C_RED}[ERROR] OpenVPN refresh failed; its previous working state was restored.${C_RESET}"
            return 1
        }
    fi
    
    echo -e "${C_BLUE}Applying final configuration...${C_RESET}"
    disable_dynamic_ssh_banner_system
    systemctl reload sshd 2>/dev/null || systemctl reload ssh 2>/dev/null || true
    
    if [ ! -f "$INSTALL_FLAG_FILE" ]; then
        touch "$INSTALL_FLAG_FILE"
    fi
    echo -e "${C_GREEN}[OK] Setup finished.${C_RESET}"
}

update_setup() {
    # Refresh generated runtime components without resetting operator data or
    # feature state. In particular, an enabled dynamic banner must remain
    # enabled after the one-line installer is re-run as an updater.
    local dynamic_banner_was_enabled=false
    local dynamic_banner_flag="$DB_DIR/banners_enabled"
    [[ -f "$dynamic_banner_flag" ]] && dynamic_banner_was_enabled=true

    check_environment
    ensure_pgytunnel_dirs
    ensure_pgytunnel_system_group
    migrate_legacy_shadow_locks || {
        echo -e "${C_YELLOW}[WARNING] Could not migrate legacy account lock reasons.${C_RESET}"
    }
    harden_sshd_for_tunnel_stability
    setup_limiter_service
    setup_ssh_auth_session_hook || {
        echo -e "${C_YELLOW}[WARNING] Could not refresh the authenticated SSH session hook.${C_RESET}"
    }
    setup_bandwidth_service
    setup_trial_cleanup_script

    if declare -F pgy_openvpn_refresh_runtime >/dev/null 2>&1 && pgy_openvpn_is_installed; then
        pgy_openvpn_refresh_runtime || {
            echo -e "${C_RED}[ERROR] OpenVPN refresh failed; its previous working state was restored.${C_RESET}"
            return 1
        }
    fi

    if $dynamic_banner_was_enabled; then
        touch "$dynamic_banner_flag"
        refresh_dynamic_banner_routing_if_enabled
    fi

    # Refresh the Telegram worker code without changing its saved bot settings
    # or turning a deliberately stopped bot back on.
    if [[ -f "$AUTO_BACKUP_CONF" ]]; then
        auto_backup_write_worker
        if command -v pm2 >/dev/null 2>&1 &&
           pm2 describe "$AUTO_BACKUP_PM2_NAME" 2>/dev/null | grep -qE 'status.*online'; then
            pm2 restart "$AUTO_BACKUP_PM2_NAME" --update-env >/dev/null 2>&1 || true
        fi
    fi

    [[ -f "$INSTALL_FLAG_FILE" ]] || touch "$INSTALL_FLAG_FILE"
    systemctl reload sshd 2>/dev/null || systemctl reload ssh 2>/dev/null || true
}


pgy_remove_managed_trial_jobs() {
    command -v atq >/dev/null 2>&1 && command -v atrm >/dev/null 2>&1 || return 0
    local job_id
    local cleanup_failed=false
    while read -r job_id _rest; do
        [[ "$job_id" =~ ^[0-9]+$ ]] || continue
        if at -c "$job_id" 2>/dev/null | grep -Fq "$TRIAL_CLEANUP_SCRIPT"; then
            atrm "$job_id" >/dev/null 2>&1 || cleanup_failed=true
        fi
    done < <(atq 2>/dev/null)
    [[ "$cleanup_failed" != true ]]
}

pgy_remove_auto_reboot_job() {
    command -v crontab >/dev/null 2>&1 || return 0
    local current filtered
    local cleanup_failed=false
    current=$(mktemp) || return 1
    filtered=$(mktemp) || { rm -f "$current"; return 1; }
    if crontab -l > "$current" 2>/dev/null; then
        grep -vF "$AUTO_REBOOT_CRON_TAG" "$current" |
            grep -vE '^[[:space:]]*0[[:space:]]+0[[:space:]]+\*[[:space:]]+\*[[:space:]]+\*[[:space:]]+systemctl[[:space:]]+reboot[[:space:]]*$' \
                > "$filtered" || true
        if [[ -s "$filtered" ]]; then
            crontab "$filtered" >/dev/null 2>&1 || cleanup_failed=true
        else
            crontab -r >/dev/null 2>&1 || cleanup_failed=true
        fi
    fi
    rm -f "$current" "$filtered"
    [[ "$cleanup_failed" != true ]]
}

pgy_uninstall_background_services() {
    local service
    local cleanup_failed=false
    for service in pgytunnel-limiter pgytunnel-bandwidth pgy-ws-ssh-bridge \
        udp-custom udpgw tdzproxy; do
        systemctl stop "$service" >/dev/null 2>&1 || true
        systemctl disable "$service" >/dev/null 2>&1 || true
        systemctl is-active --quiet "$service" && cleanup_failed=true
    done
    if command -v pm2 >/dev/null 2>&1; then
        pm2 delete "$AUTO_BACKUP_PM2_NAME" >/dev/null 2>&1 || true
        pm2 save >/dev/null 2>&1 || true
        pm2 describe "$AUTO_BACKUP_PM2_NAME" >/dev/null 2>&1 && cleanup_failed=true
    fi
    pgy_remove_managed_trial_jobs || cleanup_failed=true
    rm -f "$LIMITER_SERVICE" "$LIMITER_SCRIPT" "$BANDWIDTH_SERVICE" "$BANDWIDTH_SCRIPT"
    rm -rf "$LEGACY_BANDWIDTH_DIR"
    rm -f "$TRIAL_CLEANUP_SCRIPT"
    [[ "$cleanup_failed" != true ]]
}

pgy_remove_legacy_dead_components() {
    rm -f "$LEGACY_UDP_SERVICE" "$LEGACY_UDPGW_SERVICE" \
        "$LEGACY_UDPGW_BINARY" "$LEGACY_PROXY_SERVICE" \
        "$LEGACY_PROXY_BINARY" "$LEGACY_PROXY_CONFIG"
    rm -rf "$LEGACY_UDP_DIR"
}

pgy_uninstall_optional_components() {
    local cleanup_failed=false
    if [[ -r "$EDGE_CERT_INFO_FILE" ]]; then
        load_edge_cert_info
        if [[ "$EDGE_CERT_MODE" == "certbot" && -n "$EDGE_DOMAIN" ]] && command -v certbot >/dev/null 2>&1; then
            certbot delete --cert-name "$EDGE_DOMAIN" --non-interactive >>"$PGY_CERTIFICATE_LOG" 2>&1 || cleanup_failed=true
        fi
    fi
    if declare -F pgy_openvpn_uninstall >/dev/null 2>&1; then
        pgy_openvpn_uninstall silent || cleanup_failed=true
    fi
    uninstall_zivpn || cleanup_failed=true
    uninstall_dnstt || cleanup_failed=true
    uninstall_badvpn || cleanup_failed=true
    pgy_remove_legacy_dead_components || cleanup_failed=true
    uninstall_ssl_tunnel || cleanup_failed=true
    purge_nginx silent || cleanup_failed=true
    rm -rf /etc/nginx
    if dpkg-query -W -f='${Status}' haproxy 2>/dev/null | grep -q 'install ok installed'; then
        pgy_apt_purge haproxy || cleanup_failed=true
    fi
    rm -rf /etc/haproxy
    if dpkg-query -W -f='${Status}' haproxy 2>/dev/null | grep -q 'install ok installed'; then
        cleanup_failed=true
    fi
    [[ "$cleanup_failed" != true ]]
}

pgy_uninstall_system_integration() {
    local cleanup_failed=false
    remove_ssh_auth_session_hook >/dev/null 2>&1 || cleanup_failed=true
    pgy_remove_recorded_firewall_rules || cleanup_failed=true
    pgy_remove_auto_reboot_job || cleanup_failed=true
    rm -f "$LOGIN_INFO_SCRIPT" "$SSHD_PGY_CONFIG" "$SSH_BANNER_FILE" || cleanup_failed=true
    rm -rf "$SSH_AUTH_SESSION_DIR" || cleanup_failed=true
    chattr -i "$PGY_RESOLV_CONF" >/dev/null 2>&1 || true
    systemctl reload sshd >/dev/null 2>&1 || systemctl reload ssh >/dev/null 2>&1 || true
    systemctl daemon-reload >/dev/null 2>&1 || true
    systemctl reset-failed >/dev/null 2>&1 || true
    [[ "$cleanup_failed" != true ]]
}

pgy_uninstall_application_files() {
    local diagnostic
    rm -f "$AUTO_BACKUP_CONF" "$AUTO_BACKUP_SCRIPT" "$AUTO_BACKUP_LOG"
    rm -rf "$AUTO_BACKUP_DIR" "$BADVPN_BUILD_DIR"
    rm -rf "$DB_DIR" "$PGY_LIB_DIR" "$PGY_OPT_LIB_DIR" "/pgy-lib" "$PGY_LICENSE_STATE_DIR"
    rm -f "$WS_SSH_BRIDGE_SCRIPT" "$WS_SSH_BRIDGE_SERVICE"
    rm -f "/etc/systemd/system/pgy-api.service" "/usr/local/bin/pgy_api_service.py" "/usr/local/bin/pgy-speedtest"
    rm -f "/usr/local/bin/pgy" "/usr/local/bin/pgy-update" "/usr/local/bin/pgy-license-check"
    for diagnostic in "$PGY_PACKAGE_LOG" "$PGY_CERTIFICATE_LOG" "$PGY_SERVICE_LOG" \
        "${PGY_OVPN_DIAG_LOG:-/var/log/pgy-openvpn-setup.log}"; do
        if [[ -s "$diagnostic" ]]; then
            printf '\n--- %s ---\n' "$diagnostic" >> "$PGY_UNINSTALL_LOG"
            tail -n 250 "$diagnostic" >> "$PGY_UNINSTALL_LOG" 2>/dev/null || true
        fi
        rm -f "$diagnostic"
    done
    systemctl daemon-reload >/dev/null 2>&1 || true
}

pgy_verify_uninstall_cleanup() {
    local path unit
    local -a leftovers=() managed_paths=(
        "$DB_DIR" "$PGY_LIB_DIR" "$PGY_OPT_LIB_DIR" \
        "$LIMITER_SERVICE" "$LIMITER_SCRIPT" "$BANDWIDTH_SERVICE" "$BANDWIDTH_SCRIPT" \
        "$TRIAL_CLEANUP_SCRIPT" "$SSHD_PGY_CONFIG" "$SSH_AUTH_SESSION_DIR" \
        "$SSH_BANNER_FILE" "$LOGIN_INFO_SCRIPT" \
        "$AUTO_BACKUP_CONF" "$AUTO_BACKUP_SCRIPT" "$AUTO_BACKUP_LOG" "$AUTO_BACKUP_DIR" \
        "$BADVPN_SERVICE_FILE" "$BADVPN_BUILD_DIR" "$DNSTT_SERVICE_FILE" "$DNSTT_BINARY" \
        "$DNSTT_KEYS_DIR" "$ZIVPN_SERVICE_FILE" "$ZIVPN_BIN" "$ZIVPN_DIR" \
        "$WS_SSH_BRIDGE_SERVICE" "$WS_SSH_BRIDGE_SCRIPT" "/etc/systemd/system/pgy-api.service" \
        "$LEGACY_UDP_DIR" "$LEGACY_UDP_SERVICE" "$LEGACY_UDPGW_BINARY" \
        "$LEGACY_UDPGW_SERVICE" "$LEGACY_PROXY_BINARY" "$LEGACY_PROXY_SERVICE" \
        "$LEGACY_PROXY_CONFIG" \
        /etc/nginx /etc/haproxy
    )
    if [[ -n "${PGY_OVPN_ROOT:-}" ]]; then
        managed_paths+=(
            "$PGY_OVPN_ROOT" "$PGY_OVPN_PORTAL_BASE" "$PGY_OVPN_PAM_SERVICE"
            "$PGY_OVPN_SYSCTL" "$PGY_OVPN_FIREWALL"
        )
        if declare -F pgy_openvpn_managed_runtime_files >/dev/null 2>&1; then
            while IFS= read -r path; do
                [[ -n "$path" ]] && managed_paths+=("$path")
            done < <(pgy_openvpn_managed_runtime_files)
        fi
    fi
    for path in "${managed_paths[@]}"; do
        [[ -e "$path" || -L "$path" ]] && leftovers+=("$path")
    done
    for unit in pgytunnel-limiter pgytunnel-bandwidth pgy-ws-ssh-bridge pgy-api \
        badvpn dnstt zivpn haproxy nginx udp-custom udpgw tdzproxy \
        pgy-openvpn-network pgy-openvpn-tcp pgy-openvpn-udp pgy-openvpn-http \
        pgy-openvpn-wss pgy-openvpn-ssl pgy-openvpn-portal pgy-openvpn-accounting; do
        if systemctl is-active --quiet "$unit.service" 2>/dev/null; then
            leftovers+=("active service: $unit.service")
        fi
    done
    if (( ${#leftovers[@]} > 0 )); then
        printf 'Cleanup verification found remaining items:\n' >> "$PGY_UNINSTALL_LOG"
        printf '  %s\n' "${leftovers[@]}" >> "$PGY_UNINSTALL_LOG"
        return 1
    fi
    rm -f "$PGY_MENU_BINARY" "/usr/local/bin/pgy" "/usr/local/bin/pgy-update" "/usr/local/bin/pgy-license-check" || return 1
    [[ ! -e "$PGY_MENU_BINARY" && ! -L "$PGY_MENU_BINARY" ]]
}

uninstall_script() {
    clear; show_banner
    pgy_screen_title "UNINSTALL PGY SSH TUNNEL" \
        "Permanently remove the script, services, and configuration." "$C_DANGER"
    pgy_message WARNING "This permanently removes managed services, configuration, backups, and optional components. It cannot be undone."
    read -r -p "  Type 'yes' to confirm and proceed with uninstallation: " confirm
    if [[ "$confirm" != "yes" ]]; then
        pgy_message CANCELLED "Uninstallation cancelled."
        return
    fi

    local -a removable_users=()
    local remove_users_confirm="n" remove_users_on_uninstall=false
    local uninstall_failed=false
    mapfile -t removable_users < <(get_pgytunnel_known_users)
    if [[ ${#removable_users[@]} -gt 0 ]]; then
        echo -e "\n${C_YELLOW}Managed SSH users:${C_RESET} ${removable_users[*]}"
        read -r -p "  Permanently delete these SSH users too? (y/n): " remove_users_confirm
        [[ "$remove_users_confirm" == "y" || "$remove_users_confirm" == "Y" ]] && remove_users_on_uninstall=true
    fi

    export UNINSTALL_MODE="silent"
    mkdir -p "$(dirname "$PGY_UNINSTALL_LOG")" 2>/dev/null || true
    : > "$PGY_UNINSTALL_LOG"
    chmod 600 "$PGY_UNINSTALL_LOG" 2>/dev/null || true
    local PGY_ACTION_LOG="$PGY_UNINSTALL_LOG"
    echo
    pgy_section "UNINSTALLATION PROGRESS"

    if [[ "$remove_users_on_uninstall" == "true" ]]; then
        pgy_progress_run 1 6 "Removing selected accounts" delete_pgytunnel_user_accounts "${removable_users[@]}" || uninstall_failed=true
    else
        pgy_progress_run 1 6 "Preserving managed accounts" true || uninstall_failed=true
    fi
    pgy_progress_run 2 6 "Stopping background services" pgy_uninstall_background_services || uninstall_failed=true
    pgy_progress_run 3 6 "Removing optional components" pgy_uninstall_optional_components || uninstall_failed=true
    pgy_progress_run 4 6 "Restoring system integration" pgy_uninstall_system_integration || uninstall_failed=true
    pgy_progress_run 5 6 "Removing application files" pgy_uninstall_application_files || uninstall_failed=true
    pgy_progress_run 6 6 "Verifying cleanup" pgy_verify_uninstall_cleanup || uninstall_failed=true

    pgy_box_close_if_open

    if [[ "$uninstall_failed" == true ]]; then
        echo
        pgy_message ERROR "Cleanup finished with one or more items requiring attention."
        echo -e "${C_DIM}Diagnostic details: ${PGY_UNINSTALL_LOG}${C_RESET}"
        exit 1
    fi
    rm -f "$PGY_UNINSTALL_LOG"
    echo
    pgy_message OK "ProgoCloud Script SSH Premium was removed successfully."
    exit 0
}

# --- NEW FEATURES ---

