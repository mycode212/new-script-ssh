#!/bin/bash
# ============================================================
# Auto Script SSH By : ProgoCloud
# Module: features/users.sh - SSH and VPN account management
# ============================================================

db_has_user() {
    [[ -f "$DB_FILE" ]] || return 1
    awk -F: -v target="$1" '$1 == target { found=1; exit } END { exit(found ? 0 : 1) }' "$DB_FILE"
}

pgy_manual_lock_store_init() {
    mkdir -p "$DB_DIR" || return 1
    if [[ -L "$MANUAL_LOCK_FILE" || ( -e "$MANUAL_LOCK_FILE" && ! -f "$MANUAL_LOCK_FILE" ) ]]; then
        return 1
    fi
    touch "$MANUAL_LOCK_FILE" "$MANUAL_LOCK_MUTEX" || return 1
    chmod 600 "$MANUAL_LOCK_FILE" "$MANUAL_LOCK_MUTEX" || return 1
    if (( EUID == 0 )); then
        chown root:root "$MANUAL_LOCK_FILE" "$MANUAL_LOCK_MUTEX" || return 1
    fi
}

pgy_user_is_manually_locked() {
    local username="$1"
    [[ -f "$MANUAL_LOCK_FILE" ]] || return 1
    grep -Fxq -- "$username" "$MANUAL_LOCK_FILE" 2>/dev/null
}

pgy_set_manual_lock_state() {
    local username="$1" requested_state="$2"
    local tmp_file rc=0

    is_valid_pgytunnel_username "$username" || return 1
    [[ "$requested_state" == "locked" || "$requested_state" == "unlocked" ]] || return 1
    pgy_manual_lock_store_init || return 1

    exec 7>"$MANUAL_LOCK_MUTEX" || return 1
    flock -x 7 || { exec 7>&-; return 1; }
    tmp_file=$(mktemp "${MANUAL_LOCK_FILE}.tmp.XXXXXX") || {
        flock -u 7
        exec 7>&-
        return 1
    }

    if ! awk -v target="$username" '
        $0 != target && length($0) <= 32 && $0 ~ /^[A-Za-z_][A-Za-z0-9_-]*$/ { print }
    ' "$MANUAL_LOCK_FILE" > "$tmp_file"; then
        rc=1
    elif [[ "$requested_state" == "locked" ]]; then
        printf '%s\n' "$username" >> "$tmp_file" || rc=1
    fi

    if (( rc == 0 )); then
        LC_ALL=C sort -u -o "$tmp_file" "$tmp_file" || rc=1
        chmod 600 "$tmp_file" || rc=1
        if (( EUID == 0 )); then
            chown root:root "$tmp_file" || rc=1
        fi
    fi
    if (( rc == 0 )); then
        mv -f "$tmp_file" "$MANUAL_LOCK_FILE" || rc=1
    fi
    (( rc == 0 )) || rm -f "$tmp_file"
    flock -u 7
    exec 7>&-
    return "$rc"
}

pgy_move_manual_lock_state() {
    local old_username="$1" new_username="$2"
    local tmp_file old_was_locked=false rc=0

    is_valid_pgytunnel_username "$old_username" || return 1
    is_valid_pgytunnel_username "$new_username" || return 1
    [[ "$old_username" != "$new_username" ]] || return 0
    pgy_manual_lock_store_init || return 1

    exec 7>"$MANUAL_LOCK_MUTEX" || return 1
    flock -x 7 || { exec 7>&-; return 1; }
    if grep -Fxq -- "$new_username" "$MANUAL_LOCK_FILE" 2>/dev/null; then
        flock -u 7
        exec 7>&-
        return 2
    fi
    grep -Fxq -- "$old_username" "$MANUAL_LOCK_FILE" 2>/dev/null && old_was_locked=true
    tmp_file=$(mktemp "${MANUAL_LOCK_FILE}.tmp.XXXXXX") || {
        flock -u 7
        exec 7>&-
        return 1
    }
    if ! awk -v old="$old_username" -v new="$new_username" '
        $0 != old && $0 != new && length($0) <= 32 &&
        $0 ~ /^[A-Za-z_][A-Za-z0-9_-]*$/ { print }
    ' "$MANUAL_LOCK_FILE" > "$tmp_file"; then
        rc=1
    elif $old_was_locked; then
        printf '%s\n' "$new_username" >> "$tmp_file" || rc=1
    fi
    if (( rc == 0 )); then
        LC_ALL=C sort -u -o "$tmp_file" "$tmp_file" || rc=1
        chmod 600 "$tmp_file" || rc=1
        if (( EUID == 0 )); then
            chown root:root "$tmp_file" || rc=1
        fi
    fi
    (( rc == 0 )) && mv -f "$tmp_file" "$MANUAL_LOCK_FILE" || rc=1
    (( rc == 0 )) || rm -f "$tmp_file"
    flock -u 7
    exec 7>&-
    return "$rc"
}

pgy_clear_all_manual_locks() {
    local tmp_file rc=0
    pgy_manual_lock_store_init || return 1
    exec 7>"$MANUAL_LOCK_MUTEX" || return 1
    flock -x 7 || { exec 7>&-; return 1; }
    tmp_file=$(mktemp "${MANUAL_LOCK_FILE}.tmp.XXXXXX") || {
        flock -u 7
        exec 7>&-
        return 1
    }
    : > "$tmp_file" || rc=1
    chmod 600 "$tmp_file" || rc=1
    if (( EUID == 0 )); then
        chown root:root "$tmp_file" || rc=1
    fi
    (( rc == 0 )) && mv -f "$tmp_file" "$MANUAL_LOCK_FILE" || rc=1
    (( rc == 0 )) || rm -f "$tmp_file"
    flock -u 7
    exec 7>&-
    return "$rc"
}

