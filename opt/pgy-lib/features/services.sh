#!/bin/bash
# ============================================================
# Auto Script SSH By : ProgoCloud
# Module: features/services.sh - Protocol daemons and background services
# ============================================================

check_and_free_ports() {
    local ports_to_check=("$@")
    for port in "${ports_to_check[@]}"; do
        local conflicting_process_info
        conflicting_process_info=$(
            ss -H -lntp "( sport = :$port )" 2>/dev/null
            ss -H -lunp "( sport = :$port )" 2>/dev/null
        )
        
        if [[ -n "$conflicting_process_info" ]]; then
            local conflicting_pid
            conflicting_pid=$(echo "$conflicting_process_info" | grep -oP 'pid=\K[0-9]+' | head -n 1)
            local conflicting_name
            conflicting_name=$(echo "$conflicting_process_info" | grep -oP 'users:\(\("(\K[^"]+)' | head -n 1)
            
            echo -e "${C_YELLOW}[WARNING] Port $port is in use by process '${conflicting_name:-unknown}' (PID: ${conflicting_pid:-N/A}).${C_RESET}"
            read -p "  Do you want to attempt to stop this process? (y/n): " kill_confirm
            if [[ "$kill_confirm" == "y" || "$kill_confirm" == "Y" ]]; then
                if [[ -z "$conflicting_pid" ]]; then
                    echo -e "${C_RED}[ERROR] Could not determine which PID owns port $port. Please free it manually.${C_RESET}"
                    return 1
                fi
                echo -e "${C_GREEN}Stopping process PID $conflicting_pid...${C_RESET}"
                systemctl stop "$(ps -p "$conflicting_pid" -o comm=)" &>/dev/null || kill -9 "$conflicting_pid"
                sleep 2
                
                if ss -H -lntp "( sport = :$port )" 2>/dev/null | grep -q . || ss -H -lunp "( sport = :$port )" 2>/dev/null | grep -q .; then
                     echo -e "${C_RED}[ERROR] Failed to free port $port. Please handle it manually. Aborting.${C_RESET}"
                     return 1
                fi
            else
                echo -e "${C_RED}[ERROR] Cannot proceed without freeing port $port. Aborting.${C_RESET}"
                return 1
            fi
        fi
    done
    return 0
}


ensure_badvpn_service_is_quiet() {
    if [[ ! -f "$BADVPN_SERVICE_FILE" ]] || grep -q "^StandardOutput=null$" "$BADVPN_SERVICE_FILE" 2>/dev/null; then
        return
    fi

    local tmp_service
    tmp_service=$(mktemp)
    awk '
        /^\[Service\]$/ {
            print
            print "StandardOutput=null"
            print "StandardError=null"
            next
        }
        { print }
    ' "$BADVPN_SERVICE_FILE" > "$tmp_service" && mv "$tmp_service" "$BADVPN_SERVICE_FILE"
    rm -f "$tmp_service" 2>/dev/null
    systemctl daemon-reload >/dev/null 2>&1
    systemctl restart badvpn.service >/dev/null 2>&1 || true
}

install_badvpn() {
    pgy_screen_title "INSTALL BADVPN" "Build and enable the udpgw service on UDP port 7300."
    if [ -f "$BADVPN_SERVICE_FILE" ]; then
        echo -e "\n${C_YELLOW}[INFO] badvpn is already installed.${C_RESET}"
        return
    fi
    check_and_open_firewall_port 7300 udp || return
    echo
    pgy_section "INSTALLATION PROGRESS"
    pgy_progress_begin 1 4 "Preparing required components"
    if ! pgy_apt_install cmake g++ make screen git build-essential libssl-dev libnspr4-dev libnss3-dev pkg-config >/dev/null 2>&1; then
        pgy_progress_failed
        echo -e "${C_RED}[ERROR] Required components could not be prepared.${C_RESET}"
        return
    fi
    pgy_progress_done

    pgy_progress_begin 2 4 "Preparing service package"
    rm -rf "$BADVPN_BUILD_DIR"
    if ! git clone -q https://github.com/ambrop72/badvpn.git "$BADVPN_BUILD_DIR" >/dev/null 2>&1 ||
       ! (cd "$BADVPN_BUILD_DIR" && cmake . >/dev/null 2>&1 && make >/dev/null 2>&1); then
        pgy_progress_failed
        rm -rf "$BADVPN_BUILD_DIR"
        echo -e "${C_RED}[ERROR] The service package could not be prepared.${C_RESET}"
        return
    fi
    local badvpn_binary
    badvpn_binary=$(find "$BADVPN_BUILD_DIR" -name "badvpn-udpgw" -type f | head -n 1)
    if [[ -z "$badvpn_binary" || ! -f "$badvpn_binary" ]]; then
        pgy_progress_failed
        echo -e "${C_RED}[ERROR] The service package did not pass validation.${C_RESET}"
        rm -rf "$BADVPN_BUILD_DIR"
        return
    fi
    chmod +x "$badvpn_binary"
    pgy_progress_done

    pgy_progress_begin 3 4 "Configuring service"
    cat > "$BADVPN_SERVICE_FILE" <<-EOF
[Unit]
Description=BadVPN UDP Gateway
After=network.target
[Service]
ExecStart=$badvpn_binary --listen-addr 0.0.0.0:7300 --max-clients 1000 --max-connections-for-client 8
User=root
Restart=always
RestartSec=3
StandardOutput=null
StandardError=null
[Install]
WantedBy=multi-user.target
EOF
    pgy_progress_done

    pgy_progress_begin 4 4 "Starting and verifying service"
    systemctl daemon-reload >/dev/null 2>&1
    systemctl enable badvpn.service >/dev/null 2>&1
    systemctl start badvpn.service >/dev/null 2>&1
    sleep 2
    if systemctl is-active --quiet badvpn; then
        pgy_progress_done
        echo -e "\n${C_GREEN}[OK] badvpn (udpgw) is installed and active on port 7300.${C_RESET}"
    else
        pgy_progress_failed
        echo -e "\n${C_RED}[ERROR] badvpn service failed to start.${C_RESET}"
    fi
}

