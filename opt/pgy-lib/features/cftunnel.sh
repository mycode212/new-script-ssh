#!/bin/bash
# ============================================================
# Auto Script SSH By : ProgoCloud
# Module: features/cftunnel.sh - Cloudflare Tunnel (cloudflared) Controller
# ============================================================

PGY_CFTUNNEL_BIN="/usr/local/bin/cloudflared"
PGY_CFTUNNEL_CONFIG_FILE="/etc/pgytunnel/cf_tunnel.conf"
PGY_CFTUNNEL_SERVICE_NAME="cloudflared"

pgy_cftunnel_arch() {
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64|amd64) echo "amd64" ;;
        aarch64|arm64) echo "arm64" ;;
        armv7l|armhf) echo "arm" ;;
        i386|i686) echo "386" ;;
        *) echo "amd64" ;;
    esac
}

pgy_cftunnel_init_config() {
    mkdir -p "/etc/pgytunnel"
    if [[ ! -f "$PGY_CFTUNNEL_CONFIG_FILE" ]]; then
        cat > "$PGY_CFTUNNEL_CONFIG_FILE" <<EOF
# Cloudflare Tunnel Configuration
CF_TUNNEL_ENABLED=0
CF_TUNNEL_TOKEN=
CF_TUNNEL_VPN_DOMAIN=
CF_TUNNEL_API_DOMAIN=
EOF
        chmod 600 "$PGY_CFTUNNEL_CONFIG_FILE"
    fi
}

