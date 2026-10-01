#!/bin/bash
# ============================================================
# Auto Script SSH By : ProgoCloud
# Module: menus/xray_user_menu.sh - XRay User Management Menu
# ============================================================

xray_user_management_menu() {
    while true; do
        show_banner
        local xray_db="${XRAY_USERS_DB:-/etc/xray/users.json}"
        local total_xray=0
        if [[ -f "$xray_db" ]]; then
            total_xray=$(grep -o '"username"' "$xray_db" 2>/dev/null | wc -l || echo 0)
        fi
        local online_sessions
        online_sessions=$(count_managed_online_sessions 2>/dev/null || echo 0)

        echo
        pgy_box_top
        pgy_box_header "XRAY USER MANAGEMENT (VMESS / VLESS / TROJAN)"
        pgy_box_divider
        pgy_row "${C_GRAY}USERS :${C_RESET} ${C_WHITE}${total_xray} terdaftar${C_RESET} │ ${C_GRAY}ONLINE :${C_RESET} ${C_GREEN}${online_sessions} sesi${C_RESET}"
        pgy_box_divider
        pgy_menu2 "[ 1]" "Create User"      "[ 4]" "List Users"
        pgy_menu2 "[ 2]" "Delete User"      "[ 5]" "Client Config / Link"
        pgy_menu2 "[ 3]" "Renew Account"    "[ 6]" "Service Status & Log"
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
                echo -e "${C_TITLE}  --- PILIH PROTOKOL XRAY ---${C_RESET}"
                echo "  [1] VLESS (WS & gRPC TLS)"
                echo "  [2] VMESS (WS & gRPC TLS)"
                echo "  [3] TROJAN (WS & gRPC TLS)"
                echo "  [0] Batal"
                echo
                read -r -p "$(echo -e "${C_PROMPT}  Pilih Protokol [1-3]: ${C_RESET}")" p_choice
                local x_proto=""
                case "$p_choice" in
                    1) x_proto="vless" ;;
                    2) x_proto="vmess" ;;
                    3) x_proto="trojan" ;;
                    *) continue ;;
                esac

                echo
                echo -e "${C_TITLE}  --- BUAT AKUN ${x_proto^^} BARU ---${C_RESET}"
                read -r -p "$(echo -e "${C_PROMPT}  Username: ${C_RESET}")" x_user
                [[ -z "$x_user" ]] && continue
                read -r -p "$(echo -e "${C_PROMPT}  Masa Aktif (Hari) [30]: ${C_RESET}")" x_exp
                x_exp=${x_exp:-30}

                if pgy_xray_user_add "$x_user" "$x_proto" "$x_exp" "0"; then
                    echo -e "\n${C_GREEN}  Akun ${x_proto^^} '${x_user}' berhasil dibuat!${C_RESET}\n"
                    pgy_xray_client_config_show "$x_user"
                else
                    echo -e "${C_ERR}  Gagal membuat akun.${C_RESET}"
                fi
                echo
                read -r -p "$(echo -e "${C_PROMPT}  Tekan Enter untuk kembali...${C_RESET}")"
                ;;
            2)
                echo
                read -r -p "$(echo -e "${C_PROMPT}  Masukkan Username yang akan dihapus: ${C_RESET}")" d_user
                if [[ -n "$d_user" ]]; then
                    pgy_xray_user_del "$d_user"
                    echo -e "${C_GREEN}  Akun ${d_user} telah dihapus.${C_RESET}"
                    sleep 1.5
                fi
                ;;
            3)
                echo
                read -r -p "$(echo -e "${C_PROMPT}  Username: ${C_RESET}")" r_user
                read -r -p "$(echo -e "${C_PROMPT}  Tambah Hari [30]: ${C_RESET}")" r_days
                r_days=${r_days:-30}
                if [[ -n "$r_user" ]]; then
                    pgy_xray_user_renew "$r_user" "$r_days"
                    echo -e "${C_GREEN}  Masa aktif akun ${r_user} berhasil ditambah ${r_days} hari.${C_RESET}"
                    sleep 1.5
                fi
                ;;
            4)
                echo
                pgy_box_top
                pgy_box_header "DAFTAR SEMUA AKUN XRAY"
                pgy_box_divider
                local header_row
                header_row=$(printf "${C_CYAN}%-16s${C_RESET} ${C_CYAN}%-12s${C_RESET} ${C_CYAN}%-14s${C_RESET} ${C_CYAN}%-12s${C_RESET}" "USERNAME" "PROTOKOL" "EXPIRED" "KUOTA")
                pgy_row "$header_row"
                pgy_box_divider
                local xray_db="${XRAY_USERS_DB:-/etc/xray/users.json}"
                local found_any=false
                if [[ -s "$xray_db" && "$xray_db" != "[]" ]]; then
                    while IFS='|' read -r u_user u_proto u_exp u_quota; do
                        [[ -z "$u_user" ]] && continue
                        found_any=true
                        local row_line
                        row_line=$(printf "${C_WHITE}%-16s${C_RESET} ${C_YELLOW}%-12s${C_RESET} ${C_GREEN}%-14s${C_RESET} ${C_GRAY}%-12s${C_RESET}" "${u_user:0:16}" "${u_proto:0:12}" "${u_exp:0:14}" "${u_quota:0:12}")
                        pgy_row "$row_line"
                    done < <(python3 -c "
import json, sys, time
try:
    with open('$xray_db', 'r', encoding='utf-8') as f:
        users = json.load(f)
    for u in users:
        user = u.get('username', '')
        proto = str(u.get('protocol') or u.get('proto') or 'all').upper()
        exp_ts = u.get('exp_ts', 0)
        exp_date = time.strftime('%Y-%m-%d', time.localtime(exp_ts)) if exp_ts else 'Lifetime'
        q_val = u.get('quota_gb', 0)
        quota = (str(q_val) + ' GB') if q_val and q_val > 0 else 'Unlimited'
        print(user + '|' + proto + '|' + exp_date + '|' + quota)
except Exception:
    pass
" 2>/dev/null)
                fi
                if [[ "$found_any" != "true" ]]; then
                    pgy_row "${C_GRAY}(Belum ada akun Xray terdaftar)${C_RESET}"
                fi
                pgy_box_bot
                echo
                read -r -p "$(echo -e "${C_PROMPT}  Tekan Enter untuk kembali...${C_RESET}")"
                ;;
            5)
                echo
                read -r -p "$(echo -e "${C_PROMPT}  Masukkan Username: ${C_RESET}")" s_user
                if [[ -n "$s_user" ]]; then
                    pgy_xray_client_config_show "$s_user"
                fi
                echo
                read -r -p "$(echo -e "${C_PROMPT}  Tekan Enter untuk kembali...${C_RESET}")"
                ;;
            6)
                echo
                pgy_box_top
                pgy_box_header "XRAY CORE SERVICE STATUS & LOG"
                pgy_box_divider
                local xr_st
                xr_st=$(systemctl is-active xray 2>/dev/null || echo "inactive")
                if [[ "$xr_st" == "active" ]]; then
                    pgy_row "${C_GRAY}SERVICE STATUS :${C_RESET} ${C_GREEN}Active (Running)${C_RESET}"
                else
                    pgy_row "${C_GRAY}SERVICE STATUS :${C_RESET} ${C_RED}Inactive / Stopped${C_RESET}"
                fi
                pgy_box_bot
                echo
                echo -e "${C_TITLE}  --- RECENT XRAY LOGS (15 Lines) ---${C_RESET}"
                journalctl -u xray -n 15 --no-pager 2>/dev/null || true
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