uninstall_badvpn() {
    local mode="${UNINSTALL_MODE:-interactive}" cleanup_failed=false
    [[ "$mode" == "silent" ]] || pgy_screen_title "UNINSTALL BADVPN"
    if [[ ! -f "$BADVPN_SERVICE_FILE" && ! -d "$BADVPN_BUILD_DIR" ]] &&
       ! systemctl is-active --quiet badvpn.service; then
        [[ "$mode" == "silent" ]] || pgy_message INFO "BadVPN is not installed."
        return 0
    fi

    [[ "$mode" == "silent" ]] || { echo; pgy_section "UNINSTALLATION PROGRESS"; }
    pgy_progress_begin 1 3 "Stopping service"
    systemctl stop badvpn.service >/dev/null 2>&1 || true
    systemctl disable badvpn.service >/dev/null 2>&1 || true
    if systemctl is-active --quiet badvpn.service; then
        cleanup_failed=true; pgy_progress_failed
    else
        pgy_progress_done
    fi

    pgy_progress_begin 2 3 "Removing service files"
    if rm -f "$BADVPN_SERVICE_FILE" && rm -rf "$BADVPN_BUILD_DIR"; then
        pgy_progress_done
    else
        cleanup_failed=true; pgy_progress_failed
    fi

    pgy_progress_begin 3 3 "Verifying cleanup"
    systemctl daemon-reload >/dev/null 2>&1 || true
    if ! systemctl is-active --quiet badvpn.service &&
       [[ ! -e "$BADVPN_SERVICE_FILE" && ! -e "$BADVPN_BUILD_DIR" ]]; then
        pgy_progress_done
    else
        cleanup_failed=true; pgy_progress_failed
    fi

    if [[ "$cleanup_failed" == true ]]; then
        [[ "$mode" == "silent" ]] || pgy_message ERROR "BadVPN cleanup requires attention."
        return 1
    fi
    [[ "$mode" == "silent" ]] || pgy_message OK "BadVPN was removed successfully."
    return 0
}


write_pgy_ws_ssh_bridge_script() {
    mkdir -p "$(dirname "$WS_SSH_BRIDGE_SCRIPT")"
    cat > "$WS_SSH_BRIDGE_SCRIPT" <<'PYEOF'
#!/usr/bin/env python3
"""PGY SSH TUNNEL WebSocket-to-SSH Bridge v3 (with Bug Proxy & Split Payload Support)."""
import socket, select, threading, sys, os, signal, time, re, base64, hashlib

LISTEN_HOST = os.environ.get("PGY_WS_BRIDGE_HOST", "127.0.0.1")
LISTEN_PORT = int(os.environ.get("PGY_WS_BRIDGE_PORT", "8890"))
SSH_HOST    = os.environ.get("PGY_WS_BRIDGE_SSH_HOST", "127.0.0.1")
SSH_PORT    = int(os.environ.get("PGY_WS_BRIDGE_SSH_PORT", "22"))
BRANDING_FILE = os.environ.get("PGY_WS_BRIDGE_BRANDING", "/etc/pgytunnel/ws_branding.conf")

WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
MAX_HEADER_BYTES = 65536
RECV_CHUNK = 256 * 1024
SOCKET_BUF_SIZE = 4 * 1024 * 1024  # 4 MB
BRANDING_CACHE_TTL = 30
HANDSHAKE_TIMEOUT = 30
SSH_CONNECT_TIMEOUT = 10
BRIDGE_IDLE_TIMEOUT = 60
KEEPALIVE_IDLE = 60     # send first keepalive probe after 60s idle
KEEPALIVE_INTERVAL = 10 # then probe every 10s
KEEPALIVE_COUNT = 3     # after 3 failed probes (~90s), declare dead

_branding_cache = {"bytes": b"", "mtime": 0, "ts": 0}

def log(m):
    sys.stderr.write(f"[pgy-ws-bridge] {m}\n"); sys.stderr.flush()

def set_tcp_keepalive(sock):
    """Enable SO_KEEPALIVE + aggressive TCP_KEEPIDLE/INTVL/CNT."""
    try:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_KEEPALIVE, 1)
    except OSError:
        return
    if hasattr(socket, "TCP_KEEPIDLE"):
        try: sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_KEEPIDLE, KEEPALIVE_IDLE)
        except OSError: pass
    if hasattr(socket, "TCP_KEEPINTVL"):
        try: sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_KEEPINTVL, KEEPALIVE_INTERVAL)
        except OSError: pass
    if hasattr(socket, "TCP_KEEPCNT"):
        try: sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_KEEPCNT, KEEPALIVE_COUNT)
        except OSError: pass

def set_nodelay(sock):
    """Disable Nagle's algorithm so small SSH packets are not buffered."""
    try: sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
    except OSError: pass

def set_large_buffers(sock):
    """Set SO_RCVBUF and SO_SNDBUF to SOCKET_BUF_SIZE (4MB)."""
    try: sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, SOCKET_BUF_SIZE)
    except OSError: pass
    try: sock.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, SOCKET_BUF_SIZE)
    except OSError: pass

def load_branding_headers():
    now = time.time()
    try:
        st = os.stat(BRANDING_FILE)
    except (OSError, FileNotFoundError):
        _branding_cache["bytes"] = b""
        _branding_cache["mtime"] = 0
        _branding_cache["ts"] = now
        return b""
    if (now - _branding_cache["ts"] < BRANDING_CACHE_TTL
            and st.st_mtime == _branding_cache["mtime"]
            and _branding_cache["bytes"] is not None):
        return _branding_cache["bytes"]
    extra = []
    try:
        with open(BRANDING_FILE, "r", encoding="utf-8", errors="replace") as f:
            for line in f:
                line = line.rstrip("\r\n")
                if not line or line.lstrip().startswith("#"): continue
                if ":" not in line: continue
                if "\r" in line or "\n" in line: continue
                extra.append(line)
    except OSError:
        extra = []
    raw = "".join(h + "\r\n" for h in extra).encode("utf-8", errors="replace")
    _branding_cache["bytes"] = raw
    _branding_cache["mtime"] = st.st_mtime
    _branding_cache["ts"] = now
    return raw

def build_switching_response(req_buf=b""):
    resp = [
        b"HTTP/1.1 101 Switching Protocols\r\n",
        b"Upgrade: websocket\r\n",
        b"Connection: Upgrade\r\n",
    ]
    m = re.search(rb"(?i)sec-websocket-key:\s*([^\r\n]+)", req_buf)
    if m:
        try:
            key = m.group(1).decode("ascii", errors="ignore").strip()
            accept_hash = base64.b64encode(hashlib.sha1((key + WS_GUID).encode("ascii")).digest()).decode("ascii")
            resp.append(f"Sec-WebSocket-Accept: {accept_hash}\r\n".encode("ascii"))
        except Exception:
            pass
    branding = load_branding_headers()
    if branding:
        resp.append(branding)
    resp.append(b"\r\n")
    return b"".join(resp)

