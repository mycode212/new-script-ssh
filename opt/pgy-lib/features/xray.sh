#!/bin/bash
# ============================================================
# Auto Script SSH By : ProgoCloud
# Module: features/xray.sh - Xray-Core Engine & Multi-Protocol
# ============================================================

XRAY_BIN="/usr/local/bin/xray"
XRAY_SHARE_DIR="/usr/local/share/xray"
XRAY_DIR="/etc/xray"
XRAY_CONF="${XRAY_DIR}/config.json"
XRAY_USERS_DB="${XRAY_DIR}/users.json"
XRAY_SERVICE="/etc/systemd/system/xray.service"

# Internal ports for Xray inbounds behind HAProxy / Nginx
PORT_XRAY_VMESS=10001
PORT_XRAY_VLESS=10002
PORT_XRAY_TROJAN=10003
PORT_XRAY_VMESS_GRPC=10005
PORT_XRAY_VLESS_GRPC=10006
PORT_XRAY_TROJAN_GRPC=10007
PORT_XRAY_SS=10008

pgy_xray_arch() {
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64|amd64) echo "64" ;;
        aarch64|arm64) echo "arm64-v8a" ;;
        armv7l|armhf) echo "arm32-v7a" ;;
        *) echo "64" ;;
    esac
}

_pgy_xray_download_binaries() {
    local arch
    arch=$(pgy_xray_arch)
    mkdir -p /tmp/pgy-xray-install "$XRAY_SHARE_DIR" "$XRAY_DIR"

    # 1. Download official Xray-core
    local xray_tag="v1.8.24"
    local xray_url="https://github.com/XTLS/Xray-core/releases/download/${xray_tag}/Xray-linux-${arch}.zip"
    curl -fsSL --connect-timeout 10 --max-time 90 "$xray_url" -o /tmp/pgy-xray-install/xray.zip 2>/dev/null || return 1
    unzip -q -o /tmp/pgy-xray-install/xray.zip -d /tmp/pgy-xray-install/

    if [[ -f "/tmp/pgy-xray-install/xray" ]]; then
        install -m 755 /tmp/pgy-xray-install/xray "$XRAY_BIN"
    else
        return 1
    fi

    # 2. Assets geoip & geosite
    if [[ -f "/tmp/pgy-xray-install/geoip.dat" ]]; then
        install -m 644 /tmp/pgy-xray-install/geoip.dat "$XRAY_SHARE_DIR/geoip.dat"
        install -m 644 /tmp/pgy-xray-install/geoip.dat "$XRAY_DIR/geoip.dat"
    fi
    if [[ -f "/tmp/pgy-xray-install/geosite.dat" ]]; then
        install -m 644 /tmp/pgy-xray-install/geosite.dat "$XRAY_SHARE_DIR/geosite.dat"
        install -m 644 /tmp/pgy-xray-install/geosite.dat "$XRAY_DIR/geosite.dat"
    fi

    rm -rf /tmp/pgy-xray-install
    return 0
}

pgy_xray_install_binaries() {
    if ! command -v xray >/dev/null 2>&1; then
        if declare -F run_step_with_spinner >/dev/null 2>&1; then
            run_step_with_spinner "Mengunduh Xray Core & GeoIP/GeoSite" _pgy_xray_download_binaries
        else
            echo -e "${C_INFO}  Mengunduh Xray Core...${C_RESET}"
            _pgy_xray_download_binaries
        fi
    fi
}

pgy_xray_init_database() {
    mkdir -p "$XRAY_DIR"
    if [[ ! -s "$XRAY_USERS_DB" ]]; then
        echo "[]" > "$XRAY_USERS_DB"
    fi
}

