#!/bin/bash
# ============================================================
# Auto Script SSH By : ProgoCloud
# Module: menus/xray_menu.sh - Xray Core Service Controller
# ============================================================

xray_management_menu() {
    while true; do
        show_banner
        local xr_status
        xr_status=$(pgy_xray_get_status)
        local status_color="$C_RED"
        [[ "$xr_status" =~ "Active" ]] && status_color="$C_GREEN"

        echo
        pgy_box_top
        pgy_box_header "XRAY CORE SERVICE & STACK"
        pgy_box_divider
        pgy_row "${C_GRAY}STATUS :${C_RESET} ${status_color}${xr_status}${C_RESET}"
        pgy_box_divider
        pgy_menu1 "[ 1]" "Toggle Xray Core Service (ON / OFF)"
        pgy_menu1 "[ 2]" "Rebuild & Sync Xray Config (WARP + Adblock Outbounds)"
        pgy_menu1 "[ 3]" "Buka Menu Manajemen User Xray (VLess/VMess/Trojan)"
        pgy_menu1 "[ 4]" "Lihat Detail Config JSON (/etc/xray/config.json)"
        pgy_menu1 "[ 5]" "Lihat Log Service (journalctl -u xray)"
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
                pgy_run_action pgy_xray_toggle
                ;;
            2)
                pgy_run_action pgy_xray_generate_base_config
                pgy_xray_sync_users_to_config
                echo -e "${C_GREEN}  Konfigurasi Xray Core & Outbounds berhasil diselaraskan.${C_RESET}"
                sleep 1.5
                ;;
            3)
                xray_user_management_menu
                ;;
            4)
                echo
                if [[ -f "$XRAY_CONF" ]]; then
                    pgy_box_top
                    pgy_box_header "XRAY CONFIGURATION"
                    pgy_box_divider
                    while IFS= read -r line; do
                        pgy_row "$line"
                    done < "$XRAY_CONF"
                    pgy_box_bot
                else
                    echo -e "${C_WARN}  Konfigurasi belum dibuat.${C_RESET}"
                fi
                echo
                read -r -p "$(echo -e "${C_PROMPT}  Tekan Enter untuk kembali...${C_RESET}")"
                ;;
            5)
                echo
                journalctl -u xray.service -n 30 --no-pager
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
