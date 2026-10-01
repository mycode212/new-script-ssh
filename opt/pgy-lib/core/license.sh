#!/bin/bash
# ============================================================
# Auto Script SSH By : ProgoCloud
# Module: core/license.sh - License guard & enforcement
# ============================================================

PGY_LICENSE_BLOCKED=0
PGY_LICENSE_BLOCK_REASON=""

pgy_license_trusted_default_api_url() {
    printf '%s\n' "https://autoscript-license.worker-balancer-mang.workers.dev/api/v1/license/check"
}

pgy_license_guard_config_file() {
    printf '%s\n' "/etc/pgytunnel/license/config.env"
}

pgy_license_guard_bin_path() {
    # Check installed binary first, then local repo binary
    if [[ -x "/usr/local/bin/pgy-license-check" ]]; then
        printf '%s\n' "/usr/local/bin/pgy-license-check"
    elif [[ -x "/pgy-lib/opt/bin/pgy-license-check" ]]; then
        printf '%s\n' "/pgy-lib/opt/bin/pgy-license-check"
    elif [[ -n "${PGY_SOURCE_DIR:-}" && -x "${PGY_SOURCE_DIR}/opt/pgy-lib/bin/pgy-license-check" ]]; then
        printf '%s\n' "${PGY_SOURCE_DIR}/opt/pgy-lib/bin/pgy-license-check"
    else
        local script_dir
        script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd || true)"
        if [[ -x "${script_dir}/bin/pgy-license-check" ]]; then
            printf '%s\n' "${script_dir}/bin/pgy-license-check"
        else
            printf '%s\n' "/usr/local/bin/pgy-license-check"
        fi
    fi
}

pgy_license_guard_api_url() {
    local configured=""
    local env_file
    env_file="$(pgy_license_guard_config_file)"
    if [[ -r "${env_file}" ]]; then
        configured=$(awk -F= '$1 == "PGY_LICENSE_API_URL" {gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2; exit}' "${env_file}" 2>/dev/null || true)
    fi
    if [[ -n "${configured}" ]]; then
        printf '%s\n' "${configured}"
    else
        pgy_license_trusted_default_api_url
    fi
}

pgy_license_guard_preflight() {
    local stage="${1:-menu}"
    local license_bin api_url config_file default_api_url license_output

    PGY_LICENSE_BLOCKED=0
    PGY_LICENSE_BLOCK_REASON=""

    license_bin="$(pgy_license_guard_bin_path)"
    api_url="$(pgy_license_guard_api_url)"
    config_file="$(pgy_license_guard_config_file)"
    default_api_url="$(pgy_license_trusted_default_api_url)"

    if [[ ! -x "${license_bin}" ]]; then
        # If binary is missing, attempt to run directly using python3 if source exists
        local bin_dir
        bin_dir="$(dirname "${license_bin}")"
        if [[ -f "${license_bin}" ]]; then
            license_bin="python3 ${license_bin}"
        else
            echo "[WARN] Binary license guard tidak ditemukan: ${license_bin}" >&2
            return 0
        fi
    fi

    if ! license_output="$(
        PGY_LICENSE_DEFAULT_API_URL="${default_api_url}" \
        PGY_LICENSE_API_URL="${api_url}" \
        PGY_LICENSE_CONFIG_FILE="${config_file}" \
        ${license_bin} check --stage "${stage}" --allow-disabled=false 2>&1
    )"; then
        PGY_LICENSE_BLOCKED=1
        PGY_LICENSE_BLOCK_REASON="${license_output}"
        if [[ "${stage}" == "install" || "${stage}" == "run" ]]; then
            echo -e "${C_RED}[ERROR] Validasi Lisensi Gagal!${C_RESET}" >&2
            echo -e "${license_output}" >&2
            return 1
        fi
        return 1
    fi
    return 0
}

pgy_display_license_block_screen() {
    pgy_refresh_box_width
    [[ -t 1 ]] && clear
    echo
    pgy_box_top "$C_DANGER"
    pgy_box_header "PROGOCLOUD LICENSE GUARD" "$C_DANGER"
    pgy_box_divider "$C_DANGER"
    pgy_row "$(printf "${C_RED}${C_BOLD}[AKSES DITOLAK] Lisensi VPS Tidak Aktif / Belum Terdaftar${C_RESET}")" "$C_DANGER"
    pgy_box_divider "$C_DANGER"
    
    local ip_val
    ip_val=$(curl -4 -s --max-time 4 ifconfig.me 2>/dev/null || echo "N/A")
    pgy_row "$(printf "${C_GRAY}IP VPS :${C_RESET} ${C_WHITE}%s${C_RESET}" "$ip_val")" "$C_DANGER"
    pgy_box_divider "$C_DANGER"
    
    if [[ -n "${PGY_LICENSE_BLOCK_REASON}" ]]; then
        while IFS= read -r line; do
            [[ -n "$line" ]] || continue
            pgy_row "$(printf "${C_YELLOW}%s${C_RESET}" "${line:0:$((PGY_BOX_WIDTH-4))}")" "$C_DANGER"
        done <<< "${PGY_LICENSE_BLOCK_REASON}"
        pgy_box_divider "$C_DANGER"
    fi

    pgy_row "$(printf "${C_WHITE}Untuk aktivasi atau perpanjangan lisensi, hubungi:${C_RESET}")" "$C_DANGER"
    pgy_row "$(printf "${C_CYAN}Telegram  :${C_RESET} ${C_WHITE}https://t.me/progocloud${C_RESET}")" "$C_DANGER"
    pgy_row "$(printf "${C_CYAN}Website   :${C_RESET} ${C_WHITE}https://autoscript.license.dpdns.org${C_RESET}")" "$C_DANGER"
    pgy_box_bot "$C_DANGER"
    echo
}
