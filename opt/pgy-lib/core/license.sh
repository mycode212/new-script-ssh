#!/bin/bash
# ============================================================
# Auto Script SSH By : ProgoCloud
# Module: core/license.sh - License guard & enforcement
# ============================================================

PGY_LICENSE_BLOCKED=0
PGY_LICENSE_BLOCK_REASON=""

pgy_license_trusted_default_api_url() {
    printf '%s\n' "${PGY_LICENSE_API_DEFAULT_URL:-https://autoscript-license.worker-balancer-mang.workers.dev/api/v1/license/check}"
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
    ip_val=$(curl -4 -s --max-time 4 ifconfig.me 2>/dev/null || curl -4 -s --max-time 4 api.ipify.org 2>/dev/null || echo "N/A")
    pgy_row "$(printf "${C_GRAY}IP VPS   :${C_RESET} ${C_WHITE}%s${C_RESET}" "$ip_val")" "$C_DANGER"
    pgy_box_divider "$C_DANGER"
    
    if [[ -n "${PGY_LICENSE_BLOCK_REASON}" ]]; then
        while IFS= read -r line; do
            [[ -n "$line" ]] || continue
            pgy_row "$(printf "${C_YELLOW}%s${C_RESET}" "$line")" "$C_DANGER"
        done <<< "${PGY_LICENSE_BLOCK_REASON}"
        pgy_box_divider "$C_DANGER"
    fi

    pgy_row "$(printf "${C_WHITE}Untuk aktivasi atau perpanjangan lisensi, hubungi:${C_RESET}")" "$C_DANGER"
    pgy_row "$(printf "${C_CYAN}Telegram :${C_RESET} ${C_WHITE}https://t.me/progocloud${C_RESET}")" "$C_DANGER"
    pgy_row "$(printf "${C_CYAN}Website  :${C_RESET} ${C_WHITE}https://autoscript-license-3xj.pages.dev${C_RESET}")" "$C_DANGER"
    pgy_box_bot "$C_DANGER"
    echo
}

pgy_license_show_status() {
    clear; show_banner
    pgy_screen_title "STATUS LISENSI" "Informasi lisensi VPS ProgoCloud"

    local license_bin
    license_bin="$(pgy_license_guard_bin_path)"
    local raw_out=""
    if [[ -x "${license_bin}" ]]; then
        raw_out="$("${license_bin}" status 2>&1)"
    elif [[ -f "${PGY_LIB_DIR}/pgy-license-check" ]]; then
        raw_out="$(python3 "${PGY_LIB_DIR}/pgy-license-check" status 2>&1)"
    elif [[ -f "/pgy-lib/opt/bin/pgy-license-check" ]]; then
        raw_out="$(python3 "/pgy-lib/opt/bin/pgy-license-check" status 2>&1)"
    fi

    local st_status="" st_reason="" st_ip="" st_until="" st_next=""
    local line k v
    while IFS= read -r line; do
        line=$(echo "$line" | tr -d '\r')
        [[ -z "$line" ]] && continue
        if [[ "$line" =~ ^([A-Za-z0-9_]+)[[:space:]]*:[[:space:]]*(.*)$ ]]; then
            k="${BASH_REMATCH[1]}"
            v="${BASH_REMATCH[2]}"
            case "$k" in
                Status) st_status="$v" ;;
                Reason) st_reason="$v" ;;
                IP)     st_ip="$v" ;;
                Until)  st_until="$v" ;;
                Next)   st_next="$v" ;;
            esac
        fi
    done <<< "$raw_out"

    local status_color="$C_GREEN"
    local status_text="ALLOWED (AKTIF)"
    if [[ "$st_status" != "allowed" && "$st_status" != "active" ]]; then
        status_color="$C_RED"
        status_text="${st_status^^}"
        [[ -z "$status_text" ]] && status_text="TIDAK AKTIF / DITOLAK"
    fi

    echo
    pgy_box_top "$C_CYAN"
    pgy_box_header "DETAIL LISENSI VPS" "$C_CYAN"
    pgy_box_divider "$C_CYAN"
    pgy_detail "Status Lisensi" "${status_color}${status_text}${C_RESET}" "$C_CYAN"
    [[ -n "$st_ip" ]] && pgy_detail "IP VPS" "$st_ip" "$C_CYAN"
    [[ -n "$st_reason" ]] && pgy_detail "Keterangan" "$st_reason" "$C_CYAN"
    if [[ -n "$st_until" && "$st_until" != "none" ]]; then
        pgy_detail "Masa Aktif" "$st_until" "$C_CYAN"
    else
        pgy_detail "Masa Aktif" "Lifetime / Unlimited" "$C_CYAN"
    fi
    if [[ -n "$st_next" && "$st_next" != "none" ]]; then
        pgy_detail "Cek Otomatis" "$st_next" "$C_CYAN"
    fi
    pgy_box_divider "$C_CYAN"
    pgy_detail "Portal Lisensi" "${PGY_LICENSE_PORTAL_URL:-https://autoscript-license-3xj.pages.dev}" "$C_CYAN"
    pgy_detail "Support CS" "https://t.me/progocloud" "$C_CYAN"
    pgy_box_bot "$C_CYAN"
    press_enter
}

