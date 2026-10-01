#!/bin/bash
# ============================================================
# Auto Script SSH By : ProgoCloud
# Module: menus/adblock_menu.sh - Server-Side Adblock Management Menu
# ============================================================

adblock_management_menu() {
    while true; do
        show_banner
        local is_active=false
        if declare -F pgy_adblock_is_active >/dev/null 2>&1 && pgy_adblock_is_active; then
            is_active=true
        fi

        local ad_status
        ad_status=$(pgy_adblock_get_status)
        local status_color="$C_RED"
        [[ "$is_active" == "true" ]] && status_color="$C_GREEN"

        echo
        pgy_box_top
        pgy_box_header "ADBLOCK DATABASE MANAGEMENT"
        pgy_box_divider
        pgy_row "${C_GRAY}STATUS :${C_RESET} ${status_color}${ad_status}${C_RESET} ${C_GRAY}(DNS Port :${ADBLOCK_PORT})${C_RESET}"
        pgy_box_divider

        if [[ "$is_active" != "true" ]]; then
            pgy_row "${C_YELLOW}Perhatian: Service Adblocker saat ini NON-AKTIF.${C_RESET}"
            pgy_row "${C_GRAY}Aktifkan terlebih dahulu di Menu Protokol [3].${C_RESET}"
            pgy_box_divider
            pgy_menu1 "[ 1]" "Aktifkan Service Adblocker Sekarang"
            pgy_menu1 "[ 0]" "Kembali ke Menu Utama"
            pgy_box_bot
            echo
            if ! read -r -p "$(echo -e "${C_PROMPT}  Pilih opsi [0-1]: ${C_RESET}")" choice; then
                echo
                return
            fi
            case $choice in
                1) pgy_run_action pgy_adblock_toggle ;;
                0) return ;;
                *) invalid_option ;;
            esac
            continue
        fi

        pgy_menu1 "[ 1]" "Tambah Domain ke Custom Blacklist (Blokir Manual)"
        pgy_menu1 "[ 2]" "Tambah Domain ke Custom Whitelist (Izinkan)"
        pgy_menu1 "[ 3]" "Hapus Domain dari Custom Blacklist / Whitelist"
        pgy_menu1 "[ 4]" "Lihat Daftar Blacklist & Whitelist Custom"
        pgy_menu1 "[ 5]" "Perbarui Database Iklan (Download Rules)"
        pgy_box_divider
        pgy_menu1 "[ 0]" "Kembali ke Menu Utama"
        pgy_box_bot
        echo

        if ! read -r -p "$(echo -e "${C_PROMPT}  Pilih opsi [0-5]: ${C_RESET}")" choice; then
            echo
            return
        fi

        case $choice in
            1)
                echo
                read -r -p "$(echo -e "${C_PROMPT}  Masukkan domain yang ingin diblokir (contoh: judol.com): ${C_RESET}")" b_dom
                if [[ -n "$b_dom" ]]; then
                    pgy_adblock_add_blacklist "$b_dom"
                    echo -e "${C_GREEN}  Domain ${b_dom} berhasil ditambahkan ke Blacklist.${C_RESET}"
                    sleep 1.5
                fi
                ;;
            2)
                echo
                read -r -p "$(echo -e "${C_PROMPT}  Masukkan domain yang ingin diizinkan (contoh: example.com): ${C_RESET}")" w_dom
                if [[ -n "$w_dom" ]]; then
                    pgy_adblock_add_whitelist "$w_dom"
                    echo -e "${C_GREEN}  Domain ${w_dom} berhasil ditambahkan ke Whitelist.${C_RESET}"
                    sleep 1.5
                fi
                ;;
            3)
                echo
                echo -e "${C_TITLE}  --- HAPUS DOMAIN CUSTOM ---${C_RESET}"
                echo "  [1] Hapus dari Blacklist"
                echo "  [2] Hapus dari Whitelist"
                echo "  [0] Batal"
                echo
                read -r -p "$(echo -e "${C_PROMPT}  Pilih [0-2]: ${C_RESET}")" del_type
                case "$del_type" in
                    1)
                        read -r -p "$(echo -e "${C_PROMPT}  Masukkan domain blacklist yang ingin dihapus: ${C_RESET}")" d_dom
                        if [[ -n "$d_dom" ]]; then
                            pgy_adblock_del_blacklist "$d_dom"
                            echo -e "${C_GREEN}  Domain ${d_dom} dihapus dari Blacklist.${C_RESET}"
                            sleep 1.5
                        fi
                        ;;
                    2)
                        read -r -p "$(echo -e "${C_PROMPT}  Masukkan domain whitelist yang ingin dihapus: ${C_RESET}")" d_dom
                        if [[ -n "$d_dom" ]]; then
                            pgy_adblock_del_whitelist "$d_dom"
                            echo -e "${C_GREEN}  Domain ${d_dom} dihapus dari Whitelist.${C_RESET}"
                            sleep 1.5
                        fi
                        ;;
                    *)
                        ;;
                esac
                ;;
            4)
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
            5)
                pgy_run_action pgy_adblock_update_rules
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

adblock_quick_protocol_menu() {
    while true; do
        show_banner
        local is_active=false
        if declare -F pgy_adblock_is_active >/dev/null 2>&1 && pgy_adblock_is_active; then
            is_active=true
        fi
        local ad_status
        ad_status=$(pgy_adblock_get_status)
        local status_color="$C_RED"
        [[ "$is_active" == "true" ]] && status_color="$C_GREEN"

        echo
        pgy_box_top
        pgy_box_header "SERVER-SIDE ADBLOCKER STACK"
        pgy_box_divider
        pgy_row "${C_GRAY}STATUS :${C_RESET} ${status_color}${ad_status}${C_RESET} ${C_GRAY}(DNS Port :${ADBLOCK_PORT})${C_RESET}"
        pgy_box_divider
        if [[ "$is_active" == "true" ]]; then
            pgy_menu1 "[ 1]" "Toggle Adblocker Service (Matikan)"
        else
            pgy_menu1 "[ 1]" "Toggle Adblocker Service (Aktifkan & Install)"
        fi
        pgy_menu1 "[ 2]" "Perbarui Database Iklan (Download Rules)"
        pgy_box_divider
        pgy_menu1 "[ 0]" "Kembali ke Menu Protokol"
        pgy_box_bot
        echo
        if ! read -r -p "$(echo -e "${C_PROMPT}  Pilih opsi [0-2]: ${C_RESET}")" choice; then
            echo
            return
        fi
        case $choice in
            1) pgy_run_action pgy_adblock_toggle ;;
            2) pgy_run_action pgy_adblock_update_rules ;;
            0) return ;;
            *) invalid_option ;;
        esac
    done
}
