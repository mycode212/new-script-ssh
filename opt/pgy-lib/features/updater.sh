#!/bin/bash
# ============================================================
# Auto Script SSH By : ProgoCloud
# Module: features/updater.sh - Script Updater & Module Sync
# ============================================================

PGY_UPDATE_DEFAULT_REPO_URL="${PGY_UPDATE_DEFAULT_REPO_URL:-https://github.com/mycode212/autoscript.git}"
PGY_UPDATE_BRANCH="${PGY_UPDATE_BRANCH:-main}"

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

    local current_dir
    current_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd || true)"

    # If current directory is a git repo, attempt git pull
    if [[ -d "${current_dir}/.git" ]]; then
        echo -e "  Sinkronisasi git repository lokal..."
        if git -C "${current_dir}" pull origin "${PGY_UPDATE_BRANCH}" 2>&1; then
            pgy_message ok "Git repo berhasil diperbarui."
        else
            pgy_message warn "Git pull gagal, beralih ke sinkronisasi berkas modular..."
        fi
    fi

    # Perform atomic sync of modules to /pgy-lib/opt and /usr/local/lib/pgy-ssh-tunnel
    if [[ -d "${current_dir}/opt/pgy-lib" ]]; then
        echo -e "  Sinkronisasi modul /pgy-lib/opt ..."
        mkdir -p /pgy-lib/opt
        cp -a "${current_dir}/opt/pgy-lib/." /pgy-lib/opt/ 2>/dev/null || true
        chmod -R 755 /pgy-lib/opt 2>/dev/null || true

        mkdir -p "${PGY_LIB_DIR}"
        cp -a "${current_dir}/opt/pgy-lib/." "${PGY_LIB_DIR}/" 2>/dev/null || true
        chmod -R 755 "${PGY_LIB_DIR}" 2>/dev/null || true
    fi

    # Copy Python helper scripts to PGY_LIB_DIR
    for py_script in pgy_openvpn_gateway.py pgy_openvpn_portal.py pgy_openvpn_runtime.py pgy_ssh_auth_session.py pgy_ws_ssh_bridge.py openvpn_module.sh; do
        if [[ -f "${current_dir}/${py_script}" ]]; then
            cp -a "${current_dir}/${py_script}" "${PGY_LIB_DIR}/${py_script}" 2>/dev/null || true
            cp -a "${current_dir}/${py_script}" "/pgy-lib/opt/${py_script}" 2>/dev/null || true
            chmod 755 "${PGY_LIB_DIR}/${py_script}" "/pgy-lib/opt/${py_script}" 2>/dev/null || true
        fi
    done

    # Update binaries
    if [[ -f "${current_dir}/menu.sh" ]]; then
        install -m 755 "${current_dir}/menu.sh" /usr/local/bin/menu
        install -m 755 "${current_dir}/menu.sh" /usr/local/bin/pgy
    fi

    if [[ -f "${current_dir}/opt/pgy-lib/bin/pgy-license-check" ]]; then
        install -m 755 "${current_dir}/opt/pgy-lib/bin/pgy-license-check" /usr/local/bin/pgy-license-check
    fi

    # Create shortcut for update
    cat <<'EOF' > /usr/local/bin/pgy-update
#!/bin/bash
/usr/local/bin/menu --update-script "$@"
EOF
    chmod 755 /usr/local/bin/pgy-update

    # Restart core tunnel services if running to apply changes
    systemctl is-active --quiet pgy-ws-ssh-bridge && systemctl restart pgy-ws-ssh-bridge >/dev/null 2>&1 || true
    systemctl is-active --quiet haproxy && systemctl restart haproxy >/dev/null 2>&1 || true
    systemctl is-active --quiet nginx && systemctl restart nginx >/dev/null 2>&1 || true

    echo
    pgy_message ok "Pembaruan script Auto Script SSH ProgoCloud berhasil diselesaikan!"
    echo -e "  Versi aktif: ${C_CYAN}${PGY_VERSION_TAG}${C_RESET}"
    echo
}
