#!/bin/bash
# ============================================================
# Auto Script SSH By : ProgoCloud
# Module: features/backup.sh - Data backup, restore & Telegram bot
# ============================================================

create_user_backup_archive() {
    local backup_path="$1"
    if [ ! -d "$DB_DIR" ] || [ ! -s "$DB_FILE" ]; then
        return 2
    fi
    local temp_dir backup_root locks_file manual_locks_file
    temp_dir=$(mktemp -d)
    backup_root="$temp_dir/pgy-user-data"
    locks_file="$backup_root/locks.db"
    manual_locks_file="$backup_root/manual-locks.db"

    mkdir -p "$(dirname "$backup_path")" "$backup_root/bandwidth"
    cp "$DB_FILE" "$backup_root/users.db"

    if [ -d "$BANDWIDTH_DIR" ]; then
        cp "$BANDWIDTH_DIR"/*.usage "$backup_root/bandwidth/" 2>/dev/null || true
    fi

    if [[ -f "$MANUAL_LOCK_FILE" && ! -L "$MANUAL_LOCK_FILE" ]]; then
        cp "$MANUAL_LOCK_FILE" "$manual_locks_file"
    else
        : > "$manual_locks_file"
    fi
    chmod 600 "$manual_locks_file" 2>/dev/null || true

    # Keep locks.db for older restore implementations, but derive it from the
    # explicit operator policy rather than conflated Linux shadow state.
    : > "$locks_file"
    while IFS=: read -r user _pass _expiry _limit _bandwidth_gb _extra; do
        [[ -z "$user" || "$user" == \#* ]] && continue
        local passwd_status="missing"
        if id "$user" &>/dev/null; then
            if pgy_user_is_manually_locked "$user"; then
                passwd_status="locked"
            else
                passwd_status="unlocked"
            fi
        fi
        printf '%s:%s\n' "$user" "$passwd_status" >> "$locks_file"
    done < "$DB_FILE"

    cat > "$backup_root/meta.txt" <<EOF
format=pgy-user-data
version=2
created_at=$(date '+%Y-%m-%d %H:%M:%S %z')
EOF

    tar -czf "$backup_path" -C "$temp_dir" "pgy-user-data"
    local rc=$?
    rm -rf "$temp_dir"
    return "$rc"
}

backup_user_data() {
    clear; show_banner
    pgy_screen_title "BACKUP USER DATA" "Create a portable archive of accounts and usage data."
    read -p "  Enter path for backup file [/root/pgytunnel_users.tar.gz]: " backup_path
    backup_path=${backup_path:-/root/pgytunnel_users.tar.gz}
    create_user_backup_archive "$backup_path"
    local rc=$?
    if [ "$rc" -ne 0 ]; then
        if [ "$rc" -eq 2 ]; then
            echo -e "\n${C_YELLOW}[INFO] No user data found to back up.${C_RESET}"
        else
            echo -e "\n${C_RED}[ERROR] Backup failed.${C_RESET}"
        fi
        return
    fi
    echo -e "\n${C_GREEN}[OK] User data backup created at ${C_YELLOW}$backup_path${C_RESET}"
}

restore_user_data() {
    clear; show_banner
    pgy_screen_title "RESTORE USER DATA" "Restore accounts, limits, expiry dates, and usage data."
    read -p "  Enter the full path to the user data backup file [/root/pgytunnel_users.tar.gz]: " backup_path
    backup_path=${backup_path:-/root/pgytunnel_users.tar.gz}
    if [ ! -f "$backup_path" ]; then
        echo -e "\n${C_RED}[ERROR] Backup file not found at '$backup_path'.${C_RESET}"
        return
    fi
    echo -e "\n${C_RED}${C_BOLD}[WARNING]${C_RESET} This will overwrite all current users and settings."
    echo -e "It will restore user accounts, passwords, limits, and expiration dates from the backup file."
    read -p "  Are you absolutely sure you want to proceed? (y/n): " confirm
    if [[ "$confirm" != "y" ]]; then pgy_message CANCELLED "Restore cancelled."; return; fi
    local temp_dir
    temp_dir=$(mktemp -d)
    echo -e "\n${C_BLUE}Extracting backup file to a temporary location...${C_RESET}"
    tar -xzf "$backup_path" -C "$temp_dir"
    if [ $? -ne 0 ]; then
        echo -e "\n${C_RED}[ERROR] Failed to extract backup file. Aborting.${C_RESET}"
        rm -rf "$temp_dir"
        return
    fi
    local restore_root="$temp_dir/pgy-user-data"
    if [ ! -f "$restore_root/users.db" ]; then
        # Backward compatibility: old full-folder backups are accepted, but only
        # user-related data is restored from them.
        restore_root="$temp_dir/pgytunnel"
    fi
    local restored_db_file="$restore_root/users.db"
    if [ ! -f "$restored_db_file" ]; then
        echo -e "\n${C_RED}[ERROR] users.db not found in the backup. Cannot restore user accounts.${C_RESET}"
        rm -rf "$temp_dir"
        return
    fi
    echo -e "${C_BLUE}Overwriting current user database and usage data...${C_RESET}"
    mkdir -p "$DB_DIR"
    cp "$restored_db_file" "$DB_FILE"
    mkdir -p "$BANDWIDTH_DIR"
    rm -f "$BANDWIDTH_DIR"/*.usage 2>/dev/null || true
    if [ -d "$restore_root/bandwidth" ]; then
        cp "$restore_root/bandwidth"/*.usage "$BANDWIDTH_DIR/" 2>/dev/null || true
    fi
    
    echo -e "${C_BLUE}Re-synchronizing system accounts with the restored database...${C_RESET}"
    ensure_pgytunnel_system_group
    
    while IFS=: read -r user pass expiry limit bandwidth_gb _extra; do
        echo -e "\n  ${C_GRAY}•${C_RESET} Account: ${C_YELLOW}$user${C_RESET}"
        if ! id "$user" &>/dev/null; then
            echo -e "    ${C_GRAY}System user:${C_RESET} Creating"
            useradd -m -s /usr/sbin/nologin "$user"
        else
            echo -e "    ${C_GRAY}System user:${C_RESET} Existing"
        fi
        usermod -aG "$PGY_USERS_GROUP" "$user" 2>/dev/null
        echo -e "    ${C_GRAY}Password:${C_RESET} Restored"
        echo "$user:$pass" | chpasswd
        echo -e "    ${C_GRAY}Expiration:${C_RESET} $(pgy_format_date_display "$expiry")"
        if [[ "$expiry" == "Never" || -z "$expiry" ]]; then
            chage -E -1 "$user"
        else
            chage -E "$expiry" "$user"
        fi
        echo -e "    ${C_GRAY}Connections:${C_RESET} ${limit} (account worker)"
    done < "$DB_FILE"

    echo -e "${C_BLUE}Restoring manual account lock policy...${C_RESET}"
    if ! pgy_restore_manual_lock_archive "$restore_root"; then
        rm -rf "$temp_dir"
        echo -e "\n${C_RED}[ERROR] Manual lock policy could not be restored safely.${C_RESET}"
        return
    fi
    rm -rf "$temp_dir"
    echo -e "\n${C_GREEN}[OK] User data restore completed.${C_RESET}"
    
    invalidate_banner_cache
    refresh_dynamic_banner_routing_if_enabled
}

auto_backup_load_conf() {
    if [ ! -f "$AUTO_BACKUP_CONF" ]; then
        return 1
    fi
    source "$AUTO_BACKUP_CONF" 2>/dev/null
    [[ -n "${BOT_TOKEN:-}" && -n "${CHAT_ID:-}" && -n "${INTERVAL_SECONDS:-}" ]] || return 1
    return 0
}

auto_backup_save_conf() {
    local bot_token="$1" chat_id="$2" interval_seconds="$3" interval_label="$4"
    printf 'BOT_TOKEN=%q\nCHAT_ID=%q\nINTERVAL_SECONDS=%q\nINTERVAL_LABEL=%q\n' \
        "$bot_token" "$chat_id" "$interval_seconds" "$interval_label" > "$AUTO_BACKUP_CONF"
    chmod 600 "$AUTO_BACKUP_CONF"
}

auto_backup_ensure_pm2() {
    if command -v pm2 &>/dev/null; then
        return 0
    fi
    pgy_apt_install nodejs npm >/dev/null 2>&1 || {
        return 1
    }
    npm install -g pm2 >/dev/null 2>&1 || {
        return 1
    }
    pm2 startup systemd -u root --hp /root >/dev/null 2>&1 || true
    return 0
}

auto_backup_start_runtime() {
    pm2 delete "$AUTO_BACKUP_PM2_NAME" >/dev/null 2>&1 || true
    pm2 start "$AUTO_BACKUP_SCRIPT" --name "$AUTO_BACKUP_PM2_NAME" >/dev/null 2>&1 || return 1
    pm2 save >/dev/null 2>&1 || return 1
    local service_pid
    service_pid=$(pm2 pid "$AUTO_BACKUP_PM2_NAME" 2>/dev/null | head -n 1 | tr -dc '0-9')
    [[ "$service_pid" =~ ^[1-9][0-9]*$ ]]
}

auto_backup_write_worker() {
    cat > "$AUTO_BACKUP_SCRIPT" << 'WORKER_EOF'
#!/usr/bin/env bash
set -uo pipefail
CONF="/etc/pgytunnel-auto-backup-bot.conf"
DB_DIR="/etc/pgytunnel"
DB_FILE="$DB_DIR/users.db"
BW_DIR="$DB_DIR/bandwidth"
MANUAL_LOCK_FILE="$DB_DIR/manual-locks.db"
MANUAL_LOCK_MUTEX="$DB_DIR/.manual-locks.lock"
BACKUP_DIR="/root/pgytunnel-auto-backups"
LAST_FILE="$BACKUP_DIR/last-backup.tar.gz"
LOG_FILE="/var/log/pgytunnel-auto-backup.log"
DOWNLOAD_DIR="/tmp/pgy-restore-downloads"
USERS_GROUP="pgyusers"
TRIAL_CLEANUP_SCRIPT="/usr/local/bin/pgytunnel-trial-cleanup.sh"
API="https://api.telegram.org/bot"
OFFSET=0
RESTORE_STATE="IDLE"
RESTORE_FILE=""
CONFIRM_MSG_ID=""
LAST_AUTO_BACKUP=0

log_msg() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"; }

if [ ! -f "$CONF" ]; then
    log_msg "ERROR: Config not found. Exiting."
    exit 1
fi
source "$CONF" 2>/dev/null
if [ -z "${BOT_TOKEN:-}" ] || [ -z "${CHAT_ID:-}" ] || [ -z "${INTERVAL_SECONDS:-}" ]; then
    log_msg "ERROR: Invalid config. Exiting."
    exit 1
fi

log_msg "Auto-backup bot started. Interval: ${INTERVAL_LABEL:-unknown}"

tg_send() {
    curl -s -o /dev/null \
        -d "chat_id=$CHAT_ID" \
        --data-urlencode "text=$1" \
        "${API}${BOT_TOKEN}/sendMessage" 2>>"$LOG_FILE"
}

tg_send_keyboard() {
    local kb='{"keyboard":[["\ud83d\udcbe Backup Now","\ud83d\udce5 Restore Backup"]],"resize_keyboard":true}'
    curl -s -o /dev/null \
        -d "chat_id=$CHAT_ID" \
        --data-urlencode "text=$1" \
        --data-urlencode "reply_markup=$kb" \
        "${API}${BOT_TOKEN}/sendMessage" 2>>"$LOG_FILE"
}

tg_send_inline() {
    curl -s \
        -d "chat_id=$CHAT_ID" \
        --data-urlencode "text=$1" \
        --data-urlencode "reply_markup=$2" \
        "${API}${BOT_TOKEN}/sendMessage" 2>>"$LOG_FILE" | jq -r '.result.message_id // empty'
}

tg_edit_inline() {
    curl -s \
        -d "chat_id=$1" \
        -d "message_id=$2" \
        --data-urlencode "text=$3" \
        --data-urlencode "reply_markup=$4" \
        "${API}${BOT_TOKEN}/editMessageText" 2>>"$LOG_FILE"
}

tg_answer_callback() {
    curl -s -o /dev/null \
        -d "callback_query_id=$1" \
        --data-urlencode "text=$2" \
        "${API}${BOT_TOKEN}/answerCallbackQuery" 2>>"$LOG_FILE"
}

tg_send_document() {
    curl -s -o /dev/null -w '%{http_code}' \
        -F "chat_id=$CHAT_ID" \
        -F "document=@$1" \
        -F "caption=$2" \
        "${API}${BOT_TOKEN}/sendDocument" 2>>"$LOG_FILE"
}

legacy_lock_is_manual() {
    local username="$1" line _user _password expiry _limit quota account_type metadata _rest
    local now expiry_epoch used_bytes=0 quota_bytes
    line=$(awk -F: -v target="$username" '$1 == target { print; exit }' "$DB_FILE")
    [[ -n "$line" ]] || return 1
    IFS=: read -r _user _password expiry _limit quota account_type metadata _rest <<< "$line"
    now=$(date +%s)
    if [[ "$account_type" == "trial" && "$metadata" =~ ^[0-9]+$ ]] &&
       (( metadata > 0 && metadata <= now )); then
        return 1
    fi
    if [[ "$account_type" != "pending" && -n "$expiry" && "$expiry" != "Never" ]]; then
        expiry_epoch=$(date -d "$expiry 23:59:59" +%s 2>/dev/null || echo 0)
        (( expiry_epoch > 0 && expiry_epoch < now )) && return 1
    fi
    [[ "$quota" =~ ^[0-9]+([.][0-9]+)?$ ]] || quota=0
    if ! awk -v value="$quota" 'BEGIN { exit !(value <= 0) }'; then
        read -r used_bytes < "$BW_DIR/${username}.usage" 2>/dev/null || used_bytes=0
        [[ "$used_bytes" =~ ^[0-9]+$ ]] || used_bytes=0
        quota_bytes=$(awk "BEGIN {printf \"%.0f\", $quota * 1073741824}")
        (( used_bytes >= quota_bytes )) && return 1
    fi
    return 0
}

restore_manual_lock_policy() {
    local restore_root="$1" source_file="" legacy=false
    local username state _extra tmp_file
    mkdir -p "$DB_DIR"
    touch "$MANUAL_LOCK_MUTEX" || return 1
    chmod 600 "$MANUAL_LOCK_MUTEX" 2>/dev/null || true
    exec 9>"$MANUAL_LOCK_MUTEX" || return 1
    flock -x 9 || { exec 9>&-; return 1; }
    tmp_file=$(mktemp "${MANUAL_LOCK_FILE}.tmp.XXXXXX") || {
        flock -u 9
        exec 9>&-
        return 1
    }
    if [[ -f "$restore_root/manual-locks.db" && ! -L "$restore_root/manual-locks.db" ]]; then
        source_file="$restore_root/manual-locks.db"
    elif [[ -f "$restore_root/locks.db" && ! -L "$restore_root/locks.db" ]]; then
        source_file="$restore_root/locks.db"
        legacy=true
    fi
    if [[ -n "$source_file" ]]; then
        while IFS=: read -r username state _extra; do
            [[ "$username" =~ ^[A-Za-z_][A-Za-z0-9_-]{0,31}$ ]] || continue
            awk -F: -v target="$username" '$1 == target { found=1; exit } END { exit !found }' \
                "$DB_FILE" || continue
            id "$username" >/dev/null 2>&1 || continue
            if $legacy; then
                [[ "$state" == "locked" ]] || continue
                legacy_lock_is_manual "$username" || continue
            fi
            printf '%s\n' "$username" >> "$tmp_file"
        done < "$source_file"
    fi
    LC_ALL=C sort -u -o "$tmp_file" "$tmp_file" || {
        rm -f "$tmp_file"
        flock -u 9
        exec 9>&-
        return 1
    }
    chmod 600 "$tmp_file"
    chown root:root "$tmp_file" 2>/dev/null || true
    mv -f "$tmp_file" "$MANUAL_LOCK_FILE"
    local rc=$?
    flock -u 9
    exec 9>&-
    return "$rc"
}

create_user_data_archive() {
    local archive="$1"
    local temp_dir root locks_file manual_locks_file
    temp_dir=$(mktemp -d)
    root="$temp_dir/pgy-user-data"
    locks_file="$root/locks.db"
    manual_locks_file="$root/manual-locks.db"

    mkdir -p "$(dirname "$archive")" "$root/bandwidth"
    cp "$DB_FILE" "$root/users.db"
    cp "$BW_DIR"/*.usage "$root/bandwidth/" 2>/dev/null || true
    if [[ -f "$MANUAL_LOCK_FILE" && ! -L "$MANUAL_LOCK_FILE" ]]; then
        cp "$MANUAL_LOCK_FILE" "$manual_locks_file"
    else
        : > "$manual_locks_file"
    fi
    chmod 600 "$manual_locks_file" 2>/dev/null || true

    : > "$locks_file"
    while IFS=: read -r user _pass _expiry _limit _bandwidth_gb _extra; do
        [ -z "$user" ] && continue
        state="missing"
        if id "$user" &>/dev/null; then
            if grep -Fxq -- "$user" "$MANUAL_LOCK_FILE" 2>/dev/null; then
                state="locked"
            else
                state="unlocked"
            fi
        fi
        printf '%s:%s\n' "$user" "$state" >> "$locks_file"
    done < "$DB_FILE"

    cat > "$root/meta.txt" <<META_EOF
format=pgy-user-data
version=2
created_at=$(date '+%Y-%m-%d %H:%M:%S %z')
META_EOF

    tar -czf "$archive" -C "$temp_dir" "pgy-user-data" 2>>"$LOG_FILE"
    rc=$?
    rm -rf "$temp_dir"
    return "$rc"
}

do_backup() {
    if [ ! -d "$DB_DIR" ] || [ ! -s "$DB_FILE" ]; then
        tg_send "No user data found to backup."
        return 1
    fi
    local ts archive
    ts=$(date '+%Y%m%d-%H%M%S')
    archive="$BACKUP_DIR/backup-$ts.tar.gz"
    mkdir -p "$BACKUP_DIR"
    if ! create_user_data_archive "$archive"; then
        tg_send "Failed to create backup archive."
        return 1
    fi
    cp -f "$archive" "$LAST_FILE" 2>/dev/null
    mapfile -t oldfiles < <(find "$BACKUP_DIR" -maxdepth 1 -name 'backup-*.tar.gz' -printf '%T@ %p\n' 2>/dev/null | sort -rn | awk '{print $2}')
    count=0
    for f in "${oldfiles[@]}"; do
        ((count++))
        (( count > 5 )) && rm -f "$f" 2>/dev/null
    done
    local hc
    hc=$(tg_send_document "$archive" "PGY Backup - $(date '+%d-%m-%Y %H:%M:%S')")
    if [ "$hc" = "200" ]; then
        log_msg "Backup sent: $archive"
        tg_send "Backup sent successfully!"
    else
        log_msg "ERROR: Send failed (HTTP $hc)"
        tg_send "Failed to send backup (HTTP $hc)."
    fi
}

do_restore() {
    local backup_file="$1"
    if [ ! -f "$backup_file" ]; then
        tg_send "Backup file not found."
        return 1
    fi
    if [ -d "$DB_DIR" ] && [ -s "$DB_FILE" ]; then
        local pre="$BACKUP_DIR/pre-restore-$(date '+%Y%m%d-%H%M%S').tar.gz"
        mkdir -p "$BACKUP_DIR"
        create_user_data_archive "$pre" >/dev/null 2>&1
        log_msg "Pre-restore backup: $pre"
    fi
    tg_send "Restoring backup... Please wait."
    local temp_dir
    temp_dir=$(mktemp -d)
    if ! tar -xzf "$backup_file" -C "$temp_dir" 2>>"$LOG_FILE"; then
        tg_send "Failed to extract backup file. Restore aborted."
        rm -rf "$temp_dir"
        return 1
    fi
    local restore_root="$temp_dir/pgy-user-data"
    if [ ! -f "$restore_root/users.db" ]; then
        restore_root="$temp_dir/pgytunnel"
    fi
    local restored_db="$restore_root/users.db"
    if [ ! -f "$restored_db" ]; then
        tg_send "users.db not found in backup. Cannot restore."
        rm -rf "$temp_dir"
        return 1
    fi
    mkdir -p "$DB_DIR"
    cp "$restored_db" "$DB_FILE"
    log_msg "users.db restored"
    mkdir -p "$BW_DIR"
    rm -f "$BW_DIR"/*.usage 2>/dev/null || true
    [ -d "$restore_root/bandwidth" ] && cp "$restore_root/bandwidth"/*.usage "$BW_DIR/" 2>/dev/null || true
    getent group "$USERS_GROUP" >/dev/null 2>&1 || groupadd "$USERS_GROUP"
    local uc=0
    while IFS=: read -r user pass expiry limit bandwidth_gb account_type metadata_value _extra; do
        [ -z "$user" ] && continue
        uc=$((uc + 1))
        if ! id "$user" &>/dev/null; then
            useradd -m -s /usr/sbin/nologin "$user" 2>/dev/null
            log_msg "Created user: $user"
        fi
        usermod -aG "$USERS_GROUP" "$user" 2>/dev/null
        echo "$user:$pass" | chpasswd 2>/dev/null
        if [[ "$expiry" == "Never" || -z "$expiry" ]]; then
            chage -E -1 "$user" 2>/dev/null
        else
            chage -E "$expiry" "$user" 2>/dev/null
        fi
        if [[ "$account_type" == "trial" && "$metadata_value" =~ ^[0-9]+$ ]] &&
           command -v at >/dev/null 2>&1 && [[ -x "$TRIAL_CLEANUP_SCRIPT" ]]; then
            local restored_uid run_at
            restored_uid=$(id -u "$user" 2>/dev/null || true)
            run_at=$(date -d "@$metadata_value" '+%Y%m%d%H%M.%S' 2>/dev/null || true)
            if [[ "$restored_uid" =~ ^[0-9]+$ && -n "$run_at" ]]; then
                if (( metadata_value <= $(date +%s) )); then
                    echo "$TRIAL_CLEANUP_SCRIPT --uid $restored_uid $metadata_value" | at now >/dev/null 2>&1 || true
                else
                    echo "$TRIAL_CLEANUP_SCRIPT --uid $restored_uid $metadata_value" | at -t "$run_at" >/dev/null 2>&1 || true
                fi
            fi
        fi
        log_msg "Restored user: $user"
    done < "$DB_FILE"
    if ! restore_manual_lock_policy "$restore_root"; then
        tg_send "Restore stopped: manual lock policy could not be restored safely."
        rm -rf "$temp_dir"
        return 1
    fi
    systemctl restart pgytunnel-limiter >/dev/null 2>&1 || true
    rm -rf "$temp_dir"
    rm -f /etc/pgytunnel/.banner_cache 2>/dev/null
    tg_send "Restore complete! $uc users restored.

All users re-synced with passwords, expiry, and limits.
Server services may need restart for full effect."
    log_msg "Restore complete. $uc users processed."
    return 0
}

check_auto_backup() {
    local now
    now=$(date +%s)
    if (( now - LAST_AUTO_BACKUP >= INTERVAL_SECONDS )); then
        LAST_AUTO_BACKUP=$now
        if [ ! -d "$DB_DIR" ] || [ ! -s "$DB_FILE" ]; then
            log_msg "No user data, skipping auto-backup."
            return
        fi
        local ts archive
        ts=$(date '+%Y%m%d-%H%M%S')
        archive="$BACKUP_DIR/backup-$ts.tar.gz"
        mkdir -p "$BACKUP_DIR"
        if ! create_user_data_archive "$archive"; then
            log_msg "ERROR: Auto-backup archive failed."
            return
        fi
        cp -f "$archive" "$LAST_FILE" 2>/dev/null
        mapfile -t oldfiles < <(find "$BACKUP_DIR" -maxdepth 1 -name 'backup-*.tar.gz' -printf '%T@ %p\n' 2>/dev/null | sort -rn | awk '{print $2}')
        count=0
        for f in "${oldfiles[@]}"; do
            ((count++))
            (( count > 5 )) && rm -f "$f" 2>/dev/null
        done
        local hc
        hc=$(tg_send_document "$archive" "PGY Auto Backup - $(date '+%d-%m-%Y %H:%M:%S')")
        if [ "$hc" = "200" ]; then
            log_msg "Auto-backup sent: $archive"
        else
            log_msg "ERROR: Auto-backup send failed (HTTP $hc)"
        fi
    fi
}

LAST_AUTO_BACKUP=$(date +%s)

while true; do
    check_auto_backup

    updates=$(curl -s --max-time 5 "${API}${BOT_TOKEN}/getUpdates?offset=${OFFSET}&timeout=3" 2>>"$LOG_FILE")
    ok=$(echo "$updates" | jq -r '.ok // empty' 2>/dev/null)
    if [ "$ok" != "true" ]; then
        sleep 2
        continue
    fi

    rc=$(echo "$updates" | jq '.result | length' 2>/dev/null)
    if [ "$rc" = "0" ] || [ -z "$rc" ]; then
        continue
    fi

    for i in $(seq 0 $((rc - 1))); do
        uid=$(echo "$updates" | jq -r ".result[$i].update_id")
        OFFSET=$((uid + 1))

        is_callback=$(echo "$updates" | jq -r ".result[$i].callback_query | if . then \"yes\" else \"no\" end" 2>/dev/null)

        if [ "$is_callback" = "yes" ]; then
            cbid=$(echo "$updates" | jq -r ".result[$i].callback_query.id")
            cbdata=$(echo "$updates" | jq -r ".result[$i].callback_query.data")
            cid=$(echo "$updates" | jq -r ".result[$i].callback_query.message.chat.id // empty")
            log_msg "Callback: $cbdata (state: $RESTORE_STATE)"

            if [ "$cid" != "$CHAT_ID" ]; then
                log_msg "Unauthorized callback: chat_id=$cid"
                continue
            fi

            case "$cbdata" in
                "cb_confirm1")
                    if [ "$RESTORE_STATE" = "CONFIRM_1" ]; then
                        RESTORE_STATE="CONFIRM_2"
                        tg_answer_callback "$cbid" "Step 2/3"
                        kb='{"inline_keyboard":[[{"text":"\u2705 CONFIRM 2","callback_data":"cb_confirm2"}],[{"text":"\u274c Cancel","callback_data":"cb_cancel"}]]}'
                        tg_edit_inline "$CHAT_ID" "$CONFIRM_MSG_ID" "Step 2/3

This will OVERWRITE all current users, passwords, and settings." "$kb"
                    else
                        tg_answer_callback "$cbid" "Not expecting this"
                    fi
                    ;;
                "cb_confirm2")
                    if [ "$RESTORE_STATE" = "CONFIRM_2" ]; then
                        RESTORE_STATE="CONFIRM_3"
                        tg_answer_callback "$cbid" "Step 3/3 - Final"
                        kb='{"inline_keyboard":[[{"text":"\u26a0\ufe0f RESTORE NOW","callback_data":"cb_restore_now"}],[{"text":"\u274c Cancel","callback_data":"cb_cancel"}]]}'
                        tg_edit_inline "$CHAT_ID" "$CONFIRM_MSG_ID" "FINAL WARNING Step 3/3

This is your LAST chance to cancel!

Tap RESTORE NOW to proceed" "$kb"
                    else
                        tg_answer_callback "$cbid" "Not expecting this"
                    fi
                    ;;
                "cb_restore_now")
                    if [ "$RESTORE_STATE" = "CONFIRM_3" ]; then
                        RESTORE_STATE="RESTORING"
                        tg_answer_callback "$cbid" "Restoring..."
                        kb_remove='{"inline_keyboard":[]}'
                        tg_edit_inline "$CHAT_ID" "$CONFIRM_MSG_ID" "Restoring backup... Please wait." "$kb_remove"
                        do_restore "$RESTORE_FILE"
                        RESTORE_STATE="IDLE"
                        RESTORE_FILE=""
                        CONFIRM_MSG_ID=""
                        rm -f "$DOWNLOAD_DIR"/* 2>/dev/null
                    else
                        tg_answer_callback "$cbid" "Not expecting this"
                    fi
                    ;;
                "cb_cancel")
                    RESTORE_STATE="IDLE"
                    RESTORE_FILE=""
                    CONFIRM_MSG_ID=""
                    rm -f "$DOWNLOAD_DIR"/* 2>/dev/null
                    tg_answer_callback "$cbid" "Cancelled"
                    tg_send "Cancelled. Back to normal."
                    ;;
                *)
                    tg_answer_callback "$cbid" "Unknown action"
                    ;;
            esac
            continue
        fi

        mtype=$(echo "$updates" | jq -r ".result[$i].message | if .text then \"text\" elif .document then \"document\" else \"other\" end" 2>/dev/null)
        cid=$(echo "$updates" | jq -r ".result[$i].message.chat.id // empty" 2>/dev/null)

        if [ "$cid" != "$CHAT_ID" ]; then
            log_msg "Unauthorized: chat_id=$cid"
            continue
        fi

        if [ "$mtype" = "text" ]; then
            txt=$(echo "$updates" | jq -r ".result[$i].message.text")
            log_msg "Text: $txt (state: $RESTORE_STATE)"

            case "$txt" in
                "/start"|"/menu"|"Menu"|"menu")
                    RESTORE_STATE="IDLE"
                    tg_send_keyboard "PGY Backup Bot ready.

Commands:
/backup - Create & send backup
/restore - Restore from file
/status - Show bot status
/cancel - Cancel restore

Auto-backup: ${INTERVAL_LABEL:-unknown}"
                    ;;
                "/backup"|"Backup Now"|*"Backup Now"*)
                    RESTORE_STATE="IDLE"
                    do_backup
                    ;;
                "/restore"|"Restore Backup"|*"Restore Backup"*)
                    RESTORE_STATE="WAITING_FILE"
                    tg_send "Please send the backup .tar.gz file now.

Send the backup file directly to this chat as a document.

Type /cancel to abort."
                    ;;
                "/status"|"Status"|*"Status"*)
                    RESTORE_STATE="IDLE"
                    local_count=$(ls -1 "$BACKUP_DIR"/*.tar.gz 2>/dev/null | wc -l)
                    last_backup="Never"
                    if [ -s "$LAST_FILE" ]; then
                        last_epoch=$(stat -c %Y "$LAST_FILE" 2>/dev/null || echo 0)
                        if [[ "$last_epoch" =~ ^[0-9]+$ ]] && (( last_epoch > 0 )); then
                            last_backup=$(date -d "@$last_epoch" '+%d-%m-%Y • %H:%M' 2>/dev/null || echo "Unknown")
                        fi
                    fi
                    tg_send "[•] PGY BACKUP BOT STATUS
~--------------------------------~
• Status - Active
• Interval - ${INTERVAL_LABEL:-unknown}
• State - $RESTORE_STATE
• Backups - $local_count
• Last Backup - $last_backup"
                    ;;
                "/cancel"|"cancel"|"Cancel"|*"Cancel"*)
                    RESTORE_STATE="IDLE"
                    RESTORE_FILE=""
                    rm -f "$DOWNLOAD_DIR"/* 2>/dev/null
                    tg_send "Cancelled. Back to normal."
                    ;;
                *)
                    if [ "$RESTORE_STATE" = "WAITING_FILE" ]; then
                        tg_send "Please send the backup .tar.gz file as a document, not text.

Type /cancel to abort."
                    fi
                    ;;
            esac

        elif [ "$mtype" = "document" ]; then
            fid=$(echo "$updates" | jq -r ".result[$i].message.document.file_id")
            fname=$(echo "$updates" | jq -r ".result[$i].message.document.file_name // \"backup.tar.gz\"")

            if [ "$RESTORE_STATE" != "WAITING_FILE" ]; then
                tg_send "Received file: $fname

If you want to restore, use Restore Backup first."
                continue
            fi

            if [[ "$fname" != *.tar.gz && "$fname" != *.tgz ]]; then
                tg_send "File must be a .tar.gz backup file."
                continue
            fi

            mkdir -p "$DOWNLOAD_DIR"
            tg_send "Downloading: $fname ..."

            finfo=$(curl -s "${API}${BOT_TOKEN}/getFile?file_id=${fid}" 2>>"$LOG_FILE")
            fpath=$(echo "$finfo" | jq -r '.result.file_path // empty')

            if [ -z "$fpath" ]; then
                tg_send "Failed to get file path from Telegram."
                continue
            fi

            dl="$DOWNLOAD_DIR/$fname"
            curl -s -o "$dl" "https://api.telegram.org/file/bot${BOT_TOKEN}/${fpath}" 2>>"$LOG_FILE"

            if [ ! -f "$dl" ] || [ ! -s "$dl" ]; then
                tg_send "Failed to download backup file."
                continue
            fi

            if ! tar -tzf "$dl" >/dev/null 2>&1; then
                tg_send "File is not a valid tar.gz archive."
                rm -f "$dl"
                continue
            fi

            RESTORE_FILE="$dl"
            RESTORE_STATE="CONFIRM_1"
            fsize=$(du -h "$dl" | cut -f1)
            kb='{"inline_keyboard":[[{"text":"\u2705 CONFIRM 1","callback_data":"cb_confirm1"}],[{"text":"\u274c Cancel","callback_data":"cb_cancel"}]]}'
            CONFIRM_MSG_ID=$(tg_send_inline "Backup received: $fname ($fsize)

WARNING Step 1/3

This will OVERWRITE all current users and settings!

Tap CONFIRM 1 to continue" "$kb")
        else
            log_msg "Unsupported message type"
        fi
    done
done
WORKER_EOF
    chmod +x "$AUTO_BACKUP_SCRIPT"
}

auto_backup_choose_interval() {
    AUTO_BACKUP_SELECTED_SECONDS=""
    AUTO_BACKUP_SELECTED_LABEL=""

    echo
    pgy_box_top
    pgy_box_header "BACKUP INTERVAL"
    pgy_box_divider
    pgy_menu1 "[ 1]" "Every 10 Minutes"
    pgy_menu1 "[ 2]" "Every 30 Minutes"
    pgy_menu1 "[ 3]" "Every 1 Hour"
    pgy_menu1 "[ 4]" "Every 6 Hours"
    pgy_menu1 "[ 5]" "Every 12 Hours"
    pgy_menu1 "[ 6]" "Every 1 Day"
    pgy_menu1 "[ 7]" "Custom Interval (Minutes)"
    pgy_box_divider
    pgy_menu1 "[ 0]" "Cancel"
    pgy_box_bot
    echo
    read -r -p "$(echo -e "${C_PROMPT}  Select an interval: ${C_RESET}")" int_choice
    case "$int_choice" in
        1) AUTO_BACKUP_SELECTED_SECONDS=600; AUTO_BACKUP_SELECTED_LABEL="10 minutes" ;;
        2) AUTO_BACKUP_SELECTED_SECONDS=1800; AUTO_BACKUP_SELECTED_LABEL="30 minutes" ;;
        3) AUTO_BACKUP_SELECTED_SECONDS=3600; AUTO_BACKUP_SELECTED_LABEL="1 hour" ;;
        4) AUTO_BACKUP_SELECTED_SECONDS=21600; AUTO_BACKUP_SELECTED_LABEL="6 hours" ;;
        5) AUTO_BACKUP_SELECTED_SECONDS=43200; AUTO_BACKUP_SELECTED_LABEL="12 hours" ;;
        6) AUTO_BACKUP_SELECTED_SECONDS=86400; AUTO_BACKUP_SELECTED_LABEL="1 day" ;;
        7)
            local custom_minutes
            read -r -p "  Enter interval in minutes (1-525600): " custom_minutes
            if ! [[ "$custom_minutes" =~ ^[1-9][0-9]*$ ]] || (( custom_minutes > 525600 )); then
                echo -e "\n${C_RED}Invalid interval. Enter 1 to 525600 minutes.${C_RESET}"
                return 1
            fi
            AUTO_BACKUP_SELECTED_SECONDS=$((custom_minutes * 60))
            if (( custom_minutes == 1 )); then
                AUTO_BACKUP_SELECTED_LABEL="1 minute"
            else
                AUTO_BACKUP_SELECTED_LABEL="${custom_minutes} minutes"
            fi
            ;;
        0) echo -e "${C_YELLOW}Cancelled.${C_RESET}"; return 1 ;;
        *) echo -e "\n${C_RED}Invalid choice.${C_RESET}"; return 1 ;;
    esac
    return 0
}

auto_backup_connect_bot() {
    clear; show_banner
    pgy_screen_title "CONNECT TELEGRAM BOT" "Configure automated backups and restore controls."
    read -r -p "  Enter Bot Token: " bot_token
    [[ -z "$bot_token" ]] && { echo -e "\n${C_RED}Token cannot be empty.${C_RESET}"; press_enter; return; }
    read -r -p "  Enter Chat ID: " chat_id
    [[ -z "$chat_id" ]] && { echo -e "\n${C_RED}Chat ID cannot be empty.${C_RESET}"; press_enter; return; }

    echo -e "\n${C_BLUE}Testing bot token...${C_RESET}"
    local test_resp
    test_resp=$(curl -s --max-time 10 "https://api.telegram.org/bot$bot_token/getMe" 2>/dev/null)
    if echo "$test_resp" | grep -q '"ok":true'; then
        local bot_user
        bot_user=$(echo "$test_resp" | grep -o '"username":"[^"]*"' | cut -d'"' -f4)
        echo -e "${C_GREEN}Connected to @${bot_user}${C_RESET}"
    else
        echo -e "${C_RED}Invalid bot token.${C_RESET}"
        press_enter
        return
    fi

    if ! auto_backup_choose_interval; then
        press_enter
        return
    fi
    local interval_seconds="$AUTO_BACKUP_SELECTED_SECONDS"
    local interval_label="$AUTO_BACKUP_SELECTED_LABEL"

    if ! auto_backup_save_conf "$bot_token" "$chat_id" "$interval_seconds" "$interval_label" ||
       ! auto_backup_write_worker; then
        echo -e "\n${C_RED}Could not save the bot configuration.${C_RESET}"
        press_enter
        return
    fi

    echo -e "\n${C_GREEN}Bot connected. Interval: $interval_label${C_RESET}"
    echo -e "${C_YELLOW}Use 'Start Bot' to begin auto-backups.${C_RESET}"
    press_enter
}

auto_backup_edit_interval() {
    clear; show_banner
    pgy_screen_title "EDIT BACKUP INTERVAL" "Change how often automatic backups are sent."
    if ! auto_backup_load_conf; then
        echo -e "${C_RED}Bot not configured. Use 'Connect Bot' first.${C_RESET}"
        press_enter
        return
    fi

    local saved_bot_token="$BOT_TOKEN"
    local saved_chat_id="$CHAT_ID"
    local bot_was_running=false
    echo -e "${C_WHITE}Current interval:${C_RESET} ${C_GREEN}${INTERVAL_LABEL:-unknown}${C_RESET}"

    if ! auto_backup_choose_interval; then
        press_enter
        return
    fi

    pm2 list 2>/dev/null | grep -q "$AUTO_BACKUP_PM2_NAME" && bot_was_running=true
    if ! auto_backup_save_conf "$saved_bot_token" "$saved_chat_id" \
        "$AUTO_BACKUP_SELECTED_SECONDS" "$AUTO_BACKUP_SELECTED_LABEL" ||
       ! auto_backup_write_worker; then
        echo -e "\n${C_RED}[ERROR] Could not save the new backup interval.${C_RESET}"
        press_enter
        return
    fi

    if [[ "$bot_was_running" == true ]]; then
        if pm2 restart "$AUTO_BACKUP_PM2_NAME" --update-env >/dev/null 2>&1; then
            pm2 save >/dev/null 2>&1 || true
            echo -e "\n${C_GREEN}[OK] Interval changed to ${AUTO_BACKUP_SELECTED_LABEL}; the bot was restarted.${C_RESET}"
        else
            echo -e "\n${C_RED}[ERROR] Interval was saved, but the bot could not be restarted.${C_RESET}"
        fi
    else
        echo -e "\n${C_GREEN}[OK] Interval changed to ${AUTO_BACKUP_SELECTED_LABEL}.${C_RESET}"
        echo -e "${C_DIM}The new interval will be used the next time the bot starts.${C_RESET}"
    fi
    press_enter
}

auto_backup_start() {
    clear; show_banner
    pgy_screen_title "START BACKUP BOT"
    if ! auto_backup_load_conf; then
        echo
        pgy_message ERROR "Bot not configured. Use 'Connect Bot' first."
        press_enter; return
    fi
    echo
    pgy_section "SERVICE PROGRESS"
    if ! pgy_progress_run 1 3 "Preparing service runtime" auto_backup_ensure_pm2; then
        pgy_message ERROR "The service runtime could not be prepared."
        press_enter
        return
    fi
    if ! pgy_progress_run 2 3 "Configuring backup service" auto_backup_write_worker; then
        pgy_message ERROR "The backup service could not be configured."
        press_enter
        return
    fi
    if ! pgy_progress_run 3 3 "Starting and verifying service" auto_backup_start_runtime; then
        pgy_message ERROR "The backup service could not be started."
        press_enter
        return
    fi
    pgy_message OK "Auto-backup is active. Interval: ${INTERVAL_LABEL:-unknown}."
    press_enter
}

auto_backup_stop() {
    clear; show_banner
    pgy_screen_title "STOP BACKUP BOT"
    pm2 delete "$AUTO_BACKUP_PM2_NAME" >/dev/null 2>&1
    pm2 save >/dev/null 2>&1
    echo
    pgy_message OK "Auto-backup bot stopped."
    press_enter
}

auto_backup_restart() {
    clear; show_banner
    pgy_screen_title "RESTART BACKUP BOT"
    if pm2 list 2>/dev/null | grep -q "$AUTO_BACKUP_PM2_NAME"; then
        pm2 restart "$AUTO_BACKUP_PM2_NAME" >/dev/null 2>&1
        echo -e "${C_GREEN}Bot restarted.${C_RESET}"
    else
        auto_backup_start
        return
    fi
    press_enter
}

auto_backup_reset() {
    clear; show_banner
    pgy_screen_title "RESET BACKUP BOT" "Remove the current bot configuration and process." "$C_DANGER"
    echo -e "${C_RED}This will remove bot config and stop auto-backups.${C_RESET}"
    echo -e "${C_GREEN}Backup archives will be kept.${C_RESET}\n"
    read -r -p "  Are you sure? (y/n): " confirm
    [[ "$confirm" != "y" ]] && { echo -e "\n${C_YELLOW}Cancelled.${C_RESET}"; press_enter; return; }
    pm2 delete "$AUTO_BACKUP_PM2_NAME" >/dev/null 2>&1
    pm2 save >/dev/null 2>&1
    rm -f "$AUTO_BACKUP_CONF"
    rm -f "$AUTO_BACKUP_SCRIPT"
    rm -f "$AUTO_BACKUP_LOG"
    echo -e "\n${C_GREEN}Bot reset complete. Archives preserved.${C_RESET}"
    press_enter
}

auto_backup_send_now() {
    clear; show_banner
    pgy_screen_title "SEND BACKUP NOW"
    if ! auto_backup_load_conf; then
        echo -e "${C_RED}Bot not configured. Use 'Connect Bot' first.${C_RESET}"
        press_enter; return
    fi
    if [ ! -d "$DB_DIR" ] || [ ! -s "$DB_FILE" ]; then
        echo -e "${C_YELLOW}No user data found to back up.${C_RESET}"
        press_enter; return
    fi
    echo -e "${C_BLUE}Creating backup archive...${C_RESET}"
    local ts tmp_archive
    ts=$(date '+%Y%m%d-%H%M%S')
    tmp_archive="$AUTO_BACKUP_DIR/backup-$ts.tar.gz"
    mkdir -p "$AUTO_BACKUP_DIR"
    if ! create_user_backup_archive "$tmp_archive"; then
        echo -e "${C_RED}Failed to create backup archive.${C_RESET}"
        press_enter; return
    fi
    cp -f "$tmp_archive" "$AUTO_BACKUP_LAST_FILE" 2>/dev/null
    echo -e "${C_BLUE}Sending to Telegram...${C_RESET}"
    local http_code
    http_code=$(curl -s -o /dev/null -w '%{http_code}' \
        -F "chat_id=$CHAT_ID" \
        -F "document=@$tmp_archive" \
        -F "caption=PGY Manual Backup - $(date '+%d-%m-%Y %H:%M:%S')" \
        "https://api.telegram.org/bot$BOT_TOKEN/sendDocument" 2>/dev/null)
    if [ "$http_code" = "200" ]; then
        echo -e "${C_GREEN}Backup sent successfully!${C_RESET}"
    else
        echo -e "${C_RED}Failed to send backup (HTTP $http_code).${C_RESET}"
    fi
    press_enter
}

auto_backup_status() {
    clear; show_banner
    local configured=false config_status="Not Connected"
    local bot_status="Stopped" bot_color="$C_RED" bot_pid=""
    local interval_display="Not Set" chat_display="Not Set" token_display="Not Set"
    local archive_count=0 latest_archive="" latest_epoch=0
    local latest_display="Never" latest_size="0B" latest_bytes=0
    local -a recent_archives=()
    local archive_index archive_file archive_name archive_epoch archive_display archive_bytes archive_size
    local archive_number archive_name_cell archive_date_cell archive_size_cell archive_header

    if auto_backup_load_conf; then
        configured=true
        config_status="Connected"
        interval_display="${INTERVAL_LABEL:-Unknown}"
        chat_display="$CHAT_ID"
        token_display="${BOT_TOKEN:0:8}..."
    fi

    bot_pid=$(pm2 pid "$AUTO_BACKUP_PM2_NAME" 2>/dev/null | head -n 1 | tr -dc '0-9')
    if [[ "$bot_pid" =~ ^[1-9][0-9]*$ ]]; then
        bot_status="Running"
        bot_color="$C_GREEN"
    fi

    if [[ -d "$AUTO_BACKUP_DIR" ]]; then
        archive_count=$(find "$AUTO_BACKUP_DIR" -maxdepth 1 -type f -name '*.tar.gz' \
            ! -name 'last-backup.tar.gz' 2>/dev/null | wc -l | tr -d ' ')
        latest_archive=$(find "$AUTO_BACKUP_DIR" -maxdepth 1 -type f -name '*.tar.gz' \
            ! -name 'last-backup.tar.gz' \
            -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n 1 | cut -d' ' -f2-)
        mapfile -t recent_archives < <(find "$AUTO_BACKUP_DIR" -maxdepth 1 -type f -name '*.tar.gz' \
            -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n 5 | cut -d' ' -f2-)
    fi
    [[ "$archive_count" =~ ^[0-9]+$ ]] || archive_count=0
    if [[ -n "$latest_archive" && -s "$latest_archive" ]]; then
        latest_epoch=$(stat -c %Y "$latest_archive" 2>/dev/null || echo 0)
        latest_display=$(pgy_format_epoch_datetime_display "$latest_epoch")
        latest_bytes=$(stat -c %s "$latest_archive" 2>/dev/null || echo 0)
        latest_size=$(pgy_format_file_size "$latest_bytes")
    fi

    echo
    pgy_box_top
    pgy_box_header "AUTO BACKUP BOT STATUS"
    pgy_box_divider
    pgy_row2 "${C_GRAY}STATUS${C_RESET} ${bot_color}${C_BOLD}${bot_status}${C_RESET}" \
        "${C_GRAY}CONFIG${C_RESET} ${C_CYAN}${C_BOLD}${config_status}${C_RESET}"
    pgy_box_divider
    pgy_kv2 "INTERVAL" "$interval_display" "BACKUPS" "$archive_count"
    if $configured; then
        pgy_kv2 "CHAT ID" "$chat_display" "TOKEN" "$token_display"
    fi
    pgy_box_divider
    if (( archive_count > 0 )); then
        pgy_kv2 "LAST" "$latest_display" "SIZE" "$latest_size"
    else
        pgy_row "${C_GRAY}No backup archives have been created yet.${C_RESET}"
    fi
    pgy_box_divider
    pgy_row "${C_GRAY}LOCATION${C_RESET} ${C_GREEN}${AUTO_BACKUP_DIR}${C_RESET}"
    if (( ${#recent_archives[@]} > 0 )); then
        pgy_box_divider
        pgy_row "${C_BOLD}${C_WHITE}RECENT BACKUP FILES${C_RESET}"
        printf -v archive_header "%-3s %-29s %-18s %8s" "#" "FILE" "DATE" "SIZE"
        pgy_row "${C_GRAY}${archive_header}${C_RESET}"
        pgy_box_divider
        for archive_index in "${!recent_archives[@]}"; do
            archive_file="${recent_archives[$archive_index]}"
            archive_name=$(basename "$archive_file")
            archive_epoch=$(stat -c %Y "$archive_file" 2>/dev/null || echo 0)
            archive_display=$(pgy_format_epoch_datetime_display "$archive_epoch")
            archive_bytes=$(stat -c %s "$archive_file" 2>/dev/null || echo 0)
            archive_size=$(pgy_format_file_size "$archive_bytes")
            archive_name=$(_pgy_fit "$archive_name" 29)
            printf -v archive_number "%-3s" "[$((archive_index + 1))]"
            printf -v archive_name_cell "%-29s" "$archive_name"
            printf -v archive_date_cell "%-18s" "$archive_display"
            printf -v archive_size_cell "%8s" "$archive_size"
            pgy_row "${C_CHOICE}${archive_number}${C_RESET} ${C_WHITE}${archive_name_cell}${C_RESET} ${C_GRAY}${archive_date_cell}${C_RESET} ${C_GREEN}${archive_size_cell}${C_RESET}"
        done
    fi
    pgy_box_bot

    if ! $configured; then
        pgy_message INFO "Connect the Telegram bot to enable automatic backups."
    fi
    press_enter
}

backup_data_menu() {
    while true; do
        clear; show_banner
        local pill_bot="Stopped" pill_color="$C_RED"
        if pm2 list 2>/dev/null | grep -q "$AUTO_BACKUP_PM2_NAME"; then
            pill_bot="Active"
            pill_color="$C_GREEN"
        fi

        echo
        pgy_box_top
        pgy_box_header "BACKUP & RESTORE"
        pgy_box_divider
        pgy_row2 "${C_GRAY}AUTO BACKUP BOT${C_RESET}" "${pill_color}${C_BOLD}${pill_bot}${C_RESET}"
        pgy_box_divider
        pgy_menu1 "[ 1]" "Backup User Data"
        pgy_menu1 "[ 2]" "Connect Telegram Bot"
        pgy_menu1 "[ 3]" "Start Backup Bot"
        pgy_menu1 "[ 4]" "Stop Backup Bot"
        pgy_menu1 "[ 5]" "Restart Backup Bot"
        pgy_menu1 "[ 6]" "Send Backup Now"
        pgy_menu1 "[ 7]" "View Bot Status"
        pgy_menu1 "[ 8]" "Edit Backup Interval"
        pgy_menu1 "[ 9]" "Reset Backup Bot"
        pgy_box_divider
        pgy_menu1 "[ 0]" "Return to Main Menu"
        pgy_box_bot
        echo
        read -r -p "$(echo -e "${C_PROMPT}  Select an option: ${C_RESET}")" b_choice
        case $b_choice in
            1) pgy_run_action backup_user_data ;;
            2) pgy_run_action auto_backup_connect_bot ;;
            3) pgy_run_action auto_backup_start ;;
            4) pgy_run_action auto_backup_stop ;;
            5) pgy_run_action auto_backup_restart ;;
            6) pgy_run_action auto_backup_send_now ;;
            7) pgy_run_action auto_backup_status ;;
            8) pgy_run_action auto_backup_edit_interval ;;
            9) pgy_run_action auto_backup_reset ;;
            0) return ;;
            *) invalid_option ;;
        esac
    done
}

