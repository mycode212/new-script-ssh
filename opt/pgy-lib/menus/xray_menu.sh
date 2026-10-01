#!/bin/bash
# ============================================================
# Auto Script SSH By : ProgoCloud
# Module: menus/xray_menu.sh - Xray Multi-Protocol Management Menu
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
        pgy_box_header "XRAY MULTI-PROTOCOL (VLESS / VMESS / TROJAN)"
        pgy_box_divider
        pgy_row "${C_GRAY}STATUS :${C_RESET} ${status_color}${xr_status}${C_RESET}"
        pgy_box_divider
        pgy_menu1 "[ 1]" "Buat Akun Xray Baru (VLess / VMess / Trojan)"
        pgy_menu1 "[ 2]" "Hapus Akun Xray"
        pgy_menu1 "[ 3]" "Perpanjang Masa Aktif Akun (Renew)"
        pgy_menu1 "[ 4]" "Daftar Semua Akun Xray Terdaftar"
        pgy_menu1 "[ 5]" "Lihat Detail Config & Link Klien (VMess/VLess/Trojan)"
        pgy_menu1 "[ 6]" "Toggle Xray Service (ON / OFF)"
        pgy_menu1 "[ 7]" "Rebuild & Sync Xray Outbounds (WARP + Adblock)"
        pgy_box_divider
        pgy_menu1 "[ 0]" "Kembali ke Menu Protokol"
        pgy_box_bot
        echo
        if ! read -r -p "$(echo -e "${C_PROMPT}  Pilih opsi [0-7]: ${C_RESET}")" choice; then
            echo
            return
        fi

        case $choice in
            1)
                echo
                echo -e "${C_TITLE}  --- BUAT AKUN XRAY BARU ---${C_RESET}"
                read -r -p "$(echo -e "${C_PROMPT}  Username: ${C_RESET}")" x_user
                [[ -z "$x_user" ]] && continue
                read -r -p "$(echo -e "${C_PROMPT}  Masa Aktif (Hari) [30]: ${C_RESET}")" x_exp
                x_exp=${x_exp:-30}
                read -r -p "$(echo -e "${C_PROMPT}  Protokol (vmess/vless/trojan/all) [all]: ${C_RESET}")" x_proto
                x_proto=${x_proto:-all}

                if pgy_xray_user_add "$x_user" "$x_proto" "$x_exp" "0"; then
                    echo -e "\n${C_GREEN}  Akun ${x_user} berhasil dibuat!${C_RESET}\n"
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
                pgy_box_header "DAFTAR AKUN XRAY"
                pgy_box_divider
                if [[ -s "$XRAY_USERS_DB" && "$XRAY_USERS_DB" != "[]" ]]; then
                    python3 - <<'PY' "$XRAY_USERS_DB"
import json, sys, time
try:
    with open(sys.argv[1], "r", encoding="utf-8") as f:
        users = json.load(f)
    print(f"  { 'USERNAME':<16} { 'PROTOKOL':<12} { 'EXPIRED':<20}")
    print("  " + "-" * 50)
    for u in users:
        exp_date = time.strftime("%Y-%m-%d", time.localtime(u.get("exp_ts", 0))) if u.get("exp_ts") else "Lifetime"
        print(f"  {u.get('username',''):<16} {u.get('protocol','all'):<12} {exp_date:<20}")
except Exception:
    print("  (Tidak ada akun)")
PY
                else
                    pgy_row "  (Belum ada akun Xray terdaftar)"
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
                pgy_run_action pgy_xray_toggle
                ;;
            7)
                pgy_run_action pgy_xray_generate_base_config
                pgy_xray_sync_users_to_config
                echo -e "${C_GREEN}  Konfigurasi Xray Core berhasil diselaraskan.${C_RESET}"
                sleep 1.5
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
