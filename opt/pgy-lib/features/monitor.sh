#!/bin/bash
# ============================================================
# Auto Script SSH By : ProgoCloud
# Module: features/monitor.sh - Real-time stats & traffic monitoring
# ============================================================

# Cache variable initializations
SSH_SESSION_CACHE_TS=0
SSH_SESSION_CACHE_TTL=10
SSH_SESSION_CACHE_DB_MTIME=0
SSH_SESSION_TOTAL=0
SSH_CONNECTION_TOTAL=0
SSH_SESSION_COUNTS=()
SSH_SESSION_PIDS=()

BANNER_CACHE_TS=0
BANNER_CACHE_TTL=60
BANNER_CACHE_OS_NAME=""
BANNER_CACHE_UP_TIME=""
BANNER_CACHE_RAM_USAGE="0.00"
BANNER_CACHE_CPU_LOAD="0.00"
BANNER_CACHE_TOTAL_USERS=0
BANNER_CACHE_ONLINE_USERS=0

DASH_CACHE_TS=0
DASH_CACHE_TTL=300
DASH_CACHE_OS_NAME="Linux"
DASH_CACHE_UPTIME="unknown"
DASH_CACHE_CPU_LOAD="0.00"
DASH_CACHE_CPU_CORES=1
DASH_CACHE_RAM_PCT="0"
DASH_CACHE_RAM_USED="0 / 0"
DASH_CACHE_DISK_PCT="0"
DASH_CACHE_TOTAL_USERS=0
DASH_CACHE_ONLINE_USERS=0
DASH_CACHE_LOCATION="N/A"
DASH_CACHE_ISP="N/A"
DASH_CACHE_PUBLIC_IP="N/A"
DASH_CACHE_DOMAIN="None"

