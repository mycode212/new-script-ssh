#!/bin/bash
# ============================================================
# Auto Script SSH By : ProgoCloud
# Module: features/speedtest.sh - Ookla Speedtest & Network Benchmark
# ============================================================

PGY_SPEEDTEST_DIR="/usr/local/bin"
PGY_SPEEDTEST_BIN="/usr/local/bin/pgy-speedtest"
PGY_SPEEDTEST_TMP="/tmp/pgy-speedtest"

pgy_speedtest_arch() {
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64|amd64) echo "x86_64" ;;
        aarch64|arm64) echo "aarch64" ;;
        armv7l|armhf) echo "armhf" ;;
        i386|i686) echo "i386" ;;
        *) echo "x86_64" ;;
    esac
}

pgy_speedtest_ensure_binary() {
    if [[ -x "$PGY_SPEEDTEST_BIN" ]]; then
        return 0
    fi

    local arch url
    arch=$(pgy_speedtest_arch)
    mkdir -p "$PGY_SPEEDTEST_TMP" "$PGY_SPEEDTEST_DIR"

    case "$arch" in
        x86_64)
            url="https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-linux-x86_64.tgz"
            ;;
        aarch64)
            url="https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-linux-aarch64.tgz"
            ;;
        armhf)
            url="https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-linux-armhf.tgz"
            ;;
        i386)
            url="https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-linux-i386.tgz"
            ;;
        *)
            url="https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-linux-x86_64.tgz"
            ;;
    esac

    if curl -fsSL --connect-timeout 10 --max-time 60 "$url" -o "$PGY_SPEEDTEST_TMP/speedtest.tgz" 2>/dev/null; then
        tar -xzf "$PGY_SPEEDTEST_TMP/speedtest.tgz" -C "$PGY_SPEEDTEST_TMP" 2>/dev/null
        if [[ -f "$PGY_SPEEDTEST_TMP/speedtest" ]]; then
            install -m 755 "$PGY_SPEEDTEST_TMP/speedtest" "$PGY_SPEEDTEST_BIN"
            rm -rf "$PGY_SPEEDTEST_TMP"
            return 0
        fi
    fi

    # Fallback to official package or python speedtest if binary fails
    if command -v speedtest >/dev/null 2>&1; then
        PGY_SPEEDTEST_BIN="$(command -v speedtest)"
        return 0
    fi

    rm -rf "$PGY_SPEEDTEST_TMP"
    return 1
}

