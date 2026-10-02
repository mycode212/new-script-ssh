#!/usr/bin/env python3
"""
============================================================
Auto Script SSH By : ProgoCloud
Module: pgy_api_service.py - REST API Daemon for VPS & User Automation
============================================================
Lightweight Python 3 HTTP daemon for integrating reseller panels,
billing bots (Telegram/WhatsApp), and external web dashboards.
Zero external dependencies, running on standard library only.
"""

import os
import sys
import json
import time
import hmac
import re
import socket
import subprocess
import ipaddress
import urllib.parse
import base64
import uuid
from http.server import HTTPServer, BaseHTTPRequestHandler
from socketserver import ThreadingMixIn
from pathlib import Path
from typing import Dict, List, Optional, Tuple, Any

# ============================================================
# Paths & Default Configuration
# ============================================================
def get_config_file() -> Path:
    return Path(os.environ.get("PGY_API_CONFIG", "/etc/pgytunnel/db/api_config.conf"))

def get_db_file() -> Path:
    return Path(os.environ.get("PGY_DB_FILE", "/etc/pgytunnel/users.db"))

def get_manual_lock_file() -> Path:
    return Path(os.environ.get("PGY_MANUAL_LOCK_FILE", "/etc/pgytunnel/manual-locks.db"))

def get_bandwidth_dir() -> Path:
    return Path(os.environ.get("PGY_BW_DIR", "/etc/pgytunnel/bandwidth"))

def get_domain_file() -> Path:
    return Path(os.environ.get("PGY_DOMAIN_FILE", "/etc/pgytunnel/domain.conf"))

def get_xray_users_file() -> Path:
    return Path(os.environ.get("PGY_XRAY_USERS_FILE", "/etc/xray/users.json"))

def get_xray_config_file() -> Path:
    return Path(os.environ.get("PGY_XRAY_CONFIG_FILE", "/etc/xray/config.json"))

def is_dry_run() -> bool:
    return os.environ.get("PGY_DRY_RUN", "0") == "1"

SAFE_USERNAME = re.compile(r"^[A-Za-z0-9_][A-Za-z0-9_-]{1,31}$")


class RateLimiter:
    """Sliding-window rate limiter per client IP address."""
    def __init__(self, max_requests: int = 60, window_seconds: int = 60):
        self.max_requests = max_requests
        self.window_seconds = window_seconds
        self.requests: Dict[str, List[float]] = {}

    def is_allowed(self, ip: str) -> bool:
        now = time.time()
        window_start = now - self.window_seconds
        
        # Prune old timestamps
        history = self.requests.get(ip, [])
        history = [ts for ts in history if ts > window_start]
        
        if len(history) >= self.max_requests:
            self.requests[ip] = history
            return False
            
        history.append(now)
        self.requests[ip] = history
        return True


rate_limiter = RateLimiter(max_requests=60, window_seconds=60)


def load_api_config() -> Dict[str, Any]:
    """Load configuration from file or fallback to environment variables."""
    cfg = {
        "API_ENABLED": "1",
        "API_PORT": "8780",
        "API_KEY": "",
        "ALLOWED_IPS": "ALL",
        "RATE_LIMIT": "60",
    }
    
    cfg_file = get_config_file()
    if cfg_file.is_file():
        try:
            with cfg_file.open("r", encoding="utf-8", errors="replace") as f:
                for line in f:
                    line = line.strip()
                    if not line or line.startswith("#") or "=" not in line:
                        continue
                    k, v = line.split("=", 1)
                    cfg[k.strip()] = v.strip().strip('"\'')
        except Exception:
            pass

    # Environment variables override config file
    if "PGY_API_PORT" in os.environ:
        cfg["API_PORT"] = os.environ["PGY_API_PORT"]
    if "PGY_API_KEY" in os.environ:
        cfg["API_KEY"] = os.environ["PGY_API_KEY"]
    if "PGY_ALLOWED_IPS" in os.environ:
        cfg["ALLOWED_IPS"] = os.environ["PGY_ALLOWED_IPS"]
    if "PGY_RATE_LIMIT" in os.environ:
        cfg["RATE_LIMIT"] = os.environ["PGY_RATE_LIMIT"]

    try:
        cfg["PORT_INT"] = int(cfg["API_PORT"])
    except ValueError:
        cfg["PORT_INT"] = 8780

    return cfg


def is_ip_allowed(client_ip: str, allowed_ips_str: str) -> bool:
    """Check if client IP is within the whitelist."""
    if not allowed_ips_str or allowed_ips_str.strip().upper() in ("ALL", "*", ""):
        return True
    
    clean_client_ip = client_ip.strip()
    # Normalize IPv6 mapped IPv4
    if clean_client_ip.startswith("::ffff:"):
        clean_client_ip = clean_client_ip[7:]

    try:
        client_obj = ipaddress.ip_address(clean_client_ip)
    except ValueError:
        return False

    for rule in allowed_ips_str.split(","):
        rule = rule.strip()
        if not rule:
            continue
        try:
            if "/" in rule:
                if client_obj in ipaddress.ip_network(rule, strict=False):
                    return True
            else:
                if client_obj == ipaddress.ip_address(rule):
                    return True
        except ValueError:
            continue
            
    return False


