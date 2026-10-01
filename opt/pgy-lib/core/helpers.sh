#!/bin/bash
# ============================================================
# Auto Script SSH By : ProgoCloud
# Module: core/helpers.sh - Text formatting, metrics, and prompts
# ============================================================

# Logging helpers
log()  { echo -e "${CYAN:-$C_CYAN}[ProgoCloud]${NC:-$C_RESET} $*"; }
ok()   { echo -e "${GREEN:-$C_GREEN}[OK]${NC:-$C_RESET} $*"; }
warn() { echo -e "${YELLOW:-$C_YELLOW}[WARN]${NC:-$C_RESET} $*" >&2; }
die()  { echo -e "${RED:-$C_RED}[ERROR]${NC:-$C_RESET} $*" >&2; exit 1; }
subtle() { echo -e "${YELLOW:-$C_YELLOW}$*${NC:-$C_RESET}"; }
hr()   { echo "------------------------------------------------------------"; }

press_enter() {
    if [[ "${PGY_ACTION_PAUSE_GUARD:-${TDZ_ACTION_PAUSE_GUARD:-}}" == "active" ]]; then
        [[ "${PGY_ACTION_PAUSED:-${TDZ_ACTION_PAUSED:-false}}" == "true" ]] && return
        PGY_ACTION_PAUSED=true
        TDZ_ACTION_PAUSED=true
    fi
    echo -e "\nTekan ${C_YELLOW}[Enter]${C_RESET} untuk kembali ke menu..." && read -r || true
}

pgy_run_action() {
    local PGY_ACTION_PAUSE_GUARD="active"
    local PGY_ACTION_PAUSED="false"
    local TDZ_ACTION_PAUSE_GUARD="active"
    local TDZ_ACTION_PAUSED="false"
    "$@"
    local action_status=$?
    press_enter
    return "$action_status"
}

tdz_run_action() { pgy_run_action "$@"; }

invalid_option() {
    echo -e "\n${C_RED}[ERROR] Pilihan tidak valid.${C_RESET}" && sleep 1
}

# CPU percentage computation
compute_cpu_pct() {
    local cpu_pct="0"
    if command -v vmstat >/dev/null 2>&1; then
        local idle
        idle=$(vmstat 1 2 2>/dev/null | tail -n1 | awk '{print $(NF-2)}')
        if [[ "$idle" =~ ^[0-9]+$ ]]; then
            cpu_pct=$(( 100 - idle ))
            (( cpu_pct < 0 )) && cpu_pct=0
            (( cpu_pct > 100 )) && cpu_pct=100
            printf '%d' "$cpu_pct"
            return
        fi
    fi

    if [[ -r /proc/stat ]]; then
        local user nice system idle iowait irq softirq steal
        read -r _ user nice system idle iowait irq softirq steal _ < /proc/stat 2>/dev/null || true
        local total_1=$(( user + nice + system + idle + ${iowait:-0} + ${irq:-0} + ${softirq:-0} + ${steal:-0} ))
        local idle_1=$(( idle + ${iowait:-0} ))
        sleep 0.2
        read -r _ user nice system idle iowait irq softirq steal _ < /proc/stat 2>/dev/null || true
        local total_2=$(( user + nice + system + idle + ${iowait:-0} + ${irq:-0} + ${softirq:-0} + ${steal:-0} ))
        local idle_2=$(( idle + ${iowait:-0} ))
        local d_total=$(( total_2 - total_1 ))
        local d_idle=$(( idle_2 - idle_1 ))
        if (( d_total > 0 )); then
            cpu_pct=$(( ( (d_total - d_idle) * 100 ) / d_total ))
            (( cpu_pct < 0 )) && cpu_pct=0
            (( cpu_pct > 100 )) && cpu_pct=100
            printf '%d' "$cpu_pct"
            return
        fi
    fi

    printf '%d' "$cpu_pct"
}

# Formatting Helpers
pgy_format_date_display() {
    local raw_date="$1"
    [[ -n "$raw_date" ]] || { printf 'N/A'; return 0; }
    if date -d "$raw_date" '+%d %b %Y' 2>/dev/null; then
        return 0
    fi
    printf '%s' "$raw_date"
}
tdz_format_date_display() { pgy_format_date_display "$@"; }

pgy_format_epoch_datetime_display() {
    local raw_epoch="$1"
    if [[ "$raw_epoch" =~ ^[0-9]+$ ]] && (( raw_epoch > 0 )); then
        date -d "@$raw_epoch" '+%d %b %Y %H:%M' 2>/dev/null || date -r "$raw_epoch" '+%d %b %Y %H:%M' 2>/dev/null || printf 'N/A'
        return 0
    fi
    printf 'N/A'
}
tdz_format_epoch_datetime_display() { pgy_format_epoch_datetime_display "$@"; }

pgy_format_file_size() {
    local file="$1"
    [[ -f "$file" ]] || { printf '0 B'; return 0; }
    local size_bytes
    size_bytes=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null || echo 0)
    if (( size_bytes >= 1073741824 )); then
        awk -v b="$size_bytes" 'BEGIN { printf "%.2f GB", b / 1073741824 }'
    elif (( size_bytes >= 1048576 )); then
        awk -v b="$size_bytes" 'BEGIN { printf "%.2f MB", b / 1048576 }'
    elif (( size_bytes >= 1024 )); then
        awk -v b="$size_bytes" 'BEGIN { printf "%.1f KB", b / 1024 }'
    else
        printf '%d B' "$size_bytes"
    fi
}
tdz_format_file_size() { pgy_format_file_size "$@"; }

