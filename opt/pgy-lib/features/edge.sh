#!/bin/bash
# ============================================================
# Auto Script SSH By : ProgoCloud
# Module: features/edge.sh - HAProxy & Nginx edge TLS/WS termination
# ============================================================

domain_cert_menu() {
    clear; show_banner
    load_edge_cert_info

    local cert_domain="${EDGE_DOMAIN:-Not configured}"
    local cert_mode="${EDGE_CERT_MODE:-None}"
    echo
    pgy_box_top
    pgy_box_header "DOMAIN & SSL"
    pgy_box_divider
    pgy_kv2 "DOMAIN" "$cert_domain" "MODE" "$cert_mode"
    if [[ -n "$EDGE_EMAIL" ]]; then
        pgy_row "${C_GRAY}EMAIL${C_RESET} ${C_WHITE}$EDGE_EMAIL${C_RESET}"
    fi
    pgy_box_divider
    pgy_menu1 "[ 1]" "Issue / Renew Let's Encrypt"
    pgy_menu1 "[ 2]" "Generate Self-Signed Certificate"
    pgy_menu1 "[ 3]" "Use / Renew Existing Certificate"
    pgy_menu1 "[ 4]" "Import Fullchain and Private Key"
    pgy_menu1 "[ 5]" "Remove Current Certificate"
    pgy_box_divider
    pgy_menu1 "[ 0]" "Return"
    pgy_box_bot
    echo
    read -r -p "$(echo -e "${C_PROMPT}  Select an option: ${C_RESET}")" dc_choice

    case "$dc_choice" in
        1)
            local domain_name email
            echo -e "\n${C_BLUE}[INFO] Before continuing, make sure your domain's A record points to this server's IP.${C_RESET}"
            echo -e "${C_BLUE}[INFO] Also make sure port 80 is open (certbot needs port 80 for Let's Encrypt validation).${C_RESET}"
            echo
            read -p "  Enter your domain (e.g. vpn.example.com): " domain_name
            if [[ -z "$domain_name" ]]; then
                echo -e "\n${C_RED}[ERROR] Domain cannot be empty.${C_RESET}"
                return 1
            fi
            if _is_valid_ipv4 "$domain_name"; then
                echo -e "\n${C_RED}[ERROR] Certbot requires a real domain name, not a raw IP.${C_RESET}"
                return 1
            fi
            read -p "  Enter your email for Let's Encrypt: " email
            if [[ -z "$email" ]]; then
                echo -e "\n${C_RED}[ERROR] Email cannot be empty.${C_RESET}"
                return 1
            fi
            obtain_certbot_edge_cert "$domain_name" "$email"
            ;;
        2)
            local common_name
            local preferred_host
            preferred_host=$(detect_preferred_host)
            read -p "  Enter certificate Common Name [$preferred_host]: " common_name
            common_name=${common_name:-$preferred_host}
            generate_self_signed_edge_cert "$common_name"
            ;;
        3)
            manage_existing_certbot_certificates
            ;;
        4)
            import_custom_certificate
            ;;
        5)
            if [[ -z "$EDGE_DOMAIN" && ! -f "$PGY_SSL_CERT_FILE" ]]; then
                echo -e "\n${C_YELLOW}[INFO] No certificate to remove.${C_RESET}"
                return
            fi
            read -p "  Confirm removal? (y/n): " confirm
            if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
                rm -f "$PGY_SSL_CERT_FILE" "$SSL_CERT_CHAIN_FILE" "$SSL_CERT_KEY_FILE" "$EDGE_CERT_INFO_FILE"
                echo -e "\n${C_GREEN}[OK] Certificate removed.${C_RESET}"
                if declare -F pgy_openvpn_refresh_gateway_tls >/dev/null 2>&1 && pgy_openvpn_is_installed; then
                    pgy_openvpn_refresh_gateway_tls >/dev/null 2>&1 || true
                fi
            else
                pgy_message CANCELLED "Certificate removal cancelled."
            fi
            ;;
        0|"") return ;;
        *) echo -e "\n${C_RED}[ERROR] Invalid option.${C_RESET}" && sleep 1 ;;
    esac
}


load_edge_cert_info() {
    EDGE_CERT_MODE=""
    EDGE_DOMAIN=""
    EDGE_EMAIL=""
    if [ -f "$EDGE_CERT_INFO_FILE" ]; then
        source "$EDGE_CERT_INFO_FILE"
    fi
}

save_edge_cert_info() {
    local cert_mode="$1"
    local cert_domain="$2"
    local cert_email="$3"
    mkdir -p "$DB_DIR"
    printf 'EDGE_CERT_MODE=%q\nEDGE_DOMAIN=%q\nEDGE_EMAIL=%q\n' \
        "$cert_mode" "$cert_domain" "$cert_email" > "$EDGE_CERT_INFO_FILE"
}

detect_preferred_host() {
    local host_domain=""
    load_edge_cert_info
    if [[ -n "$EDGE_DOMAIN" ]]; then
        host_domain="$EDGE_DOMAIN"
    fi
    if [[ -z "$host_domain" && -f "$NGINX_CONFIG_FILE" ]]; then
        local nginx_domain
        nginx_domain=$(grep -oP 'server_name \K[^\s;]+' "$NGINX_CONFIG_FILE" 2>/dev/null | head -n 1)
        if [[ "$nginx_domain" != "_" && -n "$nginx_domain" ]]; then
            host_domain="$nginx_domain"
        fi
    fi
    if [[ -z "$host_domain" ]]; then
        host_domain=$(curl -s -4 icanhazip.com)
    fi
    echo "$host_domain"
}

backup_edge_configs() {
    if [ -f "$NGINX_CONFIG_FILE" ] && [ ! -f "${NGINX_CONFIG_FILE}.bak.pgytunnel" ]; then
        cp "$NGINX_CONFIG_FILE" "${NGINX_CONFIG_FILE}.bak.pgytunnel" 2>/dev/null
    fi
    if [ -f "$HAPROXY_CONFIG" ] && [ ! -f "${HAPROXY_CONFIG}.bak.pgytunnel" ]; then
        cp "$HAPROXY_CONFIG" "${HAPROXY_CONFIG}.bak.pgytunnel" 2>/dev/null
    fi
}