pgy_restore_manual_lock_archive() {
    local restore_root="$1" source_file="" legacy_format=false
    local username lock_state _extra reason

    pgy_clear_all_manual_locks || return 1
    if [[ -f "$restore_root/manual-locks.db" && ! -L "$restore_root/manual-locks.db" ]]; then
        source_file="$restore_root/manual-locks.db"
    elif [[ -f "$restore_root/locks.db" && ! -L "$restore_root/locks.db" ]]; then
        source_file="$restore_root/locks.db"
        legacy_format=true
    else
        return 0
    fi

    while IFS=: read -r username lock_state _extra; do
        [[ -n "$username" && "$username" != \#* ]] || continue
        is_valid_pgytunnel_username "$username" || continue
        db_has_user "$username" && id "$username" >/dev/null 2>&1 || continue
        if $legacy_format; then
            [[ "$lock_state" == "locked" ]] || continue
            reason=$(pgy_user_policy_reason "$username" 2>/dev/null || true)
            # Old backups used shadow locks for both operator actions and
            # automatic expiry/quota enforcement. Only an otherwise-valid
            # legacy lock can safely be migrated as an operator lock.
            [[ "$reason" != "expired" && "$reason" != "quota" ]] || continue
        fi
        pgy_set_manual_lock_state "$username" locked || return 1
    done < "$source_file"
}

pgy_user_policy_reason() {
    local username="$1" line _user _password expiry _limit quota_gb account_type metadata_value _rest
    local now expiry_epoch=0 used_bytes=0 quota_bytes

    line=$(awk -F: -v target="$username" '$1 == target { print; exit }' "$DB_FILE" 2>/dev/null)
    if [[ -z "$line" ]]; then
        printf '%s\n' "missing"
        return 1
    fi
    IFS=: read -r _user _password expiry _limit quota_gb account_type metadata_value _rest <<< "$line"
    now=$(date +%s)

    if [[ "$account_type" == "trial" && "$metadata_value" =~ ^[0-9]+$ &&
          "$metadata_value" -gt 0 && "$metadata_value" -le "$now" ]]; then
        printf '%s\n' "expired"
        return 0
    fi
    if [[ "$account_type" != "pending" && -n "$expiry" && "$expiry" != "Never" ]]; then
        expiry_epoch=$(date -d "$expiry 23:59:59" +%s 2>/dev/null || echo 0)
        if [[ "$expiry_epoch" =~ ^[0-9]+$ ]] && (( expiry_epoch > 0 && expiry_epoch < now )); then
            printf '%s\n' "expired"
            return 0
        fi
    fi

    [[ "$quota_gb" =~ ^[0-9]+([.][0-9]+)?$ ]] || quota_gb=0
    if ! pgy_quota_is_unlimited "$quota_gb"; then
        if [[ -f "$BANDWIDTH_DIR/${username}.usage" ]]; then
            read -r used_bytes < "$BANDWIDTH_DIR/${username}.usage" || used_bytes=0
            [[ "$used_bytes" =~ ^[0-9]+$ ]] || used_bytes=0
        fi
        quota_bytes=$(awk "BEGIN {printf \"%.0f\", $quota_gb * 1073741824}")
        if [[ "$quota_bytes" =~ ^[0-9]+$ ]] && (( used_bytes >= quota_bytes )); then
            printf '%s\n' "quota"
            return 0
        fi
    fi

    if pgy_user_is_manually_locked "$username"; then
        printf '%s\n' "manual_lock"
    elif [[ "$account_type" == "pending" ]]; then
        printf '%s\n' "pending"
    else
        printf '%s\n' "active"
    fi
}

migrate_legacy_shadow_locks() {
    local username _rest passwd_state policy_reason
    [[ -s "$DB_FILE" ]] || return 0
    pgy_manual_lock_store_init || return 1

    while IFS=: read -r username _rest; do
        [[ -n "$username" && "$username" != \#* ]] || continue
        id "$username" >/dev/null 2>&1 || continue
        passwd_state=$(passwd -S "$username" 2>/dev/null | awk 'NR == 1 { print $2 }')
        [[ "$passwd_state" == "L" || "$passwd_state" == "LK" ]] || continue

        if ! pgy_user_is_manually_locked "$username"; then
            policy_reason=$(pgy_user_policy_reason "$username" 2>/dev/null || true)
            # Before reason-aware policy existed, active shadow locks could only
            # represent an operator lock. Expiry/quota locks are automatic and
            # must not be imported into the manual Unlock list.
            if [[ "$policy_reason" != "expired" && "$policy_reason" != "quota" ]]; then
                pgy_set_manual_lock_state "$username" locked || return 1
            fi
        fi
        # Password authentication must succeed before the PAM account hook can
        # display a reason-specific denial banner. Access remains denied by the
        # root-owned manual policy store, expiry, or quota check.
        usermod -U "$username" >/dev/null 2>&1 || return 1
    done < "$DB_FILE"
}

db_set_pending_validity() {
    local username="$1" validity_days="$2" tmp_file

    [[ -f "$DB_FILE" && "$validity_days" =~ ^[1-9][0-9]*$ ]] || return 1
    tmp_file=$(mktemp "${DB_FILE}.pending-validity.XXXXXX") || return 1

    if ! awk -F: -v OFS=: -v target="$username" -v days="$validity_days" '
        $1 == target && $6 == "pending" {
            $3 = "Never"
            $7 = days
            updated = 1
        }
        { print }
        END { if (!updated) exit 2 }
    ' "$DB_FILE" > "$tmp_file"; then
        rm -f "$tmp_file"
        return 1
    fi

    chmod --reference="$DB_FILE" "$tmp_file" 2>/dev/null || chmod 600 "$tmp_file"
    chown --reference="$DB_FILE" "$tmp_file" 2>/dev/null || true
    mv -f "$tmp_file" "$DB_FILE"
}

is_pgytunnel_orphan_user() {
    local username="$1"
    local passwd_line system_user _ uid _ home shell

    passwd_line=$(getent passwd "$username" 2>/dev/null) || return 1
    IFS=: read -r system_user _ uid _ _ home shell <<< "$passwd_line"
    [[ "$uid" =~ ^[0-9]+$ ]] || return 1
    db_has_user "$username" && return 1

    if id -nG "$username" 2>/dev/null | tr ' ' '\n' | grep -Fxq "$PGY_USERS_GROUP"; then
        return 0
    fi

    (( uid >= 1000 )) || return 1
    [[ "$home" == "/home/$username" || "$home" == /home/* ]] || return 1

    case "$shell" in
        /usr/sbin/nologin|/usr/bin/false|/bin/false) return 0 ;;
    esac

    return 1
}

get_pgytunnel_orphan_users() {
    local username
    while IFS=: read -r username _rest; do
        [[ -n "$username" ]] || continue
        if is_pgytunnel_orphan_user "$username"; then
            echo "$username"
        fi
    done < /etc/passwd
}

get_pgytunnel_known_users() {
    local username
    local -A seen_users=()

    if [[ -f "$DB_FILE" ]]; then
        while IFS=: read -r username _rest; do
            [[ -n "$username" && "$username" != \#* ]] || continue
            seen_users["$username"]=1
        done < "$DB_FILE"
    fi

    while IFS= read -r username; do
        [[ -n "$username" ]] && seen_users["$username"]=1
    done < <(get_pgytunnel_orphan_users)

    (( ${#seen_users[@]} > 0 )) || return 0
    printf "%s\n" "${!seen_users[@]}" | sort
}

delete_pgytunnel_user_accounts() {
    local -a users_to_delete=("$@")
    local username

    [[ ${#users_to_delete[@]} -gt 0 ]] || return 0

    for username in "${users_to_delete[@]}"; do
        [[ -n "$username" ]] || continue
        if declare -F pgy_openvpn_kill_user >/dev/null 2>&1; then
            pgy_openvpn_kill_user "$username"
        fi
        killall -u "$username" -9 &>/dev/null
        if id "$username" &>/dev/null; then
            if userdel -r "$username" &>/dev/null; then
                echo -e " [OK] System user '${C_YELLOW}$username${C_RESET}' deleted."
            else
                echo -e " [ERROR] Failed to delete system user '${C_YELLOW}$username${C_RESET}'."
            fi
        else
            echo -e " [INFO] System user '${C_YELLOW}$username${C_RESET}' was already missing. Removing manager data only."
        fi
        rm -f "$BANDWIDTH_DIR/${username}.usage"
        rm -rf "$BANDWIDTH_DIR/pidtrack/${username}"
        rm -f "$DB_DIR/banners/${username}.txt" 2>/dev/null
        is_valid_pgytunnel_username "$username" && \
            rm -f "$SSH_AUTH_SESSION_DIR/${username}.denied" 2>/dev/null
        pgy_set_manual_lock_state "$username" unlocked >/dev/null 2>&1 || true
    done

    if [[ -f "$DB_FILE" ]]; then
        local db_tmp
        db_tmp=$(mktemp)
        awk -F: 'NR==FNR { drop[$1]=1; next } !($1 in drop)' <(printf "%s\n" "${users_to_delete[@]}") "$DB_FILE" > "$db_tmp" && mv "$db_tmp" "$DB_FILE"
        rm -f "$db_tmp" 2>/dev/null
    fi

    invalidate_banner_cache
    refresh_dynamic_banner_routing_if_enabled
}


_select_user_interface() {
    local title="$1"
    clear; show_banner
    if [[ ! -s $DB_FILE ]]; then
        echo
        pgy_box_top
        pgy_box_header "$title"
        pgy_box_divider
        pgy_row "${C_YELLOW}No users found in the database.${C_RESET}"
        pgy_box_bot
        SELECTED_USER="NO_USERS"; return
    fi

    local -a all_users=() users=()
    mapfile -t all_users < <(cut -d: -f1 "$DB_FILE" | sort)
    local -A all_user_lookup=()
    local username search_term user_number
    for username in "${all_users[@]}"; do
        all_user_lookup["$username"]=1
    done
    
    if [ ${#all_users[@]} -ge 15 ]; then
        read -r -p "$(echo -e "${C_PROMPT}  Search username (Enter = all): ${C_RESET}")" search_term
        if [[ -n "$search_term" ]]; then
            mapfile -t users < <(printf "%s\n" "${all_users[@]}" | grep -iF -- "$search_term")
        else
            users=("${all_users[@]}")
        fi
    else
        users=("${all_users[@]}")
    fi

    if [ ${#users[@]} -eq 0 ]; then
        echo -e "\n${C_YELLOW}No users found matching your search.${C_RESET}"
        SELECTED_USER="NO_USERS"; return
    fi

    echo
    pgy_box_top
    pgy_box_header "$title"
    pgy_box_divider
    for i in "${!users[@]}"; do
        printf -v user_number "[%2d]" "$((i+1))"
        pgy_menu1 "$user_number" "${users[$i]}"
    done
    pgy_box_divider
    pgy_menu1 "[ 0]" "Cancel"
    pgy_row "${C_GRAY}Number or exact username is accepted.${C_RESET}"
    pgy_box_bot
    echo
    local choice
    while true; do
        if ! read -r -p "$(echo -e "${C_PROMPT}  Select a user: ${C_RESET}")" choice; then
            echo
            SELECTED_USER=""
            return
        fi
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 0 ] && [ "$choice" -le "${#users[@]}" ]; then
            if [ "$choice" -eq 0 ]; then
                SELECTED_USER=""; return
            else
                SELECTED_USER="${users[$((choice-1))]}"; return
            fi
        elif [[ -n "${all_user_lookup[$choice]+x}" ]]; then
            SELECTED_USER="$choice"; return
        else
            echo -e "${C_RED}[ERROR] Invalid selection. Please try again.${C_RESET}"
        fi
    done
}

pgy_account_lock_state() {
    local username="$1"

    if ! id "$username" &>/dev/null; then
        printf '%s\n' "missing"
        return 1
    fi
    if pgy_user_is_manually_locked "$username"; then
        printf '%s\n' "locked"
    else
        printf '%s\n' "unlocked"
    fi
}

_select_multi_user_interface() {
    local title="$1"
    local include_orphan_users="${2:-false}"
    local account_state_filter="${3:-any}"
    clear; show_banner
    SELECTED_USERS=()
    local -a all_users=() users=()
    local -a state_filtered_users=()
    local -a orphan_users=()
    local -A all_user_lookup=()
    local -A orphan_user_lookup=()
    local username search_term user_number account_state

    case "$account_state_filter" in
        any|locked|unlocked) ;;
        *)
            echo -e "\n${C_RED}[ERROR] Invalid account-state filter: ${account_state_filter}.${C_RESET}"
            SELECTED_USERS=("NO_USERS")
            return 1
            ;;
    esac

    if [[ -s $DB_FILE ]]; then
        mapfile -t all_users < <(cut -d: -f1 "$DB_FILE" | sort)
    fi

    if [[ "$include_orphan_users" == "true" ]]; then
        mapfile -t orphan_users < <(get_pgytunnel_orphan_users)
        for username in "${orphan_users[@]}"; do
            orphan_user_lookup["$username"]=1
            if ! printf "%s\n" "${all_users[@]}" | grep -Fxq "$username"; then
                all_users+=("$username")
            fi
        done
        if [[ ${#all_users[@]} -gt 0 ]]; then
            mapfile -t all_users < <(printf "%s\n" "${all_users[@]}" | sort)
        fi
    fi

    if [[ "$account_state_filter" != "any" ]]; then
        for username in "${all_users[@]}"; do
            account_state=$(pgy_account_lock_state "$username" 2>/dev/null || true)
            if [[ "$account_state" == "$account_state_filter" ]]; then
                state_filtered_users+=("$username")
            fi
        done
        all_users=("${state_filtered_users[@]}")
    fi

    if [[ ${#all_users[@]} -eq 0 ]]; then
        echo
        pgy_box_top
        pgy_box_header "$title"
        pgy_box_divider
        if [[ "$account_state_filter" == "locked" ]]; then
            pgy_row "${C_YELLOW}No locked accounts are available to unlock.${C_RESET}"
        elif [[ "$account_state_filter" == "unlocked" ]]; then
            pgy_row "${C_YELLOW}No unlocked accounts are available to lock.${C_RESET}"
        else
            pgy_row "${C_YELLOW}No managed users were found.${C_RESET}"
        fi
        if [[ "$include_orphan_users" == "true" && "$account_state_filter" == "any" ]]; then
            pgy_row "${C_GRAY}No system-only accounts were found.${C_RESET}"
        fi
        pgy_box_bot
        SELECTED_USERS=("NO_USERS"); return
    fi

    for username in "${all_users[@]}"; do
        all_user_lookup["$username"]=1
    done
    
    if [ ${#all_users[@]} -ge 15 ]; then
        read -r -p "$(echo -e "${C_PROMPT}  Search username (Enter = all): ${C_RESET}")" search_term
        if [[ -n "$search_term" ]]; then
            mapfile -t users < <(printf "%s\n" "${all_users[@]}" | grep -iF -- "$search_term")
        else
            users=("${all_users[@]}")
        fi
    else
        users=("${all_users[@]}")
    fi

    if [ ${#users[@]} -eq 0 ]; then
        echo -e "\n${C_YELLOW}No users found matching your search.${C_RESET}"
        SELECTED_USERS=("NO_USERS"); return
    fi

    echo
    pgy_box_top
    pgy_box_header "$title"
    pgy_box_divider
    for i in "${!users[@]}"; do
        local display_user="${users[$i]}"
        if [[ "$include_orphan_users" == "true" && -n "${orphan_user_lookup[${users[$i]}]+x}" ]]; then
            display_user="${display_user} (system-only)"
        fi
        printf -v user_number "[%2d]" "$((i+1))"
        pgy_menu1 "$user_number" "$display_user"
    done
    pgy_box_divider
    pgy_menu1 "[all]" "Select All Listed Users"
    pgy_menu1 "[ 0]" "Cancel"
    pgy_row "${C_GRAY}Examples: 1 3 5 | 1,3 | 1-4 | alice bob${C_RESET}"
    if [[ "$include_orphan_users" == "true" ]]; then
        pgy_row "${C_GRAY}(system-only) = account missing from users.db${C_RESET}"
    fi
    pgy_box_bot
    echo
    local choice
    while true; do
        if ! read -r -p "$(echo -e "${C_PROMPT}  Select users: ${C_RESET}")" choice; then
            echo
            SELECTED_USERS=()
            return
        fi
        choice=$(echo "$choice" | tr ',' ' ') # Replace commas with spaces
        
        if [[ -z "$choice" ]]; then
            echo -e "${C_RED}[ERROR] Invalid selection. Please try again.${C_RESET}"
            continue
        fi

        if [[ "$choice" == "0" ]]; then
            SELECTED_USERS=(); return
        fi
        
        if [[ "${choice,,}" == "all" ]]; then
            SELECTED_USERS=("${users[@]}")
            return
        fi
        
        local valid=true
        local selected_indices=()
        local selected_names=()
        for token in $choice; do
            if [[ "$token" =~ ^[0-9]+-[0-9]+$ ]]; then
                local start=${token%-*}
                local end=${token#*-}
                if [ "$start" -le "$end" ]; then
                    for (( idx=start; idx<=end; idx++ )); do
                        if [ "$idx" -ge 1 ] && [ "$idx" -le "${#users[@]}" ]; then
                            selected_indices+=($idx)
                        else
                            valid=false; break
                        fi
                    done
                else
                    valid=false; break
                fi
            elif [[ "$token" =~ ^[0-9]+$ ]]; then
                if [ "$token" -ge 1 ] && [ "$token" -le "${#users[@]}" ]; then
                    selected_indices+=($token)
                elif [[ -n "${all_user_lookup[$token]+x}" ]]; then
                    selected_names+=("$token")
                else
                    valid=false; break
                fi
            elif [[ -n "${all_user_lookup[$token]+x}" ]]; then
                selected_names+=("$token")
            else
                valid=false; break
            fi
        done
        
        if [[ "$valid" == true && ( ${#selected_indices[@]} -gt 0 || ${#selected_names[@]} -gt 0 ) ]]; then
            if (( ${#selected_indices[@]} > 0 )); then
                mapfile -t unique_indices < <(printf "%s\n" "${selected_indices[@]}" | sort -u -n)
                for idx in "${unique_indices[@]}"; do
                    [[ "$idx" =~ ^[0-9]+$ ]] || continue
                    SELECTED_USERS+=("${users[$((idx-1))]}")
                done
            fi
            if (( ${#selected_names[@]} > 0 )); then
                mapfile -t unique_names < <(printf "%s\n" "${selected_names[@]}" | sort -u)
                for username in "${unique_names[@]}"; do
                    [[ -n "$username" ]] || continue
                    if ! printf "%s\n" "${SELECTED_USERS[@]}" | grep -Fxq "$username"; then
                        SELECTED_USERS+=("$username")
                    fi
                done
            fi
            return
        else
            echo -e "${C_RED}[ERROR] Invalid selection. Please check your numbers or usernames.${C_RESET}"
            SELECTED_USERS=()
            selected_indices=()
            selected_names=()
        fi
    done
}

get_user_status() {
    local username="$1"
    if ! id "$username" &>/dev/null; then echo -e "${C_RED}Not Found${C_RESET}"; return; fi
    local reason
    reason=$(pgy_user_policy_reason "$username" 2>/dev/null || true)
    case "$reason" in
        manual_lock) echo -e "${C_YELLOW}Manually Locked${C_RESET}" ;;
        expired) echo -e "${C_RED}Expired${C_RESET}" ;;
        quota) echo -e "${C_RED}Quota Ended${C_RESET}" ;;
        pending) echo -e "${C_CYAN}Waiting for First Use${C_RESET}" ;;
        active) echo -e "${C_GREEN}Active${C_RESET}" ;;
        *) echo -e "${C_RED}Unknown${C_RESET}" ;;
    esac
}

is_valid_pgytunnel_username() {
    local username="$1"
    [[ ${#username} -le 32 && "$username" =~ ^[A-Za-z_][A-Za-z0-9_-]{0,31}$ ]]
}

rollback_pgytunnel_user_rename() {
    local old_username="$1" new_username="$2"
    local old_home="$3" new_home="$4" move_home="$5"
    local group_renamed="$6" usage_moved="$7" banner_created="$8"
    local rollback_ok=true

    if [[ "$banner_created" == true ]]; then
        rm -f "$DB_DIR/banners/${new_username}.txt" 2>/dev/null || rollback_ok=false
    fi
    if [[ "$usage_moved" == true ]]; then
        mv -f "$BANDWIDTH_DIR/${new_username}.usage" \
            "$BANDWIDTH_DIR/${old_username}.usage" 2>/dev/null || rollback_ok=false
    fi
    if [[ "$group_renamed" == true ]] && getent group "$new_username" >/dev/null 2>&1; then
        groupmod -n "$old_username" "$new_username" >/dev/null 2>&1 || rollback_ok=false
    fi
    if id "$new_username" >/dev/null 2>&1; then
        if [[ "$move_home" == true ]]; then
            if [[ -d "$new_home" && ! -e "$old_home" ]]; then
                usermod -l "$old_username" -d "$old_home" -m "$new_username" >/dev/null 2>&1 || rollback_ok=false
            else
                usermod -l "$old_username" -d "$old_home" "$new_username" >/dev/null 2>&1 || rollback_ok=false
            fi
        else
            usermod -l "$old_username" "$new_username" >/dev/null 2>&1 || rollback_ok=false
        fi
    fi

    $rollback_ok
}

rename_pgytunnel_user() {
    local old_username="$1" new_username="$2"
    local passwd_entry account_type trial_expiry_epoch old_login old_password old_uid old_gid old_gecos old_home old_shell
    local primary_group new_home move_home=false
    local db_tmp="" db_backup="" banner_tmp=""
    local limiter_was_active=false group_renamed=false usage_moved=false banner_created=false
    local manual_lock_was_set=false manual_lock_moved=false
    local confirm active_process_count

    if ! db_has_user "$old_username" || ! id "$old_username" >/dev/null 2>&1; then
        echo -e "\n${C_RED}[ERROR] The current account is missing from the database or system.${C_RESET}"
        return 1
    fi
    if [[ "$new_username" == "$old_username" ]]; then
        echo -e "\n${C_YELLOW}[INFO] The username is already '${old_username}'. Nothing was changed.${C_RESET}"
        return 1
    fi
    if ! is_valid_pgytunnel_username "$new_username"; then
        echo -e "\n${C_RED}[ERROR] Invalid username.${C_RESET}"
        echo -e "${C_DIM}Use 1-32 letters, numbers, '_' or '-'; start with a letter or '_'.${C_RESET}"
        return 1
    fi
    if db_has_user "$new_username" || getent passwd "$new_username" >/dev/null 2>&1; then
        echo -e "\n${C_RED}[ERROR] Username '${new_username}' already exists.${C_RESET}"
        return 1
    fi

    # New trial cleanup jobs use UID + an immutable expiry token and remain
    # valid after a rename. Only pre-upgrade legacy trials lack that token.
    account_type=$(awk -F: -v target="$old_username" '$1 == target {print $6; exit}' "$DB_FILE")
    trial_expiry_epoch=$(awk -F: -v target="$old_username" '$1 == target {print $7; exit}' "$DB_FILE")
    if [[ "$account_type" == "trial" && ! "$trial_expiry_epoch" =~ ^[0-9]+$ ]]; then
        echo -e "\n${C_YELLOW}[WARNING] This legacy trial was scheduled by username before rename-safe cleanup existed.${C_RESET}"
        echo -e "${C_DIM}Create a new trial instead; current trial accounts can be renamed safely.${C_RESET}"
        return 1
    fi

    passwd_entry=$(getent passwd "$old_username" 2>/dev/null) || {
        echo -e "\n${C_RED}[ERROR] Could not read the system account.${C_RESET}"
        return 1
    }
    IFS=: read -r old_login old_password old_uid old_gid old_gecos old_home old_shell <<< "$passwd_entry"
    primary_group=$(getent group "$old_gid" 2>/dev/null | cut -d: -f1)
    if [[ -z "$primary_group" ]]; then
        echo -e "\n${C_RED}[ERROR] Could not resolve the account's primary group.${C_RESET}"
        return 1
    fi
    if [[ "$primary_group" == "$old_username" ]] && getent group "$new_username" >/dev/null 2>&1; then
        echo -e "\n${C_RED}[ERROR] Group '${new_username}' already exists; rename cancelled to avoid a group conflict.${C_RESET}"
        return 1
    fi

    new_home="$old_home"
    if [[ "$old_home" == "/home/${old_username}" ]]; then
        new_home="/home/${new_username}"
        move_home=true
        if [[ -e "$new_home" ]]; then
            echo -e "\n${C_RED}[ERROR] Home path '${new_home}' already exists.${C_RESET}"
            return 1
        fi
    fi
    pgy_user_is_manually_locked "$old_username" && manual_lock_was_set=true
    if [[ -e "$BANDWIDTH_DIR/${new_username}.usage" ||
          -e "$DB_DIR/banners/${new_username}.txt" ]] ||
       pgy_user_is_manually_locked "$new_username"; then
        echo -e "\n${C_RED}[ERROR] Stored data for '${new_username}' already exists; rename cancelled to prevent overwriting it.${C_RESET}"
        return 1
    fi

    db_backup=$(mktemp "${DB_FILE}.rename-backup.XXXXXX") || return 1
    db_tmp=$(mktemp "${DB_FILE}.rename-new.XXXXXX") || {
        rm -f "$db_backup"
        return 1
    }
    if ! cp -p "$DB_FILE" "$db_backup" ||
       ! awk -F: -v OFS=: -v old="$old_username" -v new="$new_username" '
            $1 == old { $1 = new; found = 1 }
            { print }
            END { if (!found) exit 3 }
        ' "$DB_FILE" > "$db_tmp"; then
        rm -f "$db_tmp" "$db_backup"
        echo -e "\n${C_RED}[ERROR] Could not prepare the database migration.${C_RESET}"
        return 1
    fi
    chmod --reference="$DB_FILE" "$db_tmp" 2>/dev/null || true
    chown --reference="$DB_FILE" "$db_tmp" 2>/dev/null || true

    if [[ -f "$DB_DIR/banners/${old_username}.txt" ]]; then
        banner_tmp=$(mktemp "$DB_DIR/banners/.rename.XXXXXX") || {
            rm -f "$db_tmp" "$db_backup"
            return 1
        }
        if ! awk -v old="$old_username" -v new="$new_username" '
                {
                    position = index($0, old)
                    if (position) {
                        $0 = substr($0, 1, position - 1) new substr($0, position + length(old))
                    }
                    print
                }
            ' "$DB_DIR/banners/${old_username}.txt" > "$banner_tmp"; then
            rm -f "$banner_tmp" "$db_tmp" "$db_backup"
            echo -e "\n${C_RED}[ERROR] Could not prepare the dynamic banner migration.${C_RESET}"
            return 1
        fi
        chmod --reference="$DB_DIR/banners/${old_username}.txt" "$banner_tmp" 2>/dev/null || true
        chown --reference="$DB_DIR/banners/${old_username}.txt" "$banner_tmp" 2>/dev/null || true
    fi

    echo -e "\n${C_YELLOW}The account will be renamed:${C_RESET}"
    echo -e "  • Username: ${C_WHITE}${old_username}${C_RESET} → ${C_GREEN}${new_username}${C_RESET}"
    read -r -p "  Type RENAME to confirm: " confirm
    if [[ "$confirm" != "RENAME" ]]; then
        rm -f "$banner_tmp" "$db_tmp" "$db_backup"
        pgy_message CANCELLED "Username change cancelled."
        return 1
    fi

    if systemctl is-active --quiet pgytunnel-limiter 2>/dev/null; then
        limiter_was_active=true
        if ! systemctl stop pgytunnel-limiter >/dev/null 2>&1; then
            rm -f "$banner_tmp" "$db_tmp" "$db_backup"
            echo -e "\n${C_RED}[ERROR] Could not pause the account worker safely; rename cancelled.${C_RESET}"
            return 1
        fi
    fi

    if declare -F pgy_openvpn_kill_user >/dev/null 2>&1; then
        pgy_openvpn_kill_user "$old_username"
    fi

    active_process_count=$(pgrep -u "$old_username" 2>/dev/null | wc -l)
    if (( active_process_count > 0 )); then
        echo -e "\n${C_YELLOW}[WARNING] ${active_process_count} active process(es) must be disconnected before renaming.${C_RESET}"
        read -r -p "  Disconnect them and continue? (y/n): " confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            $limiter_was_active && systemctl start pgytunnel-limiter >/dev/null 2>&1 || true
            rm -f "$banner_tmp" "$db_tmp" "$db_backup"
            pgy_message CANCELLED "Username change cancelled."
            return 1
        fi
        pkill -TERM -u "$old_username" >/dev/null 2>&1 || true
        sleep 1
        pgrep -u "$old_username" >/dev/null 2>&1 && pkill -KILL -u "$old_username" >/dev/null 2>&1 || true
        sleep 1
        if pgrep -u "$old_username" >/dev/null 2>&1; then
            $limiter_was_active && systemctl start pgytunnel-limiter >/dev/null 2>&1 || true
            rm -f "$banner_tmp" "$db_tmp" "$db_backup"
            echo -e "\n${C_RED}[ERROR] Some account processes could not be stopped; rename cancelled.${C_RESET}"
            return 1
        fi
    fi

    if [[ "$move_home" == true ]]; then
        if [[ -d "$old_home" ]]; then
            usermod -l "$new_username" -d "$new_home" -m "$old_username" >/dev/null 2>&1
        else
            usermod -l "$new_username" -d "$new_home" "$old_username" >/dev/null 2>&1
        fi
    else
        usermod -l "$new_username" "$old_username" >/dev/null 2>&1
    fi
    if [[ $? -ne 0 ]]; then
        local partial_rollback_ok=true
        if id "$new_username" >/dev/null 2>&1 && ! id "$old_username" >/dev/null 2>&1; then
            rollback_pgytunnel_user_rename "$old_username" "$new_username" \
                "$old_home" "$new_home" "$move_home" false false false || partial_rollback_ok=false
        fi
        $limiter_was_active && systemctl start pgytunnel-limiter >/dev/null 2>&1 || true
        rm -f "$banner_tmp" "$db_tmp" "$db_backup"
        if $partial_rollback_ok; then
            echo -e "\n${C_RED}[ERROR] Linux account rename failed; the original account was preserved.${C_RESET}"
        else
            echo -e "\n${C_RED}[ERROR] Linux account rename failed and automatic rollback was incomplete.${C_RESET}"
            echo -e "${C_YELLOW}[WARNING] Do not close this SSH session; inspect the system account manually.${C_RESET}"
        fi
        return 1
    fi

    if [[ "$primary_group" == "$old_username" ]]; then
        if ! groupmod -n "$new_username" "$old_username" >/dev/null 2>&1; then
            rollback_pgytunnel_user_rename "$old_username" "$new_username" \
                "$old_home" "$new_home" "$move_home" false false false
            $limiter_was_active && systemctl start pgytunnel-limiter >/dev/null 2>&1 || true
            rm -f "$banner_tmp" "$db_tmp" "$db_backup"
            echo -e "\n${C_RED}[ERROR] Private group rename failed; the original username was restored.${C_RESET}"
            return 1
        fi
        group_renamed=true
    fi

    if [[ -f "$BANDWIDTH_DIR/${old_username}.usage" ]]; then
        if ! mv "$BANDWIDTH_DIR/${old_username}.usage" "$BANDWIDTH_DIR/${new_username}.usage"; then
            rollback_pgytunnel_user_rename "$old_username" "$new_username" \
                "$old_home" "$new_home" "$move_home" "$group_renamed" false false
            $limiter_was_active && systemctl start pgytunnel-limiter >/dev/null 2>&1 || true
            rm -f "$banner_tmp" "$db_tmp" "$db_backup"
            echo -e "\n${C_RED}[ERROR] Bandwidth data migration failed; the original username was restored.${C_RESET}"
            return 1
        fi
        usage_moved=true
    fi

    if [[ -n "$banner_tmp" ]]; then
        if ! mv "$banner_tmp" "$DB_DIR/banners/${new_username}.txt"; then
            rollback_pgytunnel_user_rename "$old_username" "$new_username" \
                "$old_home" "$new_home" "$move_home" "$group_renamed" "$usage_moved" false
            $limiter_was_active && systemctl start pgytunnel-limiter >/dev/null 2>&1 || true
            rm -f "$banner_tmp" "$db_tmp" "$db_backup"
            echo -e "\n${C_RED}[ERROR] Banner migration failed; the original username was restored.${C_RESET}"
            return 1
        fi
        banner_created=true
        banner_tmp=""
    fi

    if ! mv -f "$db_tmp" "$DB_FILE"; then
        rollback_pgytunnel_user_rename "$old_username" "$new_username" \
            "$old_home" "$new_home" "$move_home" "$group_renamed" "$usage_moved" "$banner_created"
        $limiter_was_active && systemctl start pgytunnel-limiter >/dev/null 2>&1 || true
        rm -f "$db_tmp" "$db_backup"
        echo -e "\n${C_RED}[ERROR] Database migration failed; the original username was restored.${C_RESET}"
        return 1
    fi

    if $manual_lock_was_set; then
        if ! pgy_move_manual_lock_state "$old_username" "$new_username"; then
            mv -f "$db_backup" "$DB_FILE" 2>/dev/null
            rollback_pgytunnel_user_rename "$old_username" "$new_username" \
                "$old_home" "$new_home" "$move_home" "$group_renamed" "$usage_moved" "$banner_created"
            $limiter_was_active && systemctl start pgytunnel-limiter >/dev/null 2>&1 || true
            echo -e "\n${C_RED}[ERROR] Manual-lock policy migration failed; the original username was restored.${C_RESET}"
            return 1
        fi
        manual_lock_moved=true
    fi

    if ! id "$new_username" >/dev/null 2>&1 || id "$old_username" >/dev/null 2>&1 ||
       ! db_has_user "$new_username" || db_has_user "$old_username" ||
       { $manual_lock_was_set && ! pgy_user_is_manually_locked "$new_username"; } ||
       pgy_user_is_manually_locked "$old_username"; then
        mv -f "$db_backup" "$DB_FILE" 2>/dev/null
        $manual_lock_moved && pgy_move_manual_lock_state "$new_username" "$old_username" >/dev/null 2>&1 || true
        rollback_pgytunnel_user_rename "$old_username" "$new_username" \
            "$old_home" "$new_home" "$move_home" "$group_renamed" "$usage_moved" "$banner_created"
        $limiter_was_active && systemctl start pgytunnel-limiter >/dev/null 2>&1 || true
        echo -e "\n${C_RED}[ERROR] Post-rename verification failed; the original username was restored.${C_RESET}"
        return 1
    fi

    rm -f "$db_backup" "$DB_DIR/banners/${old_username}.txt"
    rm -f "$SSH_AUTH_SESSION_DIR/${old_username}.denied" \
        "$SSH_AUTH_SESSION_DIR/${new_username}.denied" 2>/dev/null
    rm -rf "$BANDWIDTH_DIR/pidtrack/${old_username}" 2>/dev/null
    rm -f "$BANDWIDTH_DIR/pidtrack/${old_username}__"*.last 2>/dev/null
    if ! id -nG "$new_username" 2>/dev/null | tr ' ' '\n' | grep -Fxq "$PGY_USERS_GROUP"; then
        usermod -aG "$PGY_USERS_GROUP" "$new_username" >/dev/null 2>&1 || true
    fi

    invalidate_banner_cache
    refresh_dynamic_banner_routing_if_enabled "$new_username"
    if $limiter_was_active && ! systemctl start pgytunnel-limiter >/dev/null 2>&1; then
        echo -e "${C_YELLOW}[WARNING] Username changed, but the account worker must be restarted manually.${C_RESET}"
    fi

    echo -e "\n${C_GREEN}[OK] Username changed successfully: ${old_username} → ${new_username}${C_RESET}"
    return 0
}

create_user() {
    clear; show_banner
    pgy_screen_title "CREATE SSH USER" "Create a managed SSH account with limits and expiry."
    read -r -p "$(echo -e "${C_PROMPT}  Username (0 = cancel): ${C_RESET}")" username
    local adopt_existing=false banner_sync_ok=true
    if [[ "$username" == "0" ]]; then
        pgy_message CANCELLED "User creation cancelled."
        return
    fi
    if [[ -z "$username" ]]; then
        pgy_message ERROR "Username cannot be empty."
        return
    fi
    if db_has_user "$username"; then
        pgy_message ERROR "User '$username' already exists in the managed database."
        return
    fi
    if id "$username" &>/dev/null; then
        if is_pgytunnel_orphan_user "$username"; then
            pgy_message WARNING "User '$username' exists on the system but is missing from users.db."
            echo -e "${C_DIM}This usually happens after uninstalling the script without deleting the SSH users.${C_RESET}"
            read -r -p "$(echo -e "${C_PROMPT}  Import and manage this account? [y/N]: ${C_RESET}")" adopt_confirm
            if [[ "$adopt_confirm" == "y" || "$adopt_confirm" == "Y" ]]; then
                adopt_existing=true
            else
                pgy_message CANCELLED "User creation cancelled."
                return
            fi
        else
            pgy_message ERROR "System user '$username' already exists and is not a managed account."
            return
        fi
    fi
    local password=""
    while true; do
        read -r -p "$(echo -e "${C_PROMPT}  Password (Enter = auto-generate): ${C_RESET}")" password
        if [[ -z "$password" ]]; then
            password=$(head /dev/urandom | tr -dc 'A-Za-z0-9' | head -c 8)
            printf "  ${C_GRAY}Generated password:${C_RESET} ${C_YELLOW}%s${C_RESET}\n" "$password"
            break
        else
            break
        fi
    done
    local first_use_activation=false
    local first_use_choice validity_prompt
    read -r -p "$(echo -e "${C_PROMPT}  Start After First Use? [y/N]: ${C_RESET}")" first_use_choice
    [[ "$first_use_choice" == "y" || "$first_use_choice" == "Y" ]] && first_use_activation=true
    if $first_use_activation; then
        validity_prompt="Validity after first use (days) [30]"
    else
        validity_prompt="Validity from today (days) [30]"
    fi
    read -r -p "$(echo -e "${C_PROMPT}  ${validity_prompt}: ${C_RESET}")" days
    days=${days:-30}
    if ! [[ "$days" =~ ^[1-9][0-9]*$ ]]; then pgy_message ERROR "Validity must be at least 1 day."; return; fi
    read -r -p "$(echo -e "${C_PROMPT}  Connection limit [1]: ${C_RESET}")" limit
    limit=${limit:-1}
    if ! [[ "$limit" =~ ^[0-9]+$ ]]; then pgy_message ERROR "Connection limit must be a whole number."; return; fi
    read -r -p "$(echo -e "${C_PROMPT}  Bandwidth in GB (0 = unlimited) [0]: ${C_RESET}")" bandwidth_gb
    bandwidth_gb=${bandwidth_gb:-0}
    if ! [[ "$bandwidth_gb" =~ ^[0-9]+\.?[0-9]*$ ]]; then pgy_message ERROR "Bandwidth must be a valid number."; return; fi
    local expire_date stored_expiry metadata_suffix="" expiry_display activation_display="Immediately"
    expire_date=$(date -d "+$days days" +%Y-%m-%d)
    stored_expiry="$expire_date"
    expiry_display=$(pgy_format_date_display "$expire_date")
    if $first_use_activation; then
        stored_expiry="Never"
        metadata_suffix=":pending:${days}"
        expiry_display="${days} days after first use"
        activation_display="After First Use"
    fi
    ensure_pgytunnel_system_group
    if ! pgy_set_manual_lock_state "$username" unlocked; then
        pgy_message ERROR "Could not prepare a clean account policy for '$username'."
        return
    fi
    if [[ "$adopt_existing" == "true" ]]; then
        usermod -s /usr/sbin/nologin "$username" &>/dev/null
    else
        useradd -m -s /usr/sbin/nologin "$username"
    fi
    usermod -aG "$PGY_USERS_GROUP" "$username" 2>/dev/null
    echo "$username:$password" | chpasswd
    if $first_use_activation; then
        chage -E -1 "$username"
    else
        chage -E "$expire_date" "$username"
    fi
    echo "$username:$password:$stored_expiry:$limit:$bandwidth_gb$metadata_suffix" >> "$DB_FILE"

    # Dynamic routing is part of account provisioning, not a follow-up UI
    # action. Finish it before displaying credentials or opening another
    # prompt so the account's very first SSH connection sees its banner.
    provision_dynamic_banners_for_new_users "$username" || banner_sync_ok=false
    
    local bw_display
    bw_display=$(pgy_format_quota_gb "$bandwidth_gb")
    
    clear; show_banner
    if [[ "$adopt_existing" == "true" ]]; then
        pgy_message OK "Existing system account imported successfully."
    else
        pgy_message OK "SSH account created successfully."
    fi
    echo
    pgy_section "ACCOUNT DETAILS"
    pgy_detail "Username" "$username" "$C_YELLOW"
    pgy_detail "Password" "$password" "$C_YELLOW"
    pgy_detail "Expires" "$expiry_display" "$C_YELLOW"
    pgy_detail "Expiry Starts" "$activation_display"
    pgy_detail "Connections" "$limit"
    pgy_detail "Bandwidth" "$bw_display"
    echo -e "  ${C_DIM}Limits are enforced automatically by the account worker.${C_RESET}"
    if [[ "$banner_sync_ok" != true ]]; then
        echo -e "  ${C_YELLOW}[WARNING] Account created, but dynamic banner routing is still waiting for the worker.${C_RESET}"
    fi

    # Auto-ask for config generation
    echo
    read -r -p "$(echo -e "${C_PROMPT}  Generate client configuration now? [y/N]: ${C_RESET}")" gen_conf
    if [[ "$gen_conf" == "y" || "$gen_conf" == "Y" ]]; then
        generate_client_config "$username" "$password"
    fi
}

delete_user() {
    _select_multi_user_interface "DELETE USERS" "true"
    if [[ ${#SELECTED_USERS[@]} -eq 0 || "${SELECTED_USERS[0]}" == "NO_USERS" ]]; then return; fi
    
    echo -e "\n${C_RED}[WARNING] You selected ${#SELECTED_USERS[@]} user(s) to delete: ${C_YELLOW}${SELECTED_USERS[*]}${C_RESET}"
    read -p "  Are you sure you want to PERMANENTLY delete them? (y/n): " confirm
    if [[ "$confirm" != "y" ]]; then pgy_message CANCELLED "Deletion cancelled."; return; fi
    
    echo -e "\n${C_BLUE}Deleting selected users...${C_RESET}"
    delete_pgytunnel_user_accounts "${SELECTED_USERS[@]}"
}

edit_user() {
    _select_user_interface "EDIT USER"
    local username=$SELECTED_USER
    if [[ "$username" == "NO_USERS" ]] || [[ -z "$username" ]]; then return; fi
    while true; do
        clear; show_banner
        
        # Show current user details
        local current_line; current_line=$(grep "^$username:" "$DB_FILE")
        local cur_pass; cur_pass=$(echo "$current_line" | cut -d: -f2)
        local cur_expiry; cur_expiry=$(echo "$current_line" | cut -d: -f3)
        local cur_limit; cur_limit=$(echo "$current_line" | cut -d: -f4)
        local cur_bw; cur_bw=$(echo "$current_line" | cut -d: -f5)
        local cur_metadata; cur_metadata=$(echo "$current_line" | cut -d: -f6-)
        local cur_metadata_suffix=""; [[ -n "$cur_metadata" ]] && cur_metadata_suffix=":$cur_metadata"
        [[ "$cur_limit" =~ ^[0-9]+$ ]] || cur_limit="1"
        [[ "$cur_bw" =~ ^[0-9]+\.?[0-9]*$ ]] || cur_bw="0"
        local cur_bw_display
        cur_bw_display=$(pgy_format_quota_gb "$cur_bw")
        local cur_expiry_display
        cur_expiry_display=$(pgy_format_date_display "$cur_expiry")
        local pending_first_use=false pending_validity_days=""
        if [[ "$cur_metadata" =~ ^pending:([1-9][0-9]*) ]]; then
            pending_first_use=true
            pending_validity_days="${BASH_REMATCH[1]}"
            cur_expiry_display="First use +${pending_validity_days}d"
        fi

        SSH_SESSION_CACHE_TS=0
        refresh_ssh_session_cache
        local cur_online="${SSH_SESSION_COUNTS[$username]:-0}"
        [[ "$cur_online" =~ ^[0-9]+$ ]] || cur_online="0"
        local cur_connections="${cur_online}/${cur_limit}"
        
        # Show bandwidth usage
        local bw_used_display="0.00GB"
        if [[ -f "$BANDWIDTH_DIR/${username}.usage" ]]; then
            local used_bytes; used_bytes=$(cat "$BANDWIDTH_DIR/${username}.usage" 2>/dev/null)
            [[ "$used_bytes" =~ ^[0-9]+$ ]] || used_bytes="0"
            bw_used_display=$(pgy_format_used_bytes "$used_bytes")
        fi
        
        echo
        pgy_box_top
        pgy_box_header "EDIT USER"
        pgy_box_divider
        pgy_kv2 "USER" "$username" "EXPIRES" "$cur_expiry_display"
        pgy_kv2 "PASS" "$cur_pass" "CONNS" "$cur_connections"
        pgy_kv2 "USED" "$bw_used_display" "LIMIT" "$cur_bw_display"
        pgy_box_divider
        pgy_menu1 "[ 1]" "Change Username"
        pgy_menu1 "[ 2]" "Change Password"
        if $pending_first_use; then
            pgy_menu1 "[ 3]" "Change Validity After First Use"
        else
            pgy_menu1 "[ 3]" "Change Validity from Today"
        fi
        pgy_menu1 "[ 4]" "Change Connection Limit"
        pgy_menu1 "[ 5]" "Change Bandwidth Limit"
        pgy_menu1 "[ 6]" "Reset Bandwidth Counter"
        pgy_box_divider
        pgy_menu1 "[ 0]" "Finish Editing"
        pgy_box_bot
        echo
        if ! read -r -p "$(echo -e "${C_PROMPT}  Select an option: ${C_RESET}")" edit_choice; then
            echo
            return
        fi
        case $edit_choice in
            1)
               local new_username
               read -r -p "  Enter new username: " new_username
               if rename_pgytunnel_user "$username" "$new_username"; then
                   username="$new_username"
               fi
               ;;
            2)
               local new_pass=""
               read -p "  Enter new password (or press Enter for auto-generated): " new_pass
               if [[ -z "$new_pass" ]]; then
                   new_pass=$(head /dev/urandom | tr -dc 'A-Za-z0-9' | head -c 8)
                   echo -e "${C_GREEN}Auto-generated: ${C_YELLOW}$new_pass${C_RESET}"
               fi
               echo "$username:$new_pass" | chpasswd
                sed -i "s/^$username:.*/$username:$new_pass:$cur_expiry:$cur_limit:$cur_bw$cur_metadata_suffix/" "$DB_FILE"
               echo -e "\n${C_GREEN}[OK] Password for '$username' changed to: ${C_YELLOW}$new_pass${C_RESET}"
               ;;
            3)
               if $pending_first_use; then
                   read -r -p "  Validity after first use (days) [${pending_validity_days}]: " days
                   days=${days:-$pending_validity_days}
                   if [[ "$days" =~ ^[1-9][0-9]*$ ]]; then
                       if db_set_pending_validity "$username" "$days"; then
                           echo -e "\n${C_GREEN}[OK] '$username' will remain pending and expire ${C_YELLOW}${days} days after first use${C_RESET}."
                       else
                           echo -e "\n${C_RED}[ERROR] Pending validity could not be updated. The account may have activated already.${C_RESET}"
                       fi
                   else
                       echo -e "\n${C_RED}[ERROR] Validity must be at least 1 day.${C_RESET}"
                   fi
               else
                   read -r -p "  Validity from today (days) [30]: " days
                   days=${days:-30}
                   if [[ "$days" =~ ^[1-9][0-9]*$ ]]; then
                       local new_expire_date; new_expire_date=$(date -d "+$days days" +%Y-%m-%d)
                       chage -E "$new_expire_date" "$username"
                       sed -i "s/^$username:.*/$username:$cur_pass:$new_expire_date:$cur_limit:$cur_bw$cur_metadata_suffix/" "$DB_FILE"
                       echo -e "\n${C_GREEN}[OK] Validity for '$username' set to ${C_YELLOW}${days} days from today${C_RESET} ($(pgy_format_date_display "$new_expire_date"))."
                   else
                       echo -e "\n${C_RED}[ERROR] Validity must be at least 1 day.${C_RESET}"
                   fi
               fi
               ;;
            4) read -p "  Enter new simultaneous connection limit: " new_limit
               if [[ "$new_limit" =~ ^[0-9]+$ ]]; then
                    sed -i "s/^$username:.*/$username:$cur_pass:$cur_expiry:$new_limit:$cur_bw$cur_metadata_suffix/" "$DB_FILE"
                   echo -e "\n${C_GREEN}[OK] Connection limit for '$username' set to ${C_YELLOW}$new_limit${C_RESET}."
               else echo -e "\n${C_RED}[ERROR] Invalid limit.${C_RESET}"; fi ;;
            5) read -p "  Enter new bandwidth limit in GB (0 = unlimited): " new_bw
               if [[ "$new_bw" =~ ^[0-9]+\.?[0-9]*$ ]]; then
                    sed -i "s/^$username:.*/$username:$cur_pass:$cur_expiry:$cur_limit:$new_bw$cur_metadata_suffix/" "$DB_FILE"
                   local bw_msg; bw_msg=$(pgy_format_quota_gb "$new_bw")
                   echo -e "\n${C_GREEN}[OK] Bandwidth limit for '$username' set to ${C_YELLOW}$bw_msg${C_RESET}."
               else echo -e "\n${C_RED}[ERROR] Invalid bandwidth value.${C_RESET}"; fi ;;
            6)
               echo "0" > "$BANDWIDTH_DIR/${username}.usage"
               echo -e "\n${C_GREEN}[OK] Bandwidth counter for '$username' has been reset to 0.${C_RESET}"
               ;;
            0) return ;;
            *) echo -e "\n${C_RED}[ERROR] Invalid option.${C_RESET}" ;;
        esac
        echo -e "\nPress ${C_YELLOW}[Enter]${C_RESET} to continue editing..." && read -r || return
    done
}

