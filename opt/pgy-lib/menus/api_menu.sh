#!/bin/bash
# ============================================================
# Auto Script SSH By : ProgoCloud
# Module: menus/api_menu.sh - ProgoCloud REST API Management Console
# ============================================================

api_management_menu() {
    local PGY_ACTION_PAUSE_GUARD="" TDZ_ACTION_PAUSE_GUARD=""
    local PGY_ACTION_PAUSED="false" TDZ_ACTION_PAUSED="false"
    pgy_api_init_config
    while true; do
        show_banner
        local s_status
        s_status=$(pgy_api_service_status)
        local status_color="$C_RED"
        [[ "$s_status" == "active" ]] && status_color="$C_GREEN"

        local api_port api_key allowed_ips cf_api_domain=""
        api_port=$(pgy_api_get_config_val "API_PORT" "8780")
        api_key=$(pgy_api_get_config_val "API_KEY" "Belum Diatur")
        allowed_ips=$(pgy_api_get_config_val "ALLOWED_IPS" "ALL")
        if declare -F pgy_cftunnel_get_config_val >/dev/null 2>&1; then
            cf_api_domain=$(pgy_cftunnel_get_config_val "CF_TUNNEL_API_DOMAIN" "")
        fi

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
        if [[ -n "$cf_api_domain" ]]; then
            pgy_row "${C_GRAY}TUNNEL :${C_RESET} ${C_GREEN}https://${cf_api_domain}${C_RESET} ${C_GRAY}(Zero Trust)${C_RESET}"
        fi
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
                echo
                if [[ "$s_status" == "active" ]]; then
                    pgy_progress_begin 1 2 "Menghentikan daemon REST API"
                    pgy_api_stop
                    pgy_progress_done
                    pgy_progress_begin 2 2 "Memperbarui konfigurasi sistem"
                    sleep 0.4
                    pgy_progress_done
                    echo
                    pgy_message OK "Daemon API berhasil dihentikan."
                else
                    pgy_progress_begin 1 3 "Menyiapkan binary dan konfigurasi API"
                    pgy_api_install_service
                    pgy_progress_done
                    pgy_progress_begin 2 3 "Mengaktifkan service unit systemd"
                    systemctl enable pgy-api >/dev/null 2>&1 || true
                    pgy_progress_done
                    pgy_progress_begin 3 3 "Menjalankan daemon REST API di port ${api_port}"
                    pgy_api_start
                    pgy_progress_done
                    echo
                    pgy_message OK "Daemon API berhasil dijalankan di port ${api_port}."
                fi
                press_enter
                ;;
            2)
                clear; show_banner
                pgy_screen_title "REST API SECRET KEY" "Gunakan token ini pada header HTTP request (X-API-Key)"
                echo
                pgy_box_top "$C_CYAN"
                pgy_box_header "DETAIL KREDENSIAL API" "$C_CYAN" "$C_CYAN"
                pgy_box_divider "$C_CYAN"
                pgy_detail "API Key" "${api_key}" "$C_GREEN"
                pgy_detail "Port" "${api_port}" "$C_CYAN"
                pgy_detail "Header Format" "X-API-Key: ${api_key}" "$C_YELLOW"
                pgy_box_bot "$C_CYAN"
                echo
                press_enter
                ;;
            3)
                echo
                read -r -p "$(echo -e "${C_PROMPT}  Yakin ingin mengacak ulang API Key? Integrasi bot lama akan terputus! [y/N]: ${C_RESET}")" confirm_regen
                if [[ "$confirm_regen" == "y" || "$confirm_regen" == "Y" ]]; then
                    echo
                    pgy_progress_begin 1 2 "Membuat token kriptografis baru"
                    local new_k
                    new_k=$(pgy_api_regenerate_key)
                    pgy_progress_done
                    pgy_progress_begin 2 2 "Menerapkan kunci dan memuat ulang daemon"
                    sleep 0.4
                    pgy_progress_done
                    echo
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
                    if [[ ! "$input_port" =~ ^[0-9]+$ ]] || (( input_port < 1024 || input_port > 65535 )); then
                        pgy_message ERROR "Port tidak valid. Harus berupa angka 1024 - 65535."
                    else
                        echo
                        pgy_progress_begin 1 2 "Menyimpan port ${input_port} ke konfigurasi"
                        pgy_api_set_config_val "API_PORT" "$input_port"
                        pgy_progress_done
                        pgy_progress_begin 2 2 "Memuat ulang service daemon di port baru"
                        pgy_api_restart
                        pgy_progress_done
                        echo
                        pgy_message OK "Port API berhasil diubah ke ${input_port} dan service di-restart."
                    fi
                fi
                press_enter
                ;;
            5)
                echo
                echo -e "  ${C_DIM}Format: ALL (semua IP), atau pisahkan IP dengan koma (contoh: 1.2.3.4, 5.6.7.8/24)${C_RESET}"
                read -r -p "$(echo -e "${C_PROMPT}  Masukkan IP Whitelist [${allowed_ips}]: ${C_RESET}")" input_ips
                if [[ -n "$input_ips" ]]; then
                    echo
                    pgy_progress_begin 1 2 "Memperbarui daftar IP Whitelist"
                    pgy_api_set_allowed_ips "$input_ips"
                    pgy_progress_done
                    pgy_progress_begin 2 2 "Menerapkan aturan ACL pada daemon"
                    sleep 0.4
                    pgy_progress_done
                    echo
                    pgy_message OK "IP Whitelist berhasil diperbarui: ${input_ips}"
                fi
                press_enter
                ;;
            6)
                clear; show_banner
                pgy_screen_title "API TESTING & INTEGRATION" "Dokumentasi cURL & status respon endpoint API"
                echo
                pgy_progress_begin 1 1 "Menguji koneksi internal API daemon"
                local test_ok=false
                if pgy_api_test_local; then
                    test_ok=true
                fi
                pgy_progress_done
                echo

                local api_host=""
                if declare -F detect_preferred_host >/dev/null 2>&1; then
                    api_host=$(detect_preferred_host 2>/dev/null || echo "")
                fi
                if [[ -z "$api_host" ]]; then
                    api_host=$(curl -s -4 icanhazip.com 2>/dev/null || echo "127.0.0.1")
                fi

                pgy_box_top "$C_CYAN"
                pgy_box_header "HASIL UJI KONEKSI API" "$C_CYAN" "$C_CYAN"
                pgy_box_divider "$C_CYAN"
                if $test_ok; then
                    pgy_row "$(printf "${C_GREEN}✔ API Service berjalan normal dan merespons dengan benar!${C_RESET}")" "$C_CYAN"
                else
                    pgy_row "$(printf "${C_RED}✖ API Service tidak merespons (Pastikan service AKTIF).${C_RESET}")" "$C_CYAN"
                fi
                pgy_box_divider "$C_CYAN"
                pgy_row "$(printf "${C_CYAN}Endpoint Status VPS (Direct HTTP):${C_RESET}")" "$C_CYAN"
                pgy_row "$(printf "${C_WHITE}curl -s -H 'X-API-Key: %s' http://%s:%s/api/v1/system/status${C_RESET}" "$api_key" "$api_host" "$api_port")" "$C_CYAN"
                if [[ -n "$cf_api_domain" ]]; then
                    pgy_box_divider "$C_CYAN"
                    pgy_row "$(printf "${C_GREEN}Endpoint Cloudflare Tunnel (HTTPS Zero Trust):${C_RESET}")" "$C_CYAN"
                    pgy_row "$(printf "${C_WHITE}curl -s -H 'X-API-Key: %s' https://%s/api/v1/system/status${C_RESET}" "$api_key" "$cf_api_domain")" "$C_CYAN"
                fi
                pgy_box_divider "$C_CYAN"
                pgy_row "$(printf "${C_CYAN}Endpoint Buat User SSH (POST):${C_RESET}")" "$C_CYAN"
                pgy_row "$(printf "${C_WHITE}curl -s -X POST -H 'Content-Type: application/json' \\${C_RESET}")" "$C_CYAN"
                pgy_row "$(printf "${C_WHITE}  -H 'X-API-Key: %s' \\${C_RESET}" "$api_key")" "$C_CYAN"
                pgy_row "$(printf "${C_WHITE}  -d '{\"username\":\"testuser\",\"password\":\"pass123\",\"days\":30}' \\${C_RESET}")" "$C_CYAN"
                if [[ -n "$cf_api_domain" ]]; then
                    pgy_row "$(printf "${C_WHITE}  https://%s/api/v1/user/create${C_RESET}" "$cf_api_domain")" "$C_CYAN"
                else
                    pgy_row "$(printf "${C_WHITE}  http://%s:%s/api/v1/user/create${C_RESET}" "$api_host" "$api_port")" "$C_CYAN"
                fi
                pgy_box_divider "$C_CYAN"
                pgy_row "$(printf "${C_CYAN}Endpoint Buat Akun Xray (VMess/VLess/Trojan) (POST):${C_RESET}")" "$C_CYAN"
                pgy_row "$(printf "${C_WHITE}curl -s -X POST -H 'Content-Type: application/json' \\${C_RESET}")" "$C_CYAN"
                pgy_row "$(printf "${C_WHITE}  -H 'X-API-Key: %s' \\${C_RESET}" "$api_key")" "$C_CYAN"
                pgy_row "$(printf "${C_WHITE}  -d '{\"username\":\"xrayuser\",\"protocol\":\"all\",\"days\":30}' \\${C_RESET}")" "$C_CYAN"
                if [[ -n "$cf_api_domain" ]]; then
                    pgy_row "$(printf "${C_WHITE}  https://%s/api/v1/xray/create${C_RESET}" "$cf_api_domain")" "$C_CYAN"
                else
                    pgy_row "$(printf "${C_WHITE}  http://%s:%s/api/v1/xray/create${C_RESET}" "$api_host" "$api_port")" "$C_CYAN"
                fi
                pgy_box_bot "$C_CYAN"
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