def bridge_socks(c, s, initial_client_synced=True):
    """High-throughput bidirectional TCP bridge with split payload / bug absorption.
    When initial_client_synced is False, incoming client data is filtered to strip
    any leftover HTTP headers/split payloads until the SSH identification string (SSH-2.0-...) is detected.
    """
    set_nodelay(c)
    set_nodelay(s)
    set_tcp_keepalive(c)
    set_tcp_keepalive(s)
    set_large_buffers(c)
    set_large_buffers(s)

    c_buf = bytearray(RECV_CHUNK)
    s_buf = bytearray(RECV_CHUNK)
    socks = [c, s]
    client_synced = initial_client_synced
    pending_client_data = b""

    try:
        while True:
            r, _, _ = select.select(socks, [], [], BRIDGE_IDLE_TIMEOUT)
            if not r:
                continue
            for sock in r:
                if sock is s:
                    try:
                        n = s.recv_into(s_buf, RECV_CHUNK)
                    except OSError:
                        return
                    if not n:
                        return
                    try:
                        c.sendall(memoryview(s_buf)[:n])
                    except OSError:
                        return
                else:
                    try:
                        n = c.recv_into(c_buf, RECV_CHUNK)
                    except OSError:
                        return
                    if not n:
                        return
                    data = bytes(memoryview(c_buf)[:n])
                    if client_synced:
                        try:
                            s.sendall(data)
                        except OSError:
                            return
                    else:
                        pending_client_data += data
                        idx = pending_client_data.find(b"SSH-")
                        if idx != -1:
                            ssh_payload = pending_client_data[idx:]
                            client_synced = True
                            pending_client_data = b""
                            try:
                                s.sendall(ssh_payload)
                            except OSError:
                                return
                        else:
                            if len(pending_client_data) > MAX_HEADER_BYTES:
                                pending_client_data = pending_client_data[-4096:]
    finally:
        for sock in (c, s):
            try: sock.shutdown(socket.SHUT_RDWR)
            except OSError: pass
            try: sock.close()
            except OSError: pass

def handle(client, addr):
    try:
        client.settimeout(HANDSHAKE_TIMEOUT)
        buf = b""
        while len(buf) < MAX_HEADER_BYTES:
            try: chunk = client.recv(4096)
            except socket.timeout: return
            if not chunk: return
            buf += chunk
            if buf.startswith(b"SSH-") or b"\r\n\r\n" in buf:
                break

        # 1. Direct SSH Connection
        if buf.startswith(b"SSH-"):
            client.settimeout(None)
            try: ssh = socket.create_connection((SSH_HOST, SSH_PORT), timeout=SSH_CONNECT_TIMEOUT)
            except Exception as e: log(f"ssh connect fail: {e}"); return
            ssh.sendall(buf)
            bridge_socks(client, ssh, initial_client_synced=True)
            return

        # 2. WebSocket / Bug Proxy Payload / Split Payload
        try:
            client.sendall(build_switching_response(buf))
        except OSError:
            return

        try:
            ssh = socket.create_connection((SSH_HOST, SSH_PORT), timeout=SSH_CONNECT_TIMEOUT)
        except Exception as e:
            log(f"ssh connect fail: {e}")
            return

        client.settimeout(None)
        log(f"bridged {addr[0]}:{addr[1]} -> SSH {SSH_HOST}:{SSH_PORT} (WS/Bug Payload)")

        idx = buf.find(b"SSH-")
        if idx != -1:
            try:
                ssh.sendall(buf[idx:])
            except OSError:
                return
            bridge_socks(client, ssh, initial_client_synced=True)
        else:
            bridge_socks(client, ssh, initial_client_synced=False)

    except Exception as e:
        log(f"err {addr}: {e}")
    finally:
        try: client.close()
        except OSError: pass

def main():
    log(f"starting on {LISTEN_HOST}:{LISTEN_PORT} -> SSH {SSH_HOST}:{SSH_PORT}")
    log(f"branding file: {BRANDING_FILE}")
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try: srv.bind((LISTEN_HOST, LISTEN_PORT))
    except OSError as e: log(f"FATAL bind: {e}"); sys.exit(1)
    srv.listen(1024); log("listening")
    def stop(*_):
        try: srv.close()
        except: pass
        sys.exit(0)
    signal.signal(signal.SIGTERM, stop); signal.signal(signal.SIGINT, stop)
    while True:
        try: c, a = srv.accept()
        except OSError: break
        c.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        try: c.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, SOCKET_BUF_SIZE)
        except OSError: pass
        try: c.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, SOCKET_BUF_SIZE)
        except OSError: pass
        threading.Thread(target=handle, args=(c, a), daemon=True).start()

if __name__ == "__main__": main()
PYEOF
    chmod +x "$WS_SSH_BRIDGE_SCRIPT"
}

write_pgy_ws_ssh_bridge_service() {
    cat > "$WS_SSH_BRIDGE_SERVICE" <<EOF
[Unit]
Description=PGY SSH TUNNEL WebSocket-to-SSH Bridge (DarkTunnel payload support)
After=network-online.target ssh.service
Wants=network-online.target

[Service]
Type=simple
Environment=PGY_WS_BRIDGE_HOST=127.0.0.1
Environment=PGY_WS_BRIDGE_PORT=${WS_SSH_BRIDGE_PORT}
Environment=PGY_WS_BRIDGE_SSH_HOST=127.0.0.1
Environment=PGY_WS_BRIDGE_SSH_PORT=22
ExecStart=${WS_SSH_BRIDGE_SCRIPT}
Restart=always
RestartSec=3
LimitNOFILE=65535
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
}

install_pgy_ws_ssh_bridge() {
    echo -e "${C_BLUE}Writing WS-to-SSH bridge script...${C_RESET}"
    write_pgy_ws_ssh_bridge_script
    write_pgy_ws_ssh_bridge_service
    systemctl daemon-reload >/dev/null 2>&1
    systemctl enable pgy-ws-ssh-bridge >/dev/null 2>&1
    systemctl restart pgy-ws-ssh-bridge >/dev/null 2>&1 || {
        echo -e "${C_RED}[ERROR] Failed to start WS-to-SSH bridge.${C_RESET}"
        pgy_capture_service_diagnostic pgy-ws-ssh-bridge.service
        return 1
    }
    sleep 1
    if systemctl is-active --quiet pgy-ws-ssh-bridge; then
        echo -e "${C_GREEN}[OK] WS-to-SSH bridge active on 127.0.0.1:${WS_SSH_BRIDGE_PORT}${C_RESET}"
    else
        echo -e "${C_RED}[ERROR] WS-to-SSH bridge is not active.${C_RESET}"
        return 1
    fi
}

