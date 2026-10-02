#!/usr/bin/env python3
import os
import sys
import json
import time
import io
import shutil
import tempfile
import unittest
from pathlib import Path

# Add project root to sys.path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from pgy_api_service import (
    RateLimiter,
    is_ip_allowed,
    verify_api_key,
    load_all_users,
    find_user,
    create_user_account,
    renew_user_account,
    set_user_lock,
    delete_user_account,
    load_all_xray_users,
    find_xray_user,
    create_xray_account,
    renew_xray_account,
    delete_xray_account,
    generate_xray_links,
    get_system_stats,
    ProgoCloudApiHandler,
)


class DummyMockSocket:
    def __init__(self, raw_request: bytes):
        self.rfile = io.BytesIO(raw_request)
        self.wfile = io.BytesIO()

    def makefile(self, mode, *args, **kwargs):
        if "r" in mode:
            return self.rfile
        elif "w" in mode:
            return self.wfile
        return self.rfile

    def sendall(self, data):
        self.wfile.write(data)


def simulate_request(method: str, path: str, headers: dict = None, body: bytes = b"", client_ip: str = "127.0.0.1"):
    headers = headers or {}
    raw = f"{method} {path} HTTP/1.1\r\nHost: 127.0.0.1\r\n"
    if body and "Content-Length" not in headers:
        headers["Content-Length"] = str(len(body))
    for k, v in headers.items():
        raw += f"{k}: {v}\r\n"
    raw += "\r\n"
    raw_bytes = raw.encode("utf-8") + body

    mock_sock = DummyMockSocket(raw_bytes)
    
    # Instantiate handler with mock socket
    handler = ProgoCloudApiHandler.__new__(ProgoCloudApiHandler)
    handler.connection = mock_sock
    handler.client_address = (client_ip, 12345)
    handler.rfile = mock_sock.rfile
    handler.wfile = mock_sock.wfile
    handler.headers = {}
    
    # Parse request
    handler.raw_requestline = handler.rfile.readline(65537)
    handler.parse_request()
    
    if method == "GET":
        handler.do_GET()
    elif method == "POST":
        handler.do_POST()
    elif method == "OPTIONS":
        handler.do_OPTIONS()

    # Parse response
    resp_bytes = mock_sock.wfile.getvalue()
    header_end = resp_bytes.find(b"\r\n\r\n")
    if header_end == -1:
        return 500, {}, {}
    
    raw_headers = resp_bytes[:header_end].decode("utf-8", errors="replace")
    raw_body = resp_bytes[header_end + 4:].decode("utf-8", errors="replace")
    
    status_line = raw_headers.splitlines()[0]
    status_code = int(status_line.split()[1])
    
    json_data = {}
    try:
        json_data = json.loads(raw_body)
    except Exception:
        pass
        
    return status_code, json_data, raw_headers