pgy_xray_generate_base_config() {
    mkdir -p "$XRAY_DIR"
    cat <<EOF > "$XRAY_CONF"
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "tag": "vmess-ws-in",
      "port": ${PORT_XRAY_VMESS},
      "listen": "127.0.0.1",
      "protocol": "vmess",
      "settings": {
        "clients": []
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/vmess"
        }
      }
    },
    {
      "tag": "vless-ws-in",
      "port": ${PORT_XRAY_VLESS},
      "listen": "127.0.0.1",
      "protocol": "vless",
      "settings": {
        "clients": [],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/vless"
        }
      }
    },
    {
      "tag": "trojan-ws-in",
      "port": ${PORT_XRAY_TROJAN},
      "listen": "127.0.0.1",
      "protocol": "trojan",
      "settings": {
        "clients": []
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/trojan"
        }
      }
    },
    {
      "tag": "vmess-grpc-in",
      "port": ${PORT_XRAY_VMESS_GRPC},
      "listen": "127.0.0.1",
      "protocol": "vmess",
      "settings": {
        "clients": []
      },
      "streamSettings": {
        "network": "grpc",
        "grpcSettings": {
          "serviceName": "vmess-grpc"
        }
      }
    },
    {
      "tag": "vless-grpc-in",
      "port": ${PORT_XRAY_VLESS_GRPC},
      "listen": "127.0.0.1",
      "protocol": "vless",
      "settings": {
        "clients": [],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "grpc",
        "grpcSettings": {
          "serviceName": "vless-grpc"
        }
      }
    },
    {
      "tag": "trojan-grpc-in",
      "port": ${PORT_XRAY_TROJAN_GRPC},
      "listen": "127.0.0.1",
      "protocol": "trojan",
      "settings": {
        "clients": []
      },
      "streamSettings": {
        "network": "grpc",
        "grpcSettings": {
          "serviceName": "trojan-grpc"
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    },
    {
      "protocol": "socks",
      "tag": "warp",
      "settings": {
        "servers": [
          {
            "address": "127.0.0.1",
            "port": 40000
          }
        ]
      }
    },
    {
      "protocol": "blackhole",
      "tag": "blocked"
    }
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type": "field",
        "outboundTag": "blocked",
        "domain": [
          "geosite:category-ads-all"
        ]
      },
      {
        "type": "field",
        "outboundTag": "warp",
        "domain": [
          "geosite:netflix",
          "geosite:openai",
          "geosite:disney",
          "geosite:spotify",
          "geosite:reddit",
          "domain:fast.com"
        ]
      },
      {
        "type": "field",
        "outboundTag": "direct",
        "ip": [
          "geoip:private"
        ]
      },
      {
        "type": "field",
        "outboundTag": "direct",
        "network": "tcp,udp"
      }
    ]
  }
}
EOF
    chmod 644 "$XRAY_CONF"
}

pgy_xray_install_service() {
    cat <<EOF > "$XRAY_SERVICE"
[Unit]
Description=ProgoCloud Xray Core Multi-Protocol Service
Documentation=https://github.com/xtls
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=${XRAY_BIN} run -config ${XRAY_CONF}
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload >/dev/null 2>&1 || true
    systemctl enable xray.service >/dev/null 2>&1 || true
}

pgy_xray_sync_users_to_config() {
    pgy_xray_init_database
    [[ ! -f "$XRAY_CONF" ]] && pgy_xray_generate_base_config

    python3 - <<'PY' "$XRAY_USERS_DB" "$XRAY_CONF"
import json
import sys

db_path, conf_path = sys.argv[1], sys.argv[2]

try:
    with open(db_path, "r", encoding="utf-8") as f:
        users = json.load(f)
except Exception:
    users = []

try:
    with open(conf_path, "r", encoding="utf-8") as f:
        cfg = json.load(f)
except Exception:
    sys.exit(1)

vmess_clients = []
vless_clients = []
trojan_clients = []

import time
now_ts = int(time.time())

for u in users:
    exp_ts = u.get("exp_ts", 0)
    # If expired, skip loading into active inbounds
    if exp_ts > 0 and exp_ts < now_ts:
        continue

    uuid_str = u.get("uuid", "")
    username = u.get("username", "")
    proto = u.get("protocol", "all").lower()

    if proto in ("vmess", "all"):
        vmess_clients.append({"id": uuid_str, "alterId": 0, "email": username})
    if proto in ("vless", "all"):
        vless_clients.append({"id": uuid_str, "email": username, "flow": ""})
    if proto in ("trojan", "all"):
        trojan_clients.append({"password": uuid_str, "email": username})

for ib in cfg.get("inbounds", []):
    tag = ib.get("tag", "")
    if "vmess" in tag:
        ib.setdefault("settings", {})["clients"] = vmess_clients
    elif "vless" in tag:
        ib.setdefault("settings", {})["clients"] = vless_clients
    elif "trojan" in tag:
        ib.setdefault("settings", {})["clients"] = trojan_clients

with open(conf_path, "w", encoding="utf-8") as f:
    json.dump(cfg, f, indent=2)
PY

    if pgy_xray_is_active; then
        systemctl restart xray.service >/dev/null 2>&1 || true
    fi
}