uninstall_pgy_ws_ssh_bridge() {
    systemctl stop pgy-ws-ssh-bridge >/dev/null 2>&1
    systemctl disable pgy-ws-ssh-bridge >/dev/null 2>&1
    rm -f "$WS_SSH_BRIDGE_SERVICE" "$WS_SSH_BRIDGE_SCRIPT"
    systemctl daemon-reload >/dev/null 2>&1
}



install_ssl_tunnel() {
    pgy_screen_title "INSTALL HAPROXY EDGE STACK" \
        "Public ${EDGE_PUBLIC_HTTP_PORT}/${EDGE_PUBLIC_TLS_PORT} → Nginx ${NGINX_INTERNAL_HTTP_PORT}/${NGINX_INTERNAL_TLS_PORT}"
    pgy_section "EDGE LAYOUT"
    pgy_detail "Public Ports" "${EDGE_PUBLIC_HTTP_PORT}/${EDGE_PUBLIC_TLS_PORT}"
    pgy_detail "Internal Ports" "${NGINX_INTERNAL_HTTP_PORT}/${NGINX_INTERNAL_TLS_PORT}"
    pgy_detail "Secure Backend" "$HAPROXY_INTERNAL_DECRYPT_PORT"
    pgy_box_close_if_open

    if [ -f "$HAPROXY_CONFIG" ] || [ -f "$NGINX_CONFIG_FILE" ]; then
        echo
        pgy_box_top "$C_YELLOW"
        pgy_box_header "KONFIRMASI PENGGANTIAN" "$C_YELLOW" "$C_YELLOW"
        pgy_box_divider "$C_YELLOW"
        pgy_row "Konfigurasi proxy lama yang terdeteksi akan diganti dengan susunan managed edge stack ProgoCloud." "$C_YELLOW"
        pgy_box_bot "$C_YELLOW"
        echo
        read -r -p "$(echo -e "  ${C_PROMPT}Lanjutkan proses penggantian? [y/n]: ${C_RESET}")" confirm_replace
        if [[ "$confirm_replace" != "y" && "$confirm_replace" != "Y" ]]; then
            echo
            pgy_message note "Instalasi dibatalkan oleh pengguna."
            return
        fi
    fi

    mkdir -p "$DB_DIR" "$SSL_CERT_DIR"

    echo
    pgy_section "PREPARATION"
    if ! pgy_progress_run 1 1 "Preparing required components" ensure_edge_stack_packages; then
        pgy_message ERROR "Required components could not be prepared."
        echo -e "${C_DIM}Diagnostic details: ${PGY_PACKAGE_LOG}${C_RESET}"
        return
    fi

    systemctl stop haproxy >/dev/null 2>&1
    systemctl stop nginx >/dev/null 2>&1
    sleep 1

    check_and_free_ports \
        "$EDGE_PUBLIC_HTTP_PORT" \
        "$EDGE_PUBLIC_TLS_PORT" \
        "$NGINX_INTERNAL_HTTP_PORT" \
        "$NGINX_INTERNAL_TLS_PORT" \
        "$HAPROXY_INTERNAL_DECRYPT_PORT" || return

    check_and_open_firewall_port "$EDGE_PUBLIC_HTTP_PORT" tcp || return
    check_and_open_firewall_port "$EDGE_PUBLIC_TLS_PORT" tcp || return

    select_edge_certificate || return

    load_edge_cert_info
    local server_name="${EDGE_DOMAIN:-$(detect_preferred_host)}"
    [[ -z "$server_name" ]] && server_name="_"

    configure_edge_stack "$server_name" || return

    echo -e "\n${C_GREEN}[OK] HAProxy edge stack is active.${C_RESET}"
    echo -e "   • Public edge ports: ${C_YELLOW}${EDGE_PUBLIC_HTTP_PORT}/${EDGE_PUBLIC_TLS_PORT}${C_RESET}"
    echo -e "   • Internal Nginx ports: ${C_YELLOW}${NGINX_INTERNAL_HTTP_PORT}/${NGINX_INTERNAL_TLS_PORT}${C_RESET}"
    echo -e "   • Shared certificate: ${C_YELLOW}${EDGE_CERT_MODE:-unknown}${C_RESET}"
}