class TestApiDaemon(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.mkdtemp(prefix="pgy_api_test_")
        self.root = Path(self.temp_dir)
        self.db_file = self.root / "users.db"
        self.lock_file = self.root / "manual-locks.db"
        self.bw_dir = self.root / "bandwidth"
        self.cfg_file = self.root / "api_config.conf"
        self.domain_file = self.root / "domain.conf"
        self.xray_users_file = self.root / "xray_users.json"
        self.xray_config_file = self.root / "xray_config.json"

        self.bw_dir.mkdir(parents=True, exist_ok=True)

        os.environ["PGY_DRY_RUN"] = "1"
        os.environ["PGY_DB_FILE"] = str(self.db_file)
        os.environ["PGY_MANUAL_LOCK_FILE"] = str(self.lock_file)
        os.environ["PGY_BW_DIR"] = str(self.bw_dir)
        os.environ["PGY_API_CONFIG"] = str(self.cfg_file)
        os.environ["PGY_DOMAIN_FILE"] = str(self.domain_file)
        os.environ["PGY_XRAY_USERS_FILE"] = str(self.xray_users_file)
        os.environ["PGY_XRAY_CONFIG_FILE"] = str(self.xray_config_file)
        os.environ["PGY_TEST_IP"] = "103.1.2.3"

        # Write dummy users.db
        self.db_file.write_text(
            "user1:pass1:2030-01-01:2:10.0\n"
            "user2:pass2:2020-01-01:1:0.0\n"
            "user_pending:pass3:Never:1:0.0:pending:30\n",
            encoding="utf-8"
        )
        self.domain_file.write_text("vpn.arjunacloud.app\n", encoding="utf-8")

        # Write dummy xray users.json
        self.xray_users_file.write_text(
            json.dumps([
                {
                    "username": "xuser1",
                    "protocol": "all",
                    "uuid": "11111111-1111-1111-1111-111111111111",
                    "exp_ts": int(time.time()) + 86400 * 30,
                    "quota_gb": 10,
                    "created_at": int(time.time())
                },
                {
                    "username": "xuser_exp",
                    "protocol": "vmess",
                    "uuid": "22222222-2222-2222-2222-222222222222",
                    "exp_ts": int(time.time()) - 3600,
                    "quota_gb": 0,
                    "created_at": int(time.time()) - 86400
                }
            ], indent=2),
            encoding="utf-8"
        )

        # Write dummy xray config.json
        self.xray_config_file.write_text(
            json.dumps({
                "inbounds": [
                    {"tag": "vmess-ws-in", "settings": {"clients": []}},
                    {"tag": "vless-ws-in", "settings": {"clients": []}},
                    {"tag": "trojan-ws-in", "settings": {"clients": []}}
                ]
            }, indent=2),
            encoding="utf-8"
        )

        # Write config
        self.cfg_file.write_text(
            "API_ENABLED=1\n"
            "API_PORT=18780\n"
            "API_KEY=test_secret_key_12345\n"
            "ALLOWED_IPS=ALL\n"
            "RATE_LIMIT=60\n",
            encoding="utf-8"
        )

    def tearDown(self):
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def test_rate_limiter(self):
        limiter = RateLimiter(max_requests=3, window_seconds=10)
        self.assertTrue(limiter.is_allowed("1.1.1.1"))
        self.assertTrue(limiter.is_allowed("1.1.1.1"))
        self.assertTrue(limiter.is_allowed("1.1.1.1"))
        self.assertFalse(limiter.is_allowed("1.1.1.1"))
        self.assertTrue(limiter.is_allowed("2.2.2.2"))

    def test_ip_whitelist(self):
        self.assertTrue(is_ip_allowed("1.2.3.4", "ALL"))
        self.assertTrue(is_ip_allowed("1.2.3.4", "*"))
        self.assertTrue(is_ip_allowed("1.2.3.4", ""))
        self.assertTrue(is_ip_allowed("1.2.3.4", "1.2.3.4, 5.6.7.8"))
        self.assertFalse(is_ip_allowed("1.2.3.5", "1.2.3.4, 5.6.7.8"))
        self.assertTrue(is_ip_allowed("192.168.1.50", "192.168.1.0/24"))
        self.assertFalse(is_ip_allowed("192.168.2.50", "192.168.1.0/24"))

    def test_verify_api_key(self):
        expected = "test_secret_key_12345"
        self.assertTrue(verify_api_key("test_secret_key_12345", expected))
        self.assertTrue(verify_api_key("Bearer test_secret_key_12345", expected))
        self.assertFalse(verify_api_key("wrong_key", expected))
        self.assertFalse(verify_api_key("", expected))
        self.assertFalse(verify_api_key(None, expected))

    def test_load_and_find_users(self):
        users = load_all_users()
        self.assertEqual(len(users), 3)

        u1 = find_user("user1")
        self.assertIsNotNone(u1)
        self.assertEqual(u1["username"], "user1")
        self.assertEqual(u1["limit"], 2)
        self.assertEqual(u1["quota_gb"], 10.0)
        self.assertEqual(u1["status"], "active")

        u2 = find_user("user2")
        self.assertIsNotNone(u2)
        self.assertEqual(u2["status"], "expired")

        u3 = find_user("user_pending")
        self.assertIsNotNone(u3)
        self.assertEqual(u3["status"], "pending_activation")

    def test_create_user(self):
        ok, msg, data = create_user_account({
            "username": "newclient",
            "password": "secretpassword",
            "days": 15,
            "limit": 3,
            "quota_gb": 50.0,
        })
        self.assertTrue(ok)
        self.assertIsNotNone(data)
        self.assertEqual(data["username"], "newclient")
        self.assertEqual(data["server_host"], "vpn.arjunacloud.app")

        # Verify in db
        u = find_user("newclient")
        self.assertIsNotNone(u)
        self.assertEqual(u["password"], "secretpassword")
        self.assertEqual(u["limit"], 3)
        self.assertEqual(u["quota_gb"], 50.0)

        # Duplicate creation fails
        ok_dup, msg_dup, _ = create_user_account({"username": "newclient"})
        self.assertFalse(ok_dup)

    def test_renew_user(self):
        ok, msg, data = renew_user_account({
            "username": "user1",
            "days": 30,
        })
        self.assertTrue(ok)
        u = find_user("user1")
        self.assertIsNotNone(u)
        self.assertTrue(u["expiry"] > "2030-01-01")

    def test_lock_and_unlock_user(self):
        ok, msg = set_user_lock("user1", lock=True)
        self.assertTrue(ok)
        u = find_user("user1")
        self.assertEqual(u["status"], "locked")

        ok, msg = set_user_lock("user1", lock=False)
        self.assertTrue(ok)
        u = find_user("user1")
        self.assertEqual(u["status"], "active")

    def test_delete_user(self):
        ok, msg = delete_user_account("user1")
        self.assertTrue(ok)
        self.assertIsNone(find_user("user1"))
        self.assertEqual(len(load_all_users()), 2)

    def test_system_stats(self):
        stats = get_system_stats()
        self.assertEqual(stats["server_host"], "vpn.arjunacloud.app")
        self.assertIn("users", stats)
        self.assertEqual(stats["users"]["total"], 3)

    def test_handler_endpoints(self):
        api_key = "test_secret_key_12345"

        # 1. Health endpoint (no auth needed)
        code, data, _ = simulate_request("GET", "/api/v1/health")
        self.assertEqual(code, 200)
        self.assertTrue(data["success"])
        self.assertEqual(data["status"], "healthy")

        # 2. System status endpoint without auth (should return 401)
        code, data, _ = simulate_request("GET", "/api/v1/system/status")
        self.assertEqual(code, 401)
        self.assertFalse(data["success"])

        # 3. System status with auth
        code, data, _ = simulate_request("GET", "/api/v1/system/status", headers={"X-API-Key": api_key})
        self.assertEqual(code, 200)
        self.assertTrue(data["success"])
        self.assertEqual(data["data"]["server_host"], "vpn.arjunacloud.app")

        # 4. User list
        code, data, _ = simulate_request("GET", "/api/v1/user/list", headers={"X-API-Key": api_key})
        self.assertEqual(code, 200)
        self.assertTrue(data["success"])
        self.assertEqual(data["total"], 3)

        # 5. User info
        code, data, _ = simulate_request("GET", "/api/v1/user/info/user1", headers={"X-API-Key": api_key})
        self.assertEqual(code, 200)
        self.assertTrue(data["success"])
        self.assertEqual(data["data"]["username"], "user1")

        # 6. User create POST
        body = json.dumps({
            "username": "apiuser99",
            "password": "apipassword",
            "days": 30,
            "limit": 2,
            "quota_gb": 100.0,
        }).encode("utf-8")
        code, data, _ = simulate_request("POST", "/api/v1/user/create", headers={"X-API-Key": api_key, "Content-Type": "application/json"}, body=body)
        self.assertEqual(code, 200)
        self.assertTrue(data["success"])
        self.assertEqual(data["data"]["username"], "apiuser99")

        # 7. User lock POST
        body = json.dumps({"username": "apiuser99"}).encode("utf-8")
        code, data, _ = simulate_request("POST", "/api/v1/user/lock", headers={"X-API-Key": api_key, "Content-Type": "application/json"}, body=body)
        self.assertEqual(code, 200)
        self.assertTrue(data["success"])

        # 8. User delete POST
        code, data, _ = simulate_request("POST", "/api/v1/user/delete", headers={"X-API-Key": api_key, "Content-Type": "application/json"}, body=body)
        self.assertEqual(code, 200)
        self.assertTrue(data["success"])

    def test_xray_crud_and_links(self):
        # 1. Load users
        x_users = load_all_xray_users()
        self.assertEqual(len(x_users), 2)
        u1 = find_xray_user("xuser1")
        self.assertIsNotNone(u1)
        self.assertEqual(u1["status"], "active")
        self.assertIn("links", u1)
        self.assertIn("vmess_ws", u1["links"])
        self.assertIn("vless_ws", u1["links"])
        self.assertIn("trojan_ws", u1["links"])

        # 2. Create Xray user
        ok, msg, data = create_xray_account({
            "username": "xuser_new",
            "protocol": "all",
            "days": 15,
            "quota_gb": 50,
        })
        self.assertTrue(ok)
        self.assertIsNotNone(data)
        self.assertEqual(data["username"], "xuser_new")
        self.assertIn("links", data)
        self.assertTrue(data["links"]["vmess_ws"].startswith("vmess://"))
        self.assertTrue(data["links"]["vless_ws"].startswith("vless://"))
        self.assertTrue(data["links"]["trojan_ws"].startswith("trojan://"))

        # Verify in DB
        u_new = find_xray_user("xuser_new")
        self.assertIsNotNone(u_new)
        self.assertEqual(u_new["status"], "active")

        # 3. Renew Xray user
        ok, msg, renew_data = renew_xray_account({
            "username": "xuser_exp",
            "days": 10,
        })
        self.assertTrue(ok)
        u_renewed = find_xray_user("xuser_exp")
        self.assertEqual(u_renewed["status"], "active")

        # 4. Delete Xray user
        ok, msg = delete_xray_account("xuser_new")
        self.assertTrue(ok)
        self.assertIsNone(find_xray_user("xuser_new"))

    def test_xray_handler_endpoints(self):
        api_key = "test_secret_key_12345"

        # 1. GET /api/v1/xray/list
        code, data, _ = simulate_request("GET", "/api/v1/xray/list", headers={"X-API-Key": api_key})
        self.assertEqual(code, 200)
        self.assertTrue(data["success"])
        self.assertEqual(data["total"], 2)

        # 2. GET /api/v1/xray/info/xuser1
        code, data, _ = simulate_request("GET", "/api/v1/xray/info/xuser1", headers={"X-API-Key": api_key})
        self.assertEqual(code, 200)
        self.assertTrue(data["success"])
        self.assertEqual(data["data"]["username"], "xuser1")
        self.assertIn("links", data["data"])

        # 3. POST /api/v1/xray/create
        body = json.dumps({
            "username": "apixray1",
            "protocol": "all",
            "days": 30,
            "quota_gb": 20,
        }).encode("utf-8")
        code, data, _ = simulate_request("POST", "/api/v1/xray/create", headers={"X-API-Key": api_key, "Content-Type": "application/json"}, body=body)
        self.assertEqual(code, 200)
        self.assertTrue(data["success"])
        self.assertEqual(data["data"]["username"], "apixray1")
        self.assertIn("vmess_ws", data["data"]["links"])

        # 4. POST /api/v1/xray/renew
        body = json.dumps({
            "username": "apixray1",
            "days": 30,
        }).encode("utf-8")
        code, data, _ = simulate_request("POST", "/api/v1/xray/renew", headers={"X-API-Key": api_key, "Content-Type": "application/json"}, body=body)
        self.assertEqual(code, 200)
        self.assertTrue(data["success"])

        # 5. POST /api/v1/xray/delete
        body = json.dumps({"username": "apixray1"}).encode("utf-8")
        code, data, _ = simulate_request("POST", "/api/v1/xray/delete", headers={"X-API-Key": api_key, "Content-Type": "application/json"}, body=body)
        self.assertEqual(code, 200)
        self.assertTrue(data["success"])


if __name__ == "__main__":
    unittest.main()