pgy_speedtest_get_isp_info() {
    local ip isp org country
    ip=$(curl -fsSL --max-time 3 https://api.ipify.org 2>/dev/null || curl -fsSL --max-time 3 https://ifconfig.me 2>/dev/null || echo "Unknown")
    local geo_json
    geo_json=$(curl -fsSL --max-time 3 "http://ip-api.com/json/${ip}" 2>/dev/null || echo "{}")
    
    isp=$(echo "$geo_json" | grep -o '"isp":"[^"]*' | cut -d'"' -f4)
    org=$(echo "$geo_json" | grep -o '"org":"[^"]*' | cut -d'"' -f4)
    country=$(echo "$geo_json" | grep -o '"country":"[^"]*' | cut -d'"' -f4)

    [[ -z "$isp" ]] && isp="Unknown ISP"
    [[ -z "$country" ]] && country="Unknown Location"
    
    echo "$ip|$isp|$country"
}

pgy_speedtest_run_quick() {
    show_banner
    pgy_screen_title "QUICK SPEEDTEST (BEST SERVER)" "Mengukur kecepatan download, upload, ping, dan jitter ke server terdekat..."
    echo

    pgy_progress_begin 1 2 "Menyiapkan binary Ookla Speedtest"
    if ! pgy_speedtest_ensure_binary; then
        pgy_progress_failed
        echo -e "${C_RED}[ERROR] Gagal mengunduh binary Speedtest CLI. Pastikan VPS memiliki koneksi internet.${C_RESET}"
        press_enter
        return 1
    fi
    pgy_progress_done

    pgy_progress_begin 2 2 "Menjalankan pengujian kecepatan"
    local json_output
    json_output=$("$PGY_SPEEDTEST_BIN" --accept-license --accept-gdpr --format=json 2>/dev/null)
    local test_status=$?

    if [[ $test_status -ne 0 || -z "$json_output" ]]; then
        pgy_progress_failed
        echo -e "${C_RED}[ERROR] Pengujian speedtest gagal atau timeout.${C_RESET}"
        press_enter
        return 1
    fi
    pgy_progress_done

    # Parse JSON output
    local srv_name srv_loc srv_country srv_id
    local ping_latency ping_jitter
    local dl_bytes dl_mbps ul_bytes ul_mbps result_url

    srv_name=$(echo "$json_output" | grep -o '"name":"[^"]*' | head -n1 | cut -d'"' -f4)
    srv_loc=$(echo "$json_output" | grep -o '"location":"[^"]*' | head -n1 | cut -d'"' -f4)
    srv_country=$(echo "$json_output" | grep -o '"country":"[^"]*' | head -n1 | cut -d'"' -f4)
    srv_id=$(echo "$json_output" | grep -o '"id":[0-9]*' | head -n1 | cut -d: -f2)

    ping_latency=$(echo "$json_output" | grep -o '"latency":[0-9.]*' | head -n1 | cut -d: -f2)
    ping_jitter=$(echo "$json_output" | grep -o '"jitter":[0-9.]*' | head -n1 | cut -d: -f2)

    # bandwidth in bytes/sec -> Mbps (* 8 / 1000000)
    local dl_bandwidth ul_bandwidth
    dl_bandwidth=$(echo "$json_output" | grep -o '"download":{[^}]*' | grep -o '"bandwidth":[0-9]*' | cut -d: -f2)
    ul_bandwidth=$(echo "$json_output" | grep -o '"upload":{[^}]*' | grep -o '"bandwidth":[0-9]*' | cut -d: -f2)

    if [[ -n "$dl_bandwidth" && "$dl_bandwidth" -gt 0 ]]; then
        dl_mbps=$(awk -v bw="$dl_bandwidth" 'BEGIN { printf "%.2f", (bw * 8) / 1000000 }')
    else
        dl_mbps="0.00"
    fi

    if [[ -n "$ul_bandwidth" && "$ul_bandwidth" -gt 0 ]]; then
        ul_mbps=$(awk -v bw="$ul_bandwidth" 'BEGIN { printf "%.2f", (bw * 8) / 1000000 }')
    else
        ul_mbps="0.00"
    fi

    result_url=$(echo "$json_output" | grep -o '"url":"[^"]*' | head -n1 | cut -d'"' -f4)

    echo
    pgy_box_top "$C_CYAN"
    pgy_box_header "HASIL PENGUJIAN SPEEDTEST" "$C_CYAN" "$C_CYAN"
    pgy_box_divider "$C_CYAN"
    pgy_detail "Server Target" "${srv_name} (${srv_loc}, ${srv_country}) [ID: ${srv_id}]" "$C_WHITE"
    pgy_detail "Latensi (Ping)" "${ping_latency:-0} ms (Jitter: ${ping_jitter:-0} ms)" "$C_WHITE"
    pgy_box_divider "$C_CYAN"
    pgy_detail "Download Speed" "${dl_mbps} Mbps" "$C_GREEN"
    pgy_detail "Upload Speed" "${ul_mbps} Mbps" "$C_CYAN"
    if [[ -n "$result_url" ]]; then
        pgy_box_divider "$C_CYAN"
        pgy_row "$(printf "${C_GRAY}Hasil Gambar :${C_RESET}")" "$C_CYAN"
        pgy_row "$(printf "${C_YELLOW}%s${C_RESET}" "$result_url")" "$C_CYAN"
    fi
    pgy_box_bot "$C_CYAN"
    echo
    press_enter
}

pgy_speedtest_run_target() {
    local target_code=$1 target_label=$2
    show_banner
    pgy_screen_title "TARGET SPEEDTEST: ${target_label^^}" "Mencari server terbaik di region ${target_label}..."
    echo

    pgy_progress_begin 1 3 "Menyiapkan binary Speedtest CLI"
    if ! pgy_speedtest_ensure_binary; then
        pgy_progress_failed
        echo -e "${C_RED}[ERROR] Gagal memuat binary Speedtest.${C_RESET}"
        press_enter
        return 1
    fi
    pgy_progress_done

    pgy_progress_begin 2 3 "Mengambil daftar server di ${target_label}"
    local server_id=""
    case "$target_code" in
        ID) # Indonesia (Telkom / Biznet / Indosat Jakarta)
            server_id="51761" # Telkom Indonesia
            ;;
        SG) # Singapore (Singtel / StarHub)
            server_id="13623" # Singtel Singapore
            ;;
        MY) # Malaysia (Telekom Malaysia)
            server_id="17316"
            ;;
        JP) # Japan (Tokyo)
            server_id="21569"
            ;;
        US) # USA (Los Angeles)
            server_id="15782"
            ;;
        *)
            server_id=""
            ;;
    esac
    pgy_progress_done

    pgy_progress_begin 3 3 "Melakukan pengujian ke server ${target_label}"
    local json_output
    if [[ -n "$server_id" ]]; then
        json_output=$("$PGY_SPEEDTEST_BIN" --server-id="$server_id" --accept-license --accept-gdpr --format=json 2>/dev/null)
    else
        json_output=$("$PGY_SPEEDTEST_BIN" --accept-license --accept-gdpr --format=json 2>/dev/null)
    fi

    if [[ -z "$json_output" ]]; then
        # Retry with auto server if specific server id failed
        json_output=$("$PGY_SPEEDTEST_BIN" --accept-license --accept-gdpr --format=json 2>/dev/null)
    fi

    if [[ -z "$json_output" ]]; then
        pgy_progress_failed
        echo -e "${C_RED}[ERROR] Gagal melakukan benchmark ke server target.${C_RESET}"
        press_enter
        return 1
    fi
    pgy_progress_done

    local srv_name srv_loc srv_country srv_id
    local ping_latency ping_jitter dl_mbps ul_mbps result_url

    srv_name=$(echo "$json_output" | grep -o '"name":"[^"]*' | head -n1 | cut -d'"' -f4)
    srv_loc=$(echo "$json_output" | grep -o '"location":"[^"]*' | head -n1 | cut -d'"' -f4)
    srv_country=$(echo "$json_output" | grep -o '"country":"[^"]*' | head -n1 | cut -d'"' -f4)
    srv_id=$(echo "$json_output" | grep -o '"id":[0-9]*' | head -n1 | cut -d: -f2)

    ping_latency=$(echo "$json_output" | grep -o '"latency":[0-9.]*' | head -n1 | cut -d: -f2)
    ping_jitter=$(echo "$json_output" | grep -o '"jitter":[0-9.]*' | head -n1 | cut -d: -f2)

    local dl_bandwidth ul_bandwidth
    dl_bandwidth=$(echo "$json_output" | grep -o '"download":{[^}]*' | grep -o '"bandwidth":[0-9]*' | cut -d: -f2)
    ul_bandwidth=$(echo "$json_output" | grep -o '"upload":{[^}]*' | grep -o '"bandwidth":[0-9]*' | cut -d: -f2)

    if [[ -n "$dl_bandwidth" && "$dl_bandwidth" -gt 0 ]]; then
        dl_mbps=$(awk -v bw="$dl_bandwidth" 'BEGIN { printf "%.2f", (bw * 8) / 1000000 }')
    else
        dl_mbps="0.00"
    fi

    if [[ -n "$ul_bandwidth" && "$ul_bandwidth" -gt 0 ]]; then
        ul_mbps=$(awk -v bw="$ul_bandwidth" 'BEGIN { printf "%.2f", (bw * 8) / 1000000 }')
    else
        ul_mbps="0.00"
    fi

    result_url=$(echo "$json_output" | grep -o '"url":"[^"]*' | head -n1 | cut -d'"' -f4)

    echo
    pgy_box_top "$C_CYAN"
    pgy_box_header "HASIL SPEEDTEST (${target_label^^})" "$C_CYAN" "$C_CYAN"
    pgy_box_divider "$C_CYAN"
    pgy_detail "Server Target" "${srv_name} (${srv_loc}, ${srv_country}) [ID: ${srv_id}]" "$C_WHITE"
    pgy_detail "Latensi (Ping)" "${ping_latency:-0} ms (Jitter: ${ping_jitter:-0} ms)" "$C_WHITE"
    pgy_box_divider "$C_CYAN"
    pgy_detail "Download Speed" "${dl_mbps} Mbps" "$C_GREEN"
    pgy_detail "Upload Speed" "${ul_mbps} Mbps" "$C_CYAN"
    if [[ -n "$result_url" ]]; then
        pgy_box_divider "$C_CYAN"
        pgy_row "$(printf "${C_GRAY}Hasil Gambar :${C_RESET}")" "$C_CYAN"
        pgy_row "$(printf "${C_YELLOW}%s${C_RESET}" "$result_url")" "$C_CYAN"
    fi
    pgy_box_bot "$C_CYAN"
    echo
    press_enter
}

