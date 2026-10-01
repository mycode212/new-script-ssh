#!/bin/bash
# ============================================================
# Auto Script SSH By : ProgoCloud
# Module: features/dnstt.sh - SlowDNS / DNSTT Server
# ============================================================

show_dnstt_details() {
    if [ -f "$DNSTT_CONFIG_FILE" ]; then
        source "$DNSTT_CONFIG_FILE"
        echo
        pgy_section "DNSTT CONNECTION DETAILS"
        pgy_detail "Tunnel Domain" "$TUNNEL_DOMAIN" "$C_YELLOW"
        pgy_detail "Public Key" "$PUBLIC_KEY" "$C_YELLOW"
        if [[ -n "$FORWARD_DESC" ]]; then
            pgy_detail "Forwarding To" "$FORWARD_DESC"
        else
            pgy_detail "Forwarding To" "Unknown (config missing)" "$C_YELLOW"
        fi
        if [[ -n "$MTU_VALUE" ]]; then
            pgy_detail "MTU" "$MTU_VALUE" "$C_YELLOW"
        fi
        if [[ "$DNSTT_RECORDS_MANAGED" == "false" && -n "$NS_DOMAIN" ]]; then
            pgy_detail "NS Record" "$NS_DOMAIN" "$C_YELLOW"
        fi
        
        if [[ "$FORWARD_DESC" == *"V2Ray"* ]]; then
            pgy_detail "Action Required" "Run V2Ray (VLESS/VMess/Trojan) on port 8787 without TLS" "$C_YELLOW"
        elif [[ "$FORWARD_DESC" == *"SSH"* ]]; then
            pgy_detail "Action Required" "Configure the SSH client to use this DNS tunnel" "$C_YELLOW"
        fi
        
        echo -e "\n${C_DIM}Use these details in your client configuration.${C_RESET}"
    else
        echo -e "\n${C_YELLOW}[INFO] DNSTT configuration file not found. Details are unavailable.${C_RESET}"
    fi
}

capture_dnstt_resolver_state() {
    local resolved_active=false resolved_enabled=false resolv_kind="missing" resolv_target=""
    mkdir -p "$DNSTT_KEYS_DIR" || return 1
    systemctl is-active --quiet systemd-resolved && resolved_active=true
    systemctl is-enabled --quiet systemd-resolved && resolved_enabled=true
    rm -f "$DNSTT_RESOLV_BACKUP"
    if [[ -L "$PGY_RESOLV_CONF" ]]; then
        resolv_kind="symlink"
        resolv_target=$(readlink "$PGY_RESOLV_CONF")
    elif [[ -f "$PGY_RESOLV_CONF" ]]; then
        resolv_kind="file"
        cp -a "$PGY_RESOLV_CONF" "$DNSTT_RESOLV_BACKUP" || return 1
    fi
    {
        printf 'RESOLVED_ACTIVE=%q\n' "$resolved_active"
        printf 'RESOLVED_ENABLED=%q\n' "$resolved_enabled"
        printf 'RESOLV_KIND=%q\n' "$resolv_kind"
        printf 'RESOLV_TARGET=%q\n' "$resolv_target"
    } > "$DNSTT_RESOLVER_STATE_FILE"
    chmod 600 "$DNSTT_RESOLVER_STATE_FILE" "$DNSTT_RESOLV_BACKUP" 2>/dev/null || true
}

restore_dnstt_resolver_state() {
    local RESOLVED_ACTIVE=false RESOLVED_ENABLED=false RESOLV_KIND="" RESOLV_TARGET=""
    chattr -i "$PGY_RESOLV_CONF" >/dev/null 2>&1 || true
    if [[ -r "$DNSTT_RESOLVER_STATE_FILE" ]]; then
        # Root-owned installer state containing only shell-escaped scalar data.
        source "$DNSTT_RESOLVER_STATE_FILE"
        rm -f "$PGY_RESOLV_CONF"
        case "$RESOLV_KIND" in
            symlink) [[ -n "$RESOLV_TARGET" ]] && ln -s "$RESOLV_TARGET" "$PGY_RESOLV_CONF" ;;
            file) [[ -f "$DNSTT_RESOLV_BACKUP" ]] && cp -a "$DNSTT_RESOLV_BACKUP" "$PGY_RESOLV_CONF" ;;
            missing) : ;;
        esac
        if [[ "$RESOLVED_ENABLED" == "true" ]]; then
            systemctl enable systemd-resolved >/dev/null 2>&1 || true
        else
            systemctl disable systemd-resolved >/dev/null 2>&1 || true
        fi
        if [[ "$RESOLVED_ACTIVE" == "true" ]]; then
            systemctl start systemd-resolved >/dev/null 2>&1 || true
        else
            systemctl stop systemd-resolved >/dev/null 2>&1 || true
        fi
        return 0
    fi

    # Legacy installations did not save resolver state. Restore the standard
    # systemd-resolved link when that service exists instead of leaving the VPS
    # permanently on the temporary installer resolver.
    if systemctl list-unit-files systemd-resolved.service >/dev/null 2>&1; then
        rm -f "$PGY_RESOLV_CONF"
        ln -s "$PGY_RESOLVED_STUB" "$PGY_RESOLV_CONF"
        systemctl enable --now systemd-resolved >/dev/null 2>&1 || true
    fi
}

