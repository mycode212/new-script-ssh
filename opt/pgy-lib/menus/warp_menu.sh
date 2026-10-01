#!/bin/bash
# ============================================================
# Auto Script SSH By : ProgoCloud
# Module: menus/warp_menu.sh - Cloudflare WARP Management Menu
# ============================================================

warp_management_menu() {
    while true; do
        show_banner
        local warp_status
        warp_status=$(pgy_warp_get_status)
        local status_color="$C_RED"
        [[ "$warp_status" =~ "Active" ]] && status_color="$C_GREEN"

        echo
        pgy_box_top
        pgy_box_header "CLOUDFLARE WARP SUITE"
        pgy_box_divider
        pgy_row "${C_GRAY}STATUS :${C_RESET} ${status_color}${warp_status}${C_RESET} ${C_GRAY}(SOCKS5 127.0.0.1:${WARP_SOCKS_PORT})${C_RESET}"
        pgy_box_divider
        pgy_menu1 "[ 1]" "Toggle WARP Service (ON / OFF)"
        pgy_menu1 "[ 2]" "Periksa Status Unlock (Netflix & ChatGPT)"
        pgy_menu1 "[ 3]" "Daftar Ulang Akun WARP Free (Regenerate)"
        pgy_menu1 "[ 4]" "Pasang / Ganti Lisensi WARP+ (Plus Key)"
        pgy_menu1 "[ 5]" "Lihat Detail Konfigurasi Wireproxy"
        pgy_box_divider
        pgy_menu1 "[ 0]" "Kembali ke Menu Protokol"
        pgy_box_bot
        echo
        if ! read -r -p "$(echo -e "${C_PROMPT}  Pilih opsi [0-5]: ${C_RESET}")" choice; then
            echo
            return
        fi

        case $choice in
            1)
                pgy_run_action pgy_warp_toggle_service
                ;;
            2)
                pgy_run_action pgy_warp_test_unlock
                ;;
            3)
                pgy_run_action pgy_warp_generate_config ""
                if pgy_warp_is_active; then
                    systemctl restart wireproxy.service >/dev/null 2>&1 || true
                fi
                ;;
            4)
                echo
                read -r -p "$(echo -e "${C_PROMPT}  Masukkan License Key WARP+ (26 karakter): ${C_RESET}")" wp_key
                if [[ -n "$wp_key" ]]; then
                    pgy_run_action pgy_warp_generate_config "$wp_key"
                    if pgy_warp_is_active; then
                        systemctl restart wireproxy.service >/dev/null 2>&1 || true
                    fi
                fi
                ;;
            5)
                echo
                if [[ -f "$WARP_CONF" ]]; then
                    pgy_box_top
                    pgy_box_header "WIREPROXY CONFIGURATION"
                    pgy_box_divider
                    while IFS= read -r line; do
                        pgy_row "$line"
                    done < "$WARP_CONF"
                    pgy_box_bot
                else
                    echo -e "${C_WARN}  Konfigurasi belum dibuat.${C_RESET}"
                fi
                echo
                read -r -p "$(echo -e "${C_PROMPT}  Tekan Enter untuk kembali...${C_RESET}")"
                ;;
            0)
                return
                ;;
            *)
                invalid_option
                ;;
        esac
    done
}
