#!/bin/bash
# ============================================================
# Auto Script SSH By : ProgoCloud
# Module: menus/adblock_menu.sh - Server-Side Adblock Management Menu
# ============================================================

adblock_management_menu() {
    while true; do
        show_banner
        local ad_status
        ad_status=$(pgy_adblock_get_status)
        local status_color="$C_RED"
        [[ "$ad_status" =~ "Active" ]] && status_color="$C_GREEN"

        echo
        pgy_box_top
        pgy_box_header "SERVER-SIDE ADBLOCKER"
        pgy_box_divider
        pgy_row "${C_GRAY}STATUS :${C_RESET} ${status_color}${ad_status}${C_RESET} ${C_GRAY}(DNS Port :${ADBLOCK_PORT})${C_RESET}"
        pgy_box_divider
        pgy_menu1 "[ 1]" "Toggle Adblocker Service (ON / OFF)"
        pgy_menu1 "[ 2]" "Perbarui Database Iklan (Download Rules)"
        pgy_menu1 "[ 3]" "Tambah Domain ke Custom Blacklist (Blokir Manual)"
        pgy_menu1 "[ 4]" "Tambah Domain ke Custom Whitelist (Izinkan)"
        pgy_menu1 "[ 5]" "Lihat Daftar Blacklist & Whitelist Custom"
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
                pgy_run_action pgy_adblock_toggle
                ;;
            2)
                pgy_run_action pgy_adblock_update_rules
                ;;
            3)
                echo
                read -r -p "$(echo -e "${C_PROMPT}  Masukkan domain yang ingin diblokir (contoh: judol.com): ${C_RESET}")" b_dom
                if [[ -n "$b_dom" ]]; then
                    pgy_adblock_add_blacklist "$b_dom"
                    echo -e "${C_GREEN}  Domain ${b_dom} berhasil ditambahkan ke Blacklist.${C_RESET}"
                    sleep 1.5
                fi
                ;;
            4)
                echo
                read -r -p "$(echo -e "${C_PROMPT}  Masukkan domain yang ingin diizinkan (contoh: example.com): ${C_RESET}")" w_dom
                if [[ -n "$w_dom" ]]; then
                    pgy_adblock_add_whitelist "$w_dom"
                    echo -e "${C_GREEN}  Domain ${w_dom} berhasil ditambahkan ke Whitelist.${C_RESET}"
                    sleep 1.5
                fi
                ;;
            5)
                echo
                pgy_box_top
                pgy_box_header "CUSTOM BLACKLIST & WHITELIST"
                pgy_box_divider
                pgy_row "${C_TITLE}[ Custom Blacklist ]${C_RESET}"
                if [[ -s "$ADBLOCK_CUSTOM_BLACK" ]]; then
                    while IFS= read -r line; do pgy_row "  • $line"; done < "$ADBLOCK_CUSTOM_BLACK"
                else
                    pgy_row "  (Kosong)"
                fi
                pgy_box_divider
                pgy_row "${C_TITLE}[ Custom Whitelist ]${C_RESET}"
                if [[ -s "$ADBLOCK_CUSTOM_WHITE" ]]; then
                    while IFS= read -r line; do pgy_row "  • $line"; done < "$ADBLOCK_CUSTOM_WHITE"
                else
                    pgy_row "  (Kosong)"
                fi
                pgy_box_bot
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