rollback_dnstt_failed_install() {
    local restore_resolver=${1:-false}
    systemctl stop dnstt.service >/dev/null 2>&1 || true
    systemctl disable dnstt.service >/dev/null 2>&1 || true
    if [[ "$restore_resolver" == "true" ]]; then
        restore_dnstt_resolver_state
    fi
    rm -f "$DNSTT_SERVICE_FILE" "$DNSTT_BINARY" "$DNSTT_CONFIG_FILE"
    rm -rf "$DNSTT_KEYS_DIR"
    systemctl daemon-reload >/dev/null 2>&1 || true
}

install_dnstt() {
    local disable_systemd_resolved=false
    pgy_screen_title "INSTALL DNSTT" "Configure DNS tunnelling on UDP port 53."
    if [ -f "$DNSTT_SERVICE_FILE" ]; then
        echo -e "\n${C_YELLOW}[INFO] DNSTT is already installed.${C_RESET}"
        show_dnstt_details
        return
    fi
    
    echo -e "\n${C_BLUE}Checking if port 53 (UDP) is available...${C_RESET}"
    if ss -lunp | grep -q ':53\s'; then
        if [[ $(ps -p $(ss -lunp | grep ':53\s' | grep -oP 'pid=\K[0-9]+') -o comm=) == "systemd-resolve" ]]; then
            echo -e "${C_YELLOW}[WARNING] Port 53 is in use by 'systemd-resolved'.${C_RESET}"
            echo -e "${C_YELLOW}This is the system's DNS stub resolver. It must be disabled to run DNSTT.${C_RESET}"
            read -p "  Allow the script to automatically disable it and reconfigure DNS? (y/n): " resolve_confirm
            if [[ "$resolve_confirm" == "y" || "$resolve_confirm" == "Y" ]]; then
                # Defer the resolver change until every input, download and
                # generated file is ready. Early cancellation then leaves DNS
                # completely untouched.
                disable_systemd_resolved=true
            else
                echo -e "${C_RED}[ERROR] Cannot proceed without freeing port 53. Aborting.${C_RESET}"
                return
            fi
        else
            check_and_free_ports "53" || return
        fi
    else
        echo -e "${C_GREEN}[OK] Port 53 (UDP) is free to use.${C_RESET}"
    fi

    check_and_open_firewall_port 53 udp || return



    local forward_port=""
    local forward_desc=""
    echo
    pgy_box_top
    pgy_box_header "DNSTT FORWARD TARGET"
    pgy_box_divider
    pgy_menu1 "[ 1]" "Local SSH Service (Port 22)"
    pgy_menu1 "[ 2]" "Local V2Ray Backend (Port 8787)"
    pgy_box_bot
    echo
    read -r -p "$(echo -e "${C_PROMPT}  Select a target [2]: ${C_RESET}")" fwd_choice
    fwd_choice=${fwd_choice:-2}
    if [[ "$fwd_choice" == "1" ]]; then
        forward_port="22"
        forward_desc="SSH (port 22)"
        echo -e "${C_GREEN}[INFO] DNSTT will forward to SSH on 127.0.0.1:22.${C_RESET}"
        

        
    elif [[ "$fwd_choice" == "2" ]]; then
        forward_port="8787"
        forward_desc="V2Ray (port 8787)"
        echo -e "${C_GREEN}[INFO] DNSTT will forward to V2Ray on 127.0.0.1:8787.${C_RESET}"
    else
        echo -e "${C_RED}[ERROR] Invalid choice. Aborting.${C_RESET}"
        return
    fi
    local FORWARD_TARGET="127.0.0.1:$forward_port"

    local NS_DOMAIN=""
    local TUNNEL_DOMAIN=""
    local DNSTT_RECORDS_MANAGED="false"

    echo -e "\n${C_BLUE}[INFO] DNSTT requires two DNS records that you must create yourself:${C_RESET}"
    echo -e "   ${C_CYAN}1.${C_RESET} An NS record pointing a tunnel subdomain to a nameserver subdomain"
    echo -e "   ${C_CYAN}2.${C_RESET} An A record pointing the nameserver subdomain to this server's IP"
    echo -e "   ${C_DIM}(The script will not create these for you — set them up at your DNS provider.)${C_RESET}"
    echo
    read -p "  Enter your full nameserver domain (e.g., ns1.yourdomain.com): " NS_DOMAIN
    if [[ -z "$NS_DOMAIN" ]]; then echo -e "\n${C_RED}[ERROR] Nameserver domain cannot be empty. Aborting.${C_RESET}"; return; fi
    read -p "  Enter your full tunnel domain (e.g., tun.yourdomain.com): " TUNNEL_DOMAIN
    if [[ -z "$TUNNEL_DOMAIN" ]]; then echo -e "\n${C_RED}[ERROR] Tunnel domain cannot be empty. Aborting.${C_RESET}"; return; fi

    read -p "  Enter MTU value (e.g., 512, 1200) or press [Enter] for default: " mtu_value
    local mtu_string=""
    if [[ "$mtu_value" =~ ^[0-9]+$ ]]; then
        mtu_string=" -mtu $mtu_value"
        echo -e "${C_GREEN}[INFO] Using MTU: $mtu_value${C_RESET}"
    else
        mtu_value=""
        echo -e "${C_YELLOW}[INFO] Using default MTU.${C_RESET}"
    fi

    local arch
    arch=$(uname -m)
    local binary_url=""
    if [[ "$arch" == "x86_64" ]]; then
        binary_url="https://dnstt.network/dnstt-server-linux-amd64"
    elif [[ "$arch" == "aarch64" || "$arch" == "arm64" ]]; then
        binary_url="https://dnstt.network/dnstt-server-linux-arm64"
    else
        echo -e "\n${C_RED}[ERROR] Unsupported architecture: $arch. Cannot install DNSTT.${C_RESET}"
        return
    fi

    echo
    pgy_section "INSTALLATION PROGRESS"
    pgy_progress_begin 1 4 "Preparing service package"
    if ! curl -fLsS "$binary_url" -o "$DNSTT_BINARY"; then
        pgy_progress_failed
        echo -e "${C_RED}[ERROR] The service package could not be prepared.${C_RESET}"
        rollback_dnstt_failed_install false
        return
    fi
    chmod +x "$DNSTT_BINARY"
    pgy_progress_done

    pgy_progress_begin 2 4 "Configuring secure service"
    mkdir -p "$DNSTT_KEYS_DIR"
    "$DNSTT_BINARY" -gen-key -privkey-file "$DNSTT_KEYS_DIR/server.key" -pubkey-file "$DNSTT_KEYS_DIR/server.pub" >/dev/null 2>&1
    if [[ ! -s "$DNSTT_KEYS_DIR/server.key" || ! -s "$DNSTT_KEYS_DIR/server.pub" ]]; then
        pgy_progress_failed
        echo -e "${C_RED}[ERROR] Secure service configuration failed.${C_RESET}"
        rollback_dnstt_failed_install false
        return
    fi
    pgy_progress_done
    
    local PUBLIC_KEY
    PUBLIC_KEY=$(cat "$DNSTT_KEYS_DIR/server.pub")
    
    pgy_progress_begin 3 4 "Applying service configuration"
    cat > "$DNSTT_SERVICE_FILE" <<-EOF
[Unit]
Description=DNSTT (DNS Tunnel) Server for $forward_desc
After=network.target
[Service]
Type=simple
User=root
ExecStart=$DNSTT_BINARY -udp :53$mtu_string -privkey-file $DNSTT_KEYS_DIR/server.key $TUNNEL_DOMAIN $FORWARD_TARGET
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
EOF
    cat > "$DNSTT_CONFIG_FILE" <<-EOF
NS_SUBDOMAIN="$NS_SUBDOMAIN"
TUNNEL_SUBDOMAIN="$TUNNEL_SUBDOMAIN"
NS_DOMAIN="$NS_DOMAIN"
TUNNEL_DOMAIN="$TUNNEL_DOMAIN"
PUBLIC_KEY="$PUBLIC_KEY"
FORWARD_DESC="$forward_desc"
DNSTT_RECORDS_MANAGED="$DNSTT_RECORDS_MANAGED"
HAS_IPV6="$HAS_IPV6"
MTU_VALUE="$mtu_value"
EOF
    if [[ ! -s "$DNSTT_SERVICE_FILE" || ! -s "$DNSTT_CONFIG_FILE" ]]; then
        pgy_progress_failed
        echo -e "${C_RED}[ERROR] Service configuration could not be applied.${C_RESET}"
        rollback_dnstt_failed_install false
        return
    fi
    pgy_progress_done

    pgy_progress_begin 4 4 "Starting and verifying service"
    local resolver_changed=false
    if $disable_systemd_resolved; then
        if ! capture_dnstt_resolver_state; then
            pgy_progress_failed
            echo -e "${C_RED}[ERROR] Current resolver settings could not be preserved.${C_RESET}"
            rollback_dnstt_failed_install false
            return
        fi
        if ! systemctl stop systemd-resolved >/dev/null 2>&1 ||
           ! systemctl disable systemd-resolved >/dev/null 2>&1; then
            pgy_progress_failed
            echo -e "${C_RED}[ERROR] The DNS service could not be prepared.${C_RESET}"
            rollback_dnstt_failed_install true
            return
        fi
        chattr -i "$PGY_RESOLV_CONF" >/dev/null 2>&1 || true
        rm -f "$PGY_RESOLV_CONF"
        if ! printf 'nameserver 8.8.8.8\n' > "$PGY_RESOLV_CONF"; then
            pgy_progress_failed
            echo -e "${C_RED}[ERROR] The DNS service could not be prepared.${C_RESET}"
            rollback_dnstt_failed_install true
            return
        fi
        chattr +i "$PGY_RESOLV_CONF" >/dev/null 2>&1 || true
        resolver_changed=true
    fi
    systemctl daemon-reload >/dev/null 2>&1
    systemctl enable dnstt.service >/dev/null 2>&1
    systemctl start dnstt.service >/dev/null 2>&1
    sleep 2
    if systemctl is-active --quiet dnstt.service; then
        pgy_progress_done
        echo -e "\n${C_GREEN}[OK] DNSTT has been installed and started!${C_RESET}"
        show_dnstt_details
    else
        pgy_progress_failed
        echo -e "\n${C_RED}[ERROR] DNSTT service failed to start.${C_RESET}"
        pgy_capture_service_diagnostic dnstt.service
        rollback_dnstt_failed_install "$resolver_changed"
    fi
}