pgy_cftunnel_get_config_val() {
    local key="$1" default_val="${2:-}"
    pgy_cftunnel_init_config
    local val
    val=$(grep "^${key}=" "$PGY_CFTUNNEL_CONFIG_FILE" 2>/dev/null | cut -d'=' -f2- | tr -d '"'\'' ')
    echo "${val:-$default_val}"
}

pgy_cftunnel_set_config_val() {
    local key="$1" value="$2"
    pgy_cftunnel_init_config
    if grep -q "^${key}=" "$PGY_CFTUNNEL_CONFIG_FILE" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${value}|" "$PGY_CFTUNNEL_CONFIG_FILE"
    else
        echo "${key}=${value}" >> "$PGY_CFTUNNEL_CONFIG_FILE"
    fi
}

pgy_cftunnel_ensure_binary() {
    if [[ -x "$PGY_CFTUNNEL_BIN" ]]; then
        return 0
    fi
    if command -v cloudflared >/dev/null 2>&1; then
        PGY_CFTUNNEL_BIN="$(command -v cloudflared)"
        return 0
    fi

    local arch url tmp_bin="/tmp/cloudflared_download"
    arch=$(pgy_cftunnel_arch)
    url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${arch}"

    if curl -fsSL --connect-timeout 10 --max-time 60 "$url" -o "$tmp_bin" 2>/dev/null; then
        install -m 755 "$tmp_bin" "$PGY_CFTUNNEL_BIN" 2>/dev/null || true
        rm -f "$tmp_bin"
        return 0
    fi

    # Fallback to deb package
    local deb_url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${arch}.deb"
    if curl -fsSL --connect-timeout 10 --max-time 60 "$deb_url" -o "/tmp/cloudflared.deb" 2>/dev/null; then
        dpkg -i "/tmp/cloudflared.deb" >/dev/null 2>&1 || true
        rm -f "/tmp/cloudflared.deb"
        if command -v cloudflared >/dev/null 2>&1; then
            return 0
        fi
    fi

    return 1
}

pgy_cftunnel_service_status() {
    if systemctl is-active --quiet "$PGY_CFTUNNEL_SERVICE_NAME" 2>/dev/null; then
        echo "active"
    elif systemctl is-enabled --quiet "$PGY_CFTUNNEL_SERVICE_NAME" 2>/dev/null; then
        echo "stopped"
    else
        echo "disabled"
    fi
}

pgy_cftunnel_install_service_token() {
    local token="$1"
    [[ -z "$token" ]] && return 1

    pgy_cftunnel_ensure_binary || return 1
    pgy_cftunnel_init_config

    # Stop old service if exists
    systemctl stop "$PGY_CFTUNNEL_SERVICE_NAME" >/dev/null 2>&1 || true
    "$PGY_CFTUNNEL_BIN" service uninstall >/dev/null 2>&1 || true

    # Install systemd service with token
    if "$PGY_CFTUNNEL_BIN" service install "$token" >/dev/null 2>&1; then
        systemctl daemon-reload >/dev/null 2>&1 || true
        systemctl enable "$PGY_CFTUNNEL_SERVICE_NAME" >/dev/null 2>&1 || true
        systemctl restart "$PGY_CFTUNNEL_SERVICE_NAME" >/dev/null 2>&1 || true
        pgy_cftunnel_set_config_val "CF_TUNNEL_ENABLED" "1"
        pgy_cftunnel_set_config_val "CF_TUNNEL_TOKEN" "$token"
        return 0
    fi
    return 1
}

pgy_cftunnel_start() {
    pgy_cftunnel_ensure_binary || return 1
    systemctl enable "$PGY_CFTUNNEL_SERVICE_NAME" >/dev/null 2>&1 || true
    systemctl restart "$PGY_CFTUNNEL_SERVICE_NAME" >/dev/null 2>&1 || true
    pgy_cftunnel_set_config_val "CF_TUNNEL_ENABLED" "1"
}

pgy_cftunnel_stop() {
    systemctl stop "$PGY_CFTUNNEL_SERVICE_NAME" >/dev/null 2>&1 || true
    pgy_cftunnel_set_config_val "CF_TUNNEL_ENABLED" "0"
}

pgy_cftunnel_restart() {
    systemctl restart "$PGY_CFTUNNEL_SERVICE_NAME" >/dev/null 2>&1 || true
}

pgy_cftunnel_uninstall() {
    systemctl stop "$PGY_CFTUNNEL_SERVICE_NAME" >/dev/null 2>&1 || true
    if command -v cloudflared >/dev/null 2>&1; then
        cloudflared service uninstall >/dev/null 2>&1 || true
    elif [[ -x "$PGY_CFTUNNEL_BIN" ]]; then
        "$PGY_CFTUNNEL_BIN" service uninstall >/dev/null 2>&1 || true
    fi
    rm -f "$PGY_CFTUNNEL_BIN" "$PGY_CFTUNNEL_CONFIG_FILE"
    rm -f "/etc/systemd/system/cloudflared.service"
    systemctl daemon-reload >/dev/null 2>&1 || true
}

# ============================================================
# Cloudflare API Full Automation Worker
# ============================================================

pgy_cftunnel_cf_api_worker() {
    python3 -c '
import sys, json, urllib.request, urllib.error, base64, secrets, socket

def make_req(url, method="GET", headers=None, data=None):
    if headers is None:
        headers = {}
    headers["Content-Type"] = "application/json"
    headers["Accept"] = "application/json"
    body = json.dumps(data).encode("utf-8") if data is not None else None
    req = urllib.request.Request(url, data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            return resp.getcode(), json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read().decode("utf-8"))
        except Exception:
            return e.code, {"success": False, "errors": [{"message": str(e)}]}
    except Exception as e:
        return 0, {"success": False, "errors": [{"message": str(e)}]}

def main():
    if len(sys.argv) < 5:
        print(json.dumps({"success": False, "message": "Argumen tidak lengkap"}))
        return

    auth_type = sys.argv[1] # "token" or "global"
    auth_val = sys.argv[2]  # token string or Global API Key
    auth_email = sys.argv[3] # email if global, otherwise empty
    domain = sys.argv[4].strip().lower()
    vpn_sub = sys.argv[5].strip().lower() if len(sys.argv) > 5 and sys.argv[5] else "vpn"
    api_sub = sys.argv[6].strip().lower() if len(sys.argv) > 6 and sys.argv[6] else "api"
    tunnel_name_prefix = sys.argv[7].strip() if len(sys.argv) > 7 and sys.argv[7] else "pgytunnel"

    headers = {}
    if auth_type == "token":
        headers["Authorization"] = f"Bearer {auth_val}"
    else:
        headers["X-Auth-Key"] = auth_val
        headers["X-Auth-Email"] = auth_email

    # 1. Get Zone Info & Account ID
    code, res = make_req(f"https://api.cloudflare.com/client/v4/zones?name={domain}", "GET", headers)
    if not res.get("success") or not res.get("result"):
        errs = res.get("errors", [])
        msg = errs[0].get("message") if errs else "Domain tidak ditemukan di akun Cloudflare ini"
        print(json.dumps({"success": False, "step": "zone", "message": msg}))
        return

    zone_data = res["result"][0]
    zone_id = zone_data["id"]
    account_id = zone_data.get("account", {}).get("id")

    if not account_id:
        print(json.dumps({"success": False, "step": "account", "message": "Account ID Cloudflare tidak terdeteksi dari zone"}))
        return

    # 2. Check if a tunnel with same name exists or create a new one
    hostname = socket.gethostname() or "vps"
    tunnel_name = f"{tunnel_name_prefix}-{hostname}"[:32]
    tunnel_secret = base64.b64encode(secrets.token_bytes(32)).decode("utf-8")

    # Search existing tunnel
    code, res = make_req(f"https://api.cloudflare.com/client/v4/accounts/{account_id}/tunnels?name={tunnel_name}&is_deleted=false", "GET", headers)
    tunnel_id = None
    tunnel_token = None

    if res.get("success") and res.get("result"):
        tunnel_id = res["result"][0]["id"]
        # Fetch token for existing tunnel
        code_t, res_t = make_req(f"https://api.cloudflare.com/client/v4/accounts/{account_id}/tunnels/{tunnel_id}/token", "GET", headers)
        if res_t.get("success") and res_t.get("result"):
            tunnel_token = res_t["result"]
    
    if not tunnel_id or not tunnel_token:
        # Create fresh tunnel
        create_payload = {
            "name": tunnel_name,
            "tunnel_secret": tunnel_secret,
            "config_src": "cloudflare"
        }
        code, res = make_req(f"https://api.cloudflare.com/client/v4/accounts/{account_id}/tunnels", "POST", headers, create_payload)
        if not res.get("success") or not res.get("result"):
            errs = res.get("errors", [])
            msg = errs[0].get("message") if errs else f"Gagal membuat tunnel (HTTP {code})"
            print(json.dumps({"success": False, "step": "create_tunnel", "message": msg}))
            return
        tunnel_id = res["result"]["id"]
        tunnel_token = res["result"].get("token")
        if not tunnel_token:
            code_t, res_t = make_req(f"https://api.cloudflare.com/client/v4/accounts/{account_id}/tunnels/{tunnel_id}/token", "GET", headers)
            if res_t.get("success"):
                tunnel_token = res_t.get("result")

    if not tunnel_token:
        print(json.dumps({"success": False, "step": "tunnel_token", "message": "Gagal mendapatkan connector token tunnel"}))
        return

    # 3. Configure Ingress Rules on Tunnel
    vpn_full_domain = f"{vpn_sub}.{domain}" if vpn_sub != "@" else domain
    api_full_domain = f"{api_sub}.{domain}" if api_sub != "@" else domain

    ingress_payload = {
        "config": {
            "ingress": [
                {
                    "hostname": vpn_full_domain,
                    "service": "http://localhost:1180"
                },
                {
                    "hostname": api_full_domain,
                    "service": "http://localhost:8780"
                },
                {
                    "service": "http_status:404"
                }
            ]
        }
    }
    code, res = make_req(f"https://api.cloudflare.com/client/v4/accounts/{account_id}/cfd_tunnel/{tunnel_id}/configurations", "PUT", headers, ingress_payload)
    if not res.get("success"):
        errs = res.get("errors", [])
        msg = errs[0].get("message") if errs else f"Gagal menerapkan konfigurasi routing ingress (HTTP {code})"
        print(json.dumps({"success": False, "step": "ingress", "message": msg}))
        return

    # 4. Create or Update DNS CNAME Records for both subdomains
    target_cname = f"{tunnel_id}.cfargotunnel.com"

    for sub_name in (vpn_full_domain, api_full_domain):
        code_d, res_d = make_req(f"https://api.cloudflare.com/client/v4/zones/{zone_id}/dns_records?name={sub_name}", "GET", headers)
        dns_payload = {
            "type": "CNAME",
            "name": sub_name,
            "content": target_cname,
            "ttl": 1,
            "proxied": True
        }
        if res_d.get("success") and res_d.get("result"):
            # Update existing record
            rec_id = res_d["result"][0]["id"]
            code_u, res_u = make_req(f"https://api.cloudflare.com/client/v4/zones/{zone_id}/dns_records/{rec_id}", "PUT", headers, dns_payload)
        else:
            # Create record
            code_c, res_c = make_req(f"https://api.cloudflare.com/client/v4/zones/{zone_id}/dns_records", "POST", headers, dns_payload)

    print(json.dumps({
        "success": True,
        "tunnel_id": tunnel_id,
        "tunnel_token": tunnel_token,
        "vpn_domain": vpn_full_domain,
        "api_domain": api_full_domain,
        "account_id": account_id
    }))

if __name__ == "__main__":
    main()
' "$@"
}
