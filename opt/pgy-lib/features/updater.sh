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
    if (( PGY_UPDATE_CHECK_TS > 0 && now - PGY_UPDATE_CHECK_TS < 30 )); then
        return 0
    fi
    PGY_UPDATE_CHECK_TS=$now

    local local_ver
    local_ver="$(get_pgy_installed_version 2>/dev/null || echo "${PGY_SCRIPT_VERSION:-0.0.1}")"

    local remote_ver=""
    remote_ver=$(curl -fsSL --retry 2 --max-time 5 "${REPO_URL}/version.txt?t=${now}" 2>/dev/null | tr -d ' \r\n\t')
    if [[ -z "$remote_ver" ]]; then
        remote_ver=$(curl -fsSL --retry 2 --max-time 5 "https://raw.githubusercontent.com/mycode212/new-script-ssh/main/version.txt?t=${now}" 2>/dev/null | tr -d ' \r\n\t')
    fi
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
    clear; show_banner
    echo

    if [[ $EUID -ne 0 ]]; then
        echo -e "${C_RED}[ERROR] Update script harus dijalankan sebagai root.${C_RESET}"
        press_enter
        return 1
    fi

    # Parse arguments for force mode
    local force_mode=false
    local arg
    for arg in "$@"; do
        if [[ "$arg" == "--force" || "$arg" == "-f" ]]; then
            force_mode=true
        fi
    done

    # Preflight license check before updating
    if ! pgy_license_guard_preflight "setup"; then
        pgy_display_license_block_screen
        return 1
    fi

    local local_ver
    local_ver="$(get_pgy_installed_version 2>/dev/null || echo "${PGY_SCRIPT_VERSION:-0.0.1}")"

    local now
    now=$(date +%s)
    local remote_ver=""
    remote_ver=$(curl -fsSL --retry 2 --max-time 5 "${REPO_URL}/version.txt?t=${now}" 2>/dev/null | tr -d ' \r\n\t')
    if [[ -z "$remote_ver" ]]; then
        remote_ver=$(curl -fsSL --retry 2 --max-time 5 "https://raw.githubusercontent.com/mycode212/new-script-ssh/main/version.txt?t=${now}" 2>/dev/null | tr -d ' \r\n\t')
    fi

    # Check if update is needed
    if [[ "$force_mode" == false ]]; then
        if [[ -z "$remote_ver" ]]; then
            echo -e "  ${C_YELLOW}▶ CEK PEMBARUAN SCRIPT${C_RESET}"
            echo -e "  ${C_RED}[ERROR] Gagal memeriksa versi terbaru dari server repository.${C_RESET}"
            echo -e "  ${C_GRAY}Versi lokal saat ini : ${C_WHITE}${local_ver}${C_RESET}"
            echo -e "  ${C_GRAY}Gunakan ${C_YELLOW}pgy-update --force${C_GRAY} jika ingin melakukan update paksa.${C_RESET}"
            echo
            press_enter
            return 0
        fi

        if ! pgy_is_newer_version "$remote_ver" "$local_ver"; then
            echo -e "  ${C_CYAN}▶ CEK PEMBARUAN SCRIPT${C_RESET}"
            echo -e "  ${C_GREEN}[✓] Script sudah menggunakan versi terbaru: ${C_WHITE}${C_BOLD}${local_ver}${C_RESET}"
            echo -e "  ${C_GRAY}Tidak ada pembaruan baru yang tersedia saat ini.${C_RESET}"
            echo -e "  ${C_GRAY}Ketik ${C_YELLOW}pgy-update --force${C_GRAY} untuk update paksa / reinstall.${C_RESET}"
            echo
            press_enter
            return 0
        fi
    fi

    echo -e "  ${C_CYAN}▶ MEMPERBARUI SCRIPT PROGOCLOUD${C_RESET}"

    pgy_progress_begin 1 4 "Memeriksa validasi lisensi VPS"
    sleep 0.3
    pgy_progress_done

    if [[ "$force_mode" == true ]]; then
        pgy_progress_begin 2 4 "Mengunduh berkas script (Force Reinstall: ${local_ver})"
    else
        pgy_progress_begin 2 4 "Mengunduh pembaruan (${local_ver} -> ${remote_ver})"
    fi

    local work_dir
    work_dir="$(mktemp -d /tmp/pgy-update.XXXXXX)"
    cleanup_update() {
        rm -rf "$work_dir" 2>/dev/null || true
    }
    trap cleanup_update RETURN

    local repo_url="${GIT_REPO_URL:-https://github.com/mycode212/new-script-ssh.git}"
    local src_dir="${work_dir}/repo"
    rm -rf "${src_dir}"

    local download_ok=false
    if command -v git >/dev/null 2>&1 && git clone --depth=1 -b main "${repo_url}" "${src_dir}" >/dev/null 2>&1; then
        download_ok=true
    fi

    if [[ "$download_ok" == false ]]; then
        mkdir -p "${src_dir}"
        if curl -fsSL --retry 3 --max-time 30 "https://github.com/mycode212/new-script-ssh/archive/refs/heads/main.tar.gz?t=$(date +%s)" | tar -xz -C "${src_dir}" --strip-components=1 2>/dev/null; then
            download_ok=true
        fi
    fi

    if [[ "$download_ok" == false || ! -d "${src_dir}/opt/pgy-lib" || ! -f "${src_dir}/menu.sh" ]]; then
        pgy_progress_failed
        echo
        echo -e "  ${C_RED}[ERROR] Gagal mengunduh atau struktur pembaruan tidak lengkap.${C_RESET}"
        press_enter
        return 1
    fi
    pgy_progress_done

    pgy_progress_begin 3 4 "Menyinkronkan modul dan berkas binary"
    mkdir -p /pgy-lib/opt "${PGY_LIB_DIR}" "${DB_DIR}"

    # Perform atomic sync of modules to /pgy-lib/opt and /usr/local/lib/pgy-ssh-tunnel
    if [[ -d "${src_dir}/opt/pgy-lib" ]]; then
        cp -a "${src_dir}/opt/pgy-lib/." /pgy-lib/opt/ 2>/dev/null || true
        cp -a "${src_dir}/opt/pgy-lib/." "${PGY_LIB_DIR}/" 2>/dev/null || true
        if [[ -n "${PGY_SOURCE_DIR:-}" && -d "${PGY_SOURCE_DIR}/opt/pgy-lib" ]]; then
            cp -a "${src_dir}/opt/pgy-lib/." "${PGY_SOURCE_DIR}/opt/pgy-lib/" 2>/dev/null || true
        fi
        chmod -R 755 /pgy-lib/opt "${PGY_LIB_DIR}" 2>/dev/null || true
    fi

    # Sync version.txt
    if [[ -f "${src_dir}/version.txt" ]]; then
        install -m 644 "${src_dir}/version.txt" /pgy-lib/opt/version.txt 2>/dev/null || true
        install -m 644 "${src_dir}/version.txt" "${PGY_LIB_DIR}/version.txt" 2>/dev/null || true
        install -m 644 "${src_dir}/version.txt" "${DB_DIR}/version.txt" 2>/dev/null || true
        if [[ -n "${PGY_SOURCE_DIR:-}" && -d "${PGY_SOURCE_DIR}" ]]; then
            install -m 644 "${src_dir}/version.txt" "${PGY_SOURCE_DIR}/version.txt" 2>/dev/null || true
        fi
    fi

    # Copy Python helper scripts and standalone modules
    for py_script in pgy_openvpn_gateway.py pgy_openvpn_portal.py pgy_openvpn_runtime.py pgy_ssh_auth_session.py pgy_ws_ssh_bridge.py openvpn_module.sh; do
        if [[ -f "${src_dir}/${py_script}" ]]; then
            cp -a "${src_dir}/${py_script}" "${PGY_LIB_DIR}/${py_script}" 2>/dev/null || true
            cp -a "${src_dir}/${py_script}" "/pgy-lib/opt/${py_script}" 2>/dev/null || true
            if [[ -n "${PGY_SOURCE_DIR:-}" && -d "${PGY_SOURCE_DIR}" ]]; then
                cp -a "${src_dir}/${py_script}" "${PGY_SOURCE_DIR}/${py_script}" 2>/dev/null || true
            fi
            chmod 755 "${PGY_LIB_DIR}/${py_script}" "/pgy-lib/opt/${py_script}" 2>/dev/null || true
        fi
    done

    # Update binaries
    if [[ -f "${src_dir}/menu.sh" ]]; then
        install -m 755 "${src_dir}/menu.sh" /usr/local/bin/menu
        install -m 755 "${src_dir}/menu.sh" /usr/local/bin/pgy
        if [[ -n "${PGY_SOURCE_DIR:-}" && -d "${PGY_SOURCE_DIR}" ]]; then
            install -m 755 "${src_dir}/menu.sh" "${PGY_SOURCE_DIR}/menu.sh" 2>/dev/null || true
        fi
    fi

    if [[ -f "${src_dir}/install.sh" ]]; then
        install -m 755 "${src_dir}/install.sh" /usr/local/bin/pgy-install 2>/dev/null || true
        if [[ -n "${PGY_SOURCE_DIR:-}" && -d "${PGY_SOURCE_DIR}" ]]; then
            install -m 755 "${src_dir}/install.sh" "${PGY_SOURCE_DIR}/install.sh" 2>/dev/null || true
        fi
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

    pgy_progress_done

    pgy_progress_begin 4 4 "Memverifikasi dan memuat ulang layanan"

    # Restart core tunnel services if running to apply changes
    systemctl is-active --quiet pgytunnel-limiter 2>/dev/null && systemctl restart pgytunnel-limiter >/dev/null 2>&1 || true
    systemctl is-active --quiet pgy-ws-ssh-bridge 2>/dev/null && systemctl restart pgy-ws-ssh-bridge >/dev/null 2>&1 || true
    systemctl is-active --quiet haproxy 2>/dev/null && systemctl restart haproxy >/dev/null 2>&1 || true
    systemctl is-active --quiet nginx 2>/dev/null && systemctl restart nginx >/dev/null 2>&1 || true

    # Refresh dynamic banners if enabled
    if declare -F refresh_dynamic_banner_routing_if_enabled >/dev/null 2>&1; then
        refresh_dynamic_banner_routing_if_enabled >/dev/null 2>&1 || true
    fi

    pgy_progress_done

    local new_ver
    new_ver="$(get_pgy_installed_version 2>/dev/null || echo "${remote_ver:-0.1.1}")"

    echo
    echo -e "  ${C_GREEN}${C_BOLD}[OK] Pembaruan script berhasil ke versi ${new_ver}!${C_RESET}"
    echo -e "  ${C_GRAY}Memuat ulang menu console dalam 2 detik...${C_RESET}"
    echo
    sleep 2
    exec /usr/local/bin/menu
}