def verify_api_key(header_key: Optional[str], expected_key: str) -> bool:
    """Constant-time comparison for API keys."""
    if not expected_key:
        return False
    if not header_key:
        return False
    # Support "Bearer <token>" or raw token
    if header_key.lower().startswith("bearer "):
        header_key = header_key[7:].strip()
    return hmac.compare_digest(header_key, expected_key)


# ============================================================
# User DB & System Helpers
# ============================================================
def load_all_users() -> List[Dict[str, Any]]:
    """Parse users.db and return a list of user dicts."""
    users = []
    locked_set = set()
    lock_file = get_manual_lock_file()
    if lock_file.is_file():
        try:
            with lock_file.open("r", encoding="utf-8", errors="replace") as f:
                locked_set = {line.strip() for line in f if line.strip()}
        except Exception:
            pass

    db_file = get_db_file()
    if not db_file.is_file():
        return users

    bw_dir = get_bandwidth_dir()
    try:
        with db_file.open("r", encoding="utf-8", errors="replace") as f:
            for line in f:
                fields = line.rstrip("\r\n").split(":")
                if len(fields) < 5:
                    continue
                username = fields[0]
                if not SAFE_USERNAME.match(username):
                    continue
                
                password = fields[1]
                expiry = fields[2]
                try:
                    limit = int(fields[3])
                except ValueError:
                    limit = 1
                try:
                    quota_gb = float(fields[4])
                except ValueError:
                    quota_gb = 0.0

                metadata = fields[5] if len(fields) > 5 else ""
                metadata_val = fields[6] if len(fields) > 6 else ""

                # Bandwidth used
                used_bytes = 0
                usage_file = bw_dir / f"{username}.usage"
                if usage_file.is_file():
                    try:
                        used_bytes = int(usage_file.read_text(encoding="utf-8").strip() or "0")
                    except Exception:
                        used_bytes = 0

                # Lock & Expiry status
                is_manually_locked = username in locked_set
                status = "active"
                if is_manually_locked:
                    status = "locked"
                elif metadata == "pending":
                    status = "pending_activation"
                elif expiry not in ("Never", "unlimited", ""):
                    try:
                        import datetime
                        exp_dt = datetime.datetime.strptime(expiry, "%Y-%m-%d").date()
                        today = datetime.date.today()
                        if exp_dt < today:
                            status = "expired"
                    except Exception:
                        pass

                if quota_gb > 0 and (used_bytes / (1024**3)) >= quota_gb:
                    status = "quota_exceeded"

                users.append({
                    "username": username,
                    "password": password,
                    "expiry": expiry,
                    "limit": limit,
                    "quota_gb": quota_gb,
                    "used_bytes": used_bytes,
                    "used_gb": round(used_bytes / (1024**3), 2),
                    "status": status,
                    "metadata": metadata,
                    "metadata_value": metadata_val,
                })
    except Exception:
        pass
        
    return users


def find_user(username: str) -> Optional[Dict[str, Any]]:
    """Find a single user by username."""
    for u in load_all_users():
        if u["username"] == username:
            return u
    return None


def get_public_ip_and_domain() -> Tuple[str, str]:
    """Retrieve VPS public IP and configured domain."""
    domain = ""
    domain_file = get_domain_file()
    if domain_file.is_file():
        try:
            domain = domain_file.read_text(encoding="utf-8").strip()
        except Exception:
            pass

    if not domain:
        edge_cert_file = Path(os.environ.get("PGY_EDGE_CERT_FILE", "/etc/pgytunnel/edge_cert.conf"))
        if edge_cert_file.is_file():
            try:
                for line in edge_cert_file.read_text(encoding="utf-8").splitlines():
                    if line.startswith("EDGE_DOMAIN="):
                        val = line.split("=", 1)[1].strip().strip('"\'')
                        if val:
                            domain = val
                            break
            except Exception:
                pass

    public_ip = os.environ.get("PGY_TEST_IP", "")
    if not public_ip:
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.connect(("8.8.8.8", 80))
            public_ip = s.getsockname()[0]
            s.close()
        except Exception:
            public_ip = "127.0.0.1"

    return public_ip, (domain or public_ip)


def execute_system_cmd(cmd: List[str]) -> Tuple[int, str, str]:
    """Run system command safely."""
    if is_dry_run():
        return 0, "dry_run_success", ""
    try:
        proc = subprocess.run(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
        )
        return proc.returncode, proc.stdout, proc.stderr
    except Exception as e:
        return 1, "", str(e)


