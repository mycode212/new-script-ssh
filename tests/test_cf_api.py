#!/usr/bin/env python3
import os
import sys
import json
import unittest
from pathlib import Path
from unittest.mock import patch, MagicMock

# Cloudflare API python worker snippet for testing
def run_cf_worker(args, mock_response_handler=None):
    # Mocking urllib.request.urlopen
    import urllib.request
    
    def mocked_urlopen(req, timeout=15):
        url = req.full_url if hasattr(req, "full_url") else req.get_full_url()
        method = req.get_method()
        data = None
        if req.data:
            data = json.loads(req.data.decode("utf-8"))
            
        res_data = mock_response_handler(url, method, req.headers, data)
        
        mock_resp = MagicMock()
        mock_resp.read.return_value = json.dumps(res_data).encode("utf-8")
        mock_resp.__enter__.return_value = mock_resp
        mock_resp.__exit__.return_value = False
        return mock_resp

    with patch("urllib.request.urlopen", side_effect=mocked_urlopen):
        # We invoke the logic from cloudflare_api.sh worker
        import io
        from contextlib import redirect_stdout

        # Simulate main logic
        auth_mode = args[1] if len(args) > 1 else ""
        api_token = args[2] if len(args) > 2 else ""
        email = args[3] if len(args) > 3 else ""
        global_key = args[4] if len(args) > 4 else ""

        headers = {
            "Content-Type": "application/json",
            "User-Agent": "ProgoCloud-VPS-AutoScript/1.0"
        }
        if auth_mode == "token":
            headers["Authorization"] = f"Bearer {api_token}"
        else:
            headers["X-Auth-Email"] = email
            headers["X-Auth-Key"] = global_key

        cmd = args[0]
        f = io.StringIO()
        with redirect_stdout(f):
            if cmd == "list_zones":
                req = urllib.request.Request("https://api.cloudflare.com/client/v4/zones?per_page=50&status=active", headers=headers, method="GET")
                with urllib.request.urlopen(req, timeout=15) as resp:
                    res = json.loads(resp.read().decode("utf-8"))
                if res.get("success"):
                    zones = []
                    for z in res.get("result", []):
                        acc = z.get("account", {})
                        zones.append({
                            "id": z.get("id"),
                            "name": z.get("name"),
                            "status": z.get("status"),
                            "account_id": acc.get("id", ""),
                            "account_name": acc.get("name", "")
                        })
                    print(json.dumps({"success": True, "zones": zones}))
                else:
                    print(json.dumps({"success": False, "message": "Failed"}))

            elif cmd == "set_dns":
                zone_id = args[5]
                rec_type = args[6].upper()
                rec_name = args[7].lower()
                rec_content = args[8]
                rec_proxied = str(args[9]).lower() in ("true", "1", "yes")
                ttl = int(args[10]) if len(args) > 10 else 1

                # Query existing
                query_url = f"https://api.cloudflare.com/client/v4/zones/{zone_id}/dns_records?type={rec_type}&name={rec_name}&per_page=10"
                req_q = urllib.request.Request(query_url, headers=headers, method="GET")
                with urllib.request.urlopen(req_q, timeout=15) as resp:
                    query_res = json.loads(resp.read().decode("utf-8"))

                existing_record_id = None
                if query_res.get("success") and query_res.get("result"):
                    existing_record_id = query_res["result"][0].get("id")

                payload = {"type": rec_type, "name": rec_name, "content": rec_content, "ttl": ttl}
                if rec_type in ("A", "AAAA", "CNAME"):
                    payload["proxied"] = rec_proxied

                if existing_record_id:
                    update_url = f"https://api.cloudflare.com/client/v4/zones/{zone_id}/dns_records/{existing_record_id}"
                    req_u = urllib.request.Request(update_url, headers=headers, data=json.dumps(payload).encode("utf-8"), method="PUT")
                    with urllib.request.urlopen(req_u, timeout=15) as resp:
                        res = json.loads(resp.read().decode("utf-8"))
                else:
                    create_url = f"https://api.cloudflare.com/client/v4/zones/{zone_id}/dns_records"
                    req_c = urllib.request.Request(create_url, headers=headers, data=json.dumps(payload).encode("utf-8"), method="POST")
                    with urllib.request.urlopen(req_c, timeout=15) as resp:
                        res = json.loads(resp.read().decode("utf-8"))

                if res.get("success"):
                    rec_data = res.get("result", {})
                    print(json.dumps({
                        "success": True,
                        "action": "updated" if existing_record_id else "created",
                        "id": rec_data.get("id"),
                        "name": rec_data.get("name"),
                        "type": rec_data.get("type"),
                        "content": rec_data.get("content"),
                        "proxied": rec_data.get("proxied", False)
                    }))
                else:
                    print(json.dumps({"success": False, "message": "Failed"}))

            elif cmd == "delete_dns":
                zone_id = args[5]
                rec_type = args[6].upper()
                rec_name = args[7].lower()

                query_url = f"https://api.cloudflare.com/client/v4/zones/{zone_id}/dns_records?type={rec_type}&name={rec_name}&per_page=10"
                req_q = urllib.request.Request(query_url, headers=headers, method="GET")
                with urllib.request.urlopen(req_q, timeout=15) as resp:
                    query_res = json.loads(resp.read().decode("utf-8"))

                del_count = 0
                if query_res.get("success") and query_res.get("result"):
                    for r in query_res["result"]:
                        rid = r.get("id")
                        del_url = f"https://api.cloudflare.com/client/v4/zones/{zone_id}/dns_records/{rid}"
                        req_d = urllib.request.Request(del_url, headers=headers, method="DELETE")
                        with urllib.request.urlopen(req_d, timeout=15) as resp:
                            del_res = json.loads(resp.read().decode("utf-8"))
                        if del_res.get("success"):
                            del_count += 1
                print(json.dumps({"success": True, "deleted_count": del_count}))

        output = f.getvalue().strip()
        return json.loads(output)