pgy_speedtest_gaming_latency() {
    show_banner
    pgy_screen_title "GAME SERVER LATENCY & JITTER" "Mengukur stabilitas ping & jitter ke server game terpopuler..."
    echo

    local -A games=(
        ["Mobile Legends (Singapore)"]="103.151.140.1"
        ["PUBG Mobile (Asia)"]="103.244.150.1"
        ["Valorant (Riot SEA)"]="162.249.72.1"
        ["Free Fire (Garena SG)"]="203.116.120.1"
        ["Genshin Impact (Asia)"]="8.209.112.1"
        ["Cloudflare DNS (1.1.1.1)"]="1.1.1.1"
        ["Google DNS (8.8.8.8)"]="8.8.8.8"
    )

    pgy_box_top "$C_CYAN"
    pgy_box_header "LATENSI SERVER GAME POPULER" "$C_CYAN" "$C_CYAN"
    pgy_box_divider "$C_CYAN"

    local game host ping_out avg_ping loss_pct color
    for game in "Mobile Legends (Singapore)" "PUBG Mobile (Asia)" "Valorant (Riot SEA)" "Free Fire (Garena SG)" "Genshin Impact (Asia)" "Cloudflare DNS (1.1.1.1)" "Google DNS (8.8.8.8)"; do
        host="${games[$game]}"
        ping_out=$(ping -c 4 -W 2 "$host" 2>/dev/null)
        if [[ $? -eq 0 ]]; then
            avg_ping=$(echo "$ping_out" | awk -F'/' 'END {print $5}')
            loss_pct=$(echo "$ping_out" | grep -o '[0-9]*% packet loss' | awk '{print $1}')
            
            # Format color based on ping
            if (( $(echo "${avg_ping:-999} < 50" | bc -l 2>/dev/null || echo 0) )); then
                color="$C_GREEN"
            elif (( $(echo "${avg_ping:-999} < 100" | bc -l 2>/dev/null || echo 0) )); then
                color="$C_YELLOW"
            else
                color="$C_RED"
            fi
            pgy_detail "$game" "${color}${avg_ping:-0} ms${C_RESET} ${C_GRAY}(Loss: ${loss_pct:-0%})${C_RESET}" "$C_WHITE"
        else
            pgy_detail "$game" "${C_RED}Timeout / Blocked${C_RESET}" "$C_WHITE"
        fi
    done
    pgy_box_bot "$C_CYAN"
    echo
    press_enter
}