pgy_quota_is_unlimited() {
    local quota="$1"
    [[ -z "$quota" || "$quota" == "0" || "$quota" == "unlimited" || "$quota" == "Unlimited" ]]
}
tdz_quota_is_unlimited() { pgy_quota_is_unlimited "$@"; }
quota_is_unlimited() { pgy_quota_is_unlimited "$@"; }

pgy_format_used_bytes() {
    local used_bytes="$1"
    [[ "$used_bytes" =~ ^[0-9]+$ ]] || used_bytes=0
    if (( used_bytes >= 1073741824 )); then
        awk -v b="$used_bytes" 'BEGIN { printf "%.2f GB", b / 1073741824 }'
    elif (( used_bytes >= 1048576 )); then
        awk -v b="$used_bytes" 'BEGIN { printf "%.2f MB", b / 1048576 }'
    elif (( used_bytes >= 1024 )); then
        awk -v b="$used_bytes" 'BEGIN { printf "%.1f KB", b / 1024 }'
    else
        printf '%d B' "$used_bytes"
    fi
}
tdz_format_used_bytes() { pgy_format_used_bytes "$@"; }
format_used_bytes() { pgy_format_used_bytes "$@"; }

pgy_format_quota_gb() {
    local quota_gb="$1"
    if pgy_quota_is_unlimited "$quota_gb"; then
        printf 'Unlimited'
        return 0
    fi
    if [[ "$quota_gb" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        printf '%s GB' "$quota_gb"
        return 0
    fi
    printf '%s' "$quota_gb"
}
tdz_format_quota_gb() { pgy_format_quota_gb "$@"; }
format_quota_gb() { pgy_format_quota_gb "$@"; }

pgy_format_bandwidth_usage() {
    local used_bytes="$1" quota_gb="$2"
    local used_display quota_display
    used_display=$(pgy_format_used_bytes "$used_bytes")
    quota_display=$(pgy_format_quota_gb "$quota_gb")
    printf '%s / %s' "$used_display" "$quota_display"
}
tdz_format_bandwidth_usage() { pgy_format_bandwidth_usage "$@"; }
format_bandwidth_usage() { pgy_format_bandwidth_usage "$@"; }

format_rate_from_kbps() {
    local kbps="$1"
    if [[ "$kbps" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        awk -v val="$kbps" '
        BEGIN {
            if (val >= 1048576) {
                printf "%.2f Gbps", val / 1048576;
            } else if (val >= 1024) {
                printf "%.2f Mbps", val / 1024;
            } else {
                printf "%.2f Kbps", val;
            }
        }'
    else
        echo "0.00 Kbps"
    fi
}

format_trial_time_left() {
    local expires_epoch="$1"
    local now left_sec hours mins secs
    now=$(date +%s)
    if [[ ! "$expires_epoch" =~ ^[0-9]+$ ]] || (( expires_epoch <= now )); then
        printf 'Expired'
        return 0
    fi
    left_sec=$(( expires_epoch - now ))
    hours=$(( left_sec / 3600 ))
    mins=$(( (left_sec % 3600) / 60 ))
    secs=$(( left_sec % 60 ))
    if (( hours > 0 )); then
        printf '%dh %dm' "$hours" "$mins"
    elif (( mins > 0 )); then
        printf '%dm %ds' "$mins" "$secs"
    else
        printf '%ds' "$secs"
    fi
}

ui_spinner_wait() {
    local pid="$1" label="${2:-Memproses}"
    local start_ts now elapsed frame_idx rc
    local -a frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local formatted_time

    if [[ ! "${pid}" =~ ^[0-9]+$ ]]; then
        return 1
    fi
    if [[ ! -t 1 ]]; then
        wait "${pid}"
        return $?
    fi

    printf '\033[?25l' 2>/dev/null || true
    start_ts="$(date +%s 2>/dev/null || echo 0)"
    frame_idx=0
    while kill -0 "${pid}" 2>/dev/null; do
        now="$(date +%s 2>/dev/null || echo "${start_ts}")"
        elapsed=$(( now - start_ts ))
        if (( elapsed >= 60 )); then
            formatted_time="$(( elapsed / 60 ))m $(( elapsed % 60 ))s"
        else
            formatted_time="${elapsed}s"
        fi

        printf '\r\033[2K \033[1;36m%s\033[0m \033[1;37m%s\033[0m \033[0;36m(%s)\033[0m' \
            "${frames[$frame_idx]}" "${label}" "${formatted_time}"
        frame_idx=$(( (frame_idx + 1) % ${#frames[@]} ))
        sleep 0.08
    done

    wait "${pid}"
    rc=$?
    printf '\r\033[2K\033[?25h' 2>/dev/null || true
    return "${rc}"
}

run_step_with_spinner() {
    local label="$1"
    shift || true
    local log_file pid rc

    if [[ ! -t 1 ]]; then
        "$@"
        return $?
    fi

    mkdir -p "/tmp/pgy-run-state"
    log_file="$(mktemp "/tmp/pgy-run-state/run-step.XXXXXX.log")" || {
        "$@"
        return $?
    }
    (
        "$@"
    ) >"${log_file}" 2>&1 &
    pid=$!

    set +e
    ui_spinner_wait "${pid}" "${label}"
    rc=$?
    set -e

    if (( rc == 0 )); then
        rm -f "${log_file}" >/dev/null 2>&1 || true
        return 0
    fi

    warn "${label} gagal. Detail log:"
    hr
    tail -n 30 "${log_file}" 2>/dev/null || true
    hr
    rm -f "${log_file}" >/dev/null 2>&1 || true
    return "${rc}"
}