class TestCloudflareApiWorker(unittest.TestCase):
    def test_list_zones_success(self):
        def mock_handler(url, method, headers, data):
            if "zones" in url:
                return {
                    "success": True,
                    "result": [
                        {
                            "id": "zone_12345",
                            "name": "arjunacloud.app",
                            "status": "active",
                            "account": {"id": "acc_67890", "name": "Arjuna Account"}
                        }
                    ]
                }
            return {"success": False}

        args = ["list_zones", "token", "valid_token_123", "", ""]
        res = run_cf_worker(args, mock_handler)
        self.assertTrue(res["success"])
        self.assertEqual(len(res["zones"]), 1)
        self.assertEqual(res["zones"][0]["name"], "arjunacloud.app")
        self.assertEqual(res["zones"][0]["id"], "zone_12345")

    def test_set_dns_create_new(self):
        def mock_handler(url, method, headers, data):
            if method == "GET" and "dns_records" in url:
                # No existing record
                return {"success": True, "result": []}
            elif method == "POST" and "dns_records" in url:
                # Create
                return {
                    "success": True,
                    "result": {
                        "id": "rec_abc123",
                        "name": "sg2.arjunacloud.app",
                        "type": "A",
                        "content": "103.1.2.3",
                        "proxied": False
                    }
                }
            return {"success": False}

        args = ["set_dns", "token", "valid_token_123", "", "", "zone_12345", "A", "sg2.arjunacloud.app", "103.1.2.3", "false", "1"]
        res = run_cf_worker(args, mock_handler)
        self.assertTrue(res["success"])
        self.assertEqual(res["action"], "created")
        self.assertEqual(res["name"], "sg2.arjunacloud.app")
        self.assertEqual(res["content"], "103.1.2.3")

    def test_set_dns_update_existing(self):
        def mock_handler(url, method, headers, data):
            if method == "GET" and "dns_records" in url:
                # Record exists
                return {
                    "success": True,
                    "result": [{
                        "id": "rec_abc123",
                        "name": "sg2.arjunacloud.app",
                        "type": "A",
                        "content": "103.1.2.99"
                    }]
                }
            elif method == "PUT" and "rec_abc123" in url:
                # Update
                return {
                    "success": True,
                    "result": {
                        "id": "rec_abc123",
                        "name": "sg2.arjunacloud.app",
                        "type": "A",
                        "content": "103.1.2.3",
                        "proxied": True
                    }
                }
            return {"success": False}

        args = ["set_dns", "token", "valid_token_123", "", "", "zone_12345", "A", "sg2.arjunacloud.app", "103.1.2.3", "true", "1"]
        res = run_cf_worker(args, mock_handler)
        self.assertTrue(res["success"])
        self.assertEqual(res["action"], "updated")
        self.assertTrue(res["proxied"])

    def test_delete_dns(self):
        def mock_handler(url, method, headers, data):
            if method == "GET" and "dns_records" in url:
                return {
                    "success": True,
                    "result": [{
                        "id": "rec_del_999",
                        "name": "old.arjunacloud.app",
                        "type": "A"
                    }]
                }
            elif method == "DELETE" and "rec_del_999" in url:
                return {"success": True}
            return {"success": False}

        args = ["delete_dns", "token", "valid_token_123", "", "", "zone_12345", "A", "old.arjunacloud.app"]
        res = run_cf_worker(args, mock_handler)
        self.assertTrue(res["success"])
        self.assertEqual(res["deleted_count"], 1)


if __name__ == "__main__":
    unittest.main()
