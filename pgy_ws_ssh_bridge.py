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

