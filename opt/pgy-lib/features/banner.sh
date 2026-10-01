#!/bin/bash
# ============================================================
# Auto Script SSH By : ProgoCloud
# Module: features/banner.sh - Dynamic and static SSH banners
# ============================================================

write_banner_if_changed() {
    local user="$1"
    local content="$2"
    local target_dir="${BANNER_DIR:-/etc/pgytunnel/banners}"
    mkdir -p "$target_dir"
    local banner_file="$target_dir/${user}.txt"
    local tmp_file="${banner_file}.tmp.$$"

    printf "%s" "$content" > "$tmp_file"
    if ! cmp -s "$tmp_file" "$banner_file" 2>/dev/null; then
        mv -f "$tmp_file" "$banner_file"
    else
        rm -f "$tmp_file"
    fi
    chmod 644 "$banner_file" 2>/dev/null || true
}

load_banner_identity() {
    local key value
    ADMIN_USERNAME="TUSPGY"
    CHANNEL_USERNAME="TuhinBroh"

    if [[ -r "$BANNER_IDENTITY_CONF" ]]; then
        while IFS='=' read -r key value; do
            value=${value%$'\r'}
            case "$key" in
                ADMIN_USERNAME) ADMIN_USERNAME="$value" ;;
                CHANNEL_USERNAME) CHANNEL_USERNAME="$value" ;;
            esac
        done < "$BANNER_IDENTITY_CONF"
    fi

    [[ "$ADMIN_USERNAME" =~ ^[A-Za-z][A-Za-z0-9_]{4,31}$ ]] || ADMIN_USERNAME="TUSPGY"
    [[ "$CHANNEL_USERNAME" =~ ^[A-Za-z][A-Za-z0-9_]{4,31}$ ]] || CHANNEL_USERNAME="TuhinBroh"
}


disable_dynamic_ssh_banner_system() {
    rm -f "/etc/pgytunnel/banners_enabled" "$SSHD_PGY_CONFIG" /usr/local/bin/pgytunnel-login-info.sh 2>/dev/null
    rm -rf "/etc/pgytunnel/banners" 2>/dev/null
    invalidate_banner_cache
}

disable_static_ssh_banner_in_sshd_config() {
    sed -i.bak -E "s|^[[:space:]]*Banner[[:space:]]+$SSH_BANNER_FILE[[:space:]]*$|# Banner $SSH_BANNER_FILE|" /etc/ssh/sshd_config 2>/dev/null
}

is_static_ssh_banner_enabled() {
    grep -q -E "^[[:space:]]*Banner[[:space:]]+$SSH_BANNER_FILE[[:space:]]*$" /etc/ssh/sshd_config 2>/dev/null && [ -f "$SSH_BANNER_FILE" ]
}

is_dynamic_ssh_banner_enabled() {
    [[ -f "/etc/pgytunnel/banners_enabled" && -f "$SSHD_PGY_CONFIG" ]]
}

get_ssh_banner_mode() {
    if is_dynamic_ssh_banner_enabled; then
        echo "dynamic"
    elif is_static_ssh_banner_enabled; then
        echo "static"
    else
        echo "disabled"
    fi
}

