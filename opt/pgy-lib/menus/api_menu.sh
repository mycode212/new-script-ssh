#!/bin/bash
# ============================================================
# Auto Script SSH By : ProgoCloud
# Module: menus/api_menu.sh - ProgoCloud REST API Management Console
# ============================================================

api_management_menu() {
    pgy_api_init_config
    while true; do
        show_banner
        local s_status
        s_status=$(pgy_api_service_status)
        local status_color="$C_RED"
        [[ "$s_status" == "active" ]] && status_color="$C_GREEN"

        local api_port api_key allowed_ips
        api_port=$(pgy_api_get_config_val "API_PORT" "8780")
        api_key=$(pgy_api_get_config_val "API_KEY" "Belum Diatur")
        allowed_ips=$(pgy_api_get_config_val "ALLOWED_IPS" "ALL")

        # Mask API key for display
        local masked_key="None"
        if [[ -n "$api_key" && "$api_key" != "Belum Diatur" ]]; then
            masked_key="${api_key:0:10}...${api_key: -4}"
        fi

        echo
        pgy_box_top
        pgy_box_header "PROGOCLOUD REST API DAEMON"
        pgy_box_divider
        pgy_row "${C_GRAY}STATUS :${C_RESET} ${status_color}${s_status^^}${C_RESET} ${C_GRAY}(Port: ${api_port})${C_RESET}"
        pgy_row "${C_GRAY}AUTH   :${C_RESET} ${C_CYAN}${masked_key}${C_RESET}"
        pgy_row "${C_GRAY}IP ACL :${C_RESET} ${C_YELLOW}${allowed_ips}${C_RESET}"
        pgy_box_divider
        pgy_menu1 "[ 1]" "Toggle Service API (Start / Stop / Restart)"
        pgy_menu1 "[ 2]" "Lihat Detail Kunci API Lengkap (Show Secret Key)"
        pgy_menu1 "[ 3]" "Generate / Acak Ulang Kunci API Baru"
        pgy_menu1 "[ 4]" "Ganti Port Layanan API (Default: 8780)"
        pgy_menu1 "[ 5]" "Atur IP Whitelist / Batasan IP Akses"
        pgy_menu1 "[ 6]" "Uji Coba Endpoint API & Dokumentasi cURL"
        pgy_box_divider
        pgy_menu1 "[ 0]" "Kembali ke Menu Utama"
        pgy_box_bot
        echo
        if ! read -r -p "$(echo -e "${C_PROMPT}  Pilih opsi [0-6]: ${C_RESET}")" choice; then
            echo
            return
        fi

        case $choice in
            1)
                if [[ "$s_status" == "active" ]]; then
                    echo -e "\n${C_BLUE}Menghentikan daemon REST API...${C_RESET}"
                    pgy_api_stop
                    pgy_message OK "Daemon API berhasil dihentikan."
                else
                    echo -e "\n${C_BLUE}Memulai daemon REST API...${C_RESET}"
                    pgy_api_start
                    pgy_message OK "Daemon API berhasil dijalankan di port ${api_port}."
                fi
                press_enter
                ;;
            2)
                clear; show_banner
                echo
                pgy_box_top
                pgy_box_header "REST API SECRET KEY"
                pgy_box_divider
                pgy_row "${C_GRAY}API Key:${C_RESET} ${C_GREEN}${api_key}${C_RESET}"
                pgy_row "${C_GRAY}Port   :${C_RESET} ${C_CYAN}${api_port}${C_RESET}"
                pgy_row "${C_GRAY}Header :${C_RESET} ${C_YELLOW}X-API-Key: ${api_key}${C_RESET}"
                pgy_box_bot
                echo
                press_enter
                ;;
            3)
                echo
                read -r -p "$(echo -e "${C_PROMPT}  Yakin ingin mengacak ulang API Key? Integrasi bot lama akan terputus! [y/N]: ${C_RESET}")" confirm_regen
                if [[ "$confirm_regen" == "y" || "$confirm_regen" == "Y" ]]; then
                    local new_k
                    new_k=$(pgy_api_regenerate_key)
                    pgy_message OK "API Key baru berhasil dibuat: ${new_k}"
                else
                    pgy_message CANCELLED "Operasi dibatalkan."
                fi
                press_enter
                ;;
            4)
                echo
                read -r -p "$(echo -e "${C_PROMPT}  Masukkan Port API Baru (1024-65535) [${api_port}]: ${C_RESET}")" input_port
                if [[ -n "$input_port" ]]; then
                    if pgy_api_set_port "$input_port"; then
                        pgy_message OK "Port API berhasil diubah ke ${input_port} dan service di-restart."
                    else
                        pgy_message ERROR "Port tidak valid. Harus berupa angka 1024 - 65535."
                    fi
                fi
                press_enter
                ;;
            5)
                echo
                echo -e "  ${C_DIM}Format: ALL (semua IP), atau pisahkan IP dengan koma (contoh: 1.2.3.4, 5.6.7.8/24)${C_RESET}"
                read -r -p "$(echo -e "${C_PROMPT}  Masukkan IP Whitelist [${allowed_ips}]: ${C_RESET}")" input_ips
                if [[ -n "$input_ips" ]]; then
                    pgy_api_set_allowed_ips "$input_ips"
                    pgy_message OK "IP Whitelist berhasil diperbarui."
                fi
                press_enter
                ;;
            6)
                clear; show_banner
                echo
                pgy_box_top
                pgy_box_header "API TESTING & INTEGRATION EXAMPLES"
                pgy_box_divider
                pgy_row "${C_CYAN}Endpoint Status VPS:${C_RESET}"
                pgy_row "curl -s -H 'X-API-Key: ${api_key}' http://127.0.0.1:${api_port}/api/v1/system/status"
                pgy_box_divider
                pgy_row "${C_CYAN}Endpoint Buat User SSH:${C_RESET}"
                pgy_row "curl -s -X POST -H 'Content-Type: application/json' \\"
                pgy_row "  -H 'X-API-Key: ${api_key}' \\"
                pgy_row "  -d '{\"username\":\"testuser\",\"password\":\"pass123\",\"days\":30,\"limit\":2}' \\"
                pgy_row "  http://127.0.0.1:${api_port}/api/v1/user/create"
                pgy_box_divider
                
                echo -e "  ${C_BLUE}Menguji koneksi internal ke API...${C_RESET}"
                if pgy_api_test_local; then
                    pgy_row "${C_GREEN}✔ API Service berjalan normal dan merespons dengan benar!${C_RESET}"
                else
                    pgy_row "${C_RED}✖ API Service tidak merespons (Pastikan service AKTIF).${C_RESET}"
                fi
                pgy_box_bot
                echo
                press_enter
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
