#!/bin/bash
# ============================================================
# Auto Script SSH By : ProgoCloud
# Module: core/ui.sh - Box drawing UI components and dashboard banner
# ============================================================

# Box Drawing Tokens
pgy_box_top() {
    local color="${1:-$C_CYAN}"
    printf "  %s╔" "$color"
    printf '═%.0s' $(seq 1 "$PGY_BOX_WIDTH")
    printf "╗%s\n" "$C_RESET"
}
tdz_box_top() { pgy_box_top "$@"; }

pgy_box_bot() {
    local color="${1:-$C_CYAN}"
    printf "  %s╚" "$color"
    printf '═%.0s' $(seq 1 "$PGY_BOX_WIDTH")
    printf "╝%s\n" "$C_RESET"
}
tdz_box_bot() { pgy_box_bot "$@"; }

pgy_box_divider() {
    local color="${1:-$C_CYAN}"
    printf "  %s╟" "$color"
    printf '─%.0s' $(seq 1 "$PGY_BOX_WIDTH")
    printf "╢%s\n" "$C_RESET"
}
tdz_box_divider() { pgy_box_divider "$@"; }

pgy_box_header() {
    local title="$1" color="${2:-$C_CYAN}" title_color="${3:-$C_TITLE}"
    local title_clean title_content
    title_clean=$(_pgy_fit "$title" "$(( PGY_BOX_WIDTH - 6 ))")
    title_content="${title_color}${C_BOLD}▶ ${title_clean}${C_RESET}"
    local cw
    cw=$(_pgy_w "$title_content")
    local pad=$(( PGY_BOX_WIDTH - cw - 2 ))
    local spaces=""
    if (( pad > 0 )); then
        printf -v spaces "%${pad}s" ""
    fi
    printf "  ${color}║${C_RESET} %s%s ${color}║${C_RESET}\n" "$title_content" "$spaces"
}
tdz_box_header() { pgy_box_header "$@"; }