uninstall_ssl_tunnel() {
    local mode="${UNINSTALL_MODE:-interactive}" delete_cert="n" cleanup_failed=false step_failed=false
    local had_config_backup=false
    [[ "$mode" == "silent" ]] || pgy_screen_title "UNINSTALL HAPROXY EDGE STACK"
    [[ -f "${HAPROXY_CONFIG}.bak.pgytunnel" ]] && had_config_backup=true
    if ! command -v haproxy &>/dev/null && [[ ! -e "$HAPROXY_CONFIG" &&
         ! -e "${HAPROXY_CONFIG}.bak.pgytunnel" && ! -e "$WS_SSH_BRIDGE_SERVICE" &&
         ! -e "$WS_SSH_BRIDGE_SCRIPT" && ! -e "$PGY_SSL_CERT_FILE" &&
         ! -e "$SSL_CERT_CHAIN_FILE" && ! -e "$SSL_CERT_KEY_FILE" ]] &&
       ! systemctl is-active --quiet haproxy.service; then
        [[ "$mode" == "silent" ]] || pgy_message INFO "HAProxy edge stack is not installed."
        return 0
    fi

    if [[ "$mode" == "silent" ]]; then
        delete_cert="y"
    elif [[ -f "$PGY_SSL_CERT_FILE" || -f "$SSL_CERT_CHAIN_FILE" || -f "$SSL_CERT_KEY_FILE" ]]; then
        if systemctl is-active --quiet nginx; then
            echo -e "${C_YELLOW}[WARNING] The shared certificate is also used by the internal Nginx proxy.${C_RESET}"
        fi
        read -p "  Delete the shared TLS certificate too? (y/n): " delete_cert
    fi

    [[ "$mode" == "silent" ]] || { echo; pgy_section "UNINSTALLATION PROGRESS"; }
    pgy_progress_begin 1 3 "Stopping edge services"
    systemctl stop haproxy.service >/dev/null 2>&1 || true
    systemctl disable haproxy.service >/dev/null 2>&1 || true
    uninstall_pgy_ws_ssh_bridge >/dev/null 2>&1 || true
    if systemctl is-active --quiet haproxy.service ||
       systemctl is-active --quiet pgy-ws-ssh-bridge.service; then
        cleanup_failed=true; pgy_progress_failed
    else
        pgy_progress_done
    fi

    pgy_progress_begin 2 3 "Restoring configuration"
    step_failed=false
    if $had_config_backup; then
        mv -f "${HAPROXY_CONFIG}.bak.pgytunnel" "$HAPROXY_CONFIG" || step_failed=true
    else
        rm -f "$HAPROXY_CONFIG" || step_failed=true
    fi
    if [[ "$delete_cert" == "y" || "$delete_cert" == "Y" ]]; then
        if systemctl is-active --quiet nginx; then
            systemctl stop nginx >/dev/null 2>&1 || true
        fi
        rm -f "$PGY_SSL_CERT_FILE" "$SSL_CERT_CHAIN_FILE" "$SSL_CERT_KEY_FILE" \
            "$EDGE_CERT_INFO_FILE" "$NGINX_PORTS_FILE" || step_failed=true
        if declare -F pgy_openvpn_refresh_gateway_tls >/dev/null 2>&1 && pgy_openvpn_is_installed; then
            pgy_openvpn_refresh_gateway_tls >/dev/null 2>&1 || true
        fi
    fi
    if [[ "$step_failed" == true ]]; then
        cleanup_failed=true; pgy_progress_failed
    else
        pgy_progress_done
    fi

    pgy_progress_begin 3 3 "Verifying cleanup"
    systemctl daemon-reload >/dev/null 2>&1 || true
    if systemctl is-active --quiet haproxy.service ||
       systemctl is-active --quiet pgy-ws-ssh-bridge.service ||
       [[ -e "${HAPROXY_CONFIG}.bak.pgytunnel" || -e "$WS_SSH_BRIDGE_SERVICE" ||
          -e "$WS_SSH_BRIDGE_SCRIPT" ]]; then
        cleanup_failed=true
    fi
    if [[ "$delete_cert" == "y" || "$delete_cert" == "Y" ]]; then
        [[ -e "$PGY_SSL_CERT_FILE" || -e "$SSL_CERT_CHAIN_FILE" || -e "$SSL_CERT_KEY_FILE" ]] && cleanup_failed=true
    fi
    if [[ "$cleanup_failed" == true ]]; then
        pgy_progress_failed
        [[ "$mode" == "silent" ]] || pgy_message ERROR "HAProxy edge cleanup requires attention."
        return 1
    fi
    pgy_progress_done
    [[ "$mode" == "silent" ]] || pgy_message OK "HAProxy edge stack was removed successfully."
    return 0
}


install_zivpn() {
    pgy_screen_title "INSTALL ZIVPN" "Configure the UDP VPN service on port 5667."
    
    if [ -f "$ZIVPN_SERVICE_FILE" ]; then
        echo -e "\n${C_YELLOW}[INFO] ZiVPN is already installed.${C_RESET}"
        return
    fi

    check_and_free_ports 5667 || return
    check_and_open_firewall_port 5667 udp || return
    check_and_open_firewall_port_range "6000:19999" udp || return

    local arch
    arch=$(uname -m)
    local zivpn_url=""
    
    if [[ "$arch" == "x86_64" ]]; then
        zivpn_url="https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64"
    elif [[ "$arch" == "aarch64" ]]; then
        zivpn_url="https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-arm64"
    elif [[ "$arch" == "armv7l" || "$arch" == "arm" ]]; then
         zivpn_url="https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-arm"
    else
        echo -e "${C_RED}[ERROR] Unsupported architecture: $arch${C_RESET}"
        return
    fi

    echo -e "\n${C_YELLOW}ZiVPN Password Setup${C_RESET}"
    read -r -p "  Enter passwords separated by commas (e.g., user1,user2) [Default: 'zi']: " input_config
    local json_passwords
    if [[ -n "$input_config" ]]; then
        local -a config_array
        IFS=',' read -r -a config_array <<< "$input_config"
        local configured_password
        for configured_password in "${config_array[@]}"; do
            if [[ -z "$configured_password" || ! "$configured_password" =~ ^[A-Za-z0-9._@+-]+$ ]]; then
                echo -e "${C_RED}[ERROR] Passwords may contain only letters, numbers, dot, underscore, @, + and -.${C_RESET}"
                return
            fi
        done
        json_passwords=$(printf '"%s",' "${config_array[@]}")
        json_passwords="[${json_passwords%,}]"
    else
        json_passwords='["zi"]'
    fi

    echo
    pgy_section "INSTALLATION PROGRESS"
    pgy_progress_begin 1 4 "Preparing service package"
    if ! wget -q -O "$ZIVPN_BIN" "$zivpn_url"; then
        pgy_progress_failed
        echo -e "${C_RED}[ERROR] The service package could not be prepared.${C_RESET}"
        return
    fi
    chmod +x "$ZIVPN_BIN"
    pgy_progress_done

    pgy_progress_begin 2 4 "Configuring secure service"
    mkdir -p "$ZIVPN_DIR"
    if ! command -v openssl &>/dev/null; then
        pgy_apt_install openssl >/dev/null 2>&1 || {
            pgy_progress_failed
            echo -e "${C_RED}[ERROR] A required secure component could not be prepared.${C_RESET}"
            return
        }
    fi
    
    openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 \
        -subj "/C=US/ST=California/L=Los Angeles/O=Example Corp/OU=IT Department/CN=zivpn" \
        -keyout "$ZIVPN_KEY_FILE" -out "$ZIVPN_CERT_FILE" 2>/dev/null

    if [[ ! -s "$ZIVPN_CERT_FILE" || ! -s "$ZIVPN_KEY_FILE" ]]; then
        pgy_progress_failed
        echo -e "${C_RED}[ERROR] Secure service configuration failed.${C_RESET}"
        return
    fi
    chmod 600 "$ZIVPN_KEY_FILE"
    chmod 644 "$ZIVPN_CERT_FILE"
    pgy_progress_done

    pgy_progress_begin 3 4 "Applying service configuration"
    sysctl -w net.core.rmem_max=16777216 >/dev/null 2>&1
    sysctl -w net.core.wmem_max=16777216 >/dev/null 2>&1

    cat <<EOF > "$ZIVPN_SERVICE_FILE"
[Unit]
Description=zivpn VPN Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$ZIVPN_DIR
ExecStart=$ZIVPN_BIN server -c $ZIVPN_CONFIG_FILE
Restart=always
RestartSec=3
Environment=ZIVPN_LOG_LEVEL=info
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

    cat <<EOF > "$ZIVPN_CONFIG_FILE"
{
  "listen": ":5667",
   "cert": "$ZIVPN_CERT_FILE",
   "key": "$ZIVPN_KEY_FILE",
   "obfs":"zivpn",
   "auth": {
    "mode": "passwords", 
    "config": $json_passwords
  }
}
EOF
    if [[ ! -s "$ZIVPN_SERVICE_FILE" || ! -s "$ZIVPN_CONFIG_FILE" ]]; then
        pgy_progress_failed
        echo -e "${C_RED}[ERROR] Service configuration could not be applied.${C_RESET}"
        return
    fi
    pgy_progress_done

    pgy_progress_begin 4 4 "Starting and verifying service"
    systemctl daemon-reload >/dev/null 2>&1
    systemctl enable zivpn.service >/dev/null 2>&1
    systemctl start zivpn.service >/dev/null 2>&1

    local iface
    local forwarding_ready=true
    iface=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)
    
    if [ -n "$iface" ]; then
        iptables -t nat -C PREROUTING -i "$iface" -p udp --dport 6000:19999 -j DNAT --to-destination :5667 2>/dev/null || \
            iptables -t nat -A PREROUTING -i "$iface" -p udp --dport 6000:19999 -j DNAT --to-destination :5667 >/dev/null 2>&1 || forwarding_ready=false
    else
        forwarding_ready=false
    fi

    rm -f zi.sh zi2.sh 2>/dev/null

    if systemctl is-active --quiet zivpn.service; then
        pgy_progress_done
        pgy_message OK "ZiVPN installed and started successfully."
        echo
        pgy_section "ZIVPN CONNECTION DETAILS"
        pgy_detail "Direct UDP Port" "5667"
        pgy_detail "Forwarded Ports" "6000-19999"
        if [[ "$forwarding_ready" != true ]]; then
            echo -e "${C_YELLOW}[WARNING] The forwarded port range could not be applied; direct port 5667 remains available.${C_RESET}"
        fi
    else
        pgy_progress_failed
        echo -e "\n${C_RED}[ERROR] ZiVPN service failed to start.${C_RESET}"
        pgy_capture_service_diagnostic zivpn.service
    fi
}

