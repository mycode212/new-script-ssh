#!/bin/bash
# ============================================================
# Auto Script SSH By : ProgoCloud
# Entrypoint: menu.sh - Modular Tunnel Management Console
# Repo: https://github.com/mycode212/new-script-ssh
# ============================================================

# Determine script & module roots
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P || true)"
export PGY_SOURCE_DIR="${SCRIPT_DIR}"

# Locate modular library directory (/pgy-lib/opt -> /usr/local/lib/pgy-ssh-tunnel -> local repo ./opt/pgy-lib)
if [[ -d "/pgy-lib/opt/core" ]]; then
    PGY_MODULE_ROOT="/pgy-lib/opt"
elif [[ -d "/usr/local/lib/pgy-ssh-tunnel/core" ]]; then
    PGY_MODULE_ROOT="/usr/local/lib/pgy-ssh-tunnel"
elif [[ -d "${SCRIPT_DIR}/opt/pgy-lib/core" ]]; then
    PGY_MODULE_ROOT="${SCRIPT_DIR}/opt/pgy-lib"
else
    echo "[ERROR] Direktori pustaka modul ProgoCloud tidak ditemukan." >&2
    exit 1
fi

# Load core modules
# shellcheck source=/dev/null
source "${PGY_MODULE_ROOT}/core/colors.sh"
# shellcheck source=/dev/null
source "${PGY_MODULE_ROOT}/core/config.sh"
# shellcheck source=/dev/null
source "${PGY_MODULE_ROOT}/core/helpers.sh"
# shellcheck source=/dev/null
source "${PGY_MODULE_ROOT}/core/ui.sh"
# shellcheck source=/dev/null
source "${PGY_MODULE_ROOT}/core/license.sh"
# shellcheck source=/dev/null
source "${PGY_MODULE_ROOT}/core/system.sh"

# Load feature modules
# shellcheck source=/dev/null
source "${PGY_MODULE_ROOT}/features/users.sh"
# shellcheck source=/dev/null
source "${PGY_MODULE_ROOT}/features/services.sh"
# shellcheck source=/dev/null
source "${PGY_MODULE_ROOT}/features/edge.sh"
# shellcheck source=/dev/null
source "${PGY_MODULE_ROOT}/features/openvpn.sh"
# shellcheck source=/dev/null
source "${PGY_MODULE_ROOT}/features/dnstt.sh"
# shellcheck source=/dev/null
source "${PGY_MODULE_ROOT}/features/security.sh"
# shellcheck source=/dev/null
source "${PGY_MODULE_ROOT}/features/banner.sh"
# shellcheck source=/dev/null
source "${PGY_MODULE_ROOT}/features/backup.sh"
# shellcheck source=/dev/null
source "${PGY_MODULE_ROOT}/features/monitor.sh"
# shellcheck source=/dev/null
source "${PGY_MODULE_ROOT}/features/uninstall.sh"
# shellcheck source=/dev/null
source "${PGY_MODULE_ROOT}/features/updater.sh"
# shellcheck source=/dev/null
[[ -f "${PGY_MODULE_ROOT}/features/warp.sh" ]] && source "${PGY_MODULE_ROOT}/features/warp.sh"
# shellcheck source=/dev/null
[[ -f "${PGY_MODULE_ROOT}/features/adblock.sh" ]] && source "${PGY_MODULE_ROOT}/features/adblock.sh"
# shellcheck source=/dev/null
[[ -f "${PGY_MODULE_ROOT}/features/xray.sh" ]] && source "${PGY_MODULE_ROOT}/features/xray.sh"
# shellcheck source=/dev/null
[[ -f "${PGY_MODULE_ROOT}/features/speedtest.sh" ]] && source "${PGY_MODULE_ROOT}/features/speedtest.sh"
# shellcheck source=/dev/null
[[ -f "${PGY_MODULE_ROOT}/features/api.sh" ]] && source "${PGY_MODULE_ROOT}/features/api.sh"
# shellcheck source=/dev/null
[[ -f "${PGY_MODULE_ROOT}/features/cloudflare_api.sh" ]] && source "${PGY_MODULE_ROOT}/features/cloudflare_api.sh"
# shellcheck source=/dev/null
[[ -f "${PGY_MODULE_ROOT}/features/cftunnel.sh" ]] && source "${PGY_MODULE_ROOT}/features/cftunnel.sh"

# Load menu controllers
# shellcheck source=/dev/null
[[ -f "${PGY_MODULE_ROOT}/menus/ssh_user_menu.sh" ]] && source "${PGY_MODULE_ROOT}/menus/ssh_user_menu.sh"
# shellcheck source=/dev/null
[[ -f "${PGY_MODULE_ROOT}/menus/xray_user_menu.sh" ]] && source "${PGY_MODULE_ROOT}/menus/xray_user_menu.sh"
# shellcheck source=/dev/null
[[ -f "${PGY_MODULE_ROOT}/menus/warp_menu.sh" ]] && source "${PGY_MODULE_ROOT}/menus/warp_menu.sh"
# shellcheck source=/dev/null
[[ -f "${PGY_MODULE_ROOT}/menus/adblock_menu.sh" ]] && source "${PGY_MODULE_ROOT}/menus/adblock_menu.sh"
# shellcheck source=/dev/null
[[ -f "${PGY_MODULE_ROOT}/menus/xray_menu.sh" ]] && source "${PGY_MODULE_ROOT}/menus/xray_menu.sh"
# shellcheck source=/dev/null
[[ -f "${PGY_MODULE_ROOT}/menus/speedtest_menu.sh" ]] && source "${PGY_MODULE_ROOT}/menus/speedtest_menu.sh"
# shellcheck source=/dev/null
[[ -f "${PGY_MODULE_ROOT}/menus/api_menu.sh" ]] && source "${PGY_MODULE_ROOT}/menus/api_menu.sh"
# shellcheck source=/dev/null
[[ -f "${PGY_MODULE_ROOT}/menus/cftunnel_menu.sh" ]] && source "${PGY_MODULE_ROOT}/menus/cftunnel_menu.sh"
# shellcheck source=/dev/null
source "${PGY_MODULE_ROOT}/menus/protocol_menu.sh"
# shellcheck source=/dev/null
source "${PGY_MODULE_ROOT}/menus/main_menu.sh"

# Handle CLI arguments
if [[ "${1:-}" == "--install-setup" ]]; then
    initial_setup
    exit 0
fi

if [[ "${1:-}" == "--update-setup" ]]; then
    update_setup
    exit 0
fi

if [[ "${1:-}" == "--update-script" || "${1:-}" == "update" ]]; then
    shift
    update_script "$@"
    exit 0
fi

if [[ "${1:-}" == "--license-status" || "${1:-}" == "license" ]]; then
    pgy_license_show_status
    exit 0
fi

# Source-only mode for tests and sub-scripts
if [[ "${1:-}" == "--source-only" ]]; then
    return 0 2>/dev/null || exit 0
fi

# Launch ProgoCloud Main Menu
main_menu
