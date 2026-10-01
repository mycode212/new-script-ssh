#!/bin/bash
# ============================================================
# Auto Script SSH By : ProgoCloud
# Module: features/openvpn.sh - OpenVPN integration loader
# ============================================================

PGY_MENU_SOURCE_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd || true)"

if [[ -r "$PGY_LIB_DIR/openvpn_module.sh" ]]; then
    # shellcheck source=/dev/null
    source "$PGY_LIB_DIR/openvpn_module.sh"
elif [[ -r "/pgy-lib/opt/openvpn_module.sh" ]]; then
    # shellcheck source=/dev/null
    source "/pgy-lib/opt/openvpn_module.sh"
elif [[ -n "$PGY_MENU_SOURCE_DIR" && -r "$PGY_MENU_SOURCE_DIR/openvpn_module.sh" ]]; then
    # shellcheck source=/dev/null
    source "$PGY_MENU_SOURCE_DIR/openvpn_module.sh"
fi