def create_user_account(payload: Dict[str, Any]) -> Tuple[bool, str, Optional[Dict[str, Any]]]:
    """Create a new SSH / VPN user."""
    username = str(payload.get("username", "")).strip()
    password = str(payload.get("password", "")).strip()
    days = payload.get("days", 30)
    limit = payload.get("limit", 1)
    quota_gb = payload.get("quota_gb", 0)
    first_use = bool(payload.get("first_use", False))

    if not SAFE_USERNAME.match(username):
        return False, "Invalid username format (2-32 chars alphanumeric/_/-)", None

    try:
        days = int(days)
        if days < 1:
            return False, "Days must be >= 1", None
    except ValueError:
        return False, "Days must be a valid integer", None

    try:
        limit = int(limit)
        if limit < 1:
            limit = 1
    except ValueError:
        limit = 1

    try:
        quota_gb = float(quota_gb)
        if quota_gb < 0:
            quota_gb = 0.0
    except ValueError:
        quota_gb = 0.0

    if not password:
        import secrets
        password = secrets.token_hex(4)

    if find_user(username) is not None:
        return False, f"User '{username}' already exists", None

    import datetime
    today = datetime.date.today()
    if first_use:
        stored_expiry = "Never"
        metadata_suffix = f":pending:{days}"
        exp_display = f"{days} days after first use"
    else:
        exp_date = today + datetime.timedelta(days=days)
        stored_expiry = exp_date.strftime("%Y-%m-%d")
        metadata_suffix = ""
        exp_display = stored_expiry

    if not is_dry_run():
        # Create system user
        rc, out, err = execute_system_cmd(["useradd", "-m", "-s", "/usr/sbin/nologin", username])
        if rc != 0 and "already exists" not in err:
            return False, f"Failed to create system user: {err}", None
        
        # Set password
        p_proc = subprocess.Popen(["chpasswd"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        p_proc.communicate(f"{username}:{password}\n")

        # Set chage expiry
        if not first_use:
            execute_system_cmd(["chage", "-E", stored_expiry, username])
        else:
            execute_system_cmd(["chage", "-E", "-1", username])

        # Add to group
        execute_system_cmd(["usermod", "-aG", "pgytunnel", username])

    # Append to users.db
    db_file = get_db_file()
    db_file.parent.mkdir(parents=True, exist_ok=True)
    db_line = f"{username}:{password}:{stored_expiry}:{limit}:{quota_gb}{metadata_suffix}\n"
    try:
        with db_file.open("a", encoding="utf-8") as f:
            f.write(db_line)
    except Exception as e:
        return False, f"Failed to write users.db: {e}", None

    ip, host = get_public_ip_and_domain()

    result = {
        "username": username,
        "password": password,
        "expiry": exp_display,
        "expiry_date": stored_expiry,
        "first_use": first_use,
        "limit": limit,
        "quota_gb": quota_gb,
        "server_ip": ip,
        "server_host": host,
        "ports": {
            "ssh_direct": 22,
            "ssh_ws_http": 80,
            "ssh_ws_https": 443,
            "ssh_ws_alt": 8880,
            "ssh_ssl_alt": 8443,
            "openvpn_tcp": 1194,
            "openvpn_udp": 2200,
            "openvpn_ssl": 992,
        }
    }
    return True, "User created successfully", result


def renew_user_account(payload: Dict[str, Any]) -> Tuple[bool, str, Optional[Dict[str, Any]]]:
    """Extend validity days for an existing user."""
    username = str(payload.get("username", "")).strip()
    days = payload.get("days", 30)

    if not SAFE_USERNAME.match(username):
        return False, "Invalid username format", None

    try:
        days = int(days)
        if days < 1:
            return False, "Days must be >= 1", None
    except ValueError:
        return False, "Days must be a valid integer", None

    user = find_user(username)
    if not user:
        return False, f"User '{username}' not found", None

    import datetime
    today = datetime.date.today()
    current_expiry = user["expiry"]

    if current_expiry in ("Never", "unlimited", ""):
        new_exp_date = today + datetime.timedelta(days=days)
    else:
        try:
            curr_dt = datetime.datetime.strptime(current_expiry, "%Y-%m-%d").date()
            if curr_dt < today:
                new_exp_date = today + datetime.timedelta(days=days)
            else:
                new_exp_date = curr_dt + datetime.timedelta(days=days)
        except Exception:
            new_exp_date = today + datetime.timedelta(days=days)

    new_expiry_str = new_exp_date.strftime("%Y-%m-%d")

    # Update users.db
    all_users = load_all_users()
    new_lines = []
    for u in all_users:
        if u["username"] == username:
            u["expiry"] = new_expiry_str
            u["metadata"] = ""  # Clear pending if renewed
            meta_part = ""
            new_lines.append(f"{u['username']}:{u['password']}:{new_expiry_str}:{u['limit']}:{u['quota_gb']}{meta_part}\n")
        else:
            meta_part = f":{u['metadata']}:{u['metadata_value']}" if u["metadata"] else ""
            new_lines.append(f"{u['username']}:{u['password']}:{u['expiry']}:{u['limit']}:{u['quota_gb']}{meta_part}\n")

    db_file = get_db_file()
    try:
        with db_file.open("w", encoding="utf-8") as f:
            f.writelines(new_lines)
    except Exception as e:
        return False, f"Failed to update users.db: {e}", None

    if not is_dry_run():
        execute_system_cmd(["chage", "-E", new_expiry_str, username])

    return True, "User renewed successfully", {
        "username": username,
        "old_expiry": current_expiry,
        "new_expiry": new_expiry_str,
        "added_days": days,
    }


def set_user_lock(username: str, lock: bool) -> Tuple[bool, str]:
    """Lock or unlock a user account."""
    if not SAFE_USERNAME.match(username):
        return False, "Invalid username format"

    user = find_user(username)
    if not user:
        return False, f"User '{username}' not found"

    locked_users = set()
    lock_file = get_manual_lock_file()
    if lock_file.is_file():
        try:
            with lock_file.open("r", encoding="utf-8", errors="replace") as f:
                locked_users = {line.strip() for line in f if line.strip()}
        except Exception:
            pass

    if lock:
        locked_users.add(username)
        if not is_dry_run():
            execute_system_cmd(["pkill", "-9", "-u", username])
    else:
        locked_users.discard(username)

    lock_file.parent.mkdir(parents=True, exist_ok=True)
    try:
        with lock_file.open("w", encoding="utf-8") as f:
            for u in sorted(locked_users):
                f.write(f"{u}\n")
    except Exception as e:
        return False, f"Failed to update lock file: {e}"

    action = "locked" if lock else "unlocked"
    return True, f"User '{username}' {action} successfully"


def delete_user_account(username: str) -> Tuple[bool, str]:
    """Permanently delete a user account."""
    if not SAFE_USERNAME.match(username):
        return False, "Invalid username format"

    user = find_user(username)
    if not user:
        return False, f"User '{username}' not found"

    # Remove from users.db
    all_users = load_all_users()
    new_lines = []
    for u in all_users:
        if u["username"] != username:
            meta_part = f":{u['metadata']}:{u['metadata_value']}" if u["metadata"] else ""
            new_lines.append(f"{u['username']}:{u['password']}:{u['expiry']}:{u['limit']}:{u['quota_gb']}{meta_part}\n")

    db_file = get_db_file()
    try:
        with db_file.open("w", encoding="utf-8") as f:
            f.writelines(new_lines)
    except Exception as e:
        return False, f"Failed to update users.db: {e}"

    # Remove from manual-locks.db
    set_user_lock(username, lock=False)

    # Remove bandwidth usage
    bw_dir = get_bandwidth_dir()
    usage_file = bw_dir / f"{username}.usage"
    if usage_file.is_file():
        try:
            usage_file.unlink()
        except Exception:
            pass

    if not is_dry_run():
        execute_system_cmd(["pkill", "-9", "-u", username])
        execute_system_cmd(["userdel", "-f", "-r", username])

    return True, f"User '{username}' deleted successfully"


# ============================================================
# Xray Multi-Protocol Account Management
# ============================================================
def generate_xray_links(username: str, uuid_str: str, domain: str, proto: str = "all") -> Dict[str, str]:
    """Generate subscription and client configuration links for Xray."""
    proto = (proto or "all").lower()
    links = {}

    # 1. VMess WS link
    vmess_ws_obj = {
        "v": "2",
        "ps": f"ProgoCloud-VMess-{username}",
        "add": domain,
        "port": "443",
        "id": uuid_str,
        "aid": "0",
        "net": "ws",
        "type": "none",
        "host": domain,
        "path": "/vmess",
        "tls": "tls",
        "sni": domain
    }
    vmess_ws_link = "vmess://" + base64.b64encode(json.dumps(vmess_ws_obj).encode("utf-8")).decode("utf-8")

    # VMess gRPC link
    vmess_grpc_obj = dict(vmess_ws_obj, net="grpc", path="vmess-grpc")
    vmess_grpc_obj["ps"] = f"ProgoCloud-VMess-gRPC-{username}"
    vmess_grpc_link = "vmess://" + base64.b64encode(json.dumps(vmess_grpc_obj).encode("utf-8")).decode("utf-8")

    # 2. VLess links
    vless_ws_link = f"vless://{uuid_str}@{domain}:443?path=%2Fvless&security=tls&encryption=none&type=ws&sni={domain}#ProgoCloud-VLess-{username}"
    vless_grpc_link = f"vless://{uuid_str}@{domain}:443?mode=gun&security=tls&encryption=none&type=grpc&serviceName=vless-grpc&sni={domain}#ProgoCloud-VLess-gRPC-{username}"

    # 3. Trojan links
    trojan_ws_link = f"trojan://{uuid_str}@{domain}:443?path=%2Ftrojan&security=tls&type=ws&sni={domain}#ProgoCloud-Trojan-{username}"
    trojan_grpc_link = f"trojan://{uuid_str}@{domain}:443?mode=gun&security=tls&type=grpc&serviceName=trojan-grpc&sni={domain}#ProgoCloud-Trojan-gRPC-{username}"

    if proto in ("vmess", "all"):
        links["vmess_ws"] = vmess_ws_link
        links["vmess_grpc"] = vmess_grpc_link
    if proto in ("vless", "all"):
        links["vless_ws"] = vless_ws_link
        links["vless_grpc"] = vless_grpc_link
    if proto in ("trojan", "all"):
        links["trojan_ws"] = trojan_ws_link
        links["trojan_grpc"] = trojan_grpc_link

    return links


def load_all_xray_users() -> List[Dict[str, Any]]:
    """Load all Xray accounts from users.json."""
    users_file = get_xray_users_file()
    if not users_file.is_file():
        return []

    try:
        with users_file.open("r", encoding="utf-8", errors="replace") as f:
            data = json.load(f)
            if not isinstance(data, list):
                return []
    except Exception:
        return []

    now_ts = int(time.time())
    users = []

    for item in data:
        if not isinstance(item, dict):
            continue
        u = item.get("username", "").strip()
        if not u:
            continue
        exp_ts = int(item.get("exp_ts", 0))
        created_at = int(item.get("created_at", 0))
        proto = item.get("protocol", "all").lower()
        uuid_str = item.get("uuid", "")
        quota_gb = int(item.get("quota_gb", 0))

        if exp_ts > 0 and exp_ts < now_ts:
            status = "expired"
        else:
            status = "active"

        exp_str = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(exp_ts)) if exp_ts else "Lifetime"

        users.append({
            "username": u,
            "protocol": proto,
            "uuid": uuid_str,
            "exp_ts": exp_ts,
            "expiry": exp_str,
            "quota_gb": quota_gb,
            "created_at": created_at,
            "status": status,
        })
    return users


def find_xray_user(username: str) -> Optional[Dict[str, Any]]:
    """Find Xray user details with links."""
    for u in load_all_xray_users():
        if u["username"] == username:
            ip, host = get_public_ip_and_domain()
            user_data = dict(u)
            user_data["server_ip"] = ip
            user_data["server_host"] = host
            user_data["port"] = 443
            user_data["tls"] = True
            user_data["links"] = generate_xray_links(u["username"], u["uuid"], host, u["protocol"])
            return user_data
    return None


def sync_xray_users_to_config() -> bool:
    """Synchronize active Xray users from users.json to config.json inbounds."""
    users_file = get_xray_users_file()
    conf_file = get_xray_config_file()

    if not conf_file.is_file():
        return False

    try:
        with conf_file.open("r", encoding="utf-8", errors="replace") as f:
            cfg = json.load(f)
    except Exception:
        return False

    users = load_all_xray_users()
    now_ts = int(time.time())

    vmess_clients = []
    vless_clients = []
    trojan_clients = []

    for u in users:
        exp_ts = u.get("exp_ts", 0)
        if exp_ts > 0 and exp_ts < now_ts:
            continue
        uuid_str = u.get("uuid", "")
        uname = u.get("username", "")
        proto = u.get("protocol", "all").lower()

        if proto in ("vmess", "all"):
            vmess_clients.append({"id": uuid_str, "alterId": 0, "email": uname})
        if proto in ("vless", "all"):
            vless_clients.append({"id": uuid_str, "email": uname, "flow": ""})
        if proto in ("trojan", "all"):
            trojan_clients.append({"password": uuid_str, "email": uname})

    for ib in cfg.get("inbounds", []):
        tag = ib.get("tag", "")
        if "vmess" in tag:
            ib.setdefault("settings", {})["clients"] = vmess_clients
        elif "vless" in tag:
            ib.setdefault("settings", {})["clients"] = vless_clients
        elif "trojan" in tag:
            ib.setdefault("settings", {})["clients"] = trojan_clients

    try:
        with conf_file.open("w", encoding="utf-8") as f:
            json.dump(cfg, f, indent=2)
    except Exception:
        return False

    if not is_dry_run():
        execute_system_cmd(["systemctl", "restart", "xray.service"])
    return True


def create_xray_account(payload: Dict[str, Any]) -> Tuple[bool, str, Optional[Dict[str, Any]]]:
    """Create a new Xray account (VMess, VLess, Trojan, or All)."""
    username = str(payload.get("username", "")).strip()
    proto = str(payload.get("protocol", "all")).strip().lower()
    days = payload.get("days", 30)
    quota_gb = payload.get("quota_gb", 0)
    custom_uuid = str(payload.get("uuid", "")).strip()

    if not SAFE_USERNAME.match(username):
        return False, "Invalid username format (must be 2-32 chars alphanumeric/_/-)", None

    if proto not in ("all", "vmess", "vless", "trojan"):
        return False, "Invalid protocol (must be 'all', 'vmess', 'vless', or 'trojan')", None

    try:
        days = int(days)
        if days < 1:
            return False, "Days must be >= 1", None
    except ValueError:
        return False, "Days must be a valid integer", None

    try:
        quota_gb = int(quota_gb)
        if quota_gb < 0:
            return False, "Quota must be >= 0", None
    except ValueError:
        return False, "Quota must be a valid integer", None

    users_file = get_xray_users_file()
    users_file.parent.mkdir(parents=True, exist_ok=True)

    # Check if exists
    if find_xray_user(username) is not None:
        return False, f"Xray user '{username}' already exists", None

    uuid_str = custom_uuid if custom_uuid else str(uuid.uuid4())
    now_ts = int(time.time())
    exp_ts = now_ts + (days * 86400)

    # Load existing
    current_users = []
    if users_file.is_file():
        try:
            with users_file.open("r", encoding="utf-8", errors="replace") as f:
                current_users = json.load(f)
                if not isinstance(current_users, list):
                    current_users = []
        except Exception:
            current_users = []

    new_entry = {
        "username": username,
        "protocol": proto,
        "uuid": uuid_str,
        "exp_ts": exp_ts,
        "quota_gb": quota_gb,
        "created_at": now_ts,
    }
    current_users.append(new_entry)

    try:
        with users_file.open("w", encoding="utf-8") as f:
            json.dump(current_users, f, indent=2)
    except Exception as e:
        return False, f"Failed to update Xray database: {e}", None

    sync_xray_users_to_config()

    ip, host = get_public_ip_and_domain()
    links = generate_xray_links(username, uuid_str, host, proto)
    exp_display = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(exp_ts))

    result = {
        "username": username,
        "protocol": proto,
        "uuid": uuid_str,
        "exp_ts": exp_ts,
        "expiry": exp_display,
        "quota_gb": quota_gb,
        "server_ip": ip,
        "server_host": host,
        "port": 443,
        "tls": True,
        "links": links,
    }
    return True, "Xray account created successfully", result


