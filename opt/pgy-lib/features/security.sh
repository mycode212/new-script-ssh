#!/bin/bash
# ============================================================
# Auto Script SSH By : ProgoCloud
# Module: features/security.sh - Firewall, torrent block, auto reboot & PAM
# ============================================================

setup_limiter_service() {
    # Combined limiter + bandwidth monitoring daemon
    cat > "$LIMITER_SCRIPT" << 'EOF'
#!/bin/bash
# Auto Script SSH By : ProgoCloud - Background Limiter & Session Accounting
DB_FILE="/etc/pgytunnel/users.db"
BW_DIR="/etc/pgytunnel/bandwidth"
MANUAL_LOCK_FILE="/etc/pgytunnel/manual-locks.db"
PID_DIR="$BW_DIR/pidtrack"
BANNER_DIR="/etc/pgytunnel/banners"
BANNER_IDENTITY_CONF="/etc/pgytunnel/banner_identity.conf"
SCAN_INTERVAL=2
OVPN_RUNTIME="/usr/local/lib/pgy-ssh-tunnel/pgy_openvpn_runtime.py"
OVPN_SESSION_SNAPSHOT="/etc/pgytunnel/openvpn/run/sessions.tsv"
SSH_SESSION_SNAPSHOT="$BW_DIR/ssh-sessions.tsv"
SSH_SESSION_SNAPSHOT_TMP="${SSH_SESSION_SNAPSHOT}.tmp.$$"
SSH_AUTH_SESSION_DIR="/run/pgytunnel/ssh-auth-sessions"
USAGE_LOCK="$BW_DIR/.usage.lock"

mkdir -p "$BW_DIR" "$PID_DIR"
if [[ -L "$SSH_AUTH_SESSION_DIR" || ( -e "$SSH_AUTH_SESSION_DIR" && ! -d "$SSH_AUTH_SESSION_DIR" ) ]]; then
    echo "Refusing unsafe SSH session registry path: $SSH_AUTH_SESSION_DIR" >&2
    exit 1
fi
install -d -o root -g root -m 700 "$SSH_AUTH_SESSION_DIR" || exit 1
shopt -s nullglob
trap 'rm -f "$SSH_SESSION_SNAPSHOT_TMP"' EXIT

while true; do
    if [[ -f "$DB_FILE" ]]; then
        now_epoch=$(date +%s)
        while IFS=: read -r username password exp_date max_login quota_gb trial_marker trial_expiry_epoch _rest; do
            [[ -n "$username" && ! "$username" =~ ^# ]] || continue
            
            # Check manual locks
            if [[ -f "$MANUAL_LOCK_FILE" ]] && grep -Fxq "$username" "$MANUAL_LOCK_FILE"; then
                pkill -u "$username" -9 2>/dev/null || true
                continue
            fi

            # Check expiration date
            if [[ "$trial_marker" == "trial" && -n "$trial_expiry_epoch" ]]; then
                if (( trial_expiry_epoch > 0 && now_epoch >= trial_expiry_epoch )); then
                    pkill -u "$username" -9 2>/dev/null || true
                    userdel -r "$username" 2>/dev/null || true
                    sed -i "/^${username}:/d" "$DB_FILE" 2>/dev/null || true
                    continue
                fi
            elif [[ -n "$exp_date" && "$exp_date" != "never" && "$exp_date" != "0" ]]; then
                user_exp_epoch=$(date -d "$exp_date" +%s 2>/dev/null || echo 0)
                if (( user_exp_epoch > 0 && now_epoch >= user_exp_epoch )); then
                    pkill -u "$username" -9 2>/dev/null || true
                    passwd -l "$username" >/dev/null 2>&1 || true
                    continue
                fi
            fi

            # Check max login limits for SSH
            if [[ "$max_login" =~ ^[1-9][0-9]*$ ]]; then
                user_pids=($(pgrep -u "$username" sshd 2>/dev/null || true))
                active_count=${#user_pids[@]}
                if (( active_count > max_login )); then
                    excess=$(( active_count - max_login ))
                    for ((i=0; i<excess; i++)); do
                        kill -9 "${user_pids[i]}" 2>/dev/null || true
                    done
                fi
            fi
        done < "$DB_FILE"
    fi
    sleep "$SCAN_INTERVAL"
done
EOF
    chmod +x "$LIMITER_SCRIPT"

    cat > "$LIMITER_SERVICE" << EOF
[Unit]
Description=ProgoCloud SSH & VPN Limiter Daemon
After=network.target

[Service]
Type=simple
ExecStart=$LIMITER_SCRIPT
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload 2>/dev/null || true
    systemctl enable pgytunnel-limiter.service >/dev/null 2>&1 || true
    systemctl restart pgytunnel-limiter.service >/dev/null 2>&1 || true
}

setup_ssh_auth_session_hook() {
    local account_hook_line auth_guard_line tmp_file body_file registry_security
    local auth_guard_supported=false

    account_hook_line="account requisite pam_exec.so quiet stdout type=account $SSH_AUTH_SESSION_HELPER"
    auth_guard_line="auth requisite pam_exec.so quiet type=auth $SSH_AUTH_SESSION_HELPER"

    [[ -x "$SSH_AUTH_SESSION_HELPER" && -f "$SSH_PAM_CONFIG" ]] || return 1
    if [[ -L "$SSH_AUTH_SESSION_DIR" || ( -e "$SSH_AUTH_SESSION_DIR" && ! -d "$SSH_AUTH_SESSION_DIR" ) ]]; then
        return 1
    fi
    install -d -o root -g root -m 700 "$SSH_AUTH_SESSION_DIR" || return 1
    registry_security=$(stat -c '%u:%g:%a' "$SSH_AUTH_SESSION_DIR" 2>/dev/null || true)
    [[ "$registry_security" == "0:0:700" ]] || return 1

    tmp_file=$(mktemp "${SSH_PAM_CONFIG}.pgy.XXXXXX") || return 1
    body_file="${tmp_file}.body"
    if ! awk -v helper="$SSH_AUTH_SESSION_HELPER" \
             -v begin="$SSH_PAM_HOOK_BEGIN" -v end="$SSH_PAM_HOOK_END" \
             -v auth_begin="$SSH_PAM_AUTH_GUARD_BEGIN" \
             -v auth_end="$SSH_PAM_AUTH_GUARD_END" '
        $0 == begin || $0 == end || $0 == auth_begin || $0 == auth_end ||
        index($0, helper) { next }
        { print }
    ' "$SSH_PAM_CONFIG" > "$body_file"; then
        rm -f "$tmp_file" "$body_file"
        return 1
    fi
    if grep -Eq '^[[:space:]]*(@include[[:space:]]+common-auth|auth[[:space:]]+include[[:space:]]+common-auth)([[:space:]]*(#.*)?)?$' "$body_file"; then
        auth_guard_supported=true
    fi

    if ! {
        printf '%s\n%s\n%s\n' \
            "$SSH_PAM_HOOK_BEGIN" "$account_hook_line" "$SSH_PAM_HOOK_END"
        if $auth_guard_supported; then
            awk -v begin="$SSH_PAM_AUTH_GUARD_BEGIN" \
                -v line="$auth_guard_line" -v end="$SSH_PAM_AUTH_GUARD_END" '
                {
                    print
                    if (!inserted &&
                        ($0 ~ /^[[:space:]]*@include[[:space:]]+common-auth([[:space:]]|$)/ ||
                         $0 ~ /^[[:space:]]*auth[[:space:]]+include[[:space:]]+common-auth([[:space:]]|$)/)) {
                        print begin
                        print line
                        print end
                        inserted=1
                    }
                }
                END { if (!inserted) exit 1 }
            ' "$body_file"
        else
            cat "$body_file"
        fi
    } > "$tmp_file"; then
        rm -f "$tmp_file" "$body_file"
        return 1
    fi
    rm -f "$body_file"
    if [[ $(grep -Fxc "$account_hook_line" "$tmp_file") -ne 1 ]]; then
        rm -f "$tmp_file"
        return 1
    fi
    if $auth_guard_supported && [[ $(grep -Fxc "$auth_guard_line" "$tmp_file") -ne 1 ]]; then
        rm -f "$tmp_file"
        return 1
    fi
    chmod --reference="$SSH_PAM_CONFIG" "$tmp_file" 2>/dev/null || chmod 644 "$tmp_file"
    chown --reference="$SSH_PAM_CONFIG" "$tmp_file" 2>/dev/null || true
    if cmp -s "$tmp_file" "$SSH_PAM_CONFIG" 2>/dev/null; then
        rm -f "$tmp_file"
        return 0
    fi
    mv -f "$tmp_file" "$SSH_PAM_CONFIG"
}

remove_ssh_auth_session_hook() {
    local tmp_file
    [[ -f "$SSH_PAM_CONFIG" ]] || return 0
    tmp_file=$(mktemp "${SSH_PAM_CONFIG}.pgy.XXXXXX") || return 1
    if ! awk -v helper="$SSH_AUTH_SESSION_HELPER" \
             -v begin="$SSH_PAM_HOOK_BEGIN" -v end="$SSH_PAM_HOOK_END" \
             -v auth_begin="$SSH_PAM_AUTH_GUARD_BEGIN" \
             -v auth_end="$SSH_PAM_AUTH_GUARD_END" '
        $0 == begin || $0 == end || $0 == auth_begin || $0 == auth_end ||
        index($0, helper) { next }
        { print }
    ' "$SSH_PAM_CONFIG" > "$tmp_file"; then
        rm -f "$tmp_file"
        return 1
    fi
    chmod --reference="$SSH_PAM_CONFIG" "$tmp_file" 2>/dev/null || chmod 644 "$tmp_file"
    chown --reference="$SSH_PAM_CONFIG" "$tmp_file" 2>/dev/null || true
    if cmp -s "$tmp_file" "$SSH_PAM_CONFIG" 2>/dev/null; then
        rm -f "$tmp_file"
        return 0
    fi
    mv -f "$tmp_file" "$SSH_PAM_CONFIG"
}

sync_runtime_components_if_needed() {
    local limiter_marker="# Auto Script SSH By : ProgoCloud"
    cleanup_legacy_bandwidth_runtime
    migrate_legacy_shadow_locks >/dev/null 2>&1 || true
    setup_trial_cleanup_script >/dev/null 2>&1
    harden_sshd_for_tunnel_stability
    setup_ssh_auth_session_hook >/dev/null 2>&1 || true
    if [[ ! -f "$LIMITER_SCRIPT" ]] || ! grep -Fqx "$limiter_marker" "$LIMITER_SCRIPT" 2>/dev/null; then
        setup_limiter_service >/dev/null 2>&1
    fi
    if [[ -f "$BADVPN_SERVICE_FILE" ]]; then
        ensure_badvpn_service_is_quiet
    fi
    if declare -F pgy_openvpn_needs_refresh >/dev/null 2>&1 && pgy_openvpn_needs_refresh; then
        pgy_openvpn_refresh_runtime >/dev/null 2>&1 || true
    fi
    if [[ -f "/etc/pgytunnel/banners_enabled" ]]; then
        refresh_dynamic_banner_routing_if_enabled
    elif [[ -f "$SSHD_PGY_CONFIG" ]]; then
        disable_dynamic_ssh_banner_system
        systemctl reload sshd 2>/dev/null || systemctl reload ssh 2>/dev/null || true
    fi
}

setup_bandwidth_service() {
    mkdir -p "$BANDWIDTH_DIR"
    cleanup_legacy_bandwidth_runtime
}

cleanup_legacy_bandwidth_runtime() {
    local needs_reload=false
    systemctl stop pgytunnel-bandwidth &>/dev/null || true
    systemctl disable pgytunnel-bandwidth &>/dev/null || true
    pkill -f "pgytunnel-bandwidth" &>/dev/null || true

    if [[ -e "$BANDWIDTH_SERVICE" || -e "$BANDWIDTH_SCRIPT" || -e "$LEGACY_BANDWIDTH_DIR" ]]; then
        rm -f "$BANDWIDTH_SERVICE" "$BANDWIDTH_SCRIPT" 2>/dev/null
        rm -rf "$LEGACY_BANDWIDTH_DIR" 2>/dev/null
        needs_reload=true
    fi

    if $needs_reload; then
        systemctl daemon-reload &>/dev/null || true
    fi
}

setup_trial_cleanup_script() {
    cat > "$TRIAL_CLEANUP_SCRIPT" << 'TREOF'
#!/bin/bash
# Auto Script SSH By : ProgoCloud Trial Account Auto-Cleanup
DB_FILE="/etc/pgytunnel/users.db"
BW_DIR="/etc/pgytunnel/bandwidth"
MANUAL_LOCK_FILE="/etc/pgytunnel/manual-locks.db"
MANUAL_LOCK_MUTEX="/etc/pgytunnel/.manual-locks.lock"

expected_expiry_epoch=""
if [[ "$1" == "--uid" ]]; then
    user_uid="$2"
    expected_expiry_epoch="$3"
    if ! [[ "$user_uid" =~ ^[0-9]+$ && "$expected_expiry_epoch" =~ ^[0-9]+$ ]]; then
        exit 1
    fi
    username=$(getent passwd "$user_uid" 2>/dev/null | cut -d: -f1)
else
    username="$1"
fi
if [[ -z "$username" ]]; then exit 0; fi

db_line=$(grep "^${username}:" "$DB_FILE" 2>/dev/null | head -n 1)
if [[ -z "$db_line" ]]; then exit 0; fi

IFS=: read -r _ _ _ _ _ trial_marker trial_expiry_epoch _rest <<< "$db_line"
if [[ "$trial_marker" != "trial" ]]; then
    exit 0
fi
if [[ -n "$expected_expiry_epoch" && "$trial_expiry_epoch" != "$expected_expiry_epoch" ]]; then
    exit 0
fi

# Kill active sessions
killall -u "$username" -9 &>/dev/null || true
sleep 1

# Delete system user
userdel -r "$username" &>/dev/null || true

# Remove from DB
sed -i "/^${username}:/d" "$DB_FILE"

# Remove bandwidth tracking
rm -f "$BW_DIR/${username}.usage"
rm -rf "$BW_DIR/pidtrack/${username}"

# Remove manual lock policy
if [[ -f "$MANUAL_LOCK_FILE" && ! -L "$MANUAL_LOCK_FILE" ]]; then
    touch "$MANUAL_LOCK_MUTEX" 2>/dev/null || true
    exec 9>"$MANUAL_LOCK_MUTEX"
    if flock -x 9 2>/dev/null; then
        lock_tmp=$(mktemp "${MANUAL_LOCK_FILE}.tmp.XXXXXX")
        if awk -v target="$username" '$0 != target { print }' \
            "$MANUAL_LOCK_FILE" > "$lock_tmp"; then
            chmod 600 "$lock_tmp"
            chown root:root "$lock_tmp" 2>/dev/null || true
            mv -f "$lock_tmp" "$MANUAL_LOCK_FILE"
        else
            rm -f "$lock_tmp"
        fi
        flock -u 9
    fi
    exec 9>&-
fi
TREOF
    chmod +x "$TRIAL_CLEANUP_SCRIPT"
}

setup_ssh_login_info() {
    ensure_pgytunnel_dirs || return 1
    if ! setup_ssh_auth_session_hook; then
        echo -e "${C_RED}[ERROR] Gagal memasang hook authenticated banner.${C_RESET}"
        return 1
    fi
    if ! touch "/etc/pgytunnel/banners_enabled"; then
        echo -e "${C_RED}[ERROR] Gagal mengaktifkan dynamic SSH banner.${C_RESET}"
        return 1
    fi
    disable_static_ssh_banner_in_sshd_config
    refresh_dynamic_banner_routing_if_enabled
}

torrent_block_menu() {
    pgy_screen_title "TORRENT BLOCKING" "Proteksi Anti-Torrent IPTables"
    local torrent_status="Disabled" torrent_color="$C_RED"
    if iptables -L FORWARD 2>/dev/null | grep -q "BitTorrent"; then
         torrent_status="Enabled"; torrent_color="$C_GREEN"
    elif iptables -L OUTPUT 2>/dev/null | grep -q "BitTorrent"; then
         torrent_status="Enabled"; torrent_color="$C_GREEN"
    fi

    echo
    pgy_box_top
    pgy_box_header "TORRENT BLOCKING"
    pgy_box_divider
    pgy_row2 "${C_GRAY}STATUS${C_RESET}" "${torrent_color}${C_BOLD}${torrent_status}${C_RESET}"
    pgy_box_divider
    pgy_menu1 "[ 1]" "Enable Torrent Blocking"
    pgy_menu1 "[ 2]" "Disable Torrent Blocking"
    pgy_box_divider
    pgy_menu1 "[ 0]" "Kembali"
    pgy_box_bot
    echo
    read -r -p "$(echo -e "${C_PROMPT}  Pilih opsi: ${C_RESET}")" b_choice
    
    case $b_choice in
        1)
            echo -e "\n${C_BLUE}Menerapkan aturan Anti-Torrent...${C_RESET}"
            _flush_torrent_rules
            
            iptables -A FORWARD -m string --string "BitTorrent" --algo bm -j DROP 2>/dev/null || true
            iptables -A FORWARD -m string --string "BitTorrent protocol" --algo bm -j DROP 2>/dev/null || true
            iptables -A FORWARD -m string --string "peer_id=" --algo bm -j DROP 2>/dev/null || true
            iptables -A FORWARD -m string --string ".torrent" --algo bm -j DROP 2>/dev/null || true
            iptables -A FORWARD -m string --string "announce.php?passkey=" --algo bm -j DROP 2>/dev/null || true
            iptables -A FORWARD -m string --string "torrent" --algo bm -j DROP 2>/dev/null || true
            iptables -A FORWARD -m string --string "info_hash" --algo bm -j DROP 2>/dev/null || true
            iptables -A FORWARD -m string --string "get_peers" --algo bm -j DROP 2>/dev/null || true
            iptables -A FORWARD -m string --string "find_node" --algo bm -j DROP 2>/dev/null || true
            
            iptables -A OUTPUT -m string --string "BitTorrent" --algo bm -j DROP 2>/dev/null || true
            iptables -A OUTPUT -m string --string "BitTorrent protocol" --algo bm -j DROP 2>/dev/null || true
            iptables -A OUTPUT -m string --string "peer_id=" --algo bm -j DROP 2>/dev/null || true
            iptables -A OUTPUT -m string --string ".torrent" --algo bm -j DROP 2>/dev/null || true
            iptables -A OUTPUT -m string --string "announce.php?passkey=" --algo bm -j DROP 2>/dev/null || true
            iptables -A OUTPUT -m string --string "torrent" --algo bm -j DROP 2>/dev/null || true
            iptables -A OUTPUT -m string --string "info_hash" --algo bm -j DROP 2>/dev/null || true
            iptables -A OUTPUT -m string --string "get_peers" --algo bm -j DROP 2>/dev/null || true
            iptables -A OUTPUT -m string --string "find_node" --algo bm -j DROP 2>/dev/null || true
            
            if command -v netfilter-persistent >/dev/null 2>&1; then
                netfilter-persistent save >/dev/null 2>&1 || true
            fi
            
            echo -e "${C_GREEN}[OK] Torrent Blocking berhasil diaktifkan.${C_RESET}"
            press_enter
            ;;
        2)
            echo -e "\n${C_BLUE}Menghapus aturan Anti-Torrent...${C_RESET}"
            _flush_torrent_rules
            if command -v netfilter-persistent >/dev/null 2>&1; then
                netfilter-persistent save >/dev/null 2>&1 || true
            fi
            echo -e "${C_GREEN}[OK] Torrent Blocking berhasil dinonaktifkan.${C_RESET}"
            press_enter
            ;;
        *) return ;;
    esac
}