pgy_xray_is_active() {
    systemctl is-active --quiet xray.service 2>/dev/null
}

pgy_xray_get_status() {
    if pgy_xray_is_active; then
        local user_count=0
        if [[ -f "$XRAY_USERS_DB" ]]; then
            user_count=$(grep -o '"username"' "$XRAY_USERS_DB" | wc -l)
        fi
        echo "Active (${user_count} Akun Terdaftar)"
    else
        echo "Inactive"
    fi
}

pgy_xray_user_add() {
    local username="$1" proto="${2:-all}" exp_days="${3:-30}" quota_gb="${4:-0}"
    [[ -z "$username" ]] && return 1

    pgy_xray_init_database
    local uuid_val
    uuid_val=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || openssl rand -hex 16)
    local exp_ts=$(( $(date +%s) + (exp_days * 86400) ))

    python3 - <<'PY' "$XRAY_USERS_DB" "$username" "$proto" "$uuid_val" "$exp_ts" "$quota_gb"
import json
import sys

db_path, user, proto, uuid_v, exp_ts, quota_gb = sys.argv[1:7]

try:
    with open(db_path, "r", encoding="utf-8") as f:
        db = json.load(f)
except Exception:
    db = []

# Remove existing if any
db = [x for x in db if x.get("username") != user]
db.append({
    "username": user,
    "protocol": proto,
    "uuid": uuid_v,
    "exp_ts": int(exp_ts),
    "quota_gb": int(quota_gb),
    "created_at": int(__import__("time").time())
})

with open(db_path, "w", encoding="utf-8") as f:
    json.dump(db, f, indent=2)
PY

    pgy_xray_sync_users_to_config
    return 0
}

pgy_xray_user_del() {
    local username="$1"
    [[ -z "$username" || ! -f "$XRAY_USERS_DB" ]] && return 1

    python3 - <<'PY' "$XRAY_USERS_DB" "$username"
import json
import sys
db_path, user = sys.argv[1], sys.argv[2]
try:
    with open(db_path, "r", encoding="utf-8") as f:
        db = json.load(f)
    db = [x for x in db if x.get("username") != user]
    with open(db_path, "w", encoding="utf-8") as f:
        json.dump(db, f, indent=2)
except Exception:
    pass
PY
    pgy_xray_sync_users_to_config
    return 0
}

pgy_xray_user_renew() {
    local username="$1" add_days="${2:-30}"
    [[ -z "$username" || ! -f "$XRAY_USERS_DB" ]] && return 1

    python3 - <<'PY' "$XRAY_USERS_DB" "$username" "$add_days"
import json, sys, time
db_path, user, days = sys.argv[1], sys.argv[2], int(sys.argv[3])
try:
    with open(db_path, "r", encoding="utf-8") as f:
        db = json.load(f)
    for u in db:
        if u.get("username") == user:
            cur_exp = u.get("exp_ts", int(time.time()))
            base = max(cur_exp, int(time.time()))
            u["exp_ts"] = base + (days * 86400)
    with open(db_path, "w", encoding="utf-8") as f:
        json.dump(db, f, indent=2)
except Exception:
    pass
PY
    pgy_xray_sync_users_to_config
    return 0
}