uninstall_zivpn() {
    local mode="${UNINSTALL_MODE:-interactive}" confirm="y" cleanup_failed=false step_failed=false iface=""
    if [[ "$mode" != "silent" ]]; then
        clear; show_banner
        pgy_screen_title "UNINSTALL ZIVPN"
    fi
    if [[ ! -f "$ZIVPN_SERVICE_FILE" && ! -f "$ZIVPN_BIN" && ! -d "$ZIVPN_DIR" ]] &&
       ! systemctl is-active --quiet zivpn.service; then
        [[ "$mode" == "silent" ]] || pgy_message INFO "ZiVPN is not installed."
        return 0
    fi

    if [[ "$mode" != "silent" ]]; then
        read -p "  Are you sure you want to uninstall ZiVPN? (y/n): " confirm
    fi
    if [[ "$confirm" != "y" ]]; then
        pgy_message CANCELLED "Uninstallation cancelled."
        return 0
    fi

    [[ "$mode" == "silent" ]] || { echo; pgy_section "UNINSTALLATION PROGRESS"; }
    pgy_progress_begin 1 3 "Stopping service"
    systemctl stop zivpn.service >/dev/null 2>&1 || true
    systemctl disable zivpn.service >/dev/null 2>&1 || true
    if systemctl is-active --quiet zivpn.service; then
        cleanup_failed=true; pgy_progress_failed
    else
        pgy_progress_done
    fi

    pgy_progress_begin 2 3 "Removing network rules"
    iface=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)
    if [ -n "$iface" ]; then
        iptables -t nat -D PREROUTING -i "$iface" -p udp --dport 6000:19999 -j DNAT --to-destination :5667 2>/dev/null || true
    fi
    pgy_progress_done

    pgy_progress_begin 3 3 "Removing and verifying files"
    step_failed=false
    if rm -f "$ZIVPN_SERVICE_FILE" "$ZIVPN_BIN" && rm -rf "$ZIVPN_DIR"; then
        systemctl daemon-reload >/dev/null 2>&1 || true
    else
        step_failed=true
    fi
    if [[ -e "$ZIVPN_SERVICE_FILE" || -e "$ZIVPN_BIN" || -e "$ZIVPN_DIR" ]] ||
       systemctl is-active --quiet zivpn.service; then
        step_failed=true
    fi
    if $step_failed; then
        cleanup_failed=true; pgy_progress_failed
    else
        pgy_progress_done
    fi

    if [[ "$cleanup_failed" == true ]]; then
        [[ "$mode" == "silent" ]] || pgy_message ERROR "ZiVPN cleanup requires attention."
        return 1
    fi
    [[ "$mode" == "silent" ]] || pgy_message OK "ZiVPN was removed successfully."
    return 0
}

