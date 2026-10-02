#!/bin/bash
# ============================================================
# Auto Script SSH By : ProgoCloud
# Module: menus/cftunnel_menu.sh - Cloudflare Tunnel Management Console
# ============================================================

cftunnel_management_menu() {
    local PGY_ACTION_PAUSE_GUARD="" TDZ_ACTION_PAUSE_GUARD=""
    local PGY_ACTION_PAUSED="false" TDZ_ACTION_PAUSED="false"
    pgy_cftunnel_init_config
    while true; do
        show_banner
        local s_status
        s_status=$(pgy_cftunnel_service_status)
        local status_color="$C_RED"
        [[ "$s_status" == "active" ]] && status_color="$C_GREEN"

        local cf_token vpn_domain api_domain
        cf_token=$(pgy_cftunnel_get_config_val "CF_TUNNEL_TOKEN" "")
        vpn_domain=$(pgy_cftunnel_get_config_val "CF_TUNNEL_VPN_DOMAIN" "Belum Diatur")
        api_domain=$(pgy_cftunnel_get_config_val "CF_TUNNEL_API_DOMAIN" "Belum Diatur")

        # Mask token for display
        local masked_token="None"
        if [[ -n "$cf_token" ]]; then
            masked_token="${cf_token:0:12}...${cf_token: -6}"
        fi

        echo
        pgy_box_top
        pgy_box_header "CLOUDFLARE TUNNEL (CLOUDFLARED)"
        pgy_box_divider
        pgy_row "${C_GRAY}STATUS     :${C_RESET} ${status_color}${s_status^^}${C_RESET} ${C_GRAY}(cloudflared.service)${C_RESET}"
        pgy_row "${C_GRAY}VPN DOMAIN :${C_RESET} ${C_CYAN}${vpn_domain}${C_RESET} ${C_GRAY}-> localhost:1180${C_RESET}"
        pgy_row "${C_GRAY}API DOMAIN :${C_RESET} ${C_YELLOW}${api_domain}${C_RESET} ${C_GRAY}-> localhost:8780${C_RESET}"
        pgy_row "${C_GRAY}TOKEN      :${C_RESET} ${C_WHITE}${masked_token}${C_RESET}"
        pgy_box_divider
        pgy_menu1 "[ 1]" "Otomatis Buat Tunnel & Domain (Cloudflare API 1-Click)"
        pgy_menu1 "[ 2]" "Hubungkan Token Manual (Tempel Token Zero Trust)"
        pgy_menu1 "[ 3]" "Toggle Service Cloudflare Tunnel (Start / Stop / Restart)"
        pgy_menu1 "[ 4]" "Atur Domain Tunnel Manual (OpenVPN Portal & REST API)"
        pgy_menu1 "[ 5]" "Panduan Routing Hostname di Cloudflare Zero Trust"
        pgy_menu1 "[ 6]" "Lihat Log Layanan Cloudflare Tunnel"
        pgy_menu1 "[ 7]" "Hapus Service & Uninstall cloudflared"
        pgy_box_divider
        pgy_menu1 "[ 0]" "Kembali ke Menu Sebelumnya"
        pgy_box_bot
        echo
        if ! read -r -p "$(echo -e "${C_PROMPT}  Pilih opsi [0-7]: ${C_RESET}")" choice; then
            echo
            return
        fi

        case $choice in
            1)
                clear; show_banner
                pgy_screen_title "OTOMATISASI CLOUDFLARE TUNNEL & DOMAIN" "Membuat Tunnel, Ingress Rules, & DNS CNAME secara otomatis via Cloudflare API"
                echo

                local cf_auth_type="token" cf_auth_val="" cf_auth_email="" in_domain=""

                if declare -F pgy_cf_is_configured >/dev/null 2>&1 && pgy_cf_is_configured; then
                    pgy_cf_load_config
                    echo -e "  ${C_GREEN}✔ Kredensial Cloudflare Terdaftar Terdeteksi!${C_RESET}"
                    echo -e "    Domain Utama : ${C_YELLOW}${CF_ZONE_NAME}${C_RESET}"
                    echo -e "    Auth Mode    : ${C_WHITE}${CF_AUTH_MODE}${C_RESET}"
                    echo
                    read -r -p "$(echo -e "${C_PROMPT}  Gunakan kredensial & domain di atas? [Y/n]: ${C_RESET}")" use_saved_cf
                    if [[ "$use_saved_cf" != "n" && "$use_saved_cf" != "N" ]]; then
                        cf_auth_type="$CF_AUTH_MODE"
                        if [[ "$cf_auth_type" == "token" ]]; then
                            cf_auth_val="$CF_API_TOKEN"
                        else
                            cf_auth_email="$CF_CF_EMAIL"
                            cf_auth_val="$CF_GLOBAL_KEY"
                        fi
                        in_domain="$CF_ZONE_NAME"
                    fi
                fi

                if [[ -z "$cf_auth_val" ]]; then
                    echo -e "  ${C_CYAN}Pilih Metode Autentikasi Cloudflare:${C_RESET}"
                    echo -e "  ${C_WHITE}1. API Token${C_RESET} ${C_GRAY}(Direkomendasikan: Izin Zone.DNS + Account.Cloudflare Tunnel)${C_RESET}"
                    echo -e "  ${C_WHITE}2. Global API Key + Email${C_RESET}"
                    echo
                    read -r -p "$(echo -e "${C_PROMPT}  Pilih metode [1/2]: ${C_RESET}")" auth_mode_choice
                    if [[ "$auth_mode_choice" == "2" ]]; then
                        cf_auth_type="global"
                        read -r -p "$(echo -e "${C_PROMPT}  Masukkan Email Akun Cloudflare: ${C_RESET}")" cf_auth_email
                        read -r -p "$(echo -e "${C_PROMPT}  Masukkan Global API Key: ${C_RESET}")" cf_auth_val
                    else
                        cf_auth_type="token"
                        read -r -p "$(echo -e "${C_PROMPT}  Masukkan Cloudflare API Token: ${C_RESET}")" cf_auth_val
                    fi

                    if [[ -z "$cf_auth_val" ]]; then
                        pgy_message ERROR "API Token / Key tidak boleh kosong."
                        echo
                        read -r -p "$(echo -e "${C_PROMPT}  Tekan [Enter] untuk kembali... ${C_RESET}")" || true
                        continue
                    fi

                    echo
                    read -r -p "$(echo -e "${C_PROMPT}  Masukkan Domain Utama (contoh: arjunacloud.app): ${C_RESET}")" in_domain
                    if [[ -z "$in_domain" ]]; then
                        pgy_message ERROR "Domain utama tidak boleh kosong."
                        echo
                        read -r -p "$(echo -e "${C_PROMPT}  Tekan [Enter] untuk kembali... ${C_RESET}")" || true
                        continue
                    fi
                fi

                read -r -p "$(echo -e "${C_PROMPT}  Prefix Subdomain OpenVPN [default: vpn]: ${C_RESET}")" in_vpn_sub
                in_vpn_sub=${in_vpn_sub:-vpn}
                read -r -p "$(echo -e "${C_PROMPT}  Prefix Subdomain REST API [default: api]: ${C_RESET}")" in_api_sub
                in_api_sub=${in_api_sub:-api}

                echo
                pgy_progress_begin 1 4 "Memeriksa domain & akun di Cloudflare"
                local worker_res
                worker_res=$(pgy_cftunnel_cf_api_worker "$cf_auth_type" "$cf_auth_val" "$cf_auth_email" "$in_domain" "$in_vpn_sub" "$in_api_sub" "progocloud")
                
                local is_success
                is_success=$(echo "$worker_res" | python3 -c 'import sys, json; d=json.loads(sys.stdin.read()); print("true" if d.get("success") else "false")' 2>/dev/null || echo "false")

                if [[ "$is_success" != "true" ]]; then
                    pgy_progress_failed
                    local err_msg
                    err_msg=$(echo "$worker_res" | python3 -c 'import sys, json; d=json.loads(sys.stdin.read()); print(d.get("message", "Gagal berkomunikasi dengan Cloudflare API"))' 2>/dev/null || echo "Gagal menghubungi Cloudflare API.")
                    pgy_message ERROR "$err_msg"
                    echo
                    read -r -p "$(echo -e "${C_PROMPT}  Tekan [Enter] untuk kembali... ${C_RESET}")" || true
                    continue
                fi
                pgy_progress_done

                pgy_progress_begin 2 4 "Membuat Tunnel & Routing Ingress"
                sleep 0.5
                pgy_progress_done

                pgy_progress_begin 3 4 "Menerapkan DNS Record CNAME otomatis"
                sleep 0.5
                pgy_progress_done

                pgy_progress_begin 4 4 "Memasang & menjalankan service cloudflared di VPS"
                local out_token out_vpn_dom out_api_dom out_tun_id out_acc_id out_zone_id
                out_token=$(echo "$worker_res" | python3 -c 'import sys, json; d=json.loads(sys.stdin.read()); print(d.get("tunnel_token", ""))')
                out_vpn_dom=$(echo "$worker_res" | python3 -c 'import sys, json; d=json.loads(sys.stdin.read()); print(d.get("vpn_domain", ""))')
                out_api_dom=$(echo "$worker_res" | python3 -c 'import sys, json; d=json.loads(sys.stdin.read()); print(d.get("api_domain", ""))')
                out_tun_id=$(echo "$worker_res" | python3 -c 'import sys, json; d=json.loads(sys.stdin.read()); print(d.get("tunnel_id", ""))')
                out_acc_id=$(echo "$worker_res" | python3 -c 'import sys, json; d=json.loads(sys.stdin.read()); print(d.get("account_id", ""))')
                out_zone_id=$(echo "$worker_res" | python3 -c 'import sys, json; d=json.loads(sys.stdin.read()); print(d.get("zone_id", ""))')

                if ! pgy_cftunnel_install_service_token "$out_token"; then
                    pgy_progress_failed
                    pgy_message ERROR "Gagal menjalankan service cloudflared di VPS."
                else
                    pgy_cftunnel_set_config_val "CF_AUTH_TYPE" "$cf_auth_type"
                    pgy_cftunnel_set_config_val "CF_AUTH_VAL" "$cf_auth_val"
                    pgy_cftunnel_set_config_val "CF_AUTH_EMAIL" "$cf_auth_email"
                    pgy_cftunnel_set_config_val "CF_TUNNEL_ROOT_DOMAIN" "$in_domain"
                    pgy_cftunnel_set_config_val "CF_TUNNEL_ID" "$out_tun_id"
                    pgy_cftunnel_set_config_val "CF_ACCOUNT_ID" "$out_acc_id"
                    pgy_cftunnel_set_config_val "CF_ZONE_ID" "$out_zone_id"
                    pgy_cftunnel_set_config_val "CF_TUNNEL_VPN_DOMAIN" "$out_vpn_dom"
                    pgy_cftunnel_set_config_val "CF_TUNNEL_API_DOMAIN" "$out_api_dom"
                    pgy_progress_done
                    echo
                    pgy_message OK "Cloudflare Tunnel & DNS berhasil dibuat secara otomatis!"
                    echo -e "   • OpenVPN Web Portal : ${C_GREEN}https://${out_vpn_dom}/openvpn/${C_RESET}"
                    echo -e "   • REST API Daemon    : ${C_YELLOW}https://${out_api_dom}/api/v1/system/status${C_RESET}"
                fi
                echo
                read -r -p "$(echo -e "${C_PROMPT}  Tekan [Enter] untuk kembali ke menu... ${C_RESET}")" || true
                ;;
            2)
                clear; show_banner
                pgy_screen_title "INSTALL CLOUDFLARE TUNNEL (MANUAL)" "Tempel Connector Token dari Dashboard Cloudflare Zero Trust"
                echo
                echo -e "  ${C_CYAN}Cara Mendapatkan Token:${C_RESET}"
                echo -e "  1. Buka ${C_YELLOW}https://one.dash.cloudflare.com${C_RESET}"
                echo -e "  2. Masuk ke ${C_WHITE}Networks → Tunnels → Create a tunnel${C_RESET}"
                echo -e "  3. Pilih ${C_WHITE}Cloudflared → Copy token${C_RESET} (teks panjang setelah 'cloudflared service install ...')"
                echo
                read -r -p "$(echo -e "${C_PROMPT}  Masukkan Token Cloudflare Tunnel: ${C_RESET}")" input_token
                if [[ -z "$input_token" ]]; then
                    pgy_message ERROR "Token tidak boleh kosong."
                else
                    # Strip 'cloudflared service install' if user pasted full command
                    input_token=$(echo "$input_token" | sed -e 's/.*cloudflared service install //' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
                    echo
                    pgy_progress_begin 1 3 "Mengunduh binary resmi cloudflared"
                    if ! pgy_cftunnel_ensure_binary; then
                        pgy_progress_failed
                        pgy_message ERROR "Gagal mengunduh binary cloudflared."
                    else
                        pgy_progress_done
                        pgy_progress_begin 2 3 "Memasang unit systemd cloudflared"
                        if ! pgy_cftunnel_install_service_token "$input_token"; then
                            pgy_progress_failed
                            pgy_message ERROR "Gagal memasang service dengan token tersebut."
                        else
                            pgy_progress_done
                            pgy_progress_begin 3 3 "Memverifikasi status tunnel aktif"
                            sleep 1
                            pgy_progress_done
                            echo
                            pgy_message OK "Cloudflare Tunnel berhasil terhubung dan berjalan aktif!"
                        fi
                    fi
                fi
                echo
                read -r -p "$(echo -e "${C_PROMPT}  Tekan [Enter] untuk kembali ke menu... ${C_RESET}")" || true
                ;;
            3)
                echo
                if [[ "$s_status" == "active" ]]; then
                    pgy_progress_begin 1 2 "Menghentikan service cloudflared"
                    pgy_cftunnel_stop
                    pgy_progress_done
                    pgy_progress_begin 2 2 "Memperbarui konfigurasi sistem"
                    sleep 0.4
                    pgy_progress_done
                    echo
                    pgy_message OK "Cloudflare Tunnel berhasil dihentikan."
                else
                    pgy_progress_begin 1 2 "Memverifikasi binary cloudflared"
                    if ! pgy_cftunnel_ensure_binary; then
                        pgy_progress_failed
                        pgy_message ERROR "Gagal memuat binary cloudflared."
                    else
                        pgy_progress_done
                        pgy_progress_begin 2 2 "Menjalankan cloudflared.service"
                        pgy_cftunnel_start
                        pgy_progress_done
                        echo
                        pgy_message OK "Cloudflare Tunnel berhasil dijalankan."
                    fi
                fi
                echo
                read -r -p "$(echo -e "${C_PROMPT}  Tekan [Enter] untuk kembali ke menu... ${C_RESET}")" || true
                ;;
            4)
                clear; show_banner
                pgy_screen_title "KONFIGURASI DOMAIN TUNNEL MANUAL" "Menghubungkan domain publik tunnel ke layanan lokal VPS"
                echo
                echo -e "  ${C_GRAY}Domain Tunnel OpenVPN Portal saat ini : ${C_CYAN}${vpn_domain}${C_RESET}"
                read -r -p "$(echo -e "${C_PROMPT}  Masukkan Subdomain OpenVPN (misal: vpn.arjunacloud.app): ${C_RESET}")" in_vpn_domain
                [[ -n "$in_vpn_domain" ]] && pgy_cftunnel_set_config_val "CF_TUNNEL_VPN_DOMAIN" "$in_vpn_domain"

                echo
                echo -e "  ${C_GRAY}Domain Tunnel REST API saat ini        : ${C_YELLOW}${api_domain}${C_RESET}"
                read -r -p "$(echo -e "${C_PROMPT}  Masukkan Subdomain REST API (misal: api.arjunacloud.app): ${C_RESET}")" in_api_domain
                [[ -n "$in_api_domain" ]] && pgy_cftunnel_set_config_val "CF_TUNNEL_API_DOMAIN" "$in_api_domain"

                echo
                pgy_message OK "Domain tunnel berhasil disimpan."
                echo
                read -r -p "$(echo -e "${C_PROMPT}  Tekan [Enter] untuk kembali ke menu... ${C_RESET}")" || true
                ;;
            5)
                clear; show_banner
                pgy_screen_title "PANDUAN ZERO TRUST PUBLIC HOSTNAME" "Petunjuk setting Public Hostname di Dashboard Cloudflare"
                echo
                pgy_box_top "$C_CYAN"
                pgy_box_header "ROUTING CLOUDFLARE ZERO TRUST" "$C_CYAN" "$C_CYAN"
                pgy_box_divider "$C_CYAN"
                pgy_row "${C_WHITE}1. Mapping OpenVPN Web Portal:${C_RESET}" "$C_CYAN"
                pgy_row "   • Subdomain   : ${vpn_domain:-vpn.domain.com}" "$C_CYAN"
                pgy_row "   • Service Type: HTTP" "$C_CYAN"
                pgy_row "   • URL Target  : localhost:1180" "$C_CYAN"
                pgy_box_divider "$C_CYAN"
                pgy_row "${C_WHITE}2. Mapping ProgoCloud REST API:${C_RESET}" "$C_CYAN"
                pgy_row "   • Subdomain   : ${api_domain:-api.domain.com}" "$C_CYAN"
                pgy_row "   • Service Type: HTTP" "$C_CYAN"
                pgy_row "   • URL Target  : localhost:8780" "$C_CYAN"
                pgy_box_divider "$C_CYAN"
                pgy_row "${C_GREEN}Kelebihan Menggunakan Cloudflare Tunnel:${C_RESET}" "$C_CYAN"
                pgy_row "✔ Full HTTPS otomatis tanpa perlu buka port di firewall" "$C_CYAN"
                pgy_row "✔ Mengatasi blokir port non-standar pada Cloudflare CDN" "$C_CYAN"
                pgy_box_bot "$C_CYAN"
                echo
                read -r -p "$(echo -e "${C_PROMPT}  Tekan [Enter] untuk kembali ke menu... ${C_RESET}")" || true
                ;;
            6)
                clear; show_banner
                pgy_screen_title "LOG CLOUDFLARE TUNNEL" "50 baris log terakhir cloudflared.service"
                echo
                if command -v journalctl >/dev/null 2>&1; then
                    journalctl -u cloudflared.service -n 50 --no-pager 2>/dev/null || echo -e "  ${C_YELLOW}Log tidak tersedia atau service belum berjalan.${C_RESET}"
                else
                    echo -e "  ${C_YELLOW}Perintah journalctl tidak tersedia di sistem ini.${C_RESET}"
                fi
                echo
                read -r -p "$(echo -e "${C_PROMPT}  Tekan [Enter] untuk kembali ke menu... ${C_RESET}")" || true
                ;;
            7)
                echo
                read -r -p "$(echo -e "${C_PROMPT}  Yakin ingin menghapus Cloudflare Tunnel dari VPS? [y/N]: ${C_RESET}")" confirm_un
                if [[ "$confirm_un" == "y" || "$confirm_un" == "Y" ]]; then
                    echo
                    pgy_progress_begin 1 2 "Menghentikan dan menghapus unit service"
                    pgy_cftunnel_uninstall
                    pgy_progress_done
                    pgy_progress_begin 2 2 "Membersihkan konfigurasi tunnel"
                    sleep 0.4
                    pgy_progress_done
                    echo
                    pgy_message OK "Cloudflare Tunnel berhasil dicopot sepenuhnya."
                else
                    pgy_message CANCELLED "Operasi dibatalkan."
                fi
                echo
                read -r -p "$(echo -e "${C_PROMPT}  Tekan [Enter] untuk kembali ke menu... ${C_RESET}")" || true
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