pgy_row() {
    local content="$1" color="${2:-$C_CYAN}"
    local max_inner=$(( PGY_BOX_WIDTH - 2 ))
    local clean cw
    clean=$(_pgy_strip_ansi "$content")
    cw=${#clean}
    if (( cw > max_inner )); then
        clean="${clean:0:$max_inner}"
        content="${clean}"
        cw=${#clean}
    fi
    local pad=$(( max_inner - cw ))
    local spaces=""
    if (( pad > 0 )); then
        printf -v spaces "%${pad}s" ""
    fi
    printf "  ${color}║${C_RESET} %s%s ${color}║${C_RESET}\n" "$content" "$spaces"
}
tdz_row() { pgy_row "$@"; }

pgy_row2() {
    local left="$1" right="$2" color="${3:-$C_CYAN}"
    local lw rw
    lw=$(_pgy_w "$left")
    rw=$(_pgy_w "$right")
    local inner_width=$(( PGY_BOX_WIDTH - 2 ))
    local gap=$(( inner_width - lw - rw ))
    local spaces=""
    if (( gap > 0 )); then
        printf -v spaces "%${gap}s" ""
    fi
    printf "  ${color}║${C_RESET} %s%s%s ${color}║${C_RESET}\n" "$left" "$spaces" "$right"
}
tdz_row2() { pgy_row2 "$@"; }

pgy_kv2() {
    local k1="$1" v1="$2" k2="$3" v2="$4" color="${5:-$C_CYAN}"
    local w1=$(( (PGY_BOX_WIDTH - 5) / 2 ))
    local w2=$(( (PGY_BOX_WIDTH - 5) - w1 ))
    local v1_max=$(( w1 - ${#k1} - 3 ))
    local v2_max=$(( w2 - ${#k2} - 3 ))
    (( v1_max < 0 )) && v1_max=0
    (( v2_max < 0 )) && v2_max=0
    local v1_fit v2_fit
    v1_fit=$(_pgy_fit "$v1" "$v1_max")
    v2_fit=$(_pgy_fit "$v2" "$v2_max")
    local col1 col2
    col1=$(printf "${C_GRAY}%s :${C_RESET} ${C_WHITE}%s${C_RESET}" "$k1" "$v1_fit")
    col2=$(printf "${C_GRAY}%s :${C_RESET} ${C_WHITE}%s${C_RESET}" "$k2" "$v2_fit")
    local c1w c2w
    c1w=$(_pgy_w "$col1")
    c2w=$(_pgy_w "$col2")
    local pad1=$(( w1 - c1w ))
    local pad2=$(( w2 - c2w ))
    local sp1="" sp2=""
    (( pad1 > 0 )) && printf -v sp1 "%${pad1}s" ""
    (( pad2 > 0 )) && printf -v sp2 "%${pad2}s" ""
    printf "  ${color}║${C_RESET} %s%s ${color}│${C_RESET} %s%s ${color}║${C_RESET}\n" "$col1" "$sp1" "$col2" "$sp2"
}
tdz_kv2() { pgy_kv2 "$@"; }

pgy_menu2() {
    local key1="$1" label1="$2" key2="$3" label2="$4" color="${5:-$C_CYAN}"
    local w1=$(( (PGY_BOX_WIDTH - 5) / 2 ))
    local w2=$(( (PGY_BOX_WIDTH - 5) - w1 ))
    local item1 item2
    item1=$(printf "${C_CHOICE}%s${C_RESET} %s" "$key1" "$label1")
    item2=$(printf "${C_CHOICE}%s${C_RESET} %s" "$key2" "$label2")
    local i1w i2w
    i1w=$(_pgy_w "$item1")
    i2w=$(_pgy_w "$item2")
    local pad1=$(( w1 - i1w ))
    local pad2=$(( w2 - i2w ))
    local sp1="" sp2=""
    (( pad1 > 0 )) && printf -v sp1 "%${pad1}s" ""
    (( pad2 > 0 )) && printf -v sp2 "%${pad2}s" ""
    printf "  ${color}║${C_RESET} %s%s ${color}│${C_RESET} %s%s ${color}║${C_RESET}\n" "$item1" "$sp1" "$item2" "$sp2"
}
tdz_menu2() { pgy_menu2 "$@"; }

pgy_menu1() {
    local key="$1" label="$2" color="${3:-$C_CYAN}"
    local item
    item=$(printf "${C_CHOICE}%s${C_RESET} %s" "$key" "$label")
    pgy_row "$item" "$color"
}
tdz_menu1() { pgy_menu1 "$@"; }

pgy_menu_status() {
    local key="$1" label="$2" status="$3" status_color="${4:-$C_WHITE}" color="${5:-$C_CYAN}"
    local left right
    left=$(printf "${C_CHOICE}%s${C_RESET} %s" "$key" "$label")
    right=$(printf "${status_color}%s${C_RESET}" "$status")
    pgy_row2 "$left" "$right" "$color"
}
tdz_menu_status() { pgy_menu_status "$@"; }

pgy_bar() {
    local used_pct="$1" width="${2:-12}"
    (( used_pct < 0 )) && used_pct=0
    (( used_pct > 100 )) && used_pct=100
    local filled=$(( (used_pct * width) / 100 ))
    local empty=$(( width - filled ))
    local bar_color="$C_GREEN"
    (( used_pct >= 70 )) && bar_color="$C_YELLOW"
    (( used_pct >= 90 )) && bar_color="$C_RED"
    local bar=""
    (( filled > 0 )) && printf -v bar '%*s' "$filled" '' && bar="${bar// /█}"
    local bg=""
    (( empty > 0 )) && printf -v bg '%*s' "$empty" '' && bg="${bg// /░}"
    printf "%s%s%s%s" "$bar_color" "$bar" "$C_GRAY" "$bg$C_RESET"
}
tdz_bar() { pgy_bar "$@"; }

pgy_kv_bar() {
    local label="$1" pct="$2" detail="$3" width="${4:-10}" color="${5:-$C_CYAN}"
    local bar_str
    bar_str=$(pgy_bar "$pct" "$width")
    local pct_color="$C_GREEN"
    (( pct >= 70 )) && pct_color="$C_YELLOW"
    (( pct >= 90 )) && pct_color="$C_RED"
    local left right
    left=$(printf "${C_GRAY}%s :${C_RESET} [%s] ${pct_color}%3d%%%s" "$label" "$bar_str" "$pct" "$C_RESET")
    right=$(printf "${C_WHITE}%s${C_RESET}" "$detail")
    pgy_row2 "$left" "$right" "$color"
}
tdz_kv_bar() { pgy_kv_bar "$@"; }

pgy_screen_title() {
    local title="$1" subtitle="${2:-}"
    pgy_refresh_box_width
    [[ -t 1 ]] && clear
    echo
    pgy_box_top
    pgy_box_header "$title"
    if [[ -n "$subtitle" ]]; then
        pgy_box_divider
        pgy_row "$(printf "${C_GRAY}%s${C_RESET}" "$subtitle")"
    fi
    pgy_box_bot
    echo
}
tdz_screen_title() { pgy_screen_title "$@"; }

pgy_section() {
    local title="$1" color="${2:-$C_CYAN}"
    local sep_len=$(( PGY_BOX_WIDTH - ${#title} - 5 ))
    (( sep_len < 2 )) && sep_len=2
    local sep=""
    printf -v sep '─%.0s' $(seq 1 "$sep_len")
    echo
    echo -e "  ${color}┌─${C_BOLD}${C_WHITE} ${title} ${C_RESET}${color}${sep}${C_RESET}"
}
tdz_section() { pgy_section "$@"; }

pgy_detail() {
    local label="$1" value="$2"
    printf "  ${C_GRAY}│${C_RESET}  %-18s : ${C_WHITE}%s${C_RESET}\n" "$label" "$value"
}
tdz_detail() { pgy_detail "$@"; }

pgy_message() {
    local kind="$1" text="$2" color="$C_CYAN" tag="INFO"
    case "$kind" in
        success|ok) color="$C_GREEN"; tag="OK" ;;
        warn|warning) color="$C_YELLOW"; tag="WARN" ;;
        danger|error|fail) color="$C_RED"; tag="ERROR" ;;
        note) color="$C_CYAN"; tag="NOTE" ;;
    esac
    echo -e "  ${color}[${tag}]${C_RESET} ${text}"
}
tdz_message() { pgy_message "$@"; }

PGY_PROGRESS_PID=""
PGY_PROGRESS_LABEL=""

pgy_progress_begin() {
    local step_num="" total_steps="" label=""
    if [[ "$1" =~ ^[0-9]+$ && "$2" =~ ^[0-9]+$ ]]; then
        step_num="$1"
        total_steps="$2"
        label="$3"
    else
        label="$1"
    fi

    # Terminate any previous spinner
    if [[ -n "${PGY_PROGRESS_PID:-}" ]] && kill -0 "${PGY_PROGRESS_PID}" 2>/dev/null; then
        kill "${PGY_PROGRESS_PID}" 2>/dev/null || true
        wait "${PGY_PROGRESS_PID}" 2>/dev/null || true
        PGY_PROGRESS_PID=""
    fi

    local display_text="$label"
    if [[ -n "$step_num" && -n "$total_steps" ]]; then
        display_text="[${step_num}/${total_steps}] ${label}"
    fi
    PGY_PROGRESS_LABEL="$display_text"

    if [[ -t 1 ]]; then
        printf '\033[?25l' 2>/dev/null || true
        (
            local index=0
            local -a spinners=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
            while true; do
                printf '\r\033[2K  \033[38;2;0;212;255m%s\033[0m  %s...' "${spinners[$index]}" "${display_text}"
                index=$(((index + 1) % ${#spinners[@]}))
                sleep 0.08
            done
        ) >&2 &
        PGY_PROGRESS_PID=$!
    else
        echo -e "  [..] ${display_text}..."
    fi
}
tdz_progress_begin() { pgy_progress_begin "$@"; }

pgy_progress_done() {
    local text="${1:-${PGY_PROGRESS_LABEL:-Selesai}}"
    if [[ -n "${PGY_PROGRESS_PID:-}" ]] && kill -0 "${PGY_PROGRESS_PID}" 2>/dev/null; then
        kill "${PGY_PROGRESS_PID}" 2>/dev/null || true
        wait "${PGY_PROGRESS_PID}" 2>/dev/null || true
        PGY_PROGRESS_PID=""
    fi
    printf '\r\033[2K\033[?25h' 2>/dev/null || true
    echo -e "  ${C_GREEN}[✓]${C_RESET} ${text}"
}
tdz_progress_done() { pgy_progress_done "$@"; }

pgy_progress_failed() {
    local text="${1:-${PGY_PROGRESS_LABEL:-Gagal}}"
    if [[ -n "${PGY_PROGRESS_PID:-}" ]] && kill -0 "${PGY_PROGRESS_PID}" 2>/dev/null; then
        kill "${PGY_PROGRESS_PID}" 2>/dev/null || true
        wait "${PGY_PROGRESS_PID}" 2>/dev/null || true
        PGY_PROGRESS_PID=""
    fi
    printf '\r\033[2K\033[?25h' 2>/dev/null || true
    echo -e "  ${C_RED}[✗]${C_RESET} ${text}"
}
tdz_progress_failed() { pgy_progress_failed "$@"; }

pgy_progress_finish() {
    local success="${1:-true}" message="${2:-Proses selesai.}"
    if [[ -n "${PGY_PROGRESS_PID:-}" ]] && kill -0 "${PGY_PROGRESS_PID}" 2>/dev/null; then
        kill "${PGY_PROGRESS_PID}" 2>/dev/null || true
        wait "${PGY_PROGRESS_PID}" 2>/dev/null || true
        PGY_PROGRESS_PID=""
    fi
    printf '\r\033[2K\033[?25h' 2>/dev/null || true
    if [[ "$success" == "true" ]]; then
        echo -e "  ${C_GREEN}[OK]${C_RESET} ${message}"
    else
        echo -e "  ${C_RED}[FAIL]${C_RESET} ${message}"
    fi
}
tdz_progress_finish() { pgy_progress_finish "$@"; }

pgy_progress_run() {
    local step_num="" total_steps="" label=""
    if [[ "$1" =~ ^[0-9]+$ && "$2" =~ ^[0-9]+$ ]]; then
        step_num="$1"
        total_steps="$2"
        label="$3"
        shift 3
    else
        label="$1"
        shift 1
    fi

    local display_text="$label"
    if [[ -n "$step_num" && -n "$total_steps" ]]; then
        display_text="[${step_num}/${total_steps}] ${label}"
    fi

    pgy_progress_begin "${step_num}" "${total_steps}" "${label}"
    local pgy_log="${PGY_ACTION_LOG:-${TDZ_ACTION_LOG:-/dev/null}}"
    if "$@" >> "$pgy_log" 2>&1; then
        pgy_progress_done "$display_text"
        return 0
    else
        pgy_progress_failed "$display_text"
        return 1
    fi
}
tdz_progress_run() { pgy_progress_run "$@"; }

pgy_capture_service_diagnostic() {
    local unit="$1"
    local status_out journal_out
    status_out=$(systemctl status "$unit" -n 20 --no-pager 2>&1 || true)
    journal_out=$(journalctl -u "$unit" -n 20 --no-pager 2>&1 || true)
    printf "=== systemctl status %s ===\n%s\n\n=== journalctl -u %s (tail) ===\n%s\n" \
        "$unit" "$status_out" "$unit" "$journal_out"
}
tdz_capture_service_diagnostic() { pgy_capture_service_diagnostic "$@"; }

# Header Banner Function
show_banner() {
    pgy_refresh_box_width
    refresh_banner_cache 2>/dev/null || true
    refresh_dashboard_cache 2>/dev/null || true
    [[ -t 1 ]] && clear
    echo
    printf "  %s╔" "$C_CYAN"
    printf '═%.0s' $(seq 1 "$PGY_BOX_WIDTH")
    printf "╗%s\n" "$C_RESET"

    # Title: Auto Script SSH By : ProgoCloud
    local title_text="${PGY_HEADER_BRAND:-Auto Script SSH By : ProgoCloud}"
    local title_clean title_content
    title_clean=$(_pgy_fit "$title_text" "$PGY_BOX_WIDTH")
    title_content="${C_CYAN}${C_BOLD}${title_clean}${C_RESET}"
    local title_pad=$(( (PGY_BOX_WIDTH - ${#title_clean}) / 2 ))
    [[ $title_pad -lt 0 ]] && title_pad=0
    local title_lpad="" title_rpad=""
    [[ $title_pad -gt 0 ]] && printf -v title_lpad "%${title_pad}s" ""
    local title_rpad_len=$(( PGY_BOX_WIDTH - ${#title_clean} - title_pad ))
    [[ $title_rpad_len -lt 0 ]] && title_rpad_len=0
    [[ $title_rpad_len -gt 0 ]] && printf -v title_rpad "%${title_rpad_len}s" ""
    printf "  ${C_CYAN}║${C_RESET}%s%s%s${C_CYAN}║${C_RESET}\n" "$title_lpad" "$title_content" "$title_rpad"

    # Subtitle line: Versi Script : 0.0.1 • Copyright 2026 & Team ProgoCloud
    local cur_ver
    cur_ver="$(get_pgy_installed_version 2>/dev/null || echo "${PGY_SCRIPT_VERSION:-0.0.1}")"
    local sub_text="Versi Script : ${cur_ver} • ${PGY_VERSION_TAG:-Copyright 2026 & Team ProgoCloud}"
    local sub_clean sub_content
    sub_clean=$(_pgy_fit "$sub_text" "$PGY_BOX_WIDTH")
    sub_content="${C_GRAY}${sub_clean}${C_RESET}"
    local sub_pad=$(( (PGY_BOX_WIDTH - ${#sub_clean}) / 2 ))
    [[ $sub_pad -lt 0 ]] && sub_pad=0
    local sub_lpad="" sub_rpad=""
    [[ $sub_pad -gt 0 ]] && printf -v sub_lpad "%${sub_pad}s" ""
    local sub_rpad_len=$(( PGY_BOX_WIDTH - ${#sub_clean} - sub_pad ))
    [[ $sub_rpad_len -lt 0 ]] && sub_rpad_len=0
    [[ $sub_rpad_len -gt 0 ]] && printf -v sub_rpad "%${sub_rpad_len}s" ""
    printf "  ${C_CYAN}║${C_RESET}%s%s%s${C_CYAN}║${C_RESET}\n" "$sub_lpad" "$sub_content" "$sub_rpad"

    printf "  %s╚" "$C_CYAN"
    printf '═%.0s' $(seq 1 "$PGY_BOX_WIDTH")
    printf "╝%s\n" "$C_RESET"
}