_flush_torrent_rules() {
    iptables -D FORWARD -m string --string "BitTorrent" --algo bm -j DROP 2>/dev/null || true
    iptables -D FORWARD -m string --string "BitTorrent protocol" --algo bm -j DROP 2>/dev/null || true
    iptables -D FORWARD -m string --string "peer_id=" --algo bm -j DROP 2>/dev/null || true
    iptables -D FORWARD -m string --string ".torrent" --algo bm -j DROP 2>/dev/null || true
    iptables -D FORWARD -m string --string "announce.php?passkey=" --algo bm -j DROP 2>/dev/null || true
    iptables -D FORWARD -m string --string "torrent" --algo bm -j DROP 2>/dev/null || true
    iptables -D FORWARD -m string --string "info_hash" --algo bm -j DROP 2>/dev/null || true
    iptables -D FORWARD -m string --string "get_peers" --algo bm -j DROP 2>/dev/null || true
    iptables -D FORWARD -m string --string "find_node" --algo bm -j DROP 2>/dev/null || true

    iptables -D OUTPUT -m string --string "BitTorrent" --algo bm -j DROP 2>/dev/null || true
    iptables -D OUTPUT -m string --string "BitTorrent protocol" --algo bm -j DROP 2>/dev/null || true
    iptables -D OUTPUT -m string --string "peer_id=" --algo bm -j DROP 2>/dev/null || true
    iptables -D OUTPUT -m string --string ".torrent" --algo bm -j DROP 2>/dev/null || true
    iptables -D OUTPUT -m string --string "announce.php?passkey=" --algo bm -j DROP 2>/dev/null || true
    iptables -D OUTPUT -m string --string "torrent" --algo bm -j DROP 2>/dev/null || true
    iptables -D OUTPUT -m string --string "info_hash" --algo bm -j DROP 2>/dev/null || true
    iptables -D OUTPUT -m string --string "get_peers" --algo bm -j DROP 2>/dev/null || true
    iptables -D OUTPUT -m string --string "find_node" --algo bm -j DROP 2>/dev/null || true
}