def renew_xray_account(payload: Dict[str, Any]) -> Tuple[bool, str, Optional[Dict[str, Any]]]:
    """Renew/extend expiration date for an Xray account."""
    username = str(payload.get("username", "")).strip()
    days = payload.get("days", 30)

    if not SAFE_USERNAME.match(username):
        return False, "Invalid username format", None

    try:
        days = int(days)
        if days < 1:
            return False, "Days must be >= 1", None
    except ValueError:
        return False, "Days must be a valid integer", None

    users_file = get_xray_users_file()
    if not users_file.is_file():
        return False, f"Xray user '{username}' not found", None

    try:
        with users_file.open("r", encoding="utf-8", errors="replace") as f:
            data = json.load(f)
            if not isinstance(data, list):
                return False, f"Xray user '{username}' not found", None
    except Exception:
        return False, f"Xray user '{username}' not found", None

    found = False
    now_ts = int(time.time())
    old_exp = 0
    new_exp = 0

    for item in data:
        if item.get("username") == username:
            found = True
            old_exp = int(item.get("exp_ts", 0))
            base = max(old_exp, now_ts)
            new_exp = base + (days * 86400)
            item["exp_ts"] = new_exp
            break

    if not found:
        return False, f"Xray user '{username}' not found", None

    try:
        with users_file.open("w", encoding="utf-8") as f:
            json.dump(data, f, indent=2)
    except Exception as e:
        return False, f"Failed to save Xray database: {e}", None

    sync_xray_users_to_config()

    return True, "Xray account renewed successfully", {
        "username": username,
        "old_exp_ts": old_exp,
        "new_exp_ts": new_exp,
        "old_expiry": time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(old_exp)) if old_exp else "Lifetime",
        "new_expiry": time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(new_exp)),
        "added_days": days,
    }