ensure_edge_stack_packages() {
    local missing_packages=()
    command -v haproxy &> /dev/null || missing_packages+=("haproxy")
    command -v nginx &> /dev/null || missing_packages+=("nginx")
    command -v openssl &> /dev/null || missing_packages+=("openssl")
    command -v python3 &> /dev/null || missing_packages+=("python3")

    if (( ${#missing_packages[@]} > 0 )); then
        pgy_apt_install "${missing_packages[@]}" || {
            return 1
        }
    fi
    return 0
}

build_shared_tls_bundle() {
    if [ ! -s "$SSL_CERT_CHAIN_FILE" ] || [ ! -s "$SSL_CERT_KEY_FILE" ]; then
        echo -e "${C_RED}[ERROR] Certificate chain or key is missing.${C_RESET}"
        return 1
    fi
    cat "$SSL_CERT_CHAIN_FILE" "$SSL_CERT_KEY_FILE" > "$PGY_SSL_CERT_FILE" || return 1
    chmod 644 "$SSL_CERT_CHAIN_FILE"
    chmod 600 "$SSL_CERT_KEY_FILE" "$PGY_SSL_CERT_FILE"
    return 0
}

certificate_primary_name() {
    local certificate_file="$1"
    local cert_name=""
    cert_name=$(openssl x509 -in "$certificate_file" -noout -ext subjectAltName 2>/dev/null |
        sed -n 's/.*DNS:\([^,[:space:]]*\).*/\1/p' | head -n 1)
    if [[ -z "$cert_name" ]]; then
        cert_name=$(openssl x509 -in "$certificate_file" -noout -subject -nameopt RFC2253 2>/dev/null |
            sed -n 's/^subject=.*CN=\([^,]*\).*/\1/p' | head -n 1)
    fi
    printf '%s' "${cert_name:-Unknown}"
}

certificate_expiry_label() {
    local certificate_file="$1"
    local end_date end_epoch now_epoch days_left
    end_date=$(openssl x509 -in "$certificate_file" -noout -enddate 2>/dev/null | cut -d= -f2-)
    end_epoch=$(date -d "$end_date" +%s 2>/dev/null || echo 0)
    now_epoch=$(date +%s)
    if [[ "$end_epoch" =~ ^[0-9]+$ ]] && (( end_epoch > 0 )); then
        days_left=$(( (end_epoch - now_epoch) / 86400 ))
        if (( days_left < 0 )); then
            printf 'Expired'
        else
            printf '%sd left' "$days_left"
        fi
    else
        printf 'Unknown expiry'
    fi
}

validate_certificate_pair() {
    local certificate_file="$1"
    local private_key_file="$2"
    local cert_pub key_pub

    [[ -s "$certificate_file" && -s "$private_key_file" ]] || {
        echo -e "${C_RED}[ERROR] Certificate or private key file is empty.${C_RESET}"
        return 1
    }
    openssl x509 -in "$certificate_file" -noout >/dev/null 2>&1 || {
        echo -e "${C_RED}[ERROR] The selected fullchain is not a valid certificate.${C_RESET}"
        return 1
    }
    openssl pkey -in "$private_key_file" -noout >/dev/null 2>&1 || {
        echo -e "${C_RED}[ERROR] The selected private key is not valid.${C_RESET}"
        return 1
    }
    cert_pub=$(openssl x509 -in "$certificate_file" -pubkey -noout 2>/dev/null |
        openssl pkey -pubin -outform DER 2>/dev/null | sha256sum | awk '{print $1}')
    key_pub=$(openssl pkey -in "$private_key_file" -pubout -outform DER 2>/dev/null |
        sha256sum | awk '{print $1}')
    if [[ -z "$cert_pub" || "$cert_pub" != "$key_pub" ]]; then
        echo -e "${C_RED}[ERROR] The fullchain and private key do not match.${C_RESET}"
        return 1
    fi
    return 0
}

apply_existing_certificate_files() {
    local source_chain="$1"
    local source_key="$2"
    local cert_mode="$3"
    local cert_domain="$4"
    local cert_email="${5:-}"
    local rollback_dir had_chain=false had_key=false had_bundle=false had_info=false
    local nginx_was_active=false haproxy_was_active=false ovpn_tls_rc=0

    validate_certificate_pair "$source_chain" "$source_key" || return 1
    rollback_dir=$(mktemp -d) || return 1
    [[ -f "$SSL_CERT_CHAIN_FILE" ]] && cp "$SSL_CERT_CHAIN_FILE" "$rollback_dir/chain" && had_chain=true
    [[ -f "$SSL_CERT_KEY_FILE" ]] && cp "$SSL_CERT_KEY_FILE" "$rollback_dir/key" && had_key=true
    [[ -f "$PGY_SSL_CERT_FILE" ]] && cp "$PGY_SSL_CERT_FILE" "$rollback_dir/bundle" && had_bundle=true
    [[ -f "$EDGE_CERT_INFO_FILE" ]] && cp "$EDGE_CERT_INFO_FILE" "$rollback_dir/info" && had_info=true
    systemctl is-active --quiet nginx >/dev/null 2>&1 && nginx_was_active=true
    systemctl is-active --quiet haproxy >/dev/null 2>&1 && haproxy_was_active=true

    mkdir -p "$SSL_CERT_DIR"
    if ! install -m 644 "$source_chain" "$SSL_CERT_CHAIN_FILE" ||
       ! install -m 600 "$source_key" "$SSL_CERT_KEY_FILE" ||
       ! build_shared_tls_bundle ||
       ! save_edge_cert_info "$cert_mode" "$cert_domain" "$cert_email"; then
        $had_chain && cp "$rollback_dir/chain" "$SSL_CERT_CHAIN_FILE" || rm -f "$SSL_CERT_CHAIN_FILE"
        $had_key && cp "$rollback_dir/key" "$SSL_CERT_KEY_FILE" || rm -f "$SSL_CERT_KEY_FILE"
        $had_bundle && cp "$rollback_dir/bundle" "$PGY_SSL_CERT_FILE" || rm -f "$PGY_SSL_CERT_FILE"
        $had_info && cp "$rollback_dir/info" "$EDGE_CERT_INFO_FILE" || rm -f "$EDGE_CERT_INFO_FILE"
        echo -e "${C_RED}[ERROR] Certificate could not be prepared.${C_RESET}"
        rm -rf "$rollback_dir"
        return 1
    fi

    local validation_ok=true
    if command -v nginx >/dev/null 2>&1 && [[ -f "$NGINX_CONFIG_FILE" ]]; then
        nginx -t >/dev/null 2>&1 || validation_ok=false
    fi
    if command -v haproxy >/dev/null 2>&1 && [[ -f "$HAPROXY_CONFIG" ]]; then
        haproxy -c -f "$HAPROXY_CONFIG" >/dev/null 2>&1 || validation_ok=false
    fi
    if $validation_ok && $nginx_was_active; then
        systemctl restart nginx >/dev/null 2>&1 || validation_ok=false
    fi
    if $validation_ok && $haproxy_was_active; then
        systemctl restart haproxy >/dev/null 2>&1 || validation_ok=false
    fi

    if ! $validation_ok; then
        $had_chain && cp "$rollback_dir/chain" "$SSL_CERT_CHAIN_FILE" || rm -f "$SSL_CERT_CHAIN_FILE"
        $had_key && cp "$rollback_dir/key" "$SSL_CERT_KEY_FILE" || rm -f "$SSL_CERT_KEY_FILE"
        $had_bundle && cp "$rollback_dir/bundle" "$PGY_SSL_CERT_FILE" || rm -f "$PGY_SSL_CERT_FILE"
        $had_info && cp "$rollback_dir/info" "$EDGE_CERT_INFO_FILE" || rm -f "$EDGE_CERT_INFO_FILE"
        $nginx_was_active && systemctl restart nginx >/dev/null 2>&1 || true
        $haproxy_was_active && systemctl restart haproxy >/dev/null 2>&1 || true
        rm -rf "$rollback_dir"
        echo -e "${C_RED}[ERROR] Service validation failed. The previous certificate was restored.${C_RESET}"
        return 1
    fi

    rm -rf "$rollback_dir"
    echo -e "${C_GREEN}[OK] Certificate applied successfully for ${C_YELLOW}$cert_domain${C_RESET}."
    if declare -F pgy_openvpn_refresh_gateway_tls >/dev/null 2>&1 && pgy_openvpn_is_installed; then
        pgy_openvpn_refresh_gateway_tls
        ovpn_tls_rc=$?
        case "$ovpn_tls_rc" in
            0)
                echo -e "${C_GREEN}[OK] The same certificate is active on the OpenVPN portal, WSS and SSL gateways.${C_RESET}"
                ;;
            2)
                echo -e "${C_YELLOW}[WARNING] The certificate does not cover the saved OpenVPN host, so its previous working outer-TLS certificate was kept.${C_RESET}"
                ;;
            *)
                echo -e "${C_YELLOW}[WARNING] OpenVPN kept its previous working portal/WSS/SSL certificate because the TLS refresh did not validate.${C_RESET}"
                ;;
        esac
    fi
    return 0
}

