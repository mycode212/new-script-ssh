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
        pgy_menu1 "[ 1]" "Toggle Service Cloudflare Tunnel (Start / Stop / Restart)"
        pgy_menu1 "[ 2]" "Hubungkan Token Baru (Install Cloudflare Tunnel Service)"
        pgy_menu1 "[ 3]" "Atur Domain Tunnel (OpenVPN Portal & REST API)"
        pgy_menu1 "[ 4]" "Panduan Routing Hostname di Cloudflare Zero Trust"
        pgy_menu1 "[ 5]" "Lihat Log Layanan Cloudflare Tunnel"
        pgy_menu1 "[ 6]" "Hapus Service & Uninstall cloudflared"
        pgy_box_divider
        pgy_menu1 "[ 0]" "Kembali ke Menu Sebelumnya"
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
            2)
                clear; show_banner
                pgy_screen_title "INSTALL CLOUDFLARE TUNNEL" "Tempel Connector Token dari Dashboard Cloudflare Zero Trust"
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
                clear; show_banner
                pgy_screen_title "KONFIGURASI DOMAIN TUNNEL" "Menghubungkan domain publik tunnel ke layanan lokal VPS"
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
            4)
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
            5)
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
            6)
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
