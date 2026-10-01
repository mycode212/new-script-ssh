#!/bin/bash
# ============================================================
# Auto Script SSH By : ProgoCloud
# Module: features/updater.sh - Script Updater & Module Sync
# ============================================================

PGY_UPDATE_DEFAULT_REPO_URL="${PGY_REPO_URL:-https://github.com/mycode212/new-script-ssh.git}"
PGY_UPDATE_BRANCH="${PGY_REPO_BRANCH:-main}"
PGY_UPDATE_CHECK_TS=0
PGY_UPDATE_AVAILABLE=false
PGY_LATEST_VERSION="${PGY_SCRIPT_VERSION:-0.0.1}"

check_script_update_available() {
    local now
    now=$(date +%s)
    if (( PGY_UPDATE_CHECK_TS > 0 && now - PGY_UPDATE_CHECK_TS < 60 )); then
        return 0
    fi
    PGY_UPDATE_CHECK_TS=$now

    local local_ver
    local_ver="$(get_pgy_installed_version 2>/dev/null || echo "${PGY_SCRIPT_VERSION:-0.0.1}")"

    local remote_ver=""
    remote_ver=$(curl -s --max-time 4 "${REPO_URL}/version.txt" 2>/dev/null | tr -d ' \r\n\t')
    if [[ -n "$remote_ver" ]] && pgy_is_newer_version "$remote_ver" "$local_ver"; then
        PGY_UPDATE_AVAILABLE=true
        PGY_LATEST_VERSION="$remote_ver"
    else
        PGY_UPDATE_AVAILABLE=false
        PGY_LATEST_VERSION="$local_ver"
    fi
}

show_script_update_box_if_available() {
    local local_ver
    local_ver="$(get_pgy_installed_version 2>/dev/null || echo "${PGY_SCRIPT_VERSION:-0.0.1}")"
    if [[ "${PGY_UPDATE_AVAILABLE:-false}" == "true" && -n "${PGY_LATEST_VERSION:-}" ]] && pgy_is_newer_version "${PGY_LATEST_VERSION}" "$local_ver"; then
        echo
        pgy_box_top "$C_YELLOW"
        pgy_box_header "SCRIPT UPDATE" "$C_YELLOW" "$C_YELLOW"
        pgy_box_divider "$C_YELLOW"
        pgy_row "$(printf "${C_GRAY}Versi Sekarang  :${C_RESET} ${C_WHITE}%s${C_RESET}" "$local_ver")" "$C_YELLOW"
        pgy_row "$(printf "${C_GRAY}Versi Pembaruan :${C_RESET} ${C_GREEN}${C_BOLD}%s${C_RESET}" "${PGY_LATEST_VERSION}")" "$C_YELLOW"
        pgy_box_divider "$C_YELLOW"
        pgy_row "$(printf "${C_YELLOW}Ketik ${C_BOLD}pgy-update${C_RESET}${C_YELLOW} atau pilih menu [23] untuk update${C_RESET}")" "$C_YELLOW"
        pgy_box_bot "$C_YELLOW"
    fi
}