lock_user() {
    _select_multi_user_interface "LOCK ACCOUNTS" "false" "unlocked"
    if [[ ${#SELECTED_USERS[@]} -eq 0 || "${SELECTED_USERS[0]}" == "NO_USERS" ]]; then return; fi
    
    echo -e "\n${C_BLUE}Locking selected users...${C_RESET}"
    for u in "${SELECTED_USERS[@]}"; do
        if ! id "$u" &>/dev/null; then
             echo -e " [ERROR] User '${C_YELLOW}$u${C_RESET}' does not exist on this system."
             continue
        fi

        local current_state
        current_state=$(pgy_account_lock_state "$u" 2>/dev/null || true)
        if [[ "$current_state" == "locked" ]]; then
            echo -e " [SKIP] ${C_YELLOW}$u${C_RESET} is already locked."
            continue
        fi
        if [[ "$current_state" != "unlocked" ]]; then
            echo -e " [ERROR] Could not verify the current lock state for ${C_YELLOW}$u${C_RESET}."
            continue
        fi

        if pgy_set_manual_lock_state "$u" locked; then
            if declare -F pgy_openvpn_kill_user >/dev/null 2>&1; then
                pgy_openvpn_kill_user "$u"
            fi
            killall -u "$u" -9 &>/dev/null
            current_state=$(pgy_account_lock_state "$u" 2>/dev/null || true)
            if [[ "$current_state" == "locked" ]]; then
                echo -e " [OK] ${C_YELLOW}$u${C_RESET} locked and active sessions killed."
            else
                echo -e " [ERROR] Lock command completed for ${C_YELLOW}$u${C_RESET}, but the resulting account state could not be verified."
            fi
        else
            echo -e " [ERROR] Failed to lock ${C_YELLOW}$u${C_RESET}."
        fi
    done
}

unlock_user() {
    _select_multi_user_interface "UNLOCK ACCOUNTS" "false" "locked"
    if [[ ${#SELECTED_USERS[@]} -eq 0 || "${SELECTED_USERS[0]}" == "NO_USERS" ]]; then return; fi
    
    echo -e "\n${C_BLUE}Unlocking selected users...${C_RESET}"
    for u in "${SELECTED_USERS[@]}"; do
        if ! id "$u" &>/dev/null; then
             echo -e " [ERROR] User '${C_YELLOW}$u${C_RESET}' does not exist on this system."
             continue
        fi

        local current_state
        current_state=$(pgy_account_lock_state "$u" 2>/dev/null || true)
        if [[ "$current_state" == "unlocked" ]]; then
            echo -e " [SKIP] ${C_YELLOW}$u${C_RESET} is already unlocked."
            continue
        fi
        if [[ "$current_state" != "locked" ]]; then
            echo -e " [ERROR] Could not verify the current lock state for ${C_YELLOW}$u${C_RESET}."
            continue
        fi

        if pgy_set_manual_lock_state "$u" unlocked; then
            current_state=$(pgy_account_lock_state "$u" 2>/dev/null || true)
            if [[ "$current_state" == "unlocked" ]]; then
                echo -e " [OK] ${C_YELLOW}$u${C_RESET} unlocked."
            else
                echo -e " [ERROR] Unlock command completed for ${C_YELLOW}$u${C_RESET}, but the resulting account state could not be verified."
            fi
        else
            echo -e " [ERROR] Failed to unlock ${C_YELLOW}$u${C_RESET}."
        fi
    done
}

list_users_view() {
    local view_filter="$1" view_title="$2"
    local -A system_user_lookup=()
    local user_count=0 session_count=0 active_count=0 pending_count=0 attention_count=0
    local first_account=true

    clear; show_banner
    while IFS=: read -r system_user _rest; do
        [[ -n "$system_user" ]] && system_user_lookup["$system_user"]=1
    done < /etc/passwd
    SSH_SESSION_CACHE_TS=0
    refresh_ssh_session_cache

    echo
    pgy_box_top
    pgy_box_header "$view_title"
    pgy_box_divider

    while IFS=: read -r user _password expiry limit bandwidth_gb account_type metadata_value _rest; do
        [[ -n "$user" && "$user" != \#* ]] || continue
        local reason online_count manual_locked=false
        reason=$(pgy_user_policy_reason "$user" 2>/dev/null || true)
        online_count="${SSH_SESSION_COUNTS[$user]:-0}"
        [[ "$online_count" =~ ^[0-9]+$ ]] || online_count=0
        pgy_user_is_manually_locked "$user" && manual_locked=true

        case "$view_filter" in
            all) ;;
            expired) [[ "$reason" == "expired" ]] || continue ;;
            quota) [[ "$reason" == "quota" ]] || continue ;;
            online) (( online_count > 0 )) || continue ;;
            *) continue ;;
        esac

        user_count=$((user_count + 1))
        session_count=$((session_count + online_count))
        local connection_string="$online_count/${limit:-1}"
        local plain_status="ACTIVE" status_color="$C_GREEN"
        local pending_activation=false used_bytes=0 data_display
        local expiry_display expiry_check=0 time_left="Unknown"
        local account_number display_user

        [[ "$bandwidth_gb" =~ ^[0-9]+([.][0-9]+)?$ ]] || bandwidth_gb=0
        if [[ -f "$BANDWIDTH_DIR/${user}.usage" ]]; then
            read -r used_bytes < "$BANDWIDTH_DIR/${user}.usage" || used_bytes=0
            [[ "$used_bytes" =~ ^[0-9]+$ ]] || used_bytes=0
        fi
        data_display=$(pgy_format_bandwidth_usage "$used_bytes" "$bandwidth_gb")

        if [[ "$account_type" == "pending" && "$metadata_value" =~ ^[1-9][0-9]*$ ]]; then
            pending_activation=true
            expiry_display="First use"
            time_left="${metadata_value}d after use"
        elif [[ "$account_type" == "trial" && "$metadata_value" =~ ^[0-9]+$ ]] &&
             (( metadata_value > 0 )); then
            expiry_display=$(pgy_format_epoch_datetime_display "$metadata_value")
            expiry_check=$metadata_value
        elif [[ -n "$expiry" && "$expiry" != "Never" ]]; then
            expiry_display=$(pgy_format_date_display "$expiry")
            expiry_check=$(date -d "$expiry 23:59:59" +%s 2>/dev/null || echo 0)
        else
            expiry_display="${expiry:-Unknown}"
        fi
        if $pending_activation; then
            :
        elif [[ "$expiry" == "Never" || -z "$expiry" ]]; then
            time_left="Never"
        elif [[ "$expiry_check" =~ ^[0-9]+$ ]] && (( expiry_check > 0 )); then
            time_left=$(format_trial_time_left "$expiry_check")
        fi

        if [[ -z "${system_user_lookup[$user]+x}" ]]; then
            plain_status="MISSING"
            status_color="$C_RED"
        else
            case "$reason" in
                expired) plain_status="EXPIRED"; status_color="$C_RED" ;;
                quota) plain_status="QUOTA ENDED"; status_color="$C_RED" ;;
                manual_lock) plain_status="MANUAL LOCK"; status_color="$C_YELLOW" ;;
                pending) plain_status="PENDING"; status_color="$C_CYAN" ;;
                active) plain_status="ACTIVE"; status_color="$C_GREEN" ;;
                *) plain_status="POLICY ERROR"; status_color="$C_RED" ;;
            esac
            if $manual_locked && [[ "$reason" != "manual_lock" ]]; then
                case "$plain_status" in
                    EXPIRED) plain_status="EXPIRED+LOCK" ;;
                    "QUOTA ENDED") plain_status="QUOTA+LOCK" ;;
                esac
            fi
        fi

        if [[ -z "${system_user_lookup[$user]+x}" ]]; then
            attention_count=$((attention_count + 1))
        else
            case "$reason" in
                active) active_count=$((active_count + 1)) ;;
                pending) pending_count=$((pending_count + 1)) ;;
                *) attention_count=$((attention_count + 1)) ;;
            esac
        fi
        if [[ "$first_account" != true ]]; then
            pgy_box_divider
        fi
        first_account=false

        printf -v account_number "%02d" "$user_count"
        display_user="$user"
        (( ${#display_user} > 22 )) && display_user="${display_user:0:19}..."
        expiry_display=$(_pgy_fit "$expiry_display" 20)
        time_left=$(_pgy_fit "$time_left" 20)
        connection_string=$(_pgy_fit "$connection_string" 20)
        data_display=$(_pgy_fit "$data_display" 20)

        pgy_row2 "${C_CHOICE}[${account_number}]${C_RESET} ${C_BOLD}${C_WHITE}${display_user}${C_RESET}" \
            "${status_color}${C_BOLD}[ ${plain_status} ]${C_RESET}"
        pgy_kv2 "EXPIRES" "$expiry_display" "LEFT" "$time_left"
        pgy_kv2 "CONNS" "$connection_string" "DATA" "$data_display"
    done < <(sort "$DB_FILE")

    if (( user_count == 0 )); then
        case "$view_filter" in
            expired) pgy_row "${C_GREEN}[OK] No expired users found.${C_RESET}" ;;
            quota) pgy_row "${C_GREEN}[OK] No users have exhausted their quota.${C_RESET}" ;;
            online)
                pgy_row "${C_YELLOW}[INFO] No managed users are online now.${C_RESET}"
                pgy_box_divider
                pgy_row2 "${C_GRAY}TOTAL:${C_RESET} ${C_BOLD}${C_WHITE}0${C_RESET}" \
                    "${C_GRAY}SESSIONS:${C_RESET} ${C_BOLD}${C_WHITE}0${C_RESET}"
                ;;
            *) pgy_row "${C_YELLOW}[INFO] No users are currently being managed.${C_RESET}" ;;
        esac
        pgy_box_bot
        return
    fi

    pgy_box_divider
    if [[ "$view_filter" == "online" ]]; then
        pgy_row2 "${C_GRAY}TOTAL:${C_RESET} ${C_BOLD}${C_WHITE}${user_count}${C_RESET}" \
            "${C_GRAY}SESSIONS:${C_RESET} ${C_BOLD}${C_WHITE}${session_count}${C_RESET}"
    elif [[ "$view_filter" == "expired" || "$view_filter" == "quota" ]]; then
        pgy_row2 "${C_GRAY}TOTAL:${C_RESET} ${C_BOLD}${C_WHITE}${user_count}${C_RESET}" ""
    else
        pgy_row2 "${C_GRAY}TOTAL:${C_RESET} ${C_BOLD}${C_WHITE}${user_count}${C_RESET}" \
            "${C_GREEN}ACTIVE ${active_count}${C_RESET} ${C_GRAY}/${C_RESET} ${C_CYAN}PENDING ${pending_count}${C_RESET}"
        (( attention_count > 0 )) && pgy_row2 "" "${C_YELLOW}ATTENTION ${attention_count}${C_RESET}"
    fi
    pgy_box_bot
}