uninstall_dnstt() {
    local mode="${UNINSTALL_MODE:-interactive}" confirm="y" cleanup_failed=false step_failed=false
    local dns_notice=""
    [[ "$mode" == "silent" ]] || pgy_screen_title "UNINSTALL DNSTT"
    if [[ ! -f "$DNSTT_SERVICE_FILE" && ! -f "$DNSTT_BINARY" &&
          ! -d "$DNSTT_KEYS_DIR" && ! -f "$DNSTT_CONFIG_FILE" ]] &&
       ! systemctl is-active --quiet dnstt.service; then
        [[ "$mode" == "silent" ]] || pgy_message INFO "DNSTT is not installed."
        return 0
    fi
    if [[ "$mode" != "silent" ]]; then
        read -p "  Are you sure you want to uninstall DNSTT? (y/n): " confirm
    fi
    if [[ "$confirm" != "y" ]]; then
        pgy_message CANCELLED "Uninstallation cancelled."
        return 0
    fi
    if [[ -f "$DNSTT_CONFIG_FILE" ]]; then
        source "$DNSTT_CONFIG_FILE"
        dns_notice="DNS records for ${NS_DOMAIN:-the nameserver} / ${TUNNEL_DOMAIN:-the tunnel domain} must be removed manually at the DNS provider."
    fi

    [[ "$mode" == "silent" ]] || { echo; pgy_section "UNINSTALLATION PROGRESS"; }
    pgy_progress_begin 1 3 "Stopping service"
    systemctl stop dnstt.service >/dev/null 2>&1 || true
    systemctl disable dnstt.service >/dev/null 2>&1 || true
    if systemctl is-active --quiet dnstt.service; then
        cleanup_failed=true; pgy_progress_failed
    else
        pgy_progress_done
    fi

    pgy_progress_begin 2 3 "Restoring resolver settings"
    if restore_dnstt_resolver_state; then
        pgy_progress_done
    else
        cleanup_failed=true; pgy_progress_failed
    fi

    pgy_progress_begin 3 3 "Removing and verifying files"
    step_failed=false
    if rm -f "$DNSTT_SERVICE_FILE" "$DNSTT_BINARY" "$DNSTT_CONFIG_FILE" &&
       rm -rf "$DNSTT_KEYS_DIR"; then
        systemctl daemon-reload >/dev/null 2>&1 || true
    else
        step_failed=true
    fi
    if [[ -e "$DNSTT_SERVICE_FILE" || -e "$DNSTT_BINARY" ||
          -e "$DNSTT_KEYS_DIR" || -e "$DNSTT_CONFIG_FILE" ]] ||
       systemctl is-active --quiet dnstt.service; then
        step_failed=true
    fi
    if $step_failed; then
        cleanup_failed=true; pgy_progress_failed
    else
        pgy_progress_done
    fi

    if [[ "$cleanup_failed" == true ]]; then
        [[ "$mode" == "silent" ]] || pgy_message ERROR "DNSTT cleanup requires attention."
        return 1
    fi
    [[ "$mode" == "silent" ]] || pgy_message OK "DNSTT was removed successfully."
    [[ -n "$dns_notice" && "$mode" != "silent" ]] && pgy_message WARNING "$dns_notice"
    return 0
}

# --- ZiVPN Installation Logic ---
