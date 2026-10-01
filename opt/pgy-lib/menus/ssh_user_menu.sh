#!/bin/bash
# ============================================================
# Auto Script SSH By : ProgoCloud
# Module: menus/ssh_user_menu.sh - SSH User Management Menu
# ============================================================

ssh_user_management_menu() {
    while true; do
        show_banner
        local total_users online_users
        total_users=$(count_users 2>/dev/null || echo 0)
        online_users=$(count_online_users 2>/dev/null || echo 0)

        echo
        pgy_box_top
        pgy_box_header "SSH & WS USER MANAGEMENT"
        pgy_box_divider
        pgy_row "${C_GRAY}USERS :${C_RESET} ${C_WHITE}${total_users} terdaftar${C_RESET} │ ${C_GRAY}ONLINE :${C_RESET} ${C_GREEN}${online_users} sesi${C_RESET}"
        pgy_box_divider
        pgy_menu2 "[ 1]" "Create User"      "[ 7]" "List Users"
        pgy_menu2 "[ 2]" "Delete User"      "[ 8]" "Client Config"
        pgy_menu2 "[ 3]" "Renew Account"    "[ 9]" "Create Trial"
        pgy_menu2 "[ 4]" "Lock User"        "[10]" "Trial Accounts"
        pgy_menu2 "[ 5]" "Unlock Account"   "[11]" "Bandwidth Usage"
        pgy_menu2 "[ 6]" "Edit Details"     "[12]" "Bulk Create"
        pgy_box_divider
        pgy_menu1 "[ 0]" "Kembali ke Menu Utama"
        pgy_box_bot
        echo
        if ! read -r -p "$(echo -e "${C_PROMPT}  Pilih opsi [0-12]: ${C_RESET}")" choice; then
            echo
            return
        fi

        case $choice in
            1) pgy_run_action create_user ;;
            2) pgy_run_action delete_user ;;
            3) pgy_run_action renew_user ;;
            4) pgy_run_action lock_user ;;
            5) pgy_run_action unlock_user ;;
            6) pgy_run_action edit_user ;;
            7) pgy_run_action list_users ;;
            8) pgy_run_action client_config_menu ;;
            9) pgy_run_action create_trial_account ;;
            10) pgy_run_action list_trial_accounts ;;
            11) pgy_run_action view_user_bandwidth ;;
            12) pgy_run_action bulk_create_users ;;
            0) return ;;
            *) invalid_option ;;
        esac
    done
}