list_users() {
    while true; do
        clear; show_banner
        echo
        pgy_box_top
        pgy_box_header "LIST USERS"
        pgy_box_divider
        pgy_menu1 "[ 1]" "All Managed Users"
        pgy_menu1 "[ 2]" "Expired Users"
        pgy_menu1 "[ 3]" "Quota Ended Users"
        pgy_menu1 "[ 4]" "Online Users"
        pgy_box_divider
        pgy_menu1 "[ 0]" "Return"
        pgy_box_bot
        echo
        local list_choice
        read -r -p "$(echo -e "${C_PROMPT}  Select a list: ${C_RESET}")" list_choice || return
        case "$list_choice" in
            1) list_users_view all "ALL MANAGED USERS"; return ;;
            2) list_users_view expired "EXPIRED USERS"; return ;;
            3) list_users_view quota "QUOTA ENDED USERS"; return ;;
            4) list_users_view online "ONLINE USERS"; return ;;
            0) return ;;
            *) echo -e "\n${C_RED}[ERROR] Invalid option.${C_RESET}"; sleep 1 ;;
        esac
    done
}

renew_user() {
    _select_multi_user_interface "RENEW ACCOUNTS"
    if [[ ${#SELECTED_USERS[@]} -eq 0 || "${SELECTED_USERS[0]}" == "NO_USERS" ]]; then return; fi
    read -p "  Enter number of days to extend the account(s): " days; if ! [[ "$days" =~ ^[1-9][0-9]*$ ]]; then echo -e "\n${C_RED}[ERROR] Days must be at least 1.${C_RESET}"; return; fi
    local new_expire_date; new_expire_date=$(date -d "+$days days" +%Y-%m-%d)
    
    echo -e "\n${C_BLUE}Renewing selected users for $days days...${C_RESET}"
    for u in "${SELECTED_USERS[@]}"; do
        local line record_user pass expiry limit bw account_type metadata_value metadata_rest
        line=$(grep "^$u:" "$DB_FILE")
        IFS=: read -r record_user pass expiry limit bw account_type metadata_value metadata_rest <<< "$line"
        [[ -z "$bw" ]] && bw="0"
        if [[ "$account_type" == "pending" && "$metadata_value" =~ ^[1-9][0-9]*$ ]]; then
            local extended_pending_days=$((metadata_value + days))
            chage -E -1 "$u"
            sed -i "s/^$u:.*/$u:$pass:Never:$limit:$bw:pending:$extended_pending_days/" "$DB_FILE"
            echo -e " [OK] ${C_YELLOW}$u${C_RESET} will remain valid for ${C_GREEN}${extended_pending_days} days${C_RESET} after first use."
        else
            local metadata_suffix=""
            [[ -n "$account_type" ]] && metadata_suffix=":$account_type"
            [[ -n "$metadata_value" ]] && metadata_suffix+=":$metadata_value"
            [[ -n "$metadata_rest" ]] && metadata_suffix+=":$metadata_rest"
            chage -E "$new_expire_date" "$u"
            sed -i "s/^$u:.*/$u:$pass:$new_expire_date:$limit:$bw$metadata_suffix/" "$DB_FILE"
            echo -e " [OK] ${C_YELLOW}$u${C_RESET} renewed until ${C_GREEN}$(pgy_format_date_display "$new_expire_date")${C_RESET}."
        fi
    done
}

cleanup_expired() {
    clear; show_banner
    pgy_screen_title "CLEANUP EXPIRED USERS" "Find and remove accounts whose expiry date has passed."
    
    local expired_users=()
    local current_ts
    current_ts=$(date +%s)

    if [[ ! -s "$DB_FILE" ]]; then
        echo -e "\n${C_GREEN}[OK] User database is empty. No expired users found.${C_RESET}"
        return
    fi
    
    while IFS=: read -r user pass expiry limit bandwidth_gb _extra; do
        local expiry_ts
        expiry_ts=$(date -d "$expiry 23:59:59" +%s 2>/dev/null || echo 0)
        
        if [[ $expiry_ts -lt $current_ts && $expiry_ts -ne 0 ]]; then
            expired_users+=("$user")
        fi
    done < "$DB_FILE"

    if [ ${#expired_users[@]} -eq 0 ]; then
        echo -e "\n${C_GREEN}[OK] No expired users found.${C_RESET}"
        return
    fi

    echo -e "\nThe following users have expired: ${C_RED}${expired_users[*]}${C_RESET}"
    read -p "  Do you want to delete all of them? (y/n): " confirm

    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        for user in "${expired_users[@]}"; do
            echo -e "  ${C_GRAY}•${C_RESET} Deleting ${C_YELLOW}$user${C_RESET}..."
            if declare -F pgy_openvpn_kill_user >/dev/null 2>&1; then
                pgy_openvpn_kill_user "$user"
            fi
            killall -u "$user" -9 &>/dev/null
            # Clean up bandwidth tracking
            rm -f "$BANDWIDTH_DIR/${user}.usage"
            rm -rf "$BANDWIDTH_DIR/pidtrack/${user}"
            userdel -r "$user" &>/dev/null
            sed -i "/^$user:/d" "$DB_FILE"
            rm -f "$DB_DIR/banners/${user}.txt" 2>/dev/null
            pgy_set_manual_lock_state "$user" unlocked >/dev/null 2>&1 || true
        done
        echo -e "\n${C_GREEN}[OK] Expired users have been cleaned up.${C_RESET}"
        invalidate_banner_cache
        refresh_dynamic_banner_routing_if_enabled
    else
        pgy_message CANCELLED "Cleanup cancelled."
    fi
}



ensure_trial_scheduler() {
    pgy_apt_install at >/dev/null 2>&1 || return 1
    systemctl enable atd >/dev/null 2>&1 || return 1
    systemctl start atd >/dev/null 2>&1 || return 1
    systemctl is-active --quiet atd
}

create_trial_account() {
    clear; show_banner

    if ! command -v at &>/dev/null; then
        echo
        pgy_section "PREPARATION"
        if ! pgy_progress_run 1 1 "Preparing scheduling service" ensure_trial_scheduler; then
            pgy_message ERROR "The trial scheduling service could not be prepared."
            return
        fi
    fi

    if ! systemctl is-active --quiet atd; then
        systemctl start atd >/dev/null 2>&1 || {
            pgy_message ERROR "The trial scheduling service could not be started."
            return
        }
    fi
    
    echo
    pgy_box_top
    pgy_box_header "CREATE TRIAL"
    pgy_box_divider
    pgy_menu1 "[ 1]" "1 Hour"
    pgy_menu1 "[ 2]" "2 Hours"
    pgy_menu1 "[ 3]" "3 Hours"
    pgy_menu1 "[ 4]" "6 Hours"
    pgy_menu1 "[ 5]" "12 Hours"
    pgy_menu1 "[ 6]" "1 Day"
    pgy_menu1 "[ 7]" "3 Days"
    pgy_menu1 "[ 8]" "Custom Duration (Hours)"
    pgy_box_divider
    pgy_menu1 "[ 0]" "Cancel"
    pgy_box_bot
    echo
    read -r -p "$(echo -e "${C_PROMPT}  Select a duration: ${C_RESET}")" dur_choice
    
    local duration_hours=0
    local duration_label="" banner_sync_ok=true
    case $dur_choice in
        1) duration_hours=1;   duration_label="1 Hour" ;;
        2) duration_hours=2;   duration_label="2 Hours" ;;
        3) duration_hours=3;   duration_label="3 Hours" ;;
        4) duration_hours=6;   duration_label="6 Hours" ;;
        5) duration_hours=12;  duration_label="12 Hours" ;;
        6) duration_hours=24;  duration_label="1 Day" ;;
        7) duration_hours=72;  duration_label="3 Days" ;;
        8) read -r -p "$(echo -e "${C_PROMPT}  Custom duration in hours: ${C_RESET}")" custom_hours
           if ! [[ "$custom_hours" =~ ^[0-9]+$ ]] || [[ "$custom_hours" -lt 1 ]]; then
               echo -e "\n${C_RED}[ERROR] Invalid number of hours.${C_RESET}"; return
           fi
           duration_hours=$custom_hours
           duration_label="$custom_hours Hours"
           ;;
        0) pgy_message CANCELLED "Trial creation cancelled."; return ;;
        *) echo -e "\n${C_RED}[ERROR] Invalid option.${C_RESET}"; return ;;
    esac
    
    # Username
    local rand_suffix=$(head /dev/urandom | tr -dc 'a-z0-9' | head -c 5)
    local default_username="trial_${rand_suffix}"
    read -r -p "$(echo -e "${C_PROMPT}  Username [${default_username}]: ${C_RESET}")" username
    username=${username:-$default_username}
    
    if id "$username" &>/dev/null || grep -q "^$username:" "$DB_FILE"; then
        echo -e "\n${C_RED}[ERROR] User '$username' already exists.${C_RESET}"; return
    fi
    
    # Password
    local password=$(head /dev/urandom | tr -dc 'A-Za-z0-9' | head -c 8)
    read -r -p "$(echo -e "${C_PROMPT}  Password [${password}]: ${C_RESET}")" custom_pass
    password=${custom_pass:-$password}
    
    # Connection limit
    read -r -p "$(echo -e "${C_PROMPT}  Connection limit [1]: ${C_RESET}")" limit
    limit=${limit:-1}
    if ! [[ "$limit" =~ ^[0-9]+$ ]]; then echo -e "\n${C_RED}[ERROR] Invalid number.${C_RESET}"; return; fi
    
    # Bandwidth limit
    read -r -p "$(echo -e "${C_PROMPT}  Bandwidth in GB (0 = unlimited) [0]: ${C_RESET}")" bandwidth_gb
    bandwidth_gb=${bandwidth_gb:-0}
    if ! [[ "$bandwidth_gb" =~ ^[0-9]+\.?[0-9]*$ ]]; then echo -e "\n${C_RED}[ERROR] Invalid number.${C_RESET}"; return; fi
    
    # Calculate expiry
    local expire_date
    if [[ "$duration_hours" -ge 24 ]]; then
        local days=$((duration_hours / 24))
        expire_date=$(date -d "+$days days" +%Y-%m-%d)
    else
        # For sub-day durations, set expiry to tomorrow to be safe (at job does the real cleanup)
        expire_date=$(date -d "+1 day" +%Y-%m-%d)
    fi
    local expiry_epoch expiry_timestamp
    expiry_epoch=$(date -d "+${duration_hours} hours" +%s)
    expiry_timestamp=$(pgy_format_epoch_datetime_display "$expiry_epoch")
    
    # Create the system user
    ensure_pgytunnel_system_group
    if ! pgy_set_manual_lock_state "$username" unlocked; then
        echo -e "\n${C_RED}[ERROR] Could not prepare a clean account policy for '$username'.${C_RESET}"
        return
    fi
    useradd -m -s /usr/sbin/nologin "$username"
    usermod -aG "$PGY_USERS_GROUP" "$username" 2>/dev/null
    echo "$username:$password" | chpasswd
    chage -E "$expire_date" "$username"
    echo "$username:$password:$expire_date:$limit:$bandwidth_gb:trial:$expiry_epoch" >> "$DB_FILE"
    provision_dynamic_banners_for_new_users "$username" || banner_sync_ok=false
    
    # Schedule by UID + immutable expiry token so changing the username later
    # does not detach the automatic cleanup job. The token prevents UID-reuse
    # from ever deleting a different account.
    local trial_uid
    trial_uid=$(id -u "$username")
    echo "$TRIAL_CLEANUP_SCRIPT --uid $trial_uid $expiry_epoch" | at now + ${duration_hours} hours 2>/dev/null
    
    local bw_display
    bw_display=$(pgy_format_quota_gb "$bandwidth_gb")
    
    clear; show_banner
    pgy_message OK "Trial account created successfully."
    echo
    pgy_section "TRIAL ACCOUNT DETAILS"
    pgy_detail "Username" "$username" "$C_YELLOW"
    pgy_detail "Password" "$password" "$C_YELLOW"
    pgy_detail "Duration" "$duration_label"
    pgy_detail "Auto Expires" "$expiry_timestamp" "$C_RED"
    pgy_detail "Connections" "$limit"
    pgy_detail "Bandwidth" "$bw_display"
    echo -e "  ${C_DIM}This account is removed automatically when its trial expires.${C_RESET}"
    if [[ "$banner_sync_ok" != true ]]; then
        echo -e "  ${C_YELLOW}[WARNING] Trial created, but dynamic banner routing is still waiting for the worker.${C_RESET}"
    fi
    
    # Auto-ask for config generation
    echo
    read -r -p "$(echo -e "${C_PROMPT}  Generate client configuration now? [y/N]: ${C_RESET}")" gen_conf
    if [[ "$gen_conf" == "y" || "$gen_conf" == "Y" ]]; then
        generate_client_config "$username" "$password"
    fi
}

