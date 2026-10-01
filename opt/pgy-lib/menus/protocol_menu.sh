#!/bin/bash
# ============================================================
# Auto Script SSH By : ProgoCloud
# Module: menus/protocol_menu.sh - VPN & Protocol Menu
# ============================================================

protocol_menu() {
    while true; do
        show_banner
        local badvpn_status="Inactive" badvpn_color="$C_RED"
        local zivpn_status="Inactive" zivpn_color="$C_RED"
        local ssl_tunnel_status="Inactive" ssl_tunnel_color="$C_RED"
        local dnstt_status="Inactive" dnstt_color="$C_RED"
        local nginx_status="Inactive" nginx_color="$C_RED"
        local openvpn_status="Not Installed" openvpn_color="$C_RED"
        if systemctl is-active --quiet badvpn; then badvpn_status="Active"; badvpn_color="$C_GREEN"; fi
        if systemctl is-active --quiet zivpn.service; then zivpn_status="Active"; zivpn_color="$C_GREEN"; fi
        if systemctl is-active --quiet haproxy; then
            ssl_tunnel_status="Active"
            ssl_tunnel_color="$C_GREEN"
        fi
        if systemctl is-active --quiet dnstt.service; then dnstt_status="Active"; dnstt_color="$C_GREEN"; fi
        if systemctl is-active --quiet nginx; then nginx_status="Active"; nginx_color="$C_GREEN"; fi
        if declare -F pgy_openvpn_is_active >/dev/null 2>&1 && pgy_openvpn_is_active; then
            openvpn_status="Active"; openvpn_color="$C_GREEN"
        elif declare -F pgy_openvpn_is_installed >/dev/null 2>&1 && pgy_openvpn_is_installed; then
            openvpn_status="Attention"; openvpn_color="$C_YELLOW"
        fi

        local warp_status="Inactive" warp_color="$C_RED"
        local adblock_status="Inactive" adblock_color="$C_RED"
        local xray_status="Inactive" xray_color="$C_RED"
        if declare -F pgy_warp_is_active >/dev/null 2>&1 && pgy_warp_is_active; then
            warp_status="Active"; warp_color="$C_GREEN"
        fi
        if declare -F pgy_adblock_is_active >/dev/null 2>&1 && pgy_adblock_is_active; then
            adblock_status="Active"; adblock_color="$C_GREEN"
        fi
        if declare -F pgy_xray_is_active >/dev/null 2>&1 && pgy_xray_is_active; then
            xray_status="Active"; xray_color="$C_GREEN"
        fi

        echo
        pgy_box_top
        pgy_box_header "PROTOCOL & PANEL MANAGEMENT"
        pgy_box_divider
        pgy_row "${C_GRAY}TUNNELLING & NETWORK PROTOCOLS${C_RESET}"
        pgy_menu_status "[ 1]" "Install badvpn (UDP 7300)" "$badvpn_status" "$badvpn_color"
        pgy_menu1 "[ 2]" "Uninstall badvpn"
        pgy_menu_status "[ 3]" "Install HAProxy (${EDGE_PUBLIC_HTTP_PORT}/${EDGE_PUBLIC_TLS_PORT})" "$ssl_tunnel_status" "$ssl_tunnel_color"
        pgy_menu1 "[ 4]" "Uninstall HAProxy Edge Stack"
        pgy_menu_status "[ 5]" "Install or View DNSTT (Port 53)" "$dnstt_status" "$dnstt_color"
        pgy_menu1 "[ 6]" "Uninstall DNSTT"
        pgy_menu_status "[ 7]" "Manage Nginx (${NGINX_INTERNAL_HTTP_PORT}/${NGINX_INTERNAL_TLS_PORT})" "$nginx_status" "$nginx_color"
        pgy_menu_status "[ 8]" "Install ZiVPN (UDP 5667)" "$zivpn_status" "$zivpn_color"
        pgy_menu1 "[ 9]" "Uninstall ZiVPN"
        if declare -F pgy_openvpn_menu >/dev/null 2>&1; then
            pgy_menu_status "[10]" "OpenVPN Protocol Suite" "$openvpn_status" "$openvpn_color"
        fi
        pgy_menu_status "[11]" "Cloudflare WARP Suite" "$warp_status" "$warp_color"
        pgy_menu_status "[12]" "Server-Side Adblocker" "$adblock_status" "$adblock_color"
        pgy_menu_status "[13]" "Xray Multi-Protocol Suite" "$xray_status" "$xray_color"
        pgy_box_divider
        pgy_menu1 "[ 0]" "Return to Main Menu"
        pgy_box_bot
        echo
        if ! read -r -p "$(echo -e "${C_PROMPT}  Select an option: ${C_RESET}")" choice; then
            echo
            return
        fi
        case $choice in
            1) pgy_run_action install_badvpn ;; 2) pgy_run_action uninstall_badvpn ;;
            3) pgy_run_action install_ssl_tunnel ;; 4) pgy_run_action uninstall_ssl_tunnel ;;
            5) pgy_run_action install_dnstt ;; 6) pgy_run_action uninstall_dnstt ;;
            7) nginx_proxy_menu ;;
            8) pgy_run_action install_zivpn ;; 9) pgy_run_action uninstall_zivpn ;;
            10) if declare -F pgy_openvpn_menu >/dev/null 2>&1; then pgy_openvpn_menu; else invalid_option; fi ;;
            11) if declare -F warp_management_menu >/dev/null 2>&1; then warp_management_menu; else invalid_option; fi ;;
            12) if declare -F adblock_quick_protocol_menu >/dev/null 2>&1; then adblock_quick_protocol_menu; else invalid_option; fi ;;
            13) if declare -F xray_management_menu >/dev/null 2>&1; then xray_management_menu; else invalid_option; fi ;;
            0) return ;;
            *) invalid_option ;;
        esac
    done
}