manage_existing_certbot_certificates() {
    local -a cert_names=() cert_chains=() cert_keys=()
    local cert_dir cert_name cert_domain expiry index=0

    for cert_dir in /etc/letsencrypt/live/*; do
        [[ -d "$cert_dir" && -s "$cert_dir/fullchain.pem" && -s "$cert_dir/privkey.pem" ]] || continue
        cert_names+=("$(basename "$cert_dir")")
        cert_chains+=("$cert_dir/fullchain.pem")
        cert_keys+=("$cert_dir/privkey.pem")
    done
    if (( ${#cert_names[@]} == 0 )); then
        echo -e "\n${C_YELLOW}[INFO] No existing Certbot certificates were found.${C_RESET}"
        return 1
    fi

    echo
    pgy_box_top
    pgy_box_header "EXISTING CERTIFICATES"
    pgy_box_divider
    for ((index=0; index<${#cert_names[@]}; index++)); do
        expiry=$(certificate_expiry_label "${cert_chains[$index]}")
        pgy_menu1 "[$((index + 1))]" "${cert_names[$index]} • ${expiry}"
    done
    pgy_box_divider
    pgy_menu1 "[ 0]" "Return"
    pgy_box_bot
    echo
    read -r -p "$(echo -e "${C_PROMPT}  Select a certificate: ${C_RESET}")" cert_choice
    [[ "$cert_choice" == "0" || -z "$cert_choice" ]] && return 0
    [[ "$cert_choice" =~ ^[0-9]+$ ]] || { echo -e "${C_RED}[ERROR] Invalid option.${C_RESET}"; return 1; }
    index=$((cert_choice - 1))
    (( index >= 0 && index < ${#cert_names[@]} )) || { echo -e "${C_RED}[ERROR] Invalid option.${C_RESET}"; return 1; }

    cert_name="${cert_names[$index]}"
    cert_domain=$(certificate_primary_name "${cert_chains[$index]}")
    echo
    pgy_box_top
    pgy_box_header "$cert_name"
    pgy_box_divider
    pgy_menu1 "[ 1]" "Apply Existing Certificate"
    pgy_menu1 "[ 2]" "Renew Now and Apply"
    pgy_menu1 "[ 0]" "Cancel"
    pgy_box_bot
    echo
    read -r -p "$(echo -e "${C_PROMPT}  Select an action: ${C_RESET}")" cert_action
    case "$cert_action" in
        1)
            apply_existing_certificate_files "${cert_chains[$index]}" "${cert_keys[$index]}" \
                "certbot" "$cert_domain" "${EDGE_EMAIL:-}"
            ;;
        2)
            _install_certbot || return 1
            local nginx_was_active=false haproxy_was_active=false
            systemctl is-active --quiet nginx >/dev/null 2>&1 && nginx_was_active=true
            systemctl is-active --quiet haproxy >/dev/null 2>&1 && haproxy_was_active=true
            $nginx_was_active && systemctl stop nginx >/dev/null 2>&1
            $haproxy_was_active && systemctl stop haproxy >/dev/null 2>&1
            echo -e "\n${C_BLUE}Renewing ${C_YELLOW}$cert_name${C_RESET}..."
            if ! certbot renew --cert-name "$cert_name" --force-renewal; then
                $nginx_was_active && systemctl start nginx >/dev/null 2>&1 || true
                $haproxy_was_active && systemctl start haproxy >/dev/null 2>&1 || true
                echo -e "${C_RED}[ERROR] Certificate renewal failed. The active certificate was not changed.${C_RESET}"
                return 1
            fi
            apply_existing_certificate_files "${cert_chains[$index]}" "${cert_keys[$index]}" \
                "certbot" "$cert_domain" "${EDGE_EMAIL:-}"
            local apply_rc=$?
            $nginx_was_active && systemctl start nginx >/dev/null 2>&1 || true
            $haproxy_was_active && systemctl start haproxy >/dev/null 2>&1 || true
            return "$apply_rc"
            ;;
        0|"") return 0 ;;
        *) echo -e "${C_RED}[ERROR] Invalid option.${C_RESET}"; return 1 ;;
    esac
}

import_custom_certificate() {
    local chain_path key_path cert_domain custom_domain
    echo -e "\n${C_DIM}Provide the fullchain certificate and its matching private key.${C_RESET}"
    read -r -p "  Fullchain file path: " chain_path
    read -r -p "  Private key file path: " key_path
    [[ -f "$chain_path" && -f "$key_path" ]] || {
        echo -e "${C_RED}[ERROR] One or both selected files were not found.${C_RESET}"
        return 1
    }
    validate_certificate_pair "$chain_path" "$key_path" || return 1
    cert_domain=$(certificate_primary_name "$chain_path")
    read -r -p "  Domain / SNI label [$cert_domain]: " custom_domain
    cert_domain=${custom_domain:-$cert_domain}
    apply_existing_certificate_files "$chain_path" "$key_path" "custom" "$cert_domain" ""
}

generate_self_signed_edge_cert() {
    local common_name="$1" san_type="DNS" ovpn_tls_rc=0
    [[ "$common_name" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && san_type="IP"
    mkdir -p "$SSL_CERT_DIR"
    
    pgy_section "CERTIFICATE GENERATION"
    pgy_progress_begin 1 1 "Generating self-signed certificate ($common_name)"
    if ! (
        openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
            -keyout "$SSL_CERT_KEY_FILE" \
            -out "$SSL_CERT_CHAIN_FILE" \
            -subj "/CN=$common_name" \
            -addext "subjectAltName=${san_type}:${common_name}" \
            -addext "keyUsage=digitalSignature,keyEncipherment" \
            -addext "extendedKeyUsage=serverAuth" \
            >/dev/null 2>&1 && build_shared_tls_bundle
    ); then
        pgy_progress_failed "Failed to generate self-signed certificate"
        pgy_box_close_if_open
        return 1
    fi
    save_edge_cert_info "self-signed" "$common_name" ""
    pgy_progress_done "Shared certificate created for $common_name"
    pgy_box_close_if_open

    if declare -F pgy_openvpn_refresh_gateway_tls >/dev/null 2>&1 && pgy_openvpn_is_installed; then
        pgy_openvpn_refresh_gateway_tls >/dev/null 2>&1 || true
    fi
    return 0
}

_install_certbot() {
    if command -v certbot &> /dev/null; then
        return 0
    fi
    pgy_apt_install certbot || {
        echo -e "${C_RED}[ERROR] A required certificate component could not be prepared.${C_RESET}"
        return 1
    }
    return 0
}

obtain_certbot_edge_cert() {
    local domain_name="$1"
    local email="$2"
    local restart_haproxy=0
    local restart_nginx=0

    mkdir -p "$SSL_CERT_DIR"
    _install_certbot || return 1

    if systemctl is-active --quiet haproxy; then restart_haproxy=1; fi
    if systemctl is-active --quiet nginx; then restart_nginx=1; fi

    echo -e "\n${C_BLUE}Preparing certificate validation...${C_RESET}"
    systemctl stop haproxy >/dev/null 2>&1
    systemctl stop nginx >/dev/null 2>&1
    sleep 2

    check_and_free_ports "$EDGE_PUBLIC_HTTP_PORT" "$EDGE_PUBLIC_TLS_PORT" || {
        [[ "$restart_nginx" -eq 1 ]] && systemctl start nginx >/dev/null 2>&1
        [[ "$restart_haproxy" -eq 1 ]] && systemctl start haproxy >/dev/null 2>&1
        return 1
    }

    mkdir -p "$(dirname "$PGY_CERTIFICATE_LOG")" 2>/dev/null || true
    touch "$PGY_CERTIFICATE_LOG" 2>/dev/null || true
    chmod 600 "$PGY_CERTIFICATE_LOG" 2>/dev/null || true
    echo -e "\n${C_BLUE}Requesting a secure certificate for ${C_YELLOW}$domain_name${C_RESET}"
    certbot certonly --standalone -d "$domain_name" --non-interactive --agree-tos -m "$email" >>"$PGY_CERTIFICATE_LOG" 2>&1
    if [ $? -ne 0 ]; then
        echo -e "\n${C_RED}[ERROR] Certbot failed to obtain a certificate.${C_RESET}"
        echo -e "${C_YELLOW}[INFO] Make sure the domain points to this server and port 80 is reachable.${C_RESET}"
        echo -e "${C_DIM}Diagnostic details: ${PGY_CERTIFICATE_LOG}${C_RESET}"
        [[ "$restart_nginx" -eq 1 ]] && systemctl start nginx >/dev/null 2>&1
        [[ "$restart_haproxy" -eq 1 ]] && systemctl start haproxy >/dev/null 2>&1
        return 1
    fi

    local certbot_chain="/etc/letsencrypt/live/$domain_name/fullchain.pem"
    local certbot_key="/etc/letsencrypt/live/$domain_name/privkey.pem"
    if [ ! -f "$certbot_chain" ] || [ ! -f "$certbot_key" ]; then
        echo -e "\n${C_RED}[ERROR] Certbot completed, but the certificate files were not found.${C_RESET}"
        [[ "$restart_nginx" -eq 1 ]] && systemctl start nginx >/dev/null 2>&1
        [[ "$restart_haproxy" -eq 1 ]] && systemctl start haproxy >/dev/null 2>&1
        return 1
    fi

    apply_existing_certificate_files "$certbot_chain" "$certbot_key" \
        "certbot" "$domain_name" "$email" || {
        [[ "$restart_nginx" -eq 1 ]] && systemctl start nginx >/dev/null 2>&1
        [[ "$restart_haproxy" -eq 1 ]] && systemctl start haproxy >/dev/null 2>&1
        return 1
    }
    [[ "$restart_nginx" -eq 1 ]] && systemctl start nginx >/dev/null 2>&1
    [[ "$restart_haproxy" -eq 1 ]] && systemctl start haproxy >/dev/null 2>&1
    echo -e "${C_GREEN}[OK] Certbot certificate is ready for ${C_YELLOW}$domain_name${C_RESET}."
    return 0
}

select_edge_certificate() {
    local preferred_host
    local cert_choice
    local has_existing_cert=false

    preferred_host=$(detect_preferred_host)
    if [[ -z "$preferred_host" ]]; then
        preferred_host="pgytunnel.local"
    fi

    if [ -s "$PGY_SSL_CERT_FILE" ] && [ -s "$SSL_CERT_CHAIN_FILE" ] && [ -s "$SSL_CERT_KEY_FILE" ]; then
        has_existing_cert=true
    fi

    load_edge_cert_info

    pgy_screen_title "SHARED TLS CERTIFICATE" "Konfigurasi atau pilih sertifikat TLS untuk proxy edge."
    echo
    pgy_box_top
    pgy_box_header "SHARED TLS CERTIFICATE"
    pgy_box_divider
    if $has_existing_cert; then
        local existing_label="${EDGE_CERT_MODE:-existing}"
        if [[ -n "$EDGE_DOMAIN" ]]; then
            existing_label="$existing_label - $EDGE_DOMAIN"
        fi
        pgy_row "${C_GRAY}CURRENT${C_RESET} ${C_WHITE}${existing_label}${C_RESET}"
        pgy_box_divider
        pgy_menu1 "[ 1]" "Reuse Existing Certificate"
        pgy_menu1 "[ 2]" "Replace with Self-Signed Certificate"
        pgy_menu1 "[ 3]" "Replace with Certbot Certificate"
        pgy_box_bot
        echo
        read -r -p "$(echo -e "${C_PROMPT}  Select an option [1]: ${C_RESET}")" cert_choice
        cert_choice=${cert_choice:-1}
    else
        pgy_row "${C_GRAY}No shared certificate is currently configured.${C_RESET}"
        pgy_box_divider
        pgy_menu1 "[ 1]" "Generate Self-Signed Certificate"
        pgy_menu1 "[ 2]" "Use Certbot Certificate"
        pgy_box_bot
        echo
        read -r -p "$(echo -e "${C_PROMPT}  Select an option [1]: ${C_RESET}")" cert_choice
        cert_choice=${cert_choice:-1}
    fi

    case "$cert_choice" in
        1)
            if $has_existing_cert; then
                echo -e "${C_GREEN}[OK] Reusing the existing shared certificate.${C_RESET}"
                return 0
            fi
            local common_name
            read -p "  Enter the certificate Common Name / SNI label [$preferred_host]: " common_name
            common_name=${common_name:-$preferred_host}
            generate_self_signed_edge_cert "$common_name"
            ;;
        2)
            if $has_existing_cert; then
                local common_name
                read -p "  Enter the certificate Common Name / SNI label [$preferred_host]: " common_name
                common_name=${common_name:-$preferred_host}
                generate_self_signed_edge_cert "$common_name"
            else
                local default_domain=""
                local domain_name
                local email
                if ! _is_valid_ipv4 "$preferred_host"; then
                    default_domain="$preferred_host"
                fi
                if [[ -n "$default_domain" ]]; then
                    read -p "  Enter your domain name [$default_domain]: " domain_name
                    domain_name=${domain_name:-$default_domain}
                else
                    read -p "  Enter your domain name (e.g. vpn.example.com): " domain_name
                fi
                if [[ -z "$domain_name" ]]; then
                    echo -e "${C_RED}[ERROR] Domain name cannot be empty.${C_RESET}"
                    return 1
                fi
                if _is_valid_ipv4 "$domain_name"; then
                    echo -e "${C_RED}[ERROR] Certbot requires a real domain name, not a raw IP address.${C_RESET}"
                    return 1
                fi
                read -p "  Enter your email for Let's Encrypt: " email
                if [[ -z "$email" ]]; then
                    echo -e "${C_RED}[ERROR] Email cannot be empty.${C_RESET}"
                    return 1
                fi
                obtain_certbot_edge_cert "$domain_name" "$email"
            fi
            ;;
        3)
            if ! $has_existing_cert; then
                echo -e "${C_RED}[ERROR] Invalid option.${C_RESET}"
                return 1
            fi
            local default_domain=""
            local domain_name
            local email
            if [[ -n "$EDGE_DOMAIN" ]] && ! _is_valid_ipv4 "$EDGE_DOMAIN"; then
                default_domain="$EDGE_DOMAIN"
            fi
            if [[ -z "$default_domain" ]] && ! _is_valid_ipv4 "$preferred_host"; then
                default_domain="$preferred_host"
            fi
            if [[ -n "$default_domain" ]]; then
                read -p "  Enter your domain name [$default_domain]: " domain_name
                domain_name=${domain_name:-$default_domain}
            else
                read -p "  Enter your domain name (e.g. vpn.example.com): " domain_name
            fi
            if [[ -z "$domain_name" ]]; then
                echo -e "${C_RED}[ERROR] Domain name cannot be empty.${C_RESET}"
                return 1
            fi
            if _is_valid_ipv4 "$domain_name"; then
                echo -e "${C_RED}[ERROR] Certbot requires a real domain name, not a raw IP address.${C_RESET}"
                return 1
            fi
            read -p "  Enter your email for Let's Encrypt [${EDGE_EMAIL}]: " email
            email=${email:-$EDGE_EMAIL}
            if [[ -z "$email" ]]; then
                echo -e "${C_RED}[ERROR] Email cannot be empty.${C_RESET}"
                return 1
            fi
            obtain_certbot_edge_cert "$domain_name" "$email"
            ;;
        *)
            echo -e "${C_RED}[ERROR] Invalid option.${C_RESET}"
            return 1
            ;;
    esac
}

# ============================================================================
# WebSocket-to-SSH Bridge — accepts DarkTunnel-style WS upgrade payloads
# (GET wss://[cf] HTTP/1.1 ... Upgrade: websocket) and bridges raw TCP to SSH.
# Replaces nginx_cleartext for port 2080 because nginx returns 400 Bad Request
# on the non-standard wss:// absolute-URI form.
# ============================================================================

write_internal_nginx_config() {
    local server_name="$1"
    [[ -z "$server_name" ]] && server_name="_"
    mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled
    cat > "$NGINX_CONFIG_FILE" <<EOF
server {
    listen 127.0.0.1:${NGINX_INTERNAL_HTTP_PORT} default_server;
    listen 127.0.0.1:${NGINX_INTERNAL_TLS_PORT} ssl http2 default_server;
    server_tokens off;
    server_name ${server_name};

    ssl_certificate ${SSL_CERT_CHAIN_FILE};
    ssl_certificate_key ${SSL_CERT_KEY_FILE};
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!eNULL:!MD5:!DES:!RC4:!ADH:!SSLv3:!EXP:!PSK:!DSS;
    resolver 1.1.1.1 8.8.8.8 ipv6=off valid=300s;

    location ~ ^/(?<fwdport>\d+)/(?<fwdpath>.*)$ {
        client_max_body_size 0;
        client_body_timeout 1d;
        grpc_read_timeout 1d;
        grpc_socket_keepalive on;
        proxy_read_timeout 1d;
        proxy_http_version 1.1;
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_socket_keepalive on;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        if (\$content_type ~* "GRPC") { grpc_pass grpc://127.0.0.1:\$fwdport\$is_args\$args; break; }
        proxy_pass http://127.0.0.1:\$fwdport\$is_args\$args;
        break;
    }

    location /vmess {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:10001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }

    location /vless {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:10002;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }

    location /trojan {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:10003;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }

    location ^~ /vmess-grpc {
        proxy_redirect off;
        grpc_set_header X-Real-IP \$remote_addr;
        grpc_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        grpc_set_header Host \$host;
        grpc_pass grpc://127.0.0.1:10005;
    }

    location ^~ /vless-grpc {
        proxy_redirect off;
        grpc_set_header X-Real-IP \$remote_addr;
        grpc_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        grpc_set_header Host \$host;
        grpc_pass grpc://127.0.0.1:10006;
    }

    location ^~ /trojan-grpc {
        proxy_redirect off;
        grpc_set_header X-Real-IP \$remote_addr;
        grpc_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        grpc_set_header Host \$host;
        grpc_pass grpc://127.0.0.1:10007;
    }

    location / {
        proxy_read_timeout 3600s;
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_http_version 1.1;
        proxy_socket_keepalive on;
        tcp_nodelay on;
        tcp_nopush off;
        proxy_pass http://127.0.0.1:${WS_SSH_BRIDGE_PORT:-8890};
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
EOF
    ln -sf "$NGINX_CONFIG_FILE" /etc/nginx/sites-enabled/default
}

write_haproxy_edge_config() {
    mkdir -p "$(dirname "$HAPROXY_CONFIG")"
    cat > "$HAPROXY_CONFIG" <<EOF
global
    log /dev/log local0
    log /dev/log local1 notice
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin expose-fd listeners
    stats timeout 30s
    user haproxy
    group haproxy
    daemon
    # tune.* directives MUST live in 'global', not 'defaults' — HAProxy 2.6
    # rejects them in 'defaults' with 'unknown keyword'. Bumping buffer sizes
    # to 4MB lets HAProxy's TCP window match the bridge's 4MB buffers,
    # preventing backpressure stalls that cap throughput at ~20-30 Mbps.
    tune.bufsize 1048576
    tune.rcvbuf.client 4194304
    tune.rcvbuf.server 4194304
    tune.sndbuf.client 4194304
    tune.sndbuf.server 4194304

defaults
    log     global
    mode    tcp
    option  tcplog
    option  dontlognull
    # Increased from 5s -> 2s for faster failure detection on bad backends.
    timeout connect 2s
    timeout client  24h
    timeout server  24h

# ====================================================================
# TIER 1: PORT ${EDGE_PUBLIC_HTTP_PORT} (Cleartext WS Payloads & Raw SSH)
# DarkTunnel / HTTP Custom / NPV send "GET wss://[cf] HTTP/1.1 ... Upgrade: websocket"
# — nginx rejects wss:// absolute-URI with 400, so we route ALL HTTP on this port
# to the dedicated WS-to-SSH bridge which replies 101 + bridges to SSH.
# Raw SSH (SSH-2.0-...) goes direct to sshd.
# ====================================================================
frontend port_80_edge
    bind *:${EDGE_PUBLIC_HTTP_PORT}
    mode tcp
    # Reduced from 2s -> 500ms: DarkTunnel/HTTP Custom/NPV all send their
    # WS upgrade request in the very first packet, so 500ms is plenty of time
    # to identify the protocol. 2s was adding 1.5s of unnecessary latency to
    # every new connection.
    tcp-request inspect-delay 500ms

    acl is_ssh payload(0,7) -m bin 5353482d322e30

    tcp-request content accept if is_ssh
    tcp-request content accept if HTTP

    use_backend direct_ssh if is_ssh
    default_backend pgy_ws_ssh_bridge

# ====================================================================
# TIER 1: PORT ${EDGE_PUBLIC_TLS_PORT} (TLS v2ray, SSL Payloads, Raw SSH)
# ====================================================================
frontend port_443_edge
    bind *:${EDGE_PUBLIC_TLS_PORT}
    mode tcp
    tcp-request inspect-delay 500ms

    acl is_ssh payload(0,7) -m bin 5353482d322e30
    acl is_tls req.ssl_hello_type 1
    acl has_web_alpn req.ssl_alpn -m sub h2 http/1.1

    tcp-request content accept if is_ssh
    tcp-request content accept if HTTP
    tcp-request content accept if is_tls

    use_backend direct_ssh if is_ssh
    use_backend nginx_cleartext if HTTP
    use_backend nginx_tls if is_tls has_web_alpn
    default_backend loopback_ssl_terminator

# ====================================================================
# TIER 2: INTERNAL DECRYPTOR (Only for Any-SNI SSH-TLS)
# After TLS is stripped, the inner stream may be:
#   - Raw SSH banner -> direct_ssh
#   - HTTP WS upgrade payload (GET wss://... Upgrade: websocket) -> pgy_ws_ssh_bridge
# ====================================================================
frontend internal_decryptor
    bind 127.0.0.1:${HAPROXY_INTERNAL_DECRYPT_PORT} ssl crt ${PGY_SSL_CERT_FILE}
    mode tcp
    tcp-request inspect-delay 500ms

    acl is_ssh payload(0,7) -m bin 5353482d322e30
    tcp-request content accept if is_ssh
    tcp-request content accept if HTTP

    use_backend direct_ssh if is_ssh
    default_backend pgy_ws_ssh_bridge

# ====================================================================
# DESTINATION BACKENDS (Clean handoffs, no proxy headers)
# ====================================================================
backend direct_ssh
    mode tcp
    server ssh_server 127.0.0.1:22

backend pgy_ws_ssh_bridge
    mode tcp
    # Removed the option tcp-check directive and server-line health check.
    # These caused HAProxy to open a fresh TCP connection to the bridge every
    # 2 seconds for health checks. Each check made the bridge spawn a thread,
    # accept the connection, send the branded upgrade response, then try to
    # open an SSH connection that immediately closed. Wasted CPU + file
    # descriptors + created micro-bursts that interfered with active tunnels.
    # systemd already restarts the bridge if it crashes, so HAProxy health
    # checks are redundant here.
    server ws_bridge 127.0.0.1:${WS_SSH_BRIDGE_PORT}

backend nginx_cleartext
    mode tcp
    server nginx_http 127.0.0.1:${NGINX_INTERNAL_HTTP_PORT}

backend nginx_tls
    mode tcp
    server nginx_tls 127.0.0.1:${NGINX_INTERNAL_TLS_PORT}

backend loopback_ssl_terminator
    mode tcp
    server haproxy_ssl 127.0.0.1:${HAPROXY_INTERNAL_DECRYPT_PORT}
EOF
}

save_edge_ports_info() {
    cat > "$NGINX_PORTS_FILE" <<EOF
EDGE_HTTP_PORT="${EDGE_PUBLIC_HTTP_PORT}"
EDGE_TLS_PORT="${EDGE_PUBLIC_TLS_PORT}"
HTTP_PORTS="${NGINX_INTERNAL_HTTP_PORT}"
TLS_PORTS="${NGINX_INTERNAL_TLS_PORT}"
EOF
}

configure_edge_stack() {
    local server_name="$1"
    [[ -z "$server_name" ]] && server_name="_"

    echo
    pgy_section "SERVICE PROGRESS"
    pgy_progress_begin 1 4 "Preparing service configuration"
    backup_edge_configs
    if ! write_internal_nginx_config "$server_name" || ! write_haproxy_edge_config; then
        pgy_progress_failed
        echo -e "${C_RED}[ERROR] Service configuration could not be prepared.${C_RESET}"
        return 1
    fi
    pgy_progress_done

    pgy_progress_begin 2 4 "Preparing connection service"
    if ! install_pgy_ws_ssh_bridge >/dev/null 2>&1; then
        pgy_progress_failed
        echo -e "${C_RED}[ERROR] Connection service could not be prepared.${C_RESET}"
        return 1
    fi
    pgy_progress_done

    pgy_progress_begin 3 4 "Validating service configuration"
    if ! nginx -t >/dev/null 2>&1; then
        pgy_progress_failed
        echo -e "${C_RED}[ERROR] Service configuration validation failed.${C_RESET}"
        return 1
    fi
    if ! haproxy -c -f "$HAPROXY_CONFIG" >/dev/null 2>&1; then
        pgy_progress_failed
        echo -e "${C_RED}[ERROR] Service configuration validation failed.${C_RESET}"
        return 1
    fi
    pgy_progress_done

    pgy_progress_begin 4 4 "Starting and verifying services"
    systemctl daemon-reload >/dev/null 2>&1
    systemctl enable nginx >/dev/null 2>&1
    systemctl enable haproxy >/dev/null 2>&1
    systemctl restart nginx >/dev/null 2>&1 || {
        pgy_progress_failed
        echo -e "${C_RED}[ERROR] Services could not be started.${C_RESET}"
        return 1
    }
    systemctl restart haproxy >/dev/null 2>&1 || {
        pgy_progress_failed
        echo -e "${C_RED}[ERROR] Services could not be started.${C_RESET}"
        return 1
    }

    sleep 2
    if ! systemctl is-active --quiet nginx; then
        pgy_progress_failed
        echo -e "${C_RED}[ERROR] Service verification failed.${C_RESET}"
        return 1
    fi
    if ! systemctl is-active --quiet haproxy; then
        pgy_progress_failed
        echo -e "${C_RED}[ERROR] Service verification failed.${C_RESET}"
        return 1
    fi

    save_edge_ports_info
    save_edge_port_settings || {
        pgy_progress_failed
        pgy_box_close_if_open
        echo -e "${C_RED}[ERROR] Could not save the public edge port settings.${C_RESET}"
        return 1
    }
    pgy_progress_done
    pgy_box_close_if_open
    return 0
}

pgy_tcp_port_in_use() {
    local port="$1"
    command -v ss >/dev/null 2>&1 || return 1
    ss -H -lnt "( sport = :$port )" 2>/dev/null | grep -q .
}

validate_edge_public_port() {
    local port="$1" label="$2"
    if ! pgy_is_valid_port_number "$port"; then
        echo -e "${C_RED}[ERROR] ${label} must be a number from 1 to 65535.${C_RESET}"
        return 1
    fi
    if pgy_is_reserved_edge_port "$port"; then
        echo -e "${C_RED}[ERROR] Port ${port} is reserved by an internal service.${C_RESET}"
        return 1
    fi
    return 0
}

restore_edge_stack_after_port_failure() {
    local rollback_dir="$1"
    local haproxy_was_active="$2" nginx_was_active="$3"
    local haproxy_was_enabled="$4" nginx_was_enabled="$5"

    systemctl stop haproxy nginx >/dev/null 2>&1 || true

    if [[ -f "$rollback_dir/haproxy.cfg" ]]; then
        cp -af "$rollback_dir/haproxy.cfg" "$HAPROXY_CONFIG"
    else
        rm -f "$HAPROXY_CONFIG"
    fi
    if [[ -f "$rollback_dir/nginx-default" ]]; then
        cp -af "$rollback_dir/nginx-default" "$NGINX_CONFIG_FILE"
    else
        rm -f "$NGINX_CONFIG_FILE"
    fi
    if [[ -f "$rollback_dir/nginx_ports.conf" ]]; then
        cp -af "$rollback_dir/nginx_ports.conf" "$NGINX_PORTS_FILE"
    else
        rm -f "$NGINX_PORTS_FILE"
    fi

    systemctl daemon-reload >/dev/null 2>&1 || true
    if [[ "$nginx_was_enabled" == true ]]; then
        systemctl enable nginx >/dev/null 2>&1 || true
    else
        systemctl disable nginx >/dev/null 2>&1 || true
    fi
    if [[ "$haproxy_was_enabled" == true ]]; then
        systemctl enable haproxy >/dev/null 2>&1 || true
    else
        systemctl disable haproxy >/dev/null 2>&1 || true
    fi
    [[ "$nginx_was_active" == true ]] && systemctl start nginx >/dev/null 2>&1 || true
    [[ "$haproxy_was_active" == true ]] && systemctl start haproxy >/dev/null 2>&1 || true
}

apply_edge_public_ports() {
    local new_http="$1" new_tls="$2" force_apply="${3:-false}"
    local old_http="$EDGE_PUBLIC_HTTP_PORT" old_tls="$EDGE_PUBLIC_TLS_PORT"
    local haproxy_was_active=false nginx_was_active=false
    local haproxy_was_enabled=false nginx_was_enabled=false
    local stack_ready=false rollback_dir server_name

    validate_edge_public_port "$new_http" "HTTP/WS port" || return 1
    validate_edge_public_port "$new_tls" "TLS/SSL port" || return 1
    if [[ "$new_http" == "$new_tls" ]]; then
        echo -e "${C_RED}[ERROR] HTTP/WS and TLS/SSL must use different ports.${C_RESET}"
        return 1
    fi

    if [[ "$new_http" == "$old_http" && "$new_tls" == "$old_tls" && "$force_apply" != true ]]; then
        echo -e "${C_YELLOW}[INFO] Those ports are already selected.${C_RESET}"
        return 0
    fi

    systemctl is-active --quiet haproxy && haproxy_was_active=true
    systemctl is-active --quiet nginx && nginx_was_active=true
    systemctl is-enabled --quiet haproxy 2>/dev/null && haproxy_was_enabled=true
    systemctl is-enabled --quiet nginx 2>/dev/null && nginx_was_enabled=true

    if command -v haproxy >/dev/null 2>&1 &&
       command -v nginx >/dev/null 2>&1 &&
       [[ -s "$HAPROXY_CONFIG" && -s "$NGINX_CONFIG_FILE" && -s "$PGY_SSL_CERT_FILE" ]]; then
        stack_ready=true
    fi

    if [[ "$haproxy_was_active" == true || "$nginx_was_active" == true ]]; then
        if [[ "$stack_ready" != true ]]; then
            echo -e "${C_RED}[ERROR] The running edge stack is incomplete, so its ports cannot be changed safely.${C_RESET}"
            echo -e "${C_DIM}Repair or reinstall the HAProxy edge stack first.${C_RESET}"
            return 1
        fi

        rollback_dir=$(mktemp -d /tmp/pgy-edge-port-rollback.XXXXXX) || return 1
        cp -af "$HAPROXY_CONFIG" "$rollback_dir/haproxy.cfg"
        cp -af "$NGINX_CONFIG_FILE" "$rollback_dir/nginx-default"
        [[ -f "$NGINX_PORTS_FILE" ]] && cp -af "$NGINX_PORTS_FILE" "$rollback_dir/nginx_ports.conf"

        if [[ "$new_http" != "$old_http" ]] && pgy_tcp_port_in_use "$new_http"; then
            echo -e "${C_RED}[ERROR] Port ${new_http} is already in use. No changes were applied.${C_RESET}"
            rm -rf "$rollback_dir"
            return 1
        fi
        if [[ "$new_tls" != "$old_tls" ]] && pgy_tcp_port_in_use "$new_tls"; then
            echo -e "${C_RED}[ERROR] Port ${new_tls} is already in use. No changes were applied.${C_RESET}"
            rm -rf "$rollback_dir"
            return 1
        fi

        if ! check_and_open_firewall_port "$new_http" tcp || ! check_and_open_firewall_port "$new_tls" tcp; then
            rm -rf "$rollback_dir"
            return 1
        fi

        EDGE_PUBLIC_HTTP_PORT="$new_http"
        EDGE_PUBLIC_TLS_PORT="$new_tls"
        load_edge_cert_info
        server_name="${EDGE_DOMAIN:-$(detect_preferred_host)}"
        [[ -z "$server_name" ]] && server_name="_"

        if ! configure_edge_stack "$server_name"; then
            echo -e "${C_RED}[ERROR] The new configuration failed. Restoring the previous working ports...${C_RESET}"
            EDGE_PUBLIC_HTTP_PORT="$old_http"
            EDGE_PUBLIC_TLS_PORT="$old_tls"
            restore_edge_stack_after_port_failure "$rollback_dir" \
                "$haproxy_was_active" "$nginx_was_active" "$haproxy_was_enabled" "$nginx_was_enabled"
            rm -rf "$rollback_dir"
            return 1
        fi

        rm -rf "$rollback_dir"
        echo -e "${C_GREEN}[OK] Public ports changed and the edge stack restarted successfully.${C_RESET}"
    else
        EDGE_PUBLIC_HTTP_PORT="$new_http"
        EDGE_PUBLIC_TLS_PORT="$new_tls"
        if ! save_edge_port_settings; then
            EDGE_PUBLIC_HTTP_PORT="$old_http"
            EDGE_PUBLIC_TLS_PORT="$old_tls"
            echo -e "${C_RED}[ERROR] Could not save the new public ports.${C_RESET}"
            return 1
        fi
        echo -e "${C_GREEN}[OK] Public ports saved. They will be used when the edge stack is installed or reconfigured.${C_RESET}"
    fi

    echo -e "   • HTTP/WS: ${C_YELLOW}${EDGE_PUBLIC_HTTP_PORT}${C_RESET}"
    echo -e "   • TLS/SSL: ${C_YELLOW}${EDGE_PUBLIC_TLS_PORT}${C_RESET}"
    echo -e "   • Internal Nginx: ${C_YELLOW}${NGINX_INTERNAL_HTTP_PORT}/${NGINX_INTERNAL_TLS_PORT}${C_RESET}"
    return 0
}

edge_public_port_menu() {
    while true; do
        clear; show_banner
        echo
        pgy_box_top
        pgy_box_header "PUBLIC PORT MANAGEMENT"
        pgy_box_divider
        pgy_kv2 "HTTP/WS" "$EDGE_PUBLIC_HTTP_PORT" "TLS/SSL" "$EDGE_PUBLIC_TLS_PORT"
        pgy_kv2 "DEFAULT" "${DEFAULT_EDGE_PUBLIC_HTTP_PORT}/${DEFAULT_EDGE_PUBLIC_TLS_PORT}" "BACKEND" "${NGINX_INTERNAL_HTTP_PORT}/${NGINX_INTERNAL_TLS_PORT}"
        pgy_box_divider
        pgy_menu1 "[ 1]" "Change HTTP/WS Port"
        pgy_menu1 "[ 2]" "Change TLS/SSL Port"
        pgy_menu1 "[ 3]" "Change Both Public Ports"
        pgy_menu1 "[ 4]" "Restore Default Public Ports"
        pgy_menu1 "[ 5]" "Apply or Repair Current Port Layout"
        pgy_box_divider
        pgy_menu1 "[ 0]" "Return"
        pgy_box_bot
        echo
        read -r -p "$(echo -e "${C_PROMPT}  Select an option: ${C_RESET}")" port_choice

        local new_http="$EDGE_PUBLIC_HTTP_PORT" new_tls="$EDGE_PUBLIC_TLS_PORT" force_apply=false
        case "$port_choice" in
            1) read -r -p "  New HTTP/WS port: " new_http ;;
            2) read -r -p "  New TLS/SSL port: " new_tls ;;
            3)
                read -r -p "  New HTTP/WS port: " new_http
                read -r -p "  New TLS/SSL port: " new_tls
                ;;
            4)
                new_http="$DEFAULT_EDGE_PUBLIC_HTTP_PORT"
                new_tls="$DEFAULT_EDGE_PUBLIC_TLS_PORT"
                ;;
            5) force_apply=true ;;
            0) return ;;
            *) invalid_option; continue ;;
        esac

        validate_edge_public_port "$new_http" "HTTP/WS port" || { press_enter; continue; }
        validate_edge_public_port "$new_tls" "TLS/SSL port" || { press_enter; continue; }
        if [[ "$new_http" == "$new_tls" ]]; then
            echo -e "${C_RED}[ERROR] HTTP/WS and TLS/SSL must use different ports.${C_RESET}"
            press_enter
            continue
        fi

        echo -e "\n${C_YELLOW}New public ports: HTTP/WS ${new_http}, TLS/SSL ${new_tls}.${C_RESET}"
        echo -e "${C_DIM}If the edge stack is running, active connections will briefly disconnect during restart.${C_RESET}"
        read -r -p "  Apply this configuration? (y/n): " confirm
        if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
            apply_edge_public_ports "$new_http" "$new_tls" "$force_apply"
        else
            echo -e "${C_YELLOW}Cancelled.${C_RESET}"
        fi
        press_enter
    done
}

