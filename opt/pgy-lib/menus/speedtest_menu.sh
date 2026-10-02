#!/bin/bash
# ============================================================
# Auto Script SSH By : ProgoCloud
# Module: menus/speedtest_menu.sh - Speedtest & Network Benchmark Menu
# ============================================================

speedtest_benchmark_menu() {
    local isp_info ip isp country
    isp_info=$(pgy_speedtest_get_isp_info 2>/dev/null || echo "127.0.0.1|Local|Indonesia")
    IFS='|' read -r ip isp country <<< "$isp_info"

    while true; do
        clear; show_banner
        echo
        pgy_box_top
        pgy_box_header "SPEEDTEST & NETWORK BENCHMARK"
        pgy_box_divider
        pgy_row2 "${C_GRAY}ISP / HOST${C_RESET}" "${C_WHITE}${isp}${C_RESET}"
        pgy_row2 "${C_GRAY}IP / REGION${C_RESET}" "${C_YELLOW}${ip}${C_RESET} ${C_GRAY}(${country})${C_RESET}"
        pgy_box_divider
        pgy_menu1 "[ 1]" "Quick Speedtest (Auto Best Server)"
        pgy_menu1 "[ 2]" "Target Speedtest: Indonesia (Jakarta / Telkom)"
        pgy_menu1 "[ 3]" "Target Speedtest: Singapore (Singtel)"
        pgy_menu1 "[ 4]" "Target Speedtest: Malaysia (Kuala Lumpur)"
        pgy_menu1 "[ 5]" "Target Speedtest: Japan (Tokyo)"
        pgy_menu1 "[ 6]" "Target Speedtest: United States (Los Angeles)"
        pgy_menu1 "[ 7]" "Game Server Latency & Jitter Diagnostic"
        pgy_box_divider
        pgy_menu1 "[ 0]" "Return to Main Menu"
        pgy_box_bot
        echo
        read -r -p "$(echo -e "${C_PROMPT}  Select an option: ${C_RESET}")" choice || return
        case "$choice" in
            1) pgy_speedtest_run_quick ;;
            2) pgy_speedtest_run_target "ID" "Indonesia" ;;
            3) pgy_speedtest_run_target "SG" "Singapore" ;;
            4) pgy_speedtest_run_target "MY" "Malaysia" ;;
            5) pgy_speedtest_run_target "JP" "Japan" ;;
            6) pgy_speedtest_run_target "US" "United States" ;;
            7) pgy_speedtest_gaming_latency ;;
            0) return ;;
            *) invalid_option ;;
        esac
    done
}

speedtest_menu() {
    speedtest_benchmark_menu "$@"
}