pgy_xray_client_config_show() {
    local username="$1"
    [[ -z "$username" || ! -f "$XRAY_USERS_DB" ]] && return 1

    local domain_host
    domain_host=$(get_domain_or_ip 2>/dev/null || curl -s -4 icanhazip.com || echo "127.0.0.1")

    python3 - <<'PY' "$XRAY_USERS_DB" "$username" "$domain_host"
import json
import sys
import base64
import time

db_path, user, domain = sys.argv[1:4]

try:
    with open(db_path, "r", encoding="utf-8") as f:
        db = json.load(f)
except Exception:
    db = []

target = next((x for x in db if x.get("username") == user), None)
if not target:
    print(f"User {user} tidak ditemukan.")
    sys.exit(1)

uuid_v = target.get("uuid", "")
proto = target.get("protocol", "all")
exp_ts = target.get("exp_ts", 0)
exp_date = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(exp_ts)) if exp_ts else "Lifetime"

# 1. VMess WS link
vmess_obj = {
    "v": "2",
    "ps": f"ProgoCloud-VMess-{user}",
    "add": domain,
    "port": "443",
    "id": uuid_v,
    "aid": "0",
    "net": "ws",
    "type": "none",
    "host": domain,
    "path": "/vmess",
    "tls": "tls",
    "sni": domain
}
vmess_json = json.dumps(vmess_obj)
vmess_link = "vmess://" + base64.b64encode(vmess_json.encode("utf-8")).decode("utf-8")

# 2. VLess WS link
vless_link = f"vless://{uuid_v}@{domain}:443?path=%2Fvless&security=tls&encryption=none&type=ws&sni={domain}#ProgoCloud-VLess-{user}"

# 3. Trojan WS link
trojan_link = f"trojan://{uuid_v}@{domain}:443?path=%2Ftrojan&security=tls&type=ws&sni={domain}#ProgoCloud-Trojan-{user}"

# 4. VLess gRPC link
vless_grpc_link = f"vless://{uuid_v}@{domain}:443?mode=gun&security=tls&encryption=none&type=grpc&serviceName=vless-grpc&sni={domain}#ProgoCloud-VLess-gRPC-{user}"

print("=" * 60)
print(f"DETAIL AKUN XRAY {proto.upper()}: {user.upper()}")
print(f"Domain / Host : {domain}")
print(f"Port / TLS    : 443 (TLS Enabled)")
print(f"UUID / Pass   : {uuid_v}")
print(f"Expired Date  : {exp_date}")
print("=" * 60)

if proto in ("vmess", "all"):
    print("\n[ LINK VMESS WS TLS ]")
    print(vmess_link)
    vmess_grpc_obj = dict(vmess_obj, net="grpc", path="vmess-grpc")
    vmess_grpc_link = "vmess://" + base64.b64encode(json.dumps(vmess_grpc_obj).encode("utf-8")).decode("utf-8")
    print("\n[ LINK VMESS gRPC TLS ]")
    print(vmess_grpc_link)

if proto in ("vless", "all"):
    print("\n[ LINK VLESS WS TLS ]")
    print(vless_link)
    print("\n[ LINK VLESS gRPC TLS ]")
    print(vless_grpc_link)

if proto in ("trojan", "all"):
    print("\n[ LINK TROJAN WS TLS ]")
    print(trojan_link)
    trojan_grpc_link = f"trojan://{uuid_v}@{domain}:443?mode=gun&security=tls&type=grpc&serviceName=trojan-grpc&sni={domain}#ProgoCloud-Trojan-gRPC-{user}"
    print("\n[ LINK TROJAN gRPC TLS ]")
    print(trojan_grpc_link)

print("=" * 60)
PY
}

pgy_xray_toggle() {
    if pgy_xray_is_active; then
        systemctl stop xray.service >/dev/null 2>&1 || true
        systemctl disable xray.service >/dev/null 2>&1 || true
        echo -e "${C_WARN}  Xray Core Service telah Dinonaktifkan.${C_RESET}"
    else
        pgy_xray_install_binaries
        if [[ ! -f "$XRAY_CONF" ]]; then
            pgy_xray_generate_base_config
        fi
        pgy_xray_install_service
        pgy_xray_sync_users_to_config
        systemctl start xray.service >/dev/null 2>&1 || true
        echo -e "${C_GREEN}  Xray Core Service telah Diaktifkan.${C_RESET}"
    fi
}