purge_nginx() {
    local mode="${1:-interactive}" purge_failed=false step_failed=false package
    local -a nginx_packages=(nginx nginx-common nginx-core nginx-full nginx-light nginx-extras)
    local -a installed_nginx_packages=()
    if [[ "$mode" != "silent" ]]; then
        clear; show_banner
        pgy_screen_title "PURGE INTERNAL NGINX" "Remove Nginx and its managed edge configuration." "$C_DANGER"
        if ! command -v nginx &> /dev/null && [[ ! -d /etc/nginx ]] &&
           ! dpkg-query -W -f='${Status}' "${nginx_packages[@]}" 2>/dev/null | grep -q 'install ok installed'; then
            rm -f "$NGINX_PORTS_FILE"
            pgy_message INFO "Nginx is not installed."
            return 0
        fi
        echo -e "\n${C_YELLOW}[WARNING] This removes the internal Nginx proxy on ${NGINX_INTERNAL_HTTP_PORT}/${NGINX_INTERNAL_TLS_PORT}.${C_RESET}"
        if systemctl is-active --quiet haproxy; then
            echo -e "${C_YELLOW}[WARNING] HAProxy will stay installed, but web payload routing from ${EDGE_PUBLIC_HTTP_PORT}/${EDGE_PUBLIC_TLS_PORT} will stop until you reinstall the stack.${C_RESET}"
        fi
        read -p "  Continue and purge Nginx? (y/n): " confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            pgy_message CANCELLED "Uninstallation cancelled."
            return
        fi
    fi

    [[ "$mode" == "silent" ]] || { echo; pgy_section "UNINSTALLATION PROGRESS"; }
    pgy_progress_begin 1 4 "Stopping service"
    systemctl stop nginx.service >/dev/null 2>&1 || true
    systemctl disable nginx.service >/dev/null 2>&1 || true
    if systemctl is-active --quiet nginx.service; then
        purge_failed=true; pgy_progress_failed
    else
        pgy_progress_done
    fi

    pgy_progress_begin 2 4 "Removing service packages"
    step_failed=false
    for package in "${nginx_packages[@]}"; do
        if dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -q 'install ok installed'; then
            installed_nginx_packages+=("$package")
        fi
    done
    if (( ${#installed_nginx_packages[@]} == 0 )); then
        :
    elif pgy_apt_purge "${installed_nginx_packages[@]}" >/dev/null 2>&1; then
        apt-get autoremove -y >>"$PGY_PACKAGE_LOG" 2>&1 || step_failed=true
    else
        step_failed=true
    fi
    if [[ "$step_failed" == true ]]; then
        purge_failed=true; pgy_progress_failed
    else
        pgy_progress_done
    fi

    pgy_progress_begin 3 4 "Removing configuration files"
    if rm -f /etc/ssl/certs/nginx-selfsigned.pem /etc/ssl/private/nginx-selfsigned.key \
        "${NGINX_CONFIG_FILE}.bak" "${NGINX_CONFIG_FILE}.bak.certbot" \
        "${NGINX_CONFIG_FILE}.bak.selfsigned" "${NGINX_CONFIG_FILE}.bak.pgytunnel" \
        "$NGINX_PORTS_FILE" && rm -rf /etc/nginx; then
        pgy_progress_done
    else
        purge_failed=true; pgy_progress_failed
    fi

    pgy_progress_begin 4 4 "Verifying cleanup"
    for package in "${nginx_packages[@]}"; do
        if dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -q 'install ok installed'; then
            purge_failed=true
        fi
    done
    if [[ "$purge_failed" != true && ! -e /etc/nginx ]] &&
       ! systemctl is-active --quiet nginx.service; then
        pgy_progress_done
    else
        pgy_progress_failed
    fi
    if [[ "$purge_failed" == true ]]; then
        [[ "$mode" == "silent" ]] || pgy_message ERROR "Nginx package cleanup requires attention."
        return 1
    fi
    if [[ "$mode" != "silent" ]]; then
        echo -e "\n${C_GREEN}[OK] Internal Nginx proxy purged. Shared certificates were kept.${C_RESET}"
    fi
    return 0
}

install_nginx_proxy() {
    pgy_screen_title "CONFIGURE INTERNAL NGINX" \
        "Backend ports: ${NGINX_INTERNAL_HTTP_PORT}/${NGINX_INTERNAL_TLS_PORT}"
    echo -e "\n${C_CYAN}This keeps HAProxy on ${EDGE_PUBLIC_HTTP_PORT}/${EDGE_PUBLIC_TLS_PORT} and rewrites the internal Nginx proxy on ${NGINX_INTERNAL_HTTP_PORT}/${NGINX_INTERNAL_TLS_PORT}.${C_RESET}"

    if [ ! -s "$PGY_SSL_CERT_FILE" ] || [ ! -s "$SSL_CERT_CHAIN_FILE" ] || [ ! -s "$SSL_CERT_KEY_FILE" ]; then
        echo -e "\n${C_YELLOW}[WARNING] No shared certificate was found.${C_RESET}"
        echo -e "${C_DIM}Running the full HAProxy edge installer so the certificate and both services stay aligned.${C_RESET}"
        install_ssl_tunnel
        return
    fi

    mkdir -p "$DB_DIR" "$SSL_CERT_DIR"
    ensure_edge_stack_packages || return

    systemctl stop haproxy >/dev/null 2>&1
    systemctl stop nginx >/dev/null 2>&1
    sleep 1

    check_and_free_ports \
        "$EDGE_PUBLIC_HTTP_PORT" \
        "$EDGE_PUBLIC_TLS_PORT" \
        "$NGINX_INTERNAL_HTTP_PORT" \
        "$NGINX_INTERNAL_TLS_PORT" \
        "$HAPROXY_INTERNAL_DECRYPT_PORT" || return

    check_and_open_firewall_port "$EDGE_PUBLIC_HTTP_PORT" tcp || return
    check_and_open_firewall_port "$EDGE_PUBLIC_TLS_PORT" tcp || return

    load_edge_cert_info
    local server_name="${EDGE_DOMAIN:-$(detect_preferred_host)}"
    [[ -z "$server_name" ]] && server_name="_"

    configure_edge_stack "$server_name" || return

    echo -e "\n${C_GREEN}[OK] Internal Nginx proxy reconfigured successfully.${C_RESET}"
    echo -e "   • Public HAProxy edge: ${C_YELLOW}${EDGE_PUBLIC_HTTP_PORT}/${EDGE_PUBLIC_TLS_PORT}${C_RESET}"
    echo -e "   • Internal Nginx: ${C_YELLOW}${NGINX_INTERNAL_HTTP_PORT}/${NGINX_INTERNAL_TLS_PORT}${C_RESET}"
}

request_certbot_ssl() {
    pgy_screen_title "SHARED CERTBOT CERTIFICATE" "Apply one certificate to HAProxy and internal Nginx."
    echo -e "\n${C_DIM}This will replace the shared certificate used by HAProxy on ${EDGE_PUBLIC_TLS_PORT} and internal Nginx on ${NGINX_INTERNAL_TLS_PORT}.${C_RESET}"

    mkdir -p "$DB_DIR" "$SSL_CERT_DIR"
    ensure_edge_stack_packages || return
    load_edge_cert_info

    local preferred_host
    local default_domain=""
    local domain_name
    local email

    preferred_host=$(detect_preferred_host)
    if [[ -n "$EDGE_DOMAIN" ]] && ! _is_valid_ipv4 "$EDGE_DOMAIN"; then
        default_domain="$EDGE_DOMAIN"
    elif [[ -n "$preferred_host" ]] && ! _is_valid_ipv4 "$preferred_host"; then
        default_domain="$preferred_host"
    fi

    if [[ -n "$default_domain" ]]; then
        read -p "  Enter your domain name [$default_domain]: " domain_name
        domain_name=${domain_name:-$default_domain}
    else
        read -p "  Enter your domain name (e.g. vpn.example.com): " domain_name
    fi
    if [[ -z "$domain_name" ]]; then
        echo -e "\n${C_RED}[ERROR] Domain name cannot be empty.${C_RESET}"
        return
    fi
    if _is_valid_ipv4 "$domain_name"; then
        echo -e "\n${C_RED}[ERROR] Certbot requires a real domain name, not a raw IP address.${C_RESET}"
        return
    fi

    read -p "  Enter your email for Let's Encrypt [${EDGE_EMAIL}]: " email
    email=${email:-$EDGE_EMAIL}
    if [[ -z "$email" ]]; then
        echo -e "\n${C_RED}[ERROR] Email address cannot be empty.${C_RESET}"
        return
    fi

    check_and_open_firewall_port "$EDGE_PUBLIC_HTTP_PORT" tcp || return
    check_and_open_firewall_port "$EDGE_PUBLIC_TLS_PORT" tcp || return

    obtain_certbot_edge_cert "$domain_name" "$email" || return
    configure_edge_stack "$domain_name" || return

    echo -e "\n${C_GREEN}[OK] Shared Certbot certificate applied successfully.${C_RESET}"
    echo -e "   • Domain: ${C_YELLOW}${domain_name}${C_RESET}"
    echo -e "   • Public edge: ${C_YELLOW}${EDGE_PUBLIC_HTTP_PORT}/${EDGE_PUBLIC_TLS_PORT}${C_RESET}"
}

nginx_proxy_menu() {
    clear; show_banner
    local nginx_status="Inactive" nginx_color="$C_RED"
    local haproxy_status="Inactive" haproxy_color="$C_RED"
    if systemctl is-active --quiet nginx; then
        nginx_status="Active"
        nginx_color="$C_GREEN"
    fi
    if systemctl is-active --quiet haproxy; then
        haproxy_status="Active"
        haproxy_color="$C_GREEN"
    fi

    load_edge_cert_info
    local cert_info="${EDGE_CERT_MODE:-Not configured}"
    if [[ -n "$EDGE_DOMAIN" ]]; then
        cert_info="${cert_info} - ${EDGE_DOMAIN}"
    fi

    echo
    pgy_box_top
    pgy_box_header "INTERNAL NGINX PROXY"
    pgy_box_divider
    pgy_row2 "${C_GRAY}NGINX${C_RESET} ${nginx_color}${nginx_status}${C_RESET}" \
        "${C_GRAY}HAPROXY${C_RESET} ${haproxy_color}${haproxy_status}${C_RESET}"
    pgy_kv2 "PUBLIC" "${EDGE_PUBLIC_HTTP_PORT}/${EDGE_PUBLIC_TLS_PORT}" "INTERNAL" "${NGINX_INTERNAL_HTTP_PORT}/${NGINX_INTERNAL_TLS_PORT}"
    pgy_row "${C_GRAY}CERTIFICATE${C_RESET} ${C_WHITE}${cert_info}${C_RESET}"
    pgy_box_divider
    if systemctl is-active --quiet nginx; then
         pgy_menu1 "[ 1]" "Stop Nginx Service"
         pgy_menu1 "[ 2]" "Restart HAProxy and Nginx Stack"
         pgy_menu1 "[ 3]" "Reinstall or Reconfigure Edge Stack"
         pgy_menu1 "[ 4]" "Switch or Renew Shared SSL"
         pgy_menu1 "[ 5]" "Uninstall and Purge Nginx"
    else
         pgy_menu1 "[ 1]" "Start Nginx Service"
         pgy_menu1 "[ 3]" "Install or Configure Edge Stack"
         pgy_menu1 "[ 4]" "Switch or Renew Shared SSL"
         pgy_menu1 "[ 5]" "Uninstall and Purge Nginx"
    fi
    pgy_box_divider
    pgy_menu1 "[ 0]" "Return to Previous Menu"
    pgy_box_bot
    echo
    read -r -p "$(echo -e "${C_PROMPT}  Select an option: ${C_RESET}")" choice
    
    case $choice in
        1) 
            if systemctl is-active --quiet nginx; then
                echo -e "\n${C_BLUE}Stopping Nginx...${C_RESET}"
                systemctl stop nginx >/dev/null 2>&1
                echo -e "${C_GREEN}[OK] Nginx stopped.${C_RESET}"
                if systemctl is-active --quiet haproxy; then
                    echo -e "${C_YELLOW}[WARNING] HAProxy is still running, but web traffic that depends on internal Nginx will not work until Nginx starts again.${C_RESET}"
                fi
            else
                echo -e "\n${C_BLUE}[INFO] Starting Nginx...${C_RESET}"
                systemctl start nginx >/dev/null 2>&1
                if systemctl is-active --quiet nginx; then
                    echo -e "${C_GREEN}[OK] Nginx started.${C_RESET}"
                else
                    echo -e "${C_RED}[ERROR] Failed to start Nginx.${C_RESET}"
                fi
            fi
            press_enter
            ;;
        2)
            echo -e "\n${C_BLUE}Restarting Nginx and HAProxy...${C_RESET}"
            local restart_ok=true
            systemctl restart nginx >/dev/null 2>&1 || restart_ok=false
            if command -v haproxy &> /dev/null; then
                systemctl restart haproxy >/dev/null 2>&1 || restart_ok=false
            else
                restart_ok=false
            fi
            if $restart_ok && systemctl is-active --quiet nginx && systemctl is-active --quiet haproxy; then
                echo -e "${C_GREEN}[OK] HAProxy + Nginx stack restarted.${C_RESET}"
            else
                echo -e "${C_RED}[ERROR] One or more services failed to restart.${C_RESET}"
            fi
            press_enter
            ;;
        3) 
             pgy_run_action install_nginx_proxy
             ;;
        4)
             pgy_run_action request_certbot_ssl
             ;;
        5)
             pgy_run_action purge_nginx
             ;;
        0) return ;;
        *) invalid_option ;;
    esac
}