update_script() {
    pgy_screen_title "UPDATE SCRIPT" "Memperbarui modul dan binary script ProgoCloud"

    if [[ $EUID -ne 0 ]]; then
        echo -e "${C_RED}[ERROR] Update script harus dijalankan sebagai root.${C_RESET}"
        return 1
    fi

    # Preflight license check before updating
    pgy_section "VALIDASI LISENSI"
    if ! pgy_license_guard_preflight "setup"; then
        pgy_display_license_block_screen
        return 1
    fi
    pgy_message ok "Lisensi VPS valid dan aktif."

    pgy_section "PEMBARUAN SCRIPT"
    echo -e "  Mengunduh pembaruan script terbaru dari server repository..."

    local work_dir
    work_dir="$(mktemp -d /tmp/pgy-update.XXXXXX)"
    cleanup_update() {
        rm -rf "$work_dir" 2>/dev/null || true
    }
    trap cleanup_update RETURN

    local repo_url="${GIT_REPO_URL:-https://github.com/mycode212/new-script-ssh.git}"
    local src_dir="${work_dir}/repo"
    mkdir -p "${src_dir}"

    if command -v git >/dev/null 2>&1 && git clone --depth=1 -b main "${repo_url}" "${src_dir}" >/dev/null 2>&1; then
        echo -e "  Repository berhasil diunduh via Git."
    else
        echo -e "  Mengunduh arsip paket rilis..."
        curl -Ls "https://github.com/mycode212/new-script-ssh/archive/refs/heads/main.tar.gz" | tar -xz -C "${src_dir}" --strip-components=1 2>/dev/null || {
            pgy_message danger "Gagal mengunduh pembaruan dari repository: ${repo_url}"
            return 1
        }
    fi

    if [[ ! -d "${src_dir}/opt/pgy-lib" && ! -f "${src_dir}/menu.sh" ]]; then
        pgy_message danger "Struktur berkas pembaruan tidak lengkap."
        return 1
    fi

    echo -e "  Sinkronisasi modul /pgy-lib/opt dan binary sistem..."
    mkdir -p /pgy-lib/opt "${PGY_LIB_DIR}"

    # Perform atomic sync of modules to /pgy-lib/opt and /usr/local/lib/pgy-ssh-tunnel
    if [[ -d "${src_dir}/opt/pgy-lib" ]]; then
        cp -a "${src_dir}/opt/pgy-lib/." /pgy-lib/opt/ 2>/dev/null || true
        cp -a "${src_dir}/opt/pgy-lib/." "${PGY_LIB_DIR}/" 2>/dev/null || true
        chmod -R 755 /pgy-lib/opt "${PGY_LIB_DIR}" 2>/dev/null || true
    fi

    # Sync version.txt
    if [[ -f "${src_dir}/version.txt" ]]; then
        install -m 644 "${src_dir}/version.txt" /pgy-lib/opt/version.txt
        install -m 644 "${src_dir}/version.txt" "${PGY_LIB_DIR}/version.txt"
        install -m 644 "${src_dir}/version.txt" "${DB_DIR}/version.txt"
    fi

    # Copy Python helper scripts
    for py_script in pgy_openvpn_gateway.py pgy_openvpn_portal.py pgy_openvpn_runtime.py pgy_ssh_auth_session.py pgy_ws_ssh_bridge.py openvpn_module.sh; do
        if [[ -f "${src_dir}/${py_script}" ]]; then
            cp -a "${src_dir}/${py_script}" "${PGY_LIB_DIR}/${py_script}" 2>/dev/null || true
            cp -a "${src_dir}/${py_script}" "/pgy-lib/opt/${py_script}" 2>/dev/null || true
            chmod 755 "${PGY_LIB_DIR}/${py_script}" "/pgy-lib/opt/${py_script}" 2>/dev/null || true
        fi
    done

    # Update binaries
    if [[ -f "${src_dir}/menu.sh" ]]; then
        install -m 755 "${src_dir}/menu.sh" /usr/local/bin/menu
        install -m 755 "${src_dir}/menu.sh" /usr/local/bin/pgy
    fi

    if [[ -f "${src_dir}/opt/pgy-lib/bin/pgy-license-check" ]]; then
        install -m 755 "${src_dir}/opt/pgy-lib/bin/pgy-license-check" /usr/local/bin/pgy-license-check
    fi

    # Create shortcut for update
    cat <<'EOF' > /usr/local/bin/pgy-update
#!/bin/bash
/usr/local/bin/menu --update-script "$@"
EOF
    chmod 755 /usr/local/bin/pgy-update

    # Restart core tunnel services if running to apply changes
    systemctl is-active --quiet pgy-ws-ssh-bridge 2>/dev/null && systemctl restart pgy-ws-ssh-bridge >/dev/null 2>&1 || true
    systemctl is-active --quiet haproxy 2>/dev/null && systemctl restart haproxy >/dev/null 2>&1 || true
    systemctl is-active --quiet nginx 2>/dev/null && systemctl restart nginx >/dev/null 2>&1 || true

    echo
    pgy_message ok "Pembaruan script Auto Script SSH ProgoCloud berhasil diselesaikan!"
    echo -e "  Versi aktif: ${C_CYAN}$(get_pgy_installed_version)${C_RESET}"
    echo
}