auto_reboot_menu() {
    pgy_screen_title "AUTO-REBOOT TASK" "Manajemen Jadwal Reboot Otomatis VPS"
    local cron_check
    cron_check=$(crontab -l 2>/dev/null | grep -E "${AUTO_REBOOT_CRON_TAG}|^[[:space:]]*0[[:space:]]+0[[:space:]]+\\*[[:space:]]+\\*[[:space:]]+\\*[[:space:]]+systemctl[[:space:]]+reboot[[:space:]]*$" || true)
    local status="Disabled" status_color="$C_RED"
    if [[ -n "$cron_check" ]]; then
        status="Active (Midnight 00:00)"
        status_color="$C_GREEN"
    fi

    echo
    pgy_box_top
    pgy_box_header "AUTO-REBOOT MANAGEMENT"
    pgy_box_divider
    pgy_row2 "${C_GRAY}STATUS${C_RESET}" "${status_color}${C_BOLD}${status}${C_RESET}"
    pgy_box_divider
    pgy_menu1 "[ 1]" "Enable Daily Reboot (00:00)"
    pgy_menu1 "[ 2]" "Disable Auto-Reboot"
    pgy_box_divider
    pgy_menu1 "[ 0]" "Kembali"
    pgy_box_bot
    echo
    read -r -p "$(echo -e "${C_PROMPT}  Pilih opsi: ${C_RESET}")" r_choice
    
    case $r_choice in
        1)
            pgy_remove_auto_reboot_job
            (crontab -l 2>/dev/null || true; echo "0 0 * * * systemctl reboot $AUTO_REBOOT_CRON_TAG") | crontab -
            echo -e "\n${C_GREEN}[OK] Auto-reboot dijadwalkan setiap hari pukul 00:00.${C_RESET}"
            press_enter
            ;;
        2)
            pgy_remove_auto_reboot_job
            echo -e "\n${C_GREEN}[OK] Auto-reboot berhasil dinonaktifkan.${C_RESET}"
            press_enter
            ;;
        *) return ;;
    esac
}