format_trial_time_left() {
    local expiry_epoch="$1" now remaining days hours minutes
    if ! [[ "$expiry_epoch" =~ ^[0-9]+$ ]] || (( expiry_epoch <= 0 )); then
        printf "Unknown"
        return
    fi

    now=$(date +%s)
    remaining=$((expiry_epoch - now))
    if (( remaining <= 0 )); then
        printf "Expired"
    elif (( remaining >= 86400 )); then
        days=$((remaining / 86400))
        hours=$(((remaining % 86400) / 3600))
        printf "%dd %dh" "$days" "$hours"
    elif (( remaining >= 3600 )); then
        hours=$((remaining / 3600))
        minutes=$(((remaining % 3600) / 60))
        printf "%dh %dm" "$hours" "$minutes"
    else
        minutes=$((remaining / 60))
        (( minutes < 1 )) && minutes=1
        printf "%dm" "$minutes"
    fi
}

list_trial_accounts() {
    clear; show_banner
    local trial_total=0
    if [[ -s "$DB_FILE" ]]; then
        trial_total=$(awk -F: '$6 == "trial" { count++ } END { print count + 0 }' "$DB_FILE")
    fi

    echo
    pgy_box_top
    pgy_box_header "TRIAL ACCOUNTS"
    pgy_box_divider

    if (( trial_total == 0 )); then
        pgy_row "${C_YELLOW}[INFO] No trial accounts found.${C_RESET}"
        pgy_box_bot
        return
    fi

    refresh_ssh_session_cache
    local now trial_count=0 first_account=true
    now=$(date +%s)

    while IFS=: read -r user _password expiry limit bandwidth_gb account_type trial_expiry_epoch _rest; do
        [[ "$account_type" == "trial" ]] || continue
        trial_count=$((trial_count + 1))

        local expiry_display time_left online_count connection_string
        local used_bytes=0 bandwidth_display status status_color
        local expiry_check=0 policy_reason account_number display_user

        online_count="${SSH_SESSION_COUNTS[$user]:-0}"
        connection_string="${online_count}/${limit:-1}"

        if [[ "$trial_expiry_epoch" =~ ^[0-9]+$ ]] && (( trial_expiry_epoch > 0 )); then
            expiry_display=$(pgy_format_epoch_datetime_display "$trial_expiry_epoch")
            time_left=$(format_trial_time_left "$trial_expiry_epoch")
            expiry_check=$trial_expiry_epoch
        else
            expiry_display=$(pgy_format_date_display "$expiry")
            time_left="Unknown"
            expiry_check=$(date -d "$expiry 23:59:59" +%s 2>/dev/null || echo 0)
        fi

        if [[ -f "$BANDWIDTH_DIR/${user}.usage" ]]; then
            read -r used_bytes < "$BANDWIDTH_DIR/${user}.usage" || used_bytes=0
            [[ "$used_bytes" =~ ^[0-9]+$ ]] || used_bytes=0
        fi
        bandwidth_display=$(pgy_format_bandwidth_usage "$used_bytes" "$bandwidth_gb")

        policy_reason=$(pgy_user_policy_reason "$user" 2>/dev/null || true)
        if ! id "$user" >/dev/null 2>&1; then
            status="MISSING"
            status_color="$C_RED"
        elif (( expiry_check > 0 && expiry_check <= now )); then
            status="EXPIRED"
            status_color="$C_RED"
        elif [[ "$policy_reason" == "quota" ]]; then
            status="QUOTA ENDED"
            status_color="$C_RED"
        elif [[ "$policy_reason" == "manual_lock" ]]; then
            status="MANUAL LOCK"
            status_color="$C_YELLOW"
        else
            status="ACTIVE"
            status_color="$C_GREEN"
        fi

        if [[ "$first_account" != true ]]; then
            pgy_box_divider
        fi
        first_account=false

        printf -v account_number "%02d" "$trial_count"
        display_user="$user"
        if (( ${#display_user} > 22 )); then
            display_user="${display_user:0:19}..."
        fi
        pgy_row2 "${C_CHOICE}[${account_number}]${C_RESET} ${C_BOLD}${C_WHITE}${display_user}${C_RESET}" \
            "${status_color}● ${C_BOLD}${status}${C_RESET}"
        pgy_kv2 "EXPIRES" "$expiry_display" "LEFT" "$time_left"
        pgy_kv2 "CONNS" "$connection_string" "DATA" "$bandwidth_display"
    done < <(sort "$DB_FILE")

    pgy_box_divider
    pgy_row2 "${C_GRAY}TOTAL${C_RESET} ${C_BOLD}${C_WHITE}${trial_count}${C_RESET}" \
        "${C_GREEN}● ${C_BOLD}AUTO-CLEANUP${C_RESET}"
    pgy_box_bot
}

view_user_bandwidth() {
    _select_user_interface "VIEW USER BANDWIDTH"
    local u=$SELECTED_USER
    if [[ "$u" == "NO_USERS" || -z "$u" ]]; then return; fi
    
    clear; show_banner
    pgy_screen_title "BANDWIDTH USAGE" "Account: $u"
    
    local line; line=$(grep "^$u:" "$DB_FILE")
    local bandwidth_gb; bandwidth_gb=$(echo "$line" | cut -d: -f5)
    [[ -z "$bandwidth_gb" ]] && bandwidth_gb="0"
    
    local used_bytes=0
    if [[ -f "$BANDWIDTH_DIR/${u}.usage" ]]; then
        used_bytes=$(cat "$BANDWIDTH_DIR/${u}.usage" 2>/dev/null)
        [[ -z "$used_bytes" ]] && used_bytes=0
    fi
    
    [[ "$used_bytes" =~ ^[0-9]+$ ]] || used_bytes=0
    local used_display
    used_display=$(pgy_format_used_bytes "$used_bytes")
    
    pgy_section "USAGE SUMMARY"
    pgy_detail "Data Used" "$used_display"
    
    if pgy_quota_is_unlimited "$bandwidth_gb"; then
        pgy_detail "Bandwidth Limit" "Unlimited" "$C_GREEN"
        pgy_detail "Status" "No quota restriction" "$C_GREEN"
    else
        local quota_bytes; quota_bytes=$(awk "BEGIN {printf \"%.0f\", $bandwidth_gb * 1073741824}")
        local percentage; percentage=$(awk "BEGIN {printf \"%.1f\", ($used_bytes / $quota_bytes) * 100}")
        local remaining_bytes; remaining_bytes=$((quota_bytes - used_bytes))
        if [[ "$remaining_bytes" -lt 0 ]]; then remaining_bytes=0; fi
        local remaining_display quota_display
        remaining_display=$(pgy_format_used_bytes "$remaining_bytes")
        quota_display=$(pgy_format_quota_gb "$bandwidth_gb")
        
        pgy_detail "Bandwidth Limit" "$quota_display" "$C_YELLOW"
        pgy_detail "Remaining" "$remaining_display"
        pgy_detail "Usage" "${percentage}%"
        
        # Progress bar
        local bar_width=30
        local filled; filled=$(awk "BEGIN {printf \"%.0f\", ($percentage / 100) * $bar_width}")
        if [[ "$filled" -gt "$bar_width" ]]; then filled=$bar_width; fi
        local empty=$((bar_width - filled))
        local bar_color="$C_GREEN"
        if (( $(awk "BEGIN {print ($percentage > 80)}" ) )); then bar_color="$C_RED"
        elif (( $(awk "BEGIN {print ($percentage > 50)}" ) )); then bar_color="$C_YELLOW"
        fi
        printf "  ${C_GRAY}• %-19s${C_RESET} ${bar_color}[" "Progress:"
        for ((i=0; i<filled; i++)); do printf "█"; done
        for ((i=0; i<empty; i++)); do printf "░"; done
        printf "]${C_RESET} ${percentage}%%\n"
        
        if [[ "$used_bytes" -ge "$quota_bytes" ]]; then
            pgy_message WARNING "Bandwidth quota ended; new connections are denied until top-up or reset."
        fi
    fi
}

bulk_create_users() {
    clear; show_banner
    pgy_screen_title "BULK CREATE USERS" "Create up to 100 managed accounts with shared limits."
    
    read -p "  Enter username prefix (e.g., 'user'): " prefix
    if [[ -z "$prefix" ]]; then echo -e "\n${C_RED}[ERROR] Prefix cannot be empty.${C_RESET}"; return; fi
    
    read -p "  How many users to create? " count
    if ! [[ "$count" =~ ^[0-9]+$ ]] || [[ "$count" -lt 1 ]] || [[ "$count" -gt 100 ]]; then
        echo -e "\n${C_RED}[ERROR] Invalid count (1-100).${C_RESET}"; return
    fi
    
    local first_use_activation=false first_use_choice validity_prompt
    read -r -p "  Start After First Use? [y/N]: " first_use_choice
    [[ "$first_use_choice" == "y" || "$first_use_choice" == "Y" ]] && first_use_activation=true
    if $first_use_activation; then
        validity_prompt="Validity after first use (days) [30]"
    else
        validity_prompt="Validity from today (days) [30]"
    fi
    read -r -p "  ${validity_prompt}: " days
    days=${days:-30}
    if ! [[ "$days" =~ ^[1-9][0-9]*$ ]]; then echo -e "\n${C_RED}[ERROR] Validity must be at least 1 day.${C_RESET}"; return; fi
    
    read -p "  Connection limit per user [1]: " limit
    limit=${limit:-1}
    if ! [[ "$limit" =~ ^[0-9]+$ ]]; then echo -e "\n${C_RED}[ERROR] Invalid number.${C_RESET}"; return; fi
    
    read -p "  Bandwidth limit in GB per user (0 = unlimited) [0]: " bandwidth_gb
    bandwidth_gb=${bandwidth_gb:-0}
    if ! [[ "$bandwidth_gb" =~ ^[0-9]+\.?[0-9]*$ ]]; then echo -e "\n${C_RED}[ERROR] Invalid number.${C_RESET}"; return; fi

    local expire_date stored_expiry metadata_suffix="" table_expiry activation_display="Immediately"
    expire_date=$(date -d "+$days days" +%Y-%m-%d)
    stored_expiry="$expire_date"
    table_expiry=$(pgy_format_date_display "$expire_date")
    if $first_use_activation; then
        stored_expiry="Never"
        metadata_suffix=":pending:${days}"
        table_expiry="FIRST USE"
        activation_display="After First Use"
    fi
    local bw_display
    bw_display=$(pgy_format_quota_gb "$bandwidth_gb")
    ensure_pgytunnel_system_group
    
    echo
    pgy_section "CREATED ACCOUNTS"
    printf "${C_BOLD}${C_WHITE}%-20s | %-15s | %-12s${C_RESET}\n" "USERNAME" "PASSWORD" "EXPIRES"
    echo -e "${C_GRAY}─────────────────────┼─────────────────┼─────────────${C_RESET}"
    
    local created=0 banner_sync_ok=true
    local -a created_usernames=()
    for ((i=1; i<=count; i++)); do
        local username="${prefix}${i}"
        if id "$username" &>/dev/null || grep -q "^$username:" "$DB_FILE"; then
            echo -e "${C_RED}  [WARNING] Skipping '$username' — already exists${C_RESET}"
            continue
        fi
        if ! pgy_set_manual_lock_state "$username" unlocked; then
            echo -e "${C_RED}  [WARNING] Skipping '$username' — policy store unavailable${C_RESET}"
            continue
        fi
        local password=$(head /dev/urandom | tr -dc 'A-Za-z0-9' | head -c 8)
        useradd -m -s /usr/sbin/nologin "$username"
        usermod -aG "$PGY_USERS_GROUP" "$username" 2>/dev/null
        echo "$username:$password" | chpasswd
        if $first_use_activation; then
            chage -E -1 "$username"
        else
            chage -E "$expire_date" "$username"
        fi
        echo "$username:$password:$stored_expiry:$limit:$bandwidth_gb$metadata_suffix" >> "$DB_FILE"
        printf "  ${C_GREEN}%-20s${C_RESET} | ${C_YELLOW}%-15s${C_RESET} | ${C_CYAN}%-12s${C_RESET}\n" "$username" "$password" "$table_expiry"
        created=$((created + 1))
        created_usernames+=("$username")
    done

    if (( created > 0 )); then
        provision_dynamic_banners_for_new_users "${created_usernames[@]}" || banner_sync_ok=false
    fi
    pgy_message OK "Created $created account(s). Connections: ${limit}; bandwidth: ${bw_display}; expiry starts: ${activation_display}."
    if [[ "$banner_sync_ok" != true ]]; then
        echo -e "  ${C_YELLOW}[WARNING] Accounts created, but dynamic banner routing is still waiting for the worker.${C_RESET}"
    fi
}

generate_client_config() {
    local user=$1
    local pass=$2

    local host_ip
    host_ip=$(curl -fsS -4 --max-time 5 icanhazip.com 2>/dev/null | tr -d '[:space:]')
    if [[ -z "$host_ip" ]]; then
        host_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    fi
    [[ -z "$host_ip" ]] && host_ip="Not detected"
    local host_domain
    host_domain=$(detect_preferred_host)
    [[ -z "$host_domain" ]] && host_domain="$host_ip"

    clear; show_banner
    echo
    pgy_section "CLIENT CONNECTION CONFIGURATION"
    pgy_row "${C_GRAY}Copy the required values for your client application.${C_RESET}"
    pgy_box_bot

    echo
    pgy_section "ACCOUNT"
    pgy_detail "Username" "$user" "$C_YELLOW"
    pgy_detail "Password" "$pass" "$C_YELLOW"
    pgy_detail "Host / IP" "$host_domain" "$C_WHITE"
    pgy_box_bot

    # 1. SSH Direct
    echo
    pgy_section "SSH DIRECT"
    pgy_detail "Host" "$host_domain" "$C_WHITE"
    pgy_detail "Port" "22" "$C_YELLOW"
    pgy_detail "Payload" "Standard SSH" "$C_WHITE"
    pgy_box_bot

    # 2. HAProxy edge stack
    if systemctl is-active --quiet haproxy; then
        echo
        pgy_section "HAPROXY EDGE STACK"
        pgy_detail "Host" "$host_domain" "$C_WHITE"
        pgy_detail "HTTP / Raw SSH" "$EDGE_PUBLIC_HTTP_PORT" "$C_YELLOW"
        pgy_detail "TLS / SNI / SSL" "$EDGE_PUBLIC_TLS_PORT" "$C_YELLOW"
        pgy_detail "SNI / Bug Host" "$host_domain" "$C_WHITE"
        pgy_box_bot
    elif systemctl is-active --quiet nginx; then
        echo
        pgy_section "INTERNAL NGINX PROXY"
        pgy_detail "Public Edge" "HAProxy ${EDGE_PUBLIC_HTTP_PORT}/${EDGE_PUBLIC_TLS_PORT}" "$C_YELLOW"
        pgy_box_bot
    fi

    # 3. DNSTT
    if systemctl is-active --quiet dnstt; then
        if [ -f "$DNSTT_CONFIG_FILE" ]; then
            source "$DNSTT_CONFIG_FILE"
            echo
            pgy_section "DNSTT / SLOWDNS"
            pgy_detail "Nameserver" "$TUNNEL_DOMAIN" "$C_YELLOW"
            if [[ -n "$PUBLIC_KEY" ]]; then
                pgy_detail "Public Key" "$PUBLIC_KEY" "$C_CYAN"
            fi
            pgy_detail "DNS Resolver" "1.1.1.1 / 8.8.8.8" "$C_WHITE"
            pgy_box_bot
        fi
    fi

    # 4. ZiVPN
    if systemctl is-active --quiet zivpn; then
        echo
        pgy_section "ZIVPN (UDP)"
        pgy_detail "UDP Port" "5667" "$C_YELLOW"
        pgy_detail "Forwarded Ports" "6000-19999" "$C_YELLOW"
        pgy_box_bot
    fi

    # 5. Optional OpenVPN suite — profiles use the same PGY credentials.
    if declare -F pgy_openvpn_append_client_details >/dev/null 2>&1; then
        pgy_openvpn_append_client_details
    fi
}

client_config_menu() {
    _select_user_interface "CLIENT CONFIG"
    local u=$SELECTED_USER
    if [[ "$u" == "NO_USERS" || -z "$u" ]]; then return; fi
    
    # We need to find the password. It's in the DB.
    local pass=$(grep "^$u:" "$DB_FILE" | cut -d: -f2)
    generate_client_config "$u" "$pass"
    press_enter
}