refresh_ssh_session_cache() {
    local now db_mtime
    now=$(date +%s)
    db_mtime=$(stat -c %Y "$DB_FILE" 2>/dev/null || echo 0)

    if (( SSH_SESSION_CACHE_TS > 0 && now - SSH_SESSION_CACHE_TS < SSH_SESSION_CACHE_TTL && db_mtime == SSH_SESSION_CACHE_DB_MTIME )); then
        return
    fi

    SSH_SESSION_COUNTS=()
    SSH_SESSION_PIDS=()
    SSH_SESSION_TOTAL=0
    SSH_CONNECTION_TOTAL=0
    SSH_SESSION_CACHE_DB_MTIME=$db_mtime

    if [[ ! -s "$DB_FILE" ]]; then
        SSH_SESSION_CACHE_TS=$now
        return
    fi

    local -A managed_user_lookup=()
    local -A uid_user_lookup=()
    local -A session_pids=()
    local -A sshd_session_pids=()
    local -A who_online=()
    local -A pam_online=()
    local -A pam_session_pids=()
    local -A openvpn_online=()
    local managed_user system_user system_uid ssh_pid ssh_comm ssh_args ssh_user

    while IFS=: read -r managed_user _rest; do
        [[ -n "$managed_user" && "$managed_user" != \#* ]] && managed_user_lookup["$managed_user"]=1
    done < "$DB_FILE"

    local auth_marker marker_security marker_version marker_user marker_pid marker_start marker_extra marker_name actual_start actual_comm
    shopt -s nullglob
    for auth_marker in "$SSH_AUTH_SESSION_DIR"/*.session; do
        [[ -f "$auth_marker" && ! -L "$auth_marker" ]] || continue
        marker_security=$(stat -c '%u:%a' "$auth_marker" 2>/dev/null || true)
        marker_version="" marker_user="" marker_pid="" marker_start="" marker_extra=""
        IFS=$'\t' read -r marker_version marker_user marker_pid marker_start marker_extra < "$auth_marker" || true
        marker_name=${auth_marker##*/}
        marker_name=${marker_name%.session}
        actual_start=$(awk '{print $22}' "/proc/$marker_pid/stat" 2>/dev/null || true)
        actual_comm=$(cat "/proc/$marker_pid/comm" 2>/dev/null || true)
        if [[ "$marker_security" == "0:600" && "$marker_version" == "v1" &&
              "$marker_pid" =~ ^[0-9]+$ && "$marker_pid" == "$marker_name" &&
              "$marker_start" =~ ^[0-9]+$ && "$actual_start" == "$marker_start" &&
              ( "$actual_comm" == "sshd" || "$actual_comm" == "sshd-session" ) &&
              -n "${managed_user_lookup[$marker_user]+x}" ]]; then
            pam_online["$marker_user"]=$(( ${pam_online["$marker_user"]:-0} + 1 ))
            pam_session_pids["$marker_user"]+="$marker_pid "
        fi
    done

    while IFS=: read -r system_user _ system_uid _rest; do
        [[ -n "$system_user" && "$system_uid" =~ ^[0-9]+$ ]] && uid_user_lookup["$system_uid"]="$system_user"
    done < /etc/passwd

    # ── METHOD A: `who` — catches ALL logged-in users (records utmp).
    # Works for direct-SSH, WS-bridge, HAProxy — any session sshd logged in.
    # This is the primary detector and the most reliable.
    # Also counts distinct login sessions per user (for connection-limit enforcement).
    local who_line
    while read -r who_line; do
        # who output: "username pts/0 2026-06-25 12:34 (1.2.3.4)"
        who_user=$(echo "$who_line" | awk '{print $1}')
        [[ -z "$who_user" ]] && continue
        [[ -n "${managed_user_lookup[$who_user]+x}" ]] || continue
        who_online["$who_user"]=$(( ${who_online["$who_user"]:-0} + 1 ))
    done < <(who 2>/dev/null)

    # ── METHOD B: only authenticated OpenSSH child titles count. Pre-auth
    # monitor/network processes are intentionally excluded.
    while read -r ssh_pid ssh_comm ssh_args; do
        [[ "$ssh_pid" =~ ^[0-9]+$ ]] || continue
        [[ "$ssh_comm" == "sshd" || "$ssh_comm" == "sshd-session" ]] || continue
        if [[ "$ssh_args" =~ ^(sshd|sshd-session):[[:space:]]+([A-Za-z0-9_][A-Za-z0-9_.-]{0,31})@(notty|pts/[^[:space:]]+|tty[^[:space:]]*)$ ]]; then
            ssh_user=${BASH_REMATCH[2]}
            if [[ -n "${managed_user_lookup[$ssh_user]+x}" ]]; then
                session_pids["$ssh_user"]+="$ssh_pid "
                sshd_session_pids["$ssh_user"]+="$ssh_pid "
            fi
        fi
    done < <(ps -eo pid=,comm=,args= --no-headers 2>/dev/null)

    # ── METHOD C: UID-based process scan catches ALL PIDs owned by managed users
    # (bash, sftp-server, scp, etc.). Needed for bandwidth tracking via /proc/$pid/io
    # because Method A (`who`) gives us no PIDs, and Method B misses post-exec shells.
    # Do not use ps user= here: long usernames are truncated by procps.
    local _uid _u _pid
    while read -r _uid _pid; do
        [[ "$_uid" =~ ^[0-9]+$ && "$_pid" =~ ^[0-9]+$ ]] || continue
        _u="${uid_user_lookup[$_uid]:-}"
        [[ -n "$_u" && -n "${managed_user_lookup[$_u]+x}" ]] || continue
        session_pids[$_u]="${session_pids[$_u]}$_pid "
    done < <(ps -eo uid=,pid= --no-headers 2>/dev/null)

    # Optional OpenVPN instances share the same PGY account counters.  The
    # runtime output is local TSV and also reconciles byte deltas atomically.
    if declare -F pgy_openvpn_is_installed >/dev/null 2>&1 &&
       pgy_openvpn_is_installed && [[ -x "${PGY_OVPN_RUNTIME:-}" ]]; then
        local ovpn_user ovpn_instance ovpn_client_id ovpn_connected ovpn_rows="" ovpn_snapshot_mtime=0
        ovpn_snapshot_mtime=$(stat -c %Y "$PGY_OVPN_RUN/sessions.tsv" 2>/dev/null || echo 0)
        if [[ "$ovpn_snapshot_mtime" =~ ^[0-9]+$ ]] && (( ovpn_snapshot_mtime >= now - 5 )); then
            ovpn_rows=$(<"$PGY_OVPN_RUN/sessions.tsv")
        else
            ovpn_rows=$("$PGY_OVPN_RUNTIME" sessions 2>/dev/null || true)
        fi
        while IFS=$'\t' read -r ovpn_user ovpn_instance ovpn_client_id ovpn_connected; do
            [[ -n "$ovpn_user" && -n "${managed_user_lookup[$ovpn_user]+x}" ]] || continue
            openvpn_online["$ovpn_user"]=$(( ${openvpn_online["$ovpn_user"]:-0} + 1 ))
        done <<< "$ovpn_rows"
    fi

    local user pid pid_candidates
    for user in "${!managed_user_lookup[@]}"; do
        declare -A unique_pids=()
        pid_candidates="${session_pids[$user]:-}"

        for pid in $pid_candidates; do
            [[ "$pid" =~ ^[0-9]+$ ]] && unique_pids["$pid"]=1
        done

        declare -A unique_sshd_sessions=()
        for pid in ${sshd_session_pids[$user]:-}; do
            [[ "$pid" =~ ^[0-9]+$ ]] && unique_sshd_sessions["$pid"]=1
        done

        declare -A unique_pam_sessions=()
        for pid in ${pam_session_pids[$user]:-}; do
            [[ "$pid" =~ ^[0-9]+$ ]] && unique_pam_sessions["$pid"]=1
        done

        # Mark online only from authenticated SSH/OpenVPN records. Background
        # processes remain available for traffic accounting but cannot keep a
        # disconnected account falsely online.
        if [[ -n "${who_online[$user]+x}" || ${#unique_sshd_sessions[@]} -gt 0 ||
              ${#unique_pam_sessions[@]} -gt 0 ||
              ${openvpn_online[$user]:-0} -gt 0 ]]; then
            # CONNS count: sshd sessions are authoritative for tunnel/no-PTY users.
            local _conns=${who_online[$user]:-0}
            if (( ${#unique_sshd_sessions[@]} > _conns )); then
                _conns=${#unique_sshd_sessions[@]}
            fi
            if (( ${#unique_pam_sessions[@]} > _conns )); then
                _conns=${#unique_pam_sessions[@]}
            fi
            _conns=$((_conns + ${openvpn_online[$user]:-0}))
            SSH_SESSION_COUNTS["$user"]=$_conns
            for pid in "${!unique_pids[@]}"; do
                SSH_SESSION_PIDS["$user"]+="$pid "
            done
            SSH_SESSION_TOTAL=$((SSH_SESSION_TOTAL + 1))
            SSH_CONNECTION_TOTAL=$((SSH_CONNECTION_TOTAL + _conns))
        fi
    done

    SSH_SESSION_CACHE_TS=$now
}

count_managed_online_sessions() {
    refresh_ssh_session_cache
    echo "$SSH_SESSION_TOTAL"
}

count_managed_connections() {
    refresh_ssh_session_cache
    echo "$SSH_CONNECTION_TOTAL"
}

invalidate_banner_cache() {
    BANNER_CACHE_TS=0
    SSH_SESSION_CACHE_TS=0
    DASH_CACHE_TS=0
}

get_clean_os_name() {
    local os_release_file="${1:-/etc/os-release}"
    local os_name
    os_name=$(awk -F= '
        $1 == "PRETTY_NAME" {
            sub(/^[^=]*=/, "")
            gsub(/^"|"$/, "")
            print
            exit
        }
    ' "$os_release_file" 2>/dev/null)
    os_name=$(printf '%s' "$os_name" | sed -E 's/[[:space:]]+\([^()]*\)[[:space:]]*$//')
    printf '%s\n' "${os_name:-Linux}"
}

refresh_banner_cache() {
    local now
    now=$(date +%s)
    if (( BANNER_CACHE_TS > 0 && now - BANNER_CACHE_TS < BANNER_CACHE_TTL )); then
        return
    fi

    if [[ -z "$BANNER_CACHE_OS_NAME" ]]; then
        BANNER_CACHE_OS_NAME=$(get_clean_os_name)
    fi
    BANNER_CACHE_UP_TIME=$(uptime -p 2>/dev/null | sed 's/up //' || echo "unknown")
    BANNER_CACHE_RAM_USAGE=$(free -m | awk '/^Mem:/{if($2>0){printf "%.2f", $3*100/$2}else{print "0.00"}}')
    BANNER_CACHE_CPU_LOAD=$(awk '{print $1}' /proc/loadavg 2>/dev/null)
    if [[ -s "$DB_FILE" ]]; then
        BANNER_CACHE_TOTAL_USERS=$(grep -c . "$DB_FILE")
    else
        BANNER_CACHE_TOTAL_USERS=0
    fi
    BANNER_CACHE_ONLINE_USERS=$(count_managed_online_sessions)
    BANNER_CACHE_TS=$now
}

# ── Refresh dashboard info cache (location/ISP/IP/domain/perf) ──────────────
# Uses ip-api.com (free, no key, 45 req/min) with a 5-minute cache.
refresh_dashboard_cache() {
    local now
    now=$(date +%s)
    if (( DASH_CACHE_TS > 0 && now - DASH_CACHE_TS < DASH_CACHE_TTL )); then
        return
    fi

    # OS + uptime (local, fast)
    DASH_CACHE_OS_NAME=$(get_clean_os_name | cut -c1-28)
    DASH_CACHE_UPTIME=$(uptime -p 2>/dev/null | sed 's/up //' | cut -c1-20 || echo "unknown")

    # CPU load (1-min avg) + core count (1 core / N cores)
    DASH_CACHE_CPU_LOAD=$(awk '{printf "%.2f", $1}' /proc/loadavg 2>/dev/null || echo "0.00")
    local _cores
    _cores=$(nproc 2>/dev/null || echo 1)
    [[ -z "$_cores" || "$_cores" -lt 1 ]] && _cores=1
    DASH_CACHE_CPU_CORES=$_cores

    # RAM
    local ram_pct ram_used
    ram_pct=$(free | awk '/^Mem:/{if($2>0){printf "%.0f", $3*100/$2}else{print "0"}}')
    ram_used=$(free -h | awk '/^Mem:/{print $3 " / " $2}' 2>/dev/null)
    [[ -z "$ram_pct" ]] && ram_pct="0"
    [[ -z "$ram_used" ]] && ram_used="0 / 0"
    DASH_CACHE_RAM_PCT="$ram_pct"
    DASH_CACHE_RAM_USED="$ram_used"

    # Disk
    DASH_CACHE_DISK_PCT=$(df / 2>/dev/null | awk 'NR==2{gsub(/%/,""); print $5}' || echo "0")

    # User counts
    if [[ -s "$DB_FILE" ]]; then
        DASH_CACHE_TOTAL_USERS=$(grep -c . "$DB_FILE")
    else
        DASH_CACHE_TOTAL_USERS=0
    fi
    DASH_CACHE_ONLINE_USERS=$(count_managed_online_sessions)

    # Custom domain (from edge_cert.conf, set by Domain & SSL menu)
    local domain=""
    if [[ -f "$EDGE_CERT_INFO_FILE" ]]; then
        domain=$(grep -E '^EDGE_DOMAIN=' "$EDGE_CERT_INFO_FILE" 2>/dev/null | head -1 | sed -E 's/^EDGE_DOMAIN=//; s/^"//; s/"$//')
    fi
    [[ -z "$domain" ]] && domain="None"
    DASH_CACHE_DOMAIN="$domain"

    # Location / ISP / Public IP — fetch from ip-api.com (line mode, 4 fields)
    # Fallback to ifconfig.me for IP only if ip-api fails
    local api_data
    api_data=$(curl -s --max-time 4 "http://ip-api.com/line/?fields=country,city,isp,query" 2>/dev/null)
    if [[ -n "$api_data" && $(echo "$api_data" | wc -l) -ge 4 ]]; then
        local country city isp pubip
        country=$(echo "$api_data" | sed -n '1p')
        city=$(echo "$api_data" | sed -n '2p')
        isp=$(echo "$api_data" | sed -n '3p' | cut -c1-28)
        pubip=$(echo "$api_data" | sed -n '4p')
        [[ -n "$country" && -n "$city" ]] && DASH_CACHE_LOCATION="${country}, ${city}"
        [[ -n "$isp" ]] && DASH_CACHE_ISP="$isp"
        [[ -n "$pubip" ]] && DASH_CACHE_PUBLIC_IP="$pubip"
    else
        # Fallback: just get public IP
        local pubip
        pubip=$(curl -4 -s --max-time 4 ifconfig.me 2>/dev/null || echo "N/A")
        DASH_CACHE_PUBLIC_IP="$pubip"
    fi

    DASH_CACHE_TS=$now
}


format_rate_from_kbps() {
    local kbps=${1:-0}
    if (( kbps >= 1024 )); then
        printf "%d.%02d MB/s" $((kbps / 1024)) $((((kbps % 1024) * 100) / 1024))
    else
        printf "%d KB/s" "$kbps"
    fi
}

# Lightweight Bash Monitor (No vnStat required)
simple_live_monitor() {
    local iface=$1
    local rx_file="/sys/class/net/$iface/statistics/rx_bytes"
    local tx_file="/sys/class/net/$iface/statistics/tx_bytes"
    local interval=2
    local stop_monitor=0
    local rx1 tx1 rx2 tx2 rx_diff tx_diff rx_kbs tx_kbs rx_fmt tx_fmt

    if [[ -z "$iface" || ! -r "$rx_file" || ! -r "$tx_file" ]]; then
        echo -e "\n${C_RED}[ERROR] Could not read interface statistics for '${iface:-unknown}'.${C_RESET}"
        return
    fi

    echo -e "\n${C_BLUE}Starting Lightweight Traffic Monitor for $iface...${C_RESET}"
    echo -e "${C_DIM}Press [Ctrl+C] to stop.${C_RESET}\n"

    read -r rx1 < "$rx_file"
    read -r tx1 < "$tx_file"

    pgy_section "LIVE TRANSFER RATE"
    printf "  %-15s | %-15s\n" "DOWNLOAD" "UPLOAD"

    trap 'stop_monitor=1' INT TERM
    while (( ! stop_monitor )); do
        sleep "$interval"
        read -r rx2 < "$rx_file" || break
        read -r tx2 < "$tx_file" || break

        rx_diff=$((rx2 - rx1))
        tx_diff=$((tx2 - tx1))
        (( rx_diff < 0 )) && rx_diff=0
        (( tx_diff < 0 )) && tx_diff=0

        rx_kbs=$((rx_diff / 1024 / interval))
        tx_kbs=$((tx_diff / 1024 / interval))
        rx_fmt=$(format_rate_from_kbps "$rx_kbs")
        tx_fmt=$(format_rate_from_kbps "$tx_kbs")

        printf "\r%-15s | %-15s" "$rx_fmt" "$tx_fmt"

        rx1=$rx2
        tx1=$tx2
    done
    trap - INT TERM
    echo
}

prepare_traffic_history_service() {
    local iface="$1"
    pgy_apt_install vnstat >/dev/null 2>&1 || return 1
    vnstat --add -i "$iface" >/dev/null 2>&1 || true
    systemctl enable vnstat.service >/dev/null 2>&1 || return 1
    systemctl restart vnstat.service >/dev/null 2>&1 || return 1
    systemctl is-active --quiet vnstat.service
}

show_vnstat_history() {
    local iface="$1" history_json sample_count row year month day rx tx
    local rx_display tx_display
    local -a daily_rows=() monthly_rows=()

    clear; show_banner
    echo
    pgy_screen_title "DAILY & MONTHLY HISTORY" \
        "Persistent traffic totals collected for ${iface}."

    if ! history_json=$(vnstat --json -i "$iface" 2>/dev/null) ||
       ! jq -e --arg iface "$iface" \
           '.interfaces | map(select(.name == $iface)) | length > 0' \
           >/dev/null 2>&1 <<<"$history_json"; then
        pgy_message WARNING "Traffic history is not ready for ${iface}. The collector may still be creating its interface database."
        return 0
    fi

    sample_count=$(jq -r --arg iface "$iface" '
        [.interfaces[] | select(.name == $iface) |
         ((.traffic.day // []) + (.traffic.month // []))[]] | length
    ' <<<"$history_json" 2>/dev/null)
    [[ "$sample_count" =~ ^[0-9]+$ ]] || sample_count=0
    if (( sample_count == 0 )); then
        pgy_box_top
        pgy_box_header "COLLECTING TRAFFIC HISTORY"
        pgy_box_divider
        pgy_kv2 "INTERFACE" "$iface" "STATUS" "Collecting"
        pgy_box_bot
        pgy_message INFO "vnStat has started successfully and is collecting its first sample. Daily and monthly totals will appear here automatically after data is recorded."
        return 0
    fi

    mapfile -t daily_rows < <(jq -r --arg iface "$iface" '
        .interfaces[] | select(.name == $iface) |
        (.traffic.day // []) | reverse | .[:7][] |
        [.date.year, .date.month, .date.day, .rx, .tx] | @tsv
    ' <<<"$history_json" 2>/dev/null)
    mapfile -t monthly_rows < <(jq -r --arg iface "$iface" '
        .interfaces[] | select(.name == $iface) |
        (.traffic.month // []) | reverse | .[:6][] |
        [.date.year, .date.month, .rx, .tx] | @tsv
    ' <<<"$history_json" 2>/dev/null)

    if (( ${#daily_rows[@]} > 0 )); then
        pgy_box_top
        pgy_box_header "LATEST DAILY USAGE"
        pgy_box_divider
        for row in "${daily_rows[@]}"; do
            IFS=$'\t' read -r year month day rx tx <<<"$row"
            [[ "$year" =~ ^[0-9]{4}$ && "$month" =~ ^[0-9]{1,2}$ &&
               "$day" =~ ^[0-9]{1,2}$ ]] || continue
            printf -v day '%02d' "$((10#$day))"
            printf -v month '%02d' "$((10#$month))"
            rx_display=$(pgy_format_file_size "$rx")
            tx_display=$(pgy_format_file_size "$tx")
            pgy_row2 "${C_WHITE}${day}-${month}-${year}${C_RESET}" \
                "${C_GREEN}↓ ${rx_display}${C_RESET} ${C_CYAN}↑ ${tx_display}${C_RESET}"
        done
        pgy_box_bot
        echo
    fi

    if (( ${#monthly_rows[@]} > 0 )); then
        pgy_box_top
        pgy_box_header "LATEST MONTHLY USAGE"
        pgy_box_divider
        for row in "${monthly_rows[@]}"; do
            IFS=$'\t' read -r year month rx tx <<<"$row"
            [[ "$year" =~ ^[0-9]{4}$ && "$month" =~ ^[0-9]{1,2}$ ]] || continue
            printf -v month '%02d' "$((10#$month))"
            rx_display=$(pgy_format_file_size "$rx")
            tx_display=$(pgy_format_file_size "$tx")
            pgy_row2 "${C_WHITE}${month}-${year}${C_RESET}" \
                "${C_GREEN}↓ ${rx_display}${C_RESET} ${C_CYAN}↑ ${tx_display}${C_RESET}"
        done
        pgy_box_bot
    fi
}

traffic_monitor_menu() {
    clear; show_banner
    # Find active interface
    local iface
    iface=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)

    echo
    pgy_box_top
    pgy_box_header "NETWORK TRAFFIC MONITOR"
    pgy_box_divider
    pgy_row "${C_GRAY}INTERFACE${C_RESET} ${C_WHITE}${iface:-Not detected}${C_RESET}"
    pgy_box_divider
    pgy_menu1 "[ 1]" "Live Monitor"
    pgy_menu1 "[ 2]" "Total Traffic Since Boot"
    pgy_menu1 "[ 3]" "Daily and Monthly History"
    pgy_box_divider
    pgy_menu1 "[ 0]" "Return"
    pgy_box_bot
    echo
    read -r -p "$(echo -e "${C_PROMPT}  Select an option: ${C_RESET}")" t_choice

    if [[ "$t_choice" != "0" && -z "$iface" ]]; then
        echo -e "\n${C_RED}No active default network interface was detected.${C_RESET}"
        press_enter
        return
    fi
    case $t_choice in
        1) 
           simple_live_monitor "$iface"
           ;;
        2)
            local rx_total=$(cat /sys/class/net/$iface/statistics/rx_bytes)
            local tx_total=$(cat /sys/class/net/$iface/statistics/tx_bytes)
            local rx_mb=$((rx_total / 1024 / 1024))
            local tx_mb=$((tx_total / 1024 / 1024))
            echo -e "\n${C_BLUE}Total Traffic (Since Boot):${C_RESET}"
            echo -e "   Download: ${C_WHITE}${rx_mb} MB${C_RESET}"
            echo -e "   Upload:   ${C_WHITE}${tx_mb} MB${C_RESET}"
            press_enter
            ;;
        3) 
           if ! command -v vnstat &> /dev/null; then
               pgy_message INFO "Persistent daily and monthly traffic history needs a one-time service setup."
               read -p "  Prepare traffic history now? (y/n): " confirm
                if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
                    echo
                    pgy_section "PREPARATION"
                    if ! pgy_progress_run 1 1 "Preparing traffic history" \
                        prepare_traffic_history_service "$iface"; then
                        pgy_message ERROR "Traffic history could not be prepared."
                        press_enter
                        return
                    fi
               else
                    return
               fi
           fi
           show_vnstat_history "$iface"
           press_enter
           ;;
        *) return ;;
    esac
}

