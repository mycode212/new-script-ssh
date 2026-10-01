#!/bin/bash
# ============================================================
# Auto Script SSH By : ProgoCloud
# Module: core/colors.sh - Color definitions and text metrics
# ============================================================

# ANSI Escape Codes
C_RESET=$'\033[0m'
C_BOLD=$'\033[1m'
C_DIM=$'\033[2m'
C_UL=$'\033[4m'

# ProgoCloud Premium Color Palette - Vibrant Cyan, Blue, Emerald, Amber & Crimson
C_RED=$'\033[38;5;196m'           # Bright Red
C_GREEN=$'\033[38;5;46m'          # Neon Green
C_YELLOW=$'\033[38;5;226m'        # Bright Yellow
C_NAVY=$'\033[38;5;39m'           # Bright Cyan-Blue
C_BLUE=$'\033[38;2;0;212;255m'    # Cyan #00d4ff (Brand Accent)
C_PURPLE=$'\033[38;5;99m'         # Soft Purple
C_CYAN=$'\033[38;2;0;212;255m'    # Cyan #00d4ff
C_WHITE=$'\033[38;5;255m'         # Bright White
C_GRAY=$'\033[38;5;245m'          # Gray
C_ORANGE=$'\033[38;5;208m'        # Orange

# Semantic Aliases
C_TITLE=$C_NAVY
C_CHOICE=$C_CYAN
C_PROMPT=$C_BLUE
C_WARN=$C_YELLOW
C_DANGER=$C_RED
C_STATUS_A=$C_GREEN
C_STATUS_I=$C_GRAY
C_ACCENT=$C_CYAN

# Box Dimensions
PGY_BOX_MAX_WIDTH=64
PGY_BOX_WIDTH=$PGY_BOX_MAX_WIDTH
TDZ_BOX_MAX_WIDTH=$PGY_BOX_MAX_WIDTH
TDZ_BOX_WIDTH=$PGY_BOX_WIDTH

pgy_refresh_box_width() {
    if [[ -t 1 ]]; then
        local terminal_columns="${COLUMNS:-}"
        [[ "$terminal_columns" =~ ^[0-9]+$ ]] || terminal_columns=$(tput cols 2>/dev/null || true)
        if [[ "$terminal_columns" =~ ^[0-9]+$ ]]; then
            PGY_BOX_WIDTH=$((terminal_columns - 4))
            (( PGY_BOX_WIDTH > PGY_BOX_MAX_WIDTH )) && PGY_BOX_WIDTH=$PGY_BOX_MAX_WIDTH
            (( PGY_BOX_WIDTH < 24 )) && PGY_BOX_WIDTH=24
        else
            PGY_BOX_WIDTH=$PGY_BOX_MAX_WIDTH
        fi
    else
        PGY_BOX_WIDTH=$PGY_BOX_MAX_WIDTH
    fi
    TDZ_BOX_WIDTH=$PGY_BOX_WIDTH
}

tdz_refresh_box_width() { pgy_refresh_box_width "$@"; }

# Strip ANSI escapes to compute true visual width
_pgy_strip_ansi() {
    printf '%s' "$1" | sed -E $'s/\033\\[[0-9;]*[a-zA-Z]//g'
}

_tdz_strip_ansi() { _pgy_strip_ansi "$@"; }

_pgy_w() {
    local clean
    clean=$(_pgy_strip_ansi "$1")
    printf '%d' "${#clean}"
}

_tdz_w() { _pgy_w "$@"; }

_pgy_fit() {
    local text="$1" max_width="$2"
    if (( ${#text} > max_width )); then
        printf '%s' "${text:0:max_width}"
    else
        printf '%s' "$text"
    fi
}

_tdz_fit() { _pgy_fit "$@"; }