def delete_xray_account(username: str) -> Tuple[bool, str]:
    """Permanently delete an Xray account."""
    if not SAFE_USERNAME.match(username):
        return False, "Invalid username format"

    users_file = get_xray_users_file()
    if not users_file.is_file():
        return False, f"Xray user '{username}' not found"

    try:
        with users_file.open("r", encoding="utf-8", errors="replace") as f:
            data = json.load(f)
            if not isinstance(data, list):
                return False, f"Xray user '{username}' not found"
    except Exception:
        return False, f"Xray user '{username}' not found"

    original_len = len(data)
    data = [x for x in data if x.get("username") != username]

    if len(data) == original_len:
        return False, f"Xray user '{username}' not found"

    try:
        with users_file.open("w", encoding="utf-8") as f:
            json.dump(data, f, indent=2)
    except Exception as e:
        return False, f"Failed to update Xray database: {e}"

    sync_xray_users_to_config()
    return True, f"Xray user '{username}' deleted successfully"


def get_system_stats() -> Dict[str, Any]:
    """Retrieve VPS CPU, RAM, Disk, Uptime, and connection stats."""
    uptime_str = "Unknown"
    if Path("/proc/uptime").is_file():
        try:
            up_secs = float(Path("/proc/uptime").read_text().split()[0])
            days = int(up_secs // 86400)
            hours = int((up_secs % 86400) // 3600)
            mins = int((up_secs % 3600) // 60)
            uptime_str = f"{days}d {hours}h {mins}m"
        except Exception:
            pass

    ram_total_mb = 0
    ram_used_mb = 0
    ram_pct = 0.0
    if Path("/proc/meminfo").is_file():
        try:
            mem = {}
            for line in Path("/proc/meminfo").read_text().splitlines():
                parts = line.split(":")
                if len(parts) == 2:
                    mem[parts[0].strip()] = int(parts[1].strip().split()[0])
            total = mem.get("MemTotal", 0)
            avail = mem.get("MemAvailable", mem.get("MemFree", 0))
            used = total - avail
            ram_total_mb = round(total / 1024, 1)
            ram_used_mb = round(used / 1024, 1)
            if total > 0:
                ram_pct = round((used / total) * 100, 1)
        except Exception:
            pass

    users = load_all_users()
    total_users = len(users)
    active_users = sum(1 for u in users if u["status"] == "active")
    locked_users = sum(1 for u in users if u["status"] == "locked")
    expired_users = sum(1 for u in users if u["status"] == "expired")

    xray_users = load_all_xray_users()
    total_xray = len(xray_users)
    active_xray = sum(1 for u in xray_users if u["status"] == "active")
    expired_xray = sum(1 for u in xray_users if u["status"] == "expired")

    ip, host = get_public_ip_and_domain()

    return {
        "server_ip": ip,
        "server_host": host,
        "uptime": uptime_str,
        "ram": {
            "total_mb": ram_total_mb,
            "used_mb": ram_used_mb,
            "percent": ram_pct,
        },
        "users": {
            "total": total_users,
            "active": active_users,
            "locked": locked_users,
            "expired": expired_users,
        },
        "xray_users": {
            "total": total_xray,
            "active": active_xray,
            "expired": expired_xray,
        },
        "timestamp": int(time.time()),
    }


# ============================================================
# HTTP Request Handler
# ============================================================
class ProgoCloudApiHandler(BaseHTTPRequestHandler):
    server_version = "ProgoCloudAPI/1.0.0"

    def _send_json(self, status_code: int, data: Dict[str, Any]):
        response_bytes = json.dumps(data, indent=2).encode("utf-8")
        self.send_response(status_code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(response_bytes)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, X-API-Key, Authorization")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.end_headers()
        self.wfile.write(response_bytes)

    def do_OPTIONS(self):
        self._send_json(200, {"success": True, "message": "Preflight OK"})

    def _check_security(self, cfg: Dict[str, Any]) -> bool:
        client_ip = self.client_address[0]

        # 1. IP Whitelist check
        if not is_ip_allowed(client_ip, cfg["ALLOWED_IPS"]):
            self._send_json(403, {"success": False, "message": f"Forbidden: IP {client_ip} is not whitelisted"})
            return False

        # 2. Rate limiting check
        if not rate_limiter.is_allowed(client_ip):
            self._send_json(429, {"success": False, "message": "Too Many Requests: Rate limit exceeded (60 req/min)"})
            return False

        # 3. API Key check
        auth_key = self.headers.get("X-API-Key") or self.headers.get("Authorization")
        if not verify_api_key(auth_key, cfg["API_KEY"]):
            self._send_json(401, {"success": False, "message": "Unauthorized: Invalid or missing X-API-Key"})
            return False

        return True

    def _parse_json_body(self) -> Optional[Dict[str, Any]]:
        try:
            content_length = int(self.headers.get("Content-Length", 0))
            if content_length <= 0:
                return {}
            if content_length > 65536:  # 64KB limit
                return None
            raw_body = self.rfile.read(content_length).decode("utf-8")
            return json.loads(raw_body)
        except Exception:
            return None

    def do_GET(self):
        cfg = load_api_config()
        parsed_url = urllib.parse.urlparse(self.path)
        path = parsed_url.path.rstrip("/")

        # Health endpoint doesn't require API key
        if path in ("/api/v1/health", "/health"):
            ip, host = get_public_ip_and_domain()
            self._send_json(200, {
                "success": True,
                "service": "ProgoCloud REST API Daemon",
                "version": "1.0.0",
                "status": "healthy",
                "server_host": host,
                "timestamp": int(time.time()),
            })
            return

        if not self._check_security(cfg):
            return

        if path == "/api/v1/system/status":
            stats = get_system_stats()
            self._send_json(200, {"success": True, "data": stats})
            return

        # SSH / OpenVPN User Endpoints
        if path in ("/api/v1/user/list", "/api/v1/users"):
            users = load_all_users()
            self._send_json(200, {"success": True, "total": len(users), "data": users})
            return

        if path.startswith("/api/v1/user/info/"):
            username = path[len("/api/v1/user/info/"):].strip()
            user = find_user(username)
            if user:
                self._send_json(200, {"success": True, "data": user})
            else:
                self._send_json(404, {"success": False, "message": f"User '{username}' not found"})
            return

        # Xray Multi-Protocol Endpoints
        if path in ("/api/v1/xray/list", "/api/v1/xray/user/list", "/api/v1/xray/users"):
            x_users = load_all_xray_users()
            self._send_json(200, {"success": True, "total": len(x_users), "data": x_users})
            return

        if path.startswith("/api/v1/xray/info/"):
            username = path[len("/api/v1/xray/info/"):].strip()
            user = find_xray_user(username)
            if user:
                self._send_json(200, {"success": True, "data": user})
            else:
                self._send_json(404, {"success": False, "message": f"Xray user '{username}' not found"})
            return

        if path.startswith("/api/v1/xray/user/info/"):
            username = path[len("/api/v1/xray/user/info/"):].strip()
            user = find_xray_user(username)
            if user:
                self._send_json(200, {"success": True, "data": user})
            else:
                self._send_json(404, {"success": False, "message": f"Xray user '{username}' not found"})
            return

        self._send_json(404, {"success": False, "message": f"Endpoint GET {path} not found"})

    def do_POST(self):
        cfg = load_api_config()
        parsed_url = urllib.parse.urlparse(self.path)
        path = parsed_url.path.rstrip("/")

        if not self._check_security(cfg):
            return

        body = self._parse_json_body()
        if body is None:
            self._send_json(400, {"success": False, "message": "Malformed JSON payload or payload too large"})
            return

        # SSH / OpenVPN Endpoints
        if path == "/api/v1/user/create":
            ok, msg, data = create_user_account(body)
            status_code = 200 if ok else 400
            self._send_json(status_code, {"success": ok, "message": msg, "data": data})
            return

        if path == "/api/v1/user/renew":
            ok, msg, data = renew_user_account(body)
            status_code = 200 if ok else 400
            self._send_json(status_code, {"success": ok, "message": msg, "data": data})
            return

        if path == "/api/v1/user/lock":
            username = str(body.get("username", "")).strip()
            ok, msg = set_user_lock(username, lock=True)
            status_code = 200 if ok else 400
            self._send_json(status_code, {"success": ok, "message": msg})
            return

        if path == "/api/v1/user/unlock":
            username = str(body.get("username", "")).strip()
            ok, msg = set_user_lock(username, lock=False)
            status_code = 200 if ok else 400
            self._send_json(status_code, {"success": ok, "message": msg})
            return

        if path == "/api/v1/user/delete":
            username = str(body.get("username", "")).strip()
            ok, msg = delete_user_account(username)
            status_code = 200 if ok else 400
            self._send_json(status_code, {"success": ok, "message": msg})
            return

        # Xray Multi-Protocol Endpoints
        if path in ("/api/v1/xray/create", "/api/v1/xray/user/create"):
            ok, msg, data = create_xray_account(body)
            status_code = 200 if ok else 400
            self._send_json(status_code, {"success": ok, "message": msg, "data": data})
            return

        if path in ("/api/v1/xray/renew", "/api/v1/xray/user/renew"):
            ok, msg, data = renew_xray_account(body)
            status_code = 200 if ok else 400
            self._send_json(status_code, {"success": ok, "message": msg, "data": data})
            return

        if path in ("/api/v1/xray/delete", "/api/v1/xray/user/delete"):
            username = str(body.get("username", "")).strip()
            ok, msg = delete_xray_account(username)
            status_code = 200 if ok else 400
            self._send_json(status_code, {"success": ok, "message": msg})
            return

        self._send_json(404, {"success": False, "message": f"Endpoint POST {path} not found"})

    def log_message(self, format, *args):
        # Quiet log unless debugging
        if os.environ.get("PGY_API_DEBUG") == "1":
            sys.stderr.write(f"[{self.log_date_time_string()}] {format % args}\n")


class ThreadedHTTPServer(ThreadingMixIn, HTTPServer):
    daemon_threads = True
    allow_reuse_address = True


def run_daemon():
    cfg = load_api_config()
    port = cfg["PORT_INT"]
    host = "0.0.0.0"
    
    server = ThreadedHTTPServer((host, port), ProgoCloudApiHandler)
    print(f"[PGY-API] ProgoCloud REST API Daemon listening on http://{host}:{port}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
        print("[PGY-API] Daemon stopped.")


if __name__ == "__main__":
    run_daemon()