refresh_dynamic_banner_routing_if_enabled() {
    local users=("$@") attempt user all_ready=true
    local banner_dir="/etc/pgytunnel/banners"

    # The feature flag is the source of truth. Requiring the generated sshd
    # include here made refresh a no-op when that file was missing or had been
    # removed during an update, even though Dynamic Banner was still enabled.
    [[ -f "/etc/pgytunnel/banners_enabled" ]] || return 0

    # A call without an explicit list means every currently managed account.
    # This keeps restore, cleanup, updater, and manual-enable flows consistent
    # with individual and bulk account creation.
    if (( ${#users[@]} == 0 )) && [[ -f "$DB_FILE" ]]; then
        while IFS=: read -r user _rest; do
            [[ -n "$user" && "$user" != \#* ]] && users+=("$user")
        done < "$DB_FILE"
    fi

    if ! systemctl is-active --quiet pgytunnel-limiter; then
        systemctl start pgytunnel-limiter --no-block >/dev/null 2>&1 || true
    fi

    # Publish the banner before enabling its post-auth PAM delivery.
    mkdir -p "$banner_dir"
    if (( ${#users[@]} > 0 )); then
        for user in "${users[@]}"; do
            [[ -n "$user" ]] && pgy_generate_user_banner "$user"
        done
        all_ready=true
    fi

    # Always refresh routing even after a worker timeout so the account starts
    # working automatically as soon as the supervised worker recovers.
    update_ssh_banners_config || return 1
    $all_ready
}

provision_dynamic_banners_for_new_users() {
    local users=("$@") user

    # A deleted username may leave an old banner behind. Never treat that
    # stale file as proof that a newly-created account is ready.
    for user in "${users[@]}"; do
        [[ -n "$user" ]] || continue
        pgy_set_manual_lock_state "$user" unlocked || return 1
        rm -f "$DB_DIR/banners/${user}.txt" 2>/dev/null
        is_valid_pgytunnel_username "$user" && \
            rm -f "$SSH_AUTH_SESSION_DIR/${user}.denied" 2>/dev/null
    done
    invalidate_banner_cache
    refresh_dynamic_banner_routing_if_enabled "${users[@]}"
}

update_ssh_banners_config() {
    local tmp_conf config_changed=false include_added=false

    if [[ ! -f "/etc/pgytunnel/banners_enabled" ]]; then
        if [[ -f "$SSHD_PGY_CONFIG" ]]; then
            rm -f "$SSHD_PGY_CONFIG" 2>/dev/null
            systemctl reload sshd 2>/dev/null || systemctl reload ssh 2>/dev/null
        fi
        return
    fi

    ensure_pgytunnel_dirs
    mkdir -p "$(dirname "$SSHD_PGY_CONFIG")" || return 1
    tmp_conf=$(mktemp "${SSHD_PGY_CONFIG}.tmp.XXXXXX") || return 1
    {
        echo "# PGY SSH TUNNEL - authenticated dynamic account banners"
        echo "# Account data is emitted by PAM only after successful authentication."
        echo "# Never add per-user Banner directives here; OpenSSH sends them pre-auth."
    } > "$tmp_conf"

    if ! cmp -s "$tmp_conf" "$SSHD_PGY_CONFIG" 2>/dev/null; then
        chmod 644 "$tmp_conf"
        mv -f "$tmp_conf" "$SSHD_PGY_CONFIG" || { rm -f "$tmp_conf"; return 1; }
        config_changed=true
    else
        rm -f "$tmp_conf"
    fi

    # Keep the include independently self-healing. Previously it was checked
    # only when the per-user file changed, so an otherwise-current file could
    # remain completely ignored by sshd after its Include line was removed.
    if ! grep -qE "^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config.d/\*\.conf" /etc/ssh/sshd_config 2>/dev/null; then
        echo "Include /etc/ssh/sshd_config.d/*.conf" >> /etc/ssh/sshd_config || return 1
        include_added=true
    fi

    if $config_changed || $include_added; then
        systemctl reload sshd 2>/dev/null || systemctl reload ssh 2>/dev/null
    fi
    return 0
}


_enable_banner_in_sshd_config() {
    disable_dynamic_ssh_banner_system
    sed -i.bak -E 's/^( *Banner *).*/#\1/' /etc/ssh/sshd_config 2>/dev/null
    if ! grep -q -E "^Banner $SSH_BANNER_FILE" /etc/ssh/sshd_config 2>/dev/null; then
        echo -e "\n# ProgoCloud SSH Banner\nBanner $SSH_BANNER_FILE" >> /etc/ssh/sshd_config
    fi
}

_restart_ssh() {
    local ssh_service_name="sshd.service"
    if [ -f /lib/systemd/system/ssh.service ]; then
        ssh_service_name="ssh.service"
    fi
    systemctl restart "${ssh_service_name}" >/dev/null 2>&1
}

is_valid_telegram_username() {
    [[ "$1" =~ ^[A-Za-z][A-Za-z0-9_]{4,31}$ ]]
}

load_banner_identity_config() {
    local key value
    BANNER_ADMIN_USERNAME="$DEFAULT_BANNER_ADMIN_USERNAME"
    BANNER_CHANNEL_USERNAME="$DEFAULT_BANNER_CHANNEL_USERNAME"

    if [[ -r "$BANNER_IDENTITY_CONF" ]]; then
        while IFS='=' read -r key value; do
            value=${value%$'\r'}
            case "$key" in
                ADMIN_USERNAME) BANNER_ADMIN_USERNAME="$value" ;;
                CHANNEL_USERNAME) BANNER_CHANNEL_USERNAME="$value" ;;
            esac
        done < "$BANNER_IDENTITY_CONF"
    fi

    is_valid_telegram_username "$BANNER_ADMIN_USERNAME" || BANNER_ADMIN_USERNAME="$DEFAULT_BANNER_ADMIN_USERNAME"
    is_valid_telegram_username "$BANNER_CHANNEL_USERNAME" || BANNER_CHANNEL_USERNAME="$DEFAULT_BANNER_CHANNEL_USERNAME"
}

save_banner_identity_config() {
    local admin_username="$1" channel_username="$2" tmp_file
    mkdir -p "$DB_DIR" || return 1
    tmp_file="${BANNER_IDENTITY_CONF}.tmp"
    printf 'ADMIN_USERNAME=%s\nCHANNEL_USERNAME=%s\n' \
        "$admin_username" "$channel_username" > "$tmp_file" || return 1
    chmod 600 "$tmp_file"
    mv -f "$tmp_file" "$BANNER_IDENTITY_CONF"
}

edit_dynamic_banner_contacts() {
    clear; show_banner
    pgy_screen_title "DYNAMIC BANNER CONTACTS" "Update the Telegram usernames shown to SSH users."
    load_banner_identity_config
    echo
    pgy_box_top "$C_CYAN"
    pgy_box_header "CURRENT CONTACTS" "$C_CYAN"
    pgy_box_divider "$C_CYAN"
    pgy_detail "Admin" "@${BANNER_ADMIN_USERNAME}" "$C_GREEN"
    pgy_detail "Channel" "@${BANNER_CHANNEL_USERNAME}" "$C_GREEN"
    pgy_box_divider "$C_CYAN"
    pgy_row "${C_GRAY}Enter Telegram usernames only. Links are generated automatically.${C_RESET}" "$C_CYAN"
    pgy_box_bot "$C_CYAN"
    echo

    local new_admin new_channel
    read -r -p "$(echo -e "${C_PROMPT}  Admin username [@${BANNER_ADMIN_USERNAME}]: ${C_RESET}")" new_admin
    read -r -p "$(echo -e "${C_PROMPT}  Channel username [@${BANNER_CHANNEL_USERNAME}]: ${C_RESET}")" new_channel
    new_admin=${new_admin#@}
    new_channel=${new_channel#@}
    new_admin=${new_admin:-$BANNER_ADMIN_USERNAME}
    new_channel=${new_channel:-$BANNER_CHANNEL_USERNAME}

    if ! is_valid_telegram_username "$new_admin"; then
        echo
        pgy_message ERROR "Invalid Admin username. Use 5-32 letters, numbers, or underscores, starting with a letter."
        press_enter
        return
    fi
    if ! is_valid_telegram_username "$new_channel"; then
        echo
        pgy_message ERROR "Invalid Channel username. Use 5-32 letters, numbers, or underscores, starting with a letter."
        press_enter
        return
    fi

    if ! save_banner_identity_config "$new_admin" "$new_channel"; then
        echo
        pgy_message ERROR "Could not save the banner contacts."
        press_enter
        return
    fi

    setup_limiter_service >/dev/null 2>&1 || true
    refresh_dynamic_banner_routing_if_enabled
    echo
    pgy_box_top "$C_GREEN"
    pgy_box_header "CONTACTS UPDATED" "$C_GREEN" "$C_GREEN"
    pgy_box_divider "$C_GREEN"
    pgy_detail "Admin" "@${new_admin}" "$C_YELLOW"
    pgy_detail "Channel" "@${new_channel}" "$C_YELLOW"
    pgy_box_bot "$C_GREEN"
    press_enter
}

set_ssh_banner_paste() {
    clear; show_banner
    pgy_screen_title "PASTE STATIC SSH BANNER" "Tempel isi banner lalu tekan [Ctrl+D] untuk menyimpan."
    echo
    pgy_box_top "$C_CYAN"
    pgy_box_header "PETUNJUK PENGISIAN" "$C_CYAN"
    pgy_box_divider "$C_CYAN"
    pgy_row "Tempel atau ketik custom banner Anda di bawah ini." "$C_CYAN"
    pgy_row "Tekan tombol [Ctrl+D] pada baris baru setelah selesai." "$C_CYAN"
    pgy_row "Banner statis sebelumnya akan ditimpa." "$C_CYAN"
    pgy_box_bot "$C_CYAN"
    echo
    cat > "$SSH_BANNER_FILE"
    chmod 644 "$SSH_BANNER_FILE"
    _enable_banner_in_sshd_config
    _restart_ssh
    echo
    pgy_box_top "$C_GREEN"
    pgy_box_header "STATIC BANNER TERSIMPAN" "$C_GREEN" "$C_GREEN"
    pgy_box_divider "$C_GREEN"
    pgy_row "Banner SSH statis berhasil disimpan dan diterapkan ke SSH." "$C_GREEN"
    pgy_box_bot "$C_GREEN"
    press_enter
}

pgy_generate_user_banner() {
    local target_user="$1"
    local banner_dir="/etc/pgytunnel/banners"
    mkdir -p "$banner_dir"
    load_banner_identity_config

    local user pass exp max_l quota trial_m trial_e _rest
    if [[ -f "$DB_FILE" ]]; then
        while IFS=: read -r user pass exp max_l quota trial_m trial_e _rest; do
            [[ -n "$user" && "$user" != \#* ]] || continue
            if [[ -n "$target_user" && "$user" != "$target_user" ]]; then
                continue
            fi
            
            local max_display="${max_l:-1}"
            local exp_display="${exp:-Never}"
            local quota_display="Unlimited"
            if [[ "$quota" =~ ^[0-9]+$ && "$quota" -gt 0 ]]; then
                quota_display="${quota} GB"
            fi
            if [[ "$trial_m" == "trial" && -n "$trial_e" && "$trial_e" -gt 0 ]]; then
                exp_display=$(date -d "@$trial_e" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "$exp")
            fi

            local banner_content
            banner_content=$(cat <<EOF
<br><br>---------------------------------<br>
<b>[!] ACCOUNT • DETAILS [!]</b><br>
---------------------------------<br>
<b>[-] Username:</b> ${user}<br>
<b>[-] Status:</b> Active<br>
<b>[-] Active Session:</b> 0/${max_display}<br>
<b>[-] Expiration:</b> ${exp_display}<br>
<b>[-] Quota:</b> ${quota_display}<br>
---------------------------------<br>
<b>[-] Admin:</b> <a href="https://t.me/${BANNER_ADMIN_USERNAME}">@${BANNER_ADMIN_USERNAME}</a><br>
<b>[-] Channel:</b> <a href="https://t.me/${BANNER_CHANNEL_USERNAME}">@${BANNER_CHANNEL_USERNAME}</a><br>
---------------------------------
EOF
)
            write_banner_if_changed "$user" "$banner_content"
        done < "$DB_FILE"
    fi
}

view_ssh_banner() {
    clear; show_banner
    pgy_screen_title "CURRENT STATIC SSH BANNER"
    if [ -f "$SSH_BANNER_FILE" ]; then
        echo
        pgy_section "BANNER CONTENT"
        local bline
        while IFS= read -r bline; do
            pgy_row "$bline" "$C_CYAN"
        done < "$SSH_BANNER_FILE"
        pgy_box_bot
    else
        echo
        pgy_message INFO "No static banner is configured."
    fi
    press_enter
}

remove_ssh_banner() {
    clear; show_banner
    pgy_screen_title "DISABLE SSH BANNERS" "Disable both dynamic and static SSH login banners." "$C_DANGER"
    read -p "  Are you sure you want to disable all SSH banners? (y/n): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo
        pgy_message CANCELLED "Action cancelled."
        press_enter
        return
    fi
    if [ -f "$SSH_BANNER_FILE" ]; then
        rm -f "$SSH_BANNER_FILE"
    fi
    disable_dynamic_ssh_banner_system
    disable_static_ssh_banner_in_sshd_config
    _restart_ssh >/dev/null 2>&1 || true
    echo
    pgy_message OK "All SSH banners have been disabled."
    press_enter
}

preview_dynamic_ssh_banner() {
    if ! is_dynamic_ssh_banner_enabled; then
        echo
        pgy_message ERROR "Dynamic banners are not enabled right now."
        press_enter
        return
    fi

    _select_user_interface "PREVIEW DYNAMIC BANNER"
    local u=$SELECTED_USER
    if [[ -z "$u" || "$u" == "NO_USERS" ]]; then
        return
    fi

    pgy_generate_user_banner "$u"

    echo
    pgy_section "DYNAMIC BANNER PREVIEW — $u"
    if [[ -f "/etc/pgytunnel/banners/${u}.txt" ]]; then
        local raw_content line
        raw_content=$(cat "/etc/pgytunnel/banners/${u}.txt" 2>/dev/null | sed 's/<br>/\n/g; s/<[^>]*>//g')
        while IFS= read -r line; do
            line=$(echo "$line" | tr -d '\r')
            [[ -z "$line" ]] && continue
            if [[ "$line" =~ ^---+ ]]; then
                pgy_box_divider
            elif [[ "$line" =~ ^\[\!\] ]]; then
                pgy_row "${C_BOLD}${C_CYAN}${line}${C_RESET}"
            elif [[ "$line" =~ ^\[\-\]\ (.*):\ (.*)$ ]]; then
                pgy_detail "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "$C_WHITE"
            else
                pgy_row "${C_WHITE}${line}${C_RESET}"
            fi
        done <<< "$raw_content"
        pgy_box_bot
    else
        pgy_row "${C_YELLOW}Banner file not generated yet for user: $u${C_RESET}"
        pgy_box_bot
    fi
    press_enter
}


ssh_banner_menu() {
    while true; do
        show_banner
        local banner_mode
        local banner_status banner_color
        banner_mode=$(get_ssh_banner_mode)
        case "$banner_mode" in
            dynamic) banner_status="Dynamic"; banner_color="$C_GREEN" ;;
            static) banner_status="Static"; banner_color="$C_GREEN" ;;
            *) banner_status="Disabled"; banner_color="$C_RED" ;;
        esac

        echo
        pgy_box_top
        pgy_box_header "SSH BANNER MANAGEMENT"
        pgy_box_divider
        pgy_row2 "${C_GRAY}CURRENT MODE${C_RESET}" "${banner_color}${C_BOLD}${banner_status}${C_RESET}"
        pgy_box_divider
        pgy_menu1 "[ 1]" "Enable Dynamic Account Banner"
        pgy_menu1 "[ 2]" "Paste or Replace Static Banner"
        pgy_menu1 "[ 3]" "View Current Static Banner"
        pgy_menu1 "[ 4]" "Preview Dynamic Banner"
        pgy_menu1 "[ 5]" "Edit Dynamic Banner Contacts"
        pgy_menu1 "[ 6]" "Disable All SSH Banners"
        pgy_box_divider
        pgy_menu1 "[ 0]" "Return to Main Menu"
        pgy_box_bot
        echo
        if ! read -r -p "$(echo -e "${C_PROMPT}  Select an option: ${C_RESET}")" choice; then
            echo
            return
        fi
        case $choice in
            1)
                if setup_ssh_login_info; then
                    echo -e "\n${C_GREEN}[OK] Dynamic account banner enabled.${C_RESET}"
                    echo -e "${C_DIM}Users will now see their account info banner instead of the static banner.${C_RESET}"
                fi
                press_enter
                ;;
            2) set_ssh_banner_paste ;;
            3) view_ssh_banner ;;
            4) preview_dynamic_ssh_banner ;;
            5) edit_dynamic_banner_contacts ;;
            6) remove_ssh_banner ;;
            0) return ;;
            *) echo -e "\n${C_RED}[ERROR] Invalid option.${C_RESET}" && sleep 1 ;;
        esac
    done
}

