#!/bin/bash
# ============================================================
# Auto Script SSH By : ProgoCloud
# Module: features/cloudflare_api.sh - Cloudflare DNS Automation Engine
# ============================================================

PGY_CF_CREDS_FILE="/etc/pgytunnel/cf_creds.conf"

pgy_cf_load_config() {
    CF_AUTH_MODE=""
    CF_API_TOKEN=""
    CF_CF_EMAIL=""
    CF_GLOBAL_KEY=""
    CF_ZONE_NAME=""
    CF_ZONE_ID=""
    CF_ACCOUNT_ID=""
    CF_UPDATED_AT=""

    if [[ -f "$PGY_CF_CREDS_FILE" ]]; then
        # shellcheck disable=SC1090
        source "$PGY_CF_CREDS_FILE"
    fi
}

pgy_cf_save_config() {
    local mode="$1" token="$2" email="$3" gkey="$4" zname="$5" zid="$6" aid="$7"
    mkdir -p "$(dirname "$PGY_CF_CREDS_FILE")"
    cat > "$PGY_CF_CREDS_FILE" <<-EOF
# ProgoCloud Cloudflare Credentials & Zone Config
CF_AUTH_MODE="$mode"
CF_API_TOKEN="$token"
CF_CF_EMAIL="$email"
CF_GLOBAL_KEY="$gkey"
CF_ZONE_NAME="$zname"
CF_ZONE_ID="$zid"
CF_ACCOUNT_ID="$aid"
CF_UPDATED_AT="$(date +%s)"
EOF
    chmod 600 "$PGY_CF_CREDS_FILE"
}

pgy_cf_is_configured() {
    pgy_cf_load_config
    if [[ -n "$CF_ZONE_ID" && -n "$CF_ZONE_NAME" ]]; then
        if [[ "$CF_AUTH_MODE" == "token" && -n "$CF_API_TOKEN" ]]; then
            return 0
        elif [[ "$CF_AUTH_MODE" == "global" && -n "$CF_CF_EMAIL" && -n "$CF_GLOBAL_KEY" ]]; then
            return 0
        fi
    fi
    return 1
}

# ============================================================
# Python Cloudflare API Worker
# ============================================================
pgy_cf_api_worker() {
    python3 - "$@" << 'PY'
import sys
import json
import urllib.request
import urllib.error

def make_headers(auth_mode, api_token, email, global_key):
    headers = {
        "Content-Type": "application/json",
        "User-Agent": "ProgoCloud-VPS-AutoScript/1.0"
    }
    if auth_mode == "token":
        headers["Authorization"] = f"Bearer {api_token}"
    else:
        headers["X-Auth-Email"] = email
        headers["X-Auth-Key"] = global_key
    return headers

def api_request(url, method="GET", headers=None, data=None):
    req = urllib.request.Request(url, headers=headers or {}, method=method)
    if data:
        req.data = json.dumps(data).encode("utf-8")
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            body = resp.read().decode("utf-8")
            return json.loads(body)
    except urllib.error.HTTPError as e:
        err_body = e.read().decode("utf-8", errors="replace")
        try:
            return json.loads(err_body)
        except Exception:
            return {"success": False, "errors": [{"message": f"HTTP {e.code}: {e.reason}"}]}
    except Exception as e:
        return {"success": False, "errors": [{"message": str(e)}]}

def main():
    if len(sys.argv) < 2:
        print(json.dumps({"success": False, "message": "Missing command argument"}))
        sys.exit(1)

    cmd = sys.argv[1]

    # Common params
    auth_mode = sys.argv[2] if len(sys.argv) > 2 else ""
    api_token = sys.argv[3] if len(sys.argv) > 3 else ""
    email = sys.argv[4] if len(sys.argv) > 4 else ""
    global_key = sys.argv[5] if len(sys.argv) > 5 else ""

    headers = make_headers(auth_mode, api_token, email, global_key)

    if cmd == "list_zones":
        url = "https://api.cloudflare.com/client/v4/zones?per_page=50&status=active"
        res = api_request(url, "GET", headers)
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
            err_msg = "; ".join([e.get("message", "") for e in res.get("errors", [])]) or "Failed to list zones"
            print(json.dumps({"success": False, "message": err_msg}))

    elif cmd == "set_dns":
        # sys.argv: cmd auth_mode token email key zone_id record_type name content proxied ttl
        if len(sys.argv) < 11:
            print(json.dumps({"success": False, "message": "Insufficient arguments for set_dns"}))
            sys.exit(1)

        zone_id = sys.argv[6]
        rec_type = sys.argv[7].upper()
        rec_name = sys.argv[8].lower()
        rec_content = sys.argv[9]
        rec_proxied = sys.argv[10].lower() in ("true", "1", "yes")
        ttl = int(sys.argv[11]) if len(sys.argv) > 11 and sys.argv[11].isdigit() else 1

        # Check existing DNS record
        query_url = f"https://api.cloudflare.com/client/v4/zones/{zone_id}/dns_records?type={rec_type}&name={rec_name}&per_page=10"
        query_res = api_request(query_url, "GET", headers)

        existing_record_id = None
        if query_res.get("success") and query_res.get("result"):
            existing_record_id = query_res["result"][0].get("id")

        payload = {
            "type": rec_type,
            "name": rec_name,
            "content": rec_content,
            "ttl": ttl
        }
        # Only A, AAAA, CNAME support proxied flag in Cloudflare
        if rec_type in ("A", "AAAA", "CNAME"):
            payload["proxied"] = rec_proxied

        if existing_record_id:
            # Update existing
            update_url = f"https://api.cloudflare.com/client/v4/zones/{zone_id}/dns_records/{existing_record_id}"
            res = api_request(update_url, "PUT", headers, payload)
        else:
            # Create new
            create_url = f"https://api.cloudflare.com/client/v4/zones/{zone_id}/dns_records"
            res = api_request(create_url, "POST", headers, payload)

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
            err_msg = "; ".join([e.get("message", "") for e in res.get("errors", [])]) or "Failed to set DNS record"
            print(json.dumps({"success": False, "message": err_msg}))

    elif cmd == "delete_dns":
        # sys.argv: cmd auth_mode token email key zone_id record_type name
        if len(sys.argv) < 9:
            print(json.dumps({"success": False, "message": "Insufficient arguments for delete_dns"}))
            sys.exit(1)

        zone_id = sys.argv[6]
        rec_type = sys.argv[7].upper()
        rec_name = sys.argv[8].lower()

        query_url = f"https://api.cloudflare.com/client/v4/zones/{zone_id}/dns_records?type={rec_type}&name={rec_name}&per_page=10"
        query_res = api_request(query_url, "GET", headers)

        if query_res.get("success") and query_res.get("result"):
            del_count = 0
            for r in query_res["result"]:
                rid = r.get("id")
                del_url = f"https://api.cloudflare.com/client/v4/zones/{zone_id}/dns_records/{rid}"
                del_res = api_request(del_url, "DELETE", headers)
                if del_res.get("success"):
                    del_count += 1
            print(json.dumps({"success": True, "deleted_count": del_count}))
        else:
            print(json.dumps({"success": True, "deleted_count": 0, "message": "Record not found (already clean)"}))

    elif cmd == "list_dns":
        zone_id = sys.argv[6] if len(sys.argv) > 6 else ""
        query_url = f"https://api.cloudflare.com/client/v4/zones/{zone_id}/dns_records?per_page=100"
        res = api_request(query_url, "GET", headers)
        if res.get("success"):
            recs = [{
                "id": r.get("id"),
                "name": r.get("name"),
                "type": r.get("type"),
                "content": r.get("content"),
                "proxied": r.get("proxied", False)
            } for r in res.get("result", [])]
            print(json.dumps({"success": True, "records": recs}))
        else:
            err_msg = "; ".join([e.get("message", "") for e in res.get("errors", [])]) or "Failed to list records"
            print(json.dumps({"success": False, "message": err_msg}))

    else:
        print(json.dumps({"success": False, "message": f"Unknown command: {cmd}"}))

if __name__ == "__main__":
    main()
PY
}

# ============================================================
# Interactive Wizard & Management
# ============================================================
pgy_cf_setup_wizard() {
    clear; show_banner
    pgy_screen_title "PENGATURAN KREDENSIAL CLOUDFLARE API" "Otomatisasi Domain, SlowDNS, dan Tunnel Zero Trust"
    echo

    pgy_box_top "$C_CYAN"
    pgy_box_header "PILIH METODE AUTENTIKASI" "$C_CYAN" "$C_CYAN"
    pgy_box_divider "$C_CYAN"
    pgy_menu1 "[ 1]" "Cloudflare API Token (Rekomendasi - Izin Zone.DNS:Edit & Zone:Read)"
    pgy_menu1 "[ 2]" "Global API Key (Email Akun + Global API Key)"
    pgy_box_divider "$C_CYAN"
    pgy_menu1 "[ 0]" "Batal & Kembali"
    pgy_box_bot "$C_CYAN"
    echo

    local auth_choice
    read -r -p "$(echo -e "${C_PROMPT}  Pilihan [1]: ${C_RESET}")" auth_choice
    auth_choice=${auth_choice:-1}

    local mode="" token="" email="" gkey=""
    if [[ "$auth_choice" == "1" ]]; then
        mode="token"
        echo
        read -r -p "$(echo -e "${C_PROMPT}  Masukkan Cloudflare API Token: ${C_RESET}")" token
        token=$(echo "$token" | tr -d '[:space:]')
        if [[ -z "$token" ]]; then
            pgy_message ERROR "API Token tidak boleh kosong."
            press_enter
            return 1
        fi
    elif [[ "$auth_choice" == "2" ]]; then
        mode="global"
        echo
        read -r -p "$(echo -e "${C_PROMPT}  Masukkan Email Akun Cloudflare: ${C_RESET}")" email
        email=$(echo "$email" | tr -d '[:space:]')
        read -r -p "$(echo -e "${C_PROMPT}  Masukkan Global API Key: ${C_RESET}")" gkey
        gkey=$(echo "$gkey" | tr -d '[:space:]')
        if [[ -z "$email" || -z "$gkey" ]]; then
            pgy_message ERROR "Email dan Global API Key tidak boleh kosong."
            press_enter
            return 1
        fi
    elif [[ "$auth_choice" == "0" ]]; then
        return 0
    else
        pgy_message ERROR "Pilihan tidak valid."
        press_enter
        return 1
    fi

    echo
    pgy_progress_begin 1 2 "Menghubungi Cloudflare API & Mendeteksi Domain"
    local raw_json
    raw_json=$(pgy_cf_api_worker "list_zones" "$mode" "$token" "$email" "$gkey")
    pgy_progress_done

    local ok
    ok=$(echo "$raw_json" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('success', False))" 2>/dev/null || echo "False")
    if [[ "$ok" != "True" ]]; then
        local err_msg
        err_msg=$(echo "$raw_json" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('message', 'Autentikasi gagal'))" 2>/dev/null || echo "Autentikasi gagal")
        echo
        pgy_message ERROR "Gagal menghubungkan ke Cloudflare: ${err_msg}"
        echo -e "  ${C_YELLOW}Pastikan Token memiliki izin Zone.Zone (Read) dan Zone.DNS (Edit).${C_RESET}"
        press_enter
        return 1
    fi

    local zone_count
    zone_count=$(echo "$raw_json" | python3 -c "import sys, json; data=json.load(sys.stdin); print(len(data.get('zones', [])))" 2>/dev/null || echo "0")

    if [[ "$zone_count" -eq 0 ]]; then
        echo
        pgy_message ERROR "Tidak ditemukan domain (zone) aktif pada akun Cloudflare ini."
        press_enter
        return 1
    fi

    local selected_zid="" selected_zname="" selected_aid=""

    if [[ "$zone_count" -eq 1 ]]; then
        selected_zid=$(echo "$raw_json" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data['zones'][0]['id'])")
        selected_zname=$(echo "$raw_json" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data['zones'][0]['name'])")
        selected_aid=$(echo "$raw_json" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data['zones'][0]['account_id'])")
        echo
        pgy_message OK "Ditemukan 1 Domain Aktif: ${C_YELLOW}${selected_zname}${C_RESET} (Otomatis dipilih)"
    else
        echo
        pgy_box_top "$C_CYAN"
        pgy_box_header "PILIH DOMAIN UTAMA UNTUK VPS INI" "$C_CYAN" "$C_CYAN"
        pgy_box_divider "$C_CYAN"
        
        local i=0
        while (( i < zone_count )); do
            local zn
            zn=$(echo "$raw_json" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data['zones'][$i]['name'])")
            pgy_menu1 "[ $((i+1))]" "$zn"
            (( i++ ))
        done
        pgy_box_bot "$C_CYAN"
        echo

        local z_choice
        read -r -p "$(echo -e "${C_PROMPT}  Pilih nomor domain [1-${zone_count}]: ${C_RESET}")" z_choice
        z_choice=${z_choice:-1}

        if [[ ! "$z_choice" =~ ^[0-9]+$ ]] || (( z_choice < 1 || z_choice > zone_count )); then
            pgy_message ERROR "Pilihan domain tidak valid."
            press_enter
            return 1
        fi

        local idx=$(( z_choice - 1 ))
        selected_zid=$(echo "$raw_json" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data['zones'][$idx]['id'])")
        selected_zname=$(echo "$raw_json" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data['zones'][$idx]['name'])")
        selected_aid=$(echo "$raw_json" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data['zones'][$idx]['account_id'])")
    fi

    pgy_progress_begin 2 2 "Menyimpan konfigurasi kredensial Cloudflare"
    pgy_cf_save_config "$mode" "$token" "$email" "$gkey" "$selected_zname" "$selected_zid" "$selected_aid"
    sleep 0.4
    pgy_progress_done

    echo
    pgy_message OK "Cloudflare Automation Hub berhasil diaktifkan untuk domain: ${C_GREEN}${selected_zname}${C_RESET}"
    press_enter
    return 0
}

pgy_cf_switch_zone_menu() {
    if ! pgy_cf_is_configured; then
        pgy_cf_setup_wizard
        return $?
    fi

    pgy_cf_load_config
    echo
    pgy_progress_begin 1 1 "Mengambil daftar domain dari akun Cloudflare"
    local raw_json
    raw_json=$(pgy_cf_api_worker "list_zones" "$CF_AUTH_MODE" "$CF_API_TOKEN" "$CF_CF_EMAIL" "$CF_GLOBAL_KEY")
    pgy_progress_done

    local ok
    ok=$(echo "$raw_json" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('success', False))" 2>/dev/null || echo "False")
    if [[ "$ok" != "True" ]]; then
        pgy_message ERROR "Gagal mengambil daftar domain. Periksa kembali token API Anda."
        press_enter
        return 1
    fi

    local zone_count
    zone_count=$(echo "$raw_json" | python3 -c "import sys, json; data=json.load(sys.stdin); print(len(data.get('zones', [])))" 2>/dev/null || echo "0")

    if [[ "$zone_count" -le 1 ]]; then
        pgy_message INFO "Hanya ada 1 domain terdaftar di akun ini (${CF_ZONE_NAME})."
        press_enter
        return 0
    fi

    clear; show_banner
    pgy_screen_title "GANTI DOMAIN UTAMA" "Pilih domain aktif yang akan digunakan untuk VPS ini"
    echo
    pgy_box_top "$C_CYAN"
    pgy_box_header "DAFTAR DOMAIN CLOUDFLARE" "$C_CYAN" "$C_CYAN"
    pgy_box_divider "$C_CYAN"
    
    local i=0
    while (( i < zone_count )); do
        local zn
        zn=$(echo "$raw_json" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data['zones'][$i]['name'])")
        local mark=""
        if [[ "$zn" == "$CF_ZONE_NAME" ]]; then
            mark=" ${C_GREEN}(Aktif Saat Ini)${C_RESET}"
        fi
        pgy_row "  [ $((i+1))] ${C_WHITE}${zn}${C_RESET}${mark}" "$C_CYAN"
        (( i++ ))
    done
    pgy_box_divider "$C_CYAN"
    pgy_menu1 "[ 0]" "Batal & Kembali"
    pgy_box_bot "$C_CYAN"
    echo

    local z_choice
    read -r -p "$(echo -e "${C_PROMPT}  Pilih domain baru [1-${zone_count}]: ${C_RESET}")" z_choice
    if [[ "$z_choice" == "0" || -z "$z_choice" ]]; then
        return 0
    fi

    if [[ ! "$z_choice" =~ ^[0-9]+$ ]] || (( z_choice < 1 || z_choice > zone_count )); then
        pgy_message ERROR "Pilihan tidak valid."
        press_enter
        return 1
    fi

    local idx=$(( z_choice - 1 ))
    local selected_zid selected_zname selected_aid
    selected_zid=$(echo "$raw_json" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data['zones'][$idx]['id'])")
    selected_zname=$(echo "$raw_json" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data['zones'][$idx]['name'])")
    selected_aid=$(echo "$raw_json" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data['zones'][$idx]['account_id'])")

    pgy_cf_save_config "$CF_AUTH_MODE" "$CF_API_TOKEN" "$CF_CF_EMAIL" "$CF_GLOBAL_KEY" "$selected_zname" "$selected_zid" "$selected_aid"
    echo
    pgy_message OK "Domain utama VPS berhasil diubah ke: ${C_GREEN}${selected_zname}${C_RESET}"
    press_enter
    return 0
}

# ============================================================
# Core Automation Actions (Subdomain, SlowDNS)
# ============================================================
pgy_cf_auto_pointing_subdomain() {
    if ! pgy_cf_is_configured; then
        pgy_cf_setup_wizard || return 1
    fi

    pgy_cf_load_config
    clear; show_banner
    pgy_screen_title "1-CLICK AUTO POINTING SUBDOMAIN" "Buat dan arahkan A Record ke IP VPS ini via Cloudflare"
    echo

    local public_ip
    public_ip=$(curl -s -4 icanhazip.com 2>/dev/null || curl -s -4 ifconfig.me 2>/dev/null || echo "")
    if [[ -z "$public_ip" ]]; then
        pgy_message ERROR "Gagal mendeteksi IP publik VPS."
        press_enter
        return 1
    fi

    pgy_box_top "$C_CYAN"
    pgy_box_header "INFORMASI DOMAIN & TARGET" "$C_CYAN" "$C_CYAN"
    pgy_box_divider "$C_CYAN"
    pgy_detail "Domain Utama (Zone)" "$CF_ZONE_NAME" "$C_GREEN"
    pgy_detail "IP Publik VPS" "$public_ip" "$C_YELLOW"
    pgy_box_bot "$C_CYAN"
    echo

    local sub_prefix
    read -r -p "$(echo -e "${C_PROMPT}  Masukkan Prefix Subdomain [contoh: sg2 / vpn]: ${C_RESET}")" sub_prefix
    sub_prefix=$(echo "$sub_prefix" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')

    if [[ -z "$sub_prefix" ]]; then
        pgy_message ERROR "Prefix Subdomain tidak boleh kosong."
        press_enter
        return 1
    fi

    # Sanitize prefix (remove domain suffix if user typed full domain)
    if [[ "$sub_prefix" == *".$CF_ZONE_NAME" ]]; then
        sub_prefix="${sub_prefix%.$CF_ZONE_NAME}"
    fi

    local full_target_domain="${sub_prefix}.${CF_ZONE_NAME}"

    echo
    pgy_box_top "$C_CYAN"
    pgy_box_header "PILIH MODE PROXY CLOUDFLARE" "$C_CYAN" "$C_CYAN"
    pgy_box_divider "$C_CYAN"
    pgy_menu1 "[ 1]" "DNS Only (Gray Cloud - Rekomendasi untuk SSH Direct, OpenVPN, SlowDNS)"
    pgy_menu1 "[ 2]" "Proxied CDN (Orange Cloud - Untuk WebSocket Port 80/443 Bug Kuota)"
    pgy_box_bot "$C_CYAN"
    echo

    local proxy_choice
    read -r -p "$(echo -e "${C_PROMPT}  Pilihan Mode Proxy [1]: ${C_RESET}")" proxy_choice
    proxy_choice=${proxy_choice:-1}
    local is_proxied="false"
    if [[ "$proxy_choice" == "2" ]]; then
        is_proxied="true"
    fi

    echo
    pgy_progress_begin 1 2 "Membuat/memperbarui A Record: ${full_target_domain} -> ${public_ip}"
    local raw_res
    raw_res=$(pgy_cf_api_worker "set_dns" "$CF_AUTH_MODE" "$CF_API_TOKEN" "$CF_CF_EMAIL" "$CF_GLOBAL_KEY" "$CF_ZONE_ID" "A" "$full_target_domain" "$public_ip" "$is_proxied" "1")
    pgy_progress_done

    local ok
    ok=$(echo "$raw_res" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('success', False))" 2>/dev/null || echo "False")
    if [[ "$ok" != "True" ]]; then
        local err_msg
        err_msg=$(echo "$raw_res" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('message', 'Gagal mengatur DNS'))" 2>/dev/null || echo "Gagal")
        pgy_message ERROR "Gagal mengatur DNS Cloudflare: ${err_msg}"
        press_enter
        return 1
    fi

    pgy_progress_begin 2 2 "Menerapkan domain ke konfigurasi VPS lokal"
    mkdir -p "/etc/pgytunnel"
    echo "$full_target_domain" > "/etc/pgytunnel/domain.conf"
    if declare -F save_edge_cert_info >/dev/null 2>&1; then
        save_edge_cert_info "${EDGE_CERT_MODE:-None}" "$full_target_domain" "${EDGE_EMAIL:-}"
    fi
    sleep 0.3
    pgy_progress_done

    echo
    pgy_box_top "$C_GREEN"
    pgy_box_header "SUBDOMAIN BERHASIL DIKONFIGURASI" "$C_GREEN" "$C_GREEN"
    pgy_box_divider "$C_GREEN"
    pgy_detail "Full Subdomain" "$full_target_domain" "$C_GREEN"
    pgy_detail "IP Target" "$public_ip" "$C_WHITE"
    pgy_detail "Proxy Status" "$( [[ "$is_proxied" == "true" ]] && echo "Proxied (Orange Cloud)" || echo "DNS Only (Gray Cloud)" )" "$C_YELLOW"
    pgy_box_bot "$C_GREEN"
    echo
    pgy_message OK "Domain lokal VPS diperbarui ke: ${full_target_domain}"
    press_enter
    return 0
}

pgy_cf_auto_setup_slowdns() {
    if ! pgy_cf_is_configured; then
        pgy_cf_setup_wizard || return 1
    fi

    pgy_cf_load_config
    local public_ip
    public_ip=$(curl -s -4 icanhazip.com 2>/dev/null || curl -s -4 ifconfig.me 2>/dev/null || echo "")
    if [[ -z "$public_ip" ]]; then
        pgy_message ERROR "Gagal mendeteksi IP publik VPS."
        return 1
    fi

    local default_sub
    default_sub=$(hostname -s 2>/dev/null || echo "vps")
    default_sub=$(echo "$default_sub" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-')
    [[ -z "$default_sub" ]] && default_sub="vps"

    local a_sub="ns-${default_sub}"
    local ns_sub="tun-${default_sub}"

    echo
    pgy_box_top "$C_CYAN"
    pgy_box_header "OTOMATISASI SLOWDNS CLOUDFLARE" "$C_CYAN" "$C_CYAN"
    pgy_box_divider "$C_CYAN"
    pgy_detail "Domain Utama" "$CF_ZONE_NAME" "$C_GREEN"
    pgy_detail "Target IP" "$public_ip" "$C_YELLOW"
    pgy_detail "A Record Nameserver" "${a_sub}.${CF_ZONE_NAME}" "$C_WHITE"
    pgy_detail "NS Record Tunnel" "${ns_sub}.${CF_ZONE_NAME}" "$C_WHITE"
    pgy_box_bot "$C_CYAN"
    echo

    read -r -p "$(echo -e "${C_PROMPT}  Gunakan konfigurasi otomatis di atas? [Y/n]: ${C_RESET}")" confirm_auto
    if [[ "$confirm_auto" == "n" || "$confirm_auto" == "N" ]]; then
        read -r -p "$(echo -e "${C_PROMPT}  Prefix Nameserver A Record [${a_sub}]: ${C_RESET}")" in_a
        [[ -n "$in_a" ]] && a_sub=$(echo "$in_a" | tr -cd 'a-z0-9-')
        read -r -p "$(echo -e "${C_PROMPT}  Prefix Tunnel NS Record [${ns_sub}]: ${C_RESET}")" in_ns
        [[ -n "$in_ns" ]] && ns_sub=$(echo "$in_ns" | tr -cd 'a-z0-9-')
    fi

    local full_a="${a_sub}.${CF_ZONE_NAME}"
    local full_ns="${ns_sub}.${CF_ZONE_NAME}"

    echo
    pgy_progress_begin 1 2 "Membuat A Record (DNS Only): ${full_a} -> ${public_ip}"
    local res_a
    res_a=$(pgy_cf_api_worker "set_dns" "$CF_AUTH_MODE" "$CF_API_TOKEN" "$CF_CF_EMAIL" "$CF_GLOBAL_KEY" "$CF_ZONE_ID" "A" "$full_a" "$public_ip" "false" "1")
    pgy_progress_done

    pgy_progress_begin 2 2 "Membuat NS Record: ${full_ns} -> ${full_a}"
    local res_ns
    res_ns=$(pgy_cf_api_worker "set_dns" "$CF_AUTH_MODE" "$CF_API_TOKEN" "$CF_CF_EMAIL" "$CF_GLOBAL_KEY" "$CF_ZONE_ID" "NS" "$full_ns" "$full_a" "false" "1")
    pgy_progress_done

    CF_SLOWDNS_NS_DOMAIN="$full_a"
    CF_SLOWDNS_TUNNEL_DOMAIN="$full_ns"
    return 0
}

pgy_cf_menu() {
    while true; do
        clear; show_banner
        pgy_cf_load_config

        local cf_status="${C_RED}Belum Dikonfigurasi${C_RESET}"
        if pgy_cf_is_configured; then
            cf_status="${C_GREEN}Terhubung${C_RESET} (${C_YELLOW}${CF_ZONE_NAME}${C_RESET})"
        fi

        pgy_screen_title "CLOUDFLARE AUTOMATION HUB" "Pusat Integrasi DNS, Subdomain, SlowDNS & Tunnel"
        echo
        pgy_box_top "$C_CYAN"
        pgy_box_header "STATUS KONEKSI CLOUDFLARE" "$C_CYAN" "$C_CYAN"
        pgy_box_divider "$C_CYAN"
        pgy_detail "Status" "$cf_status"
        if pgy_cf_is_configured; then
            pgy_detail "Auth Mode" "$CF_AUTH_MODE" "$C_WHITE"
            pgy_detail "Domain Utama" "$CF_ZONE_NAME" "$C_GREEN"
            pgy_detail "Zone ID" "${CF_ZONE_ID:0:8}..." "$C_GRAY"
        fi
        pgy_box_divider "$C_CYAN"
        pgy_menu1 "[ 1]" "1-Click Auto Pointing Subdomain VPS (A Record)"
        pgy_menu1 "[ 2]" "Setup / Perbarui Kredensial Cloudflare API"
        pgy_menu1 "[ 3]" "Ganti Domain Utama (Switch Primary Zone)"
        pgy_menu1 "[ 4]" "Lihat Daftar DNS Record di Cloudflare"
        pgy_menu1 "[ 5]" "Kelola Cloudflare Zero Trust Tunnel"
        pgy_menu1 "[ 6]" "Hapus Kredensial Cloudflare dari VPS"
        pgy_box_divider "$C_CYAN"
        pgy_menu1 "[ 0]" "Kembali ke Menu Domain & SSL"
        pgy_box_bot "$C_CYAN"
        echo

        local choice
        read -r -p "$(echo -e "${C_PROMPT}  Pilihan Anda: ${C_RESET}")" choice
        case "$choice" in
            1)
                pgy_cf_auto_pointing_subdomain
                ;;
            2)
                pgy_cf_setup_wizard
                ;;
            3)
                pgy_cf_switch_zone_menu
                ;;
            4)
                if ! pgy_cf_is_configured; then
                    pgy_message ERROR "Konfigurasikan kredensial Cloudflare terlebih dahulu."
                    press_enter
                    continue
                fi
                clear; show_banner
                pgy_screen_title "DNS RECORDS" "Daftar DNS Record pada Zone: ${CF_ZONE_NAME}"
                echo
                pgy_progress_begin 1 1 "Mengambil data DNS dari Cloudflare"
                local rec_json
                rec_json=$(pgy_cf_api_worker "list_dns" "$CF_AUTH_MODE" "$CF_API_TOKEN" "$CF_CF_EMAIL" "$CF_GLOBAL_KEY" "$CF_ZONE_ID")
                pgy_progress_done
                echo
                python3 - "$rec_json" << 'PY'
import sys, json
data = json.loads(sys.argv[1])
recs = data.get("records", [])
print(f"{'TIPE':<8} {'NAMA RECORD':<35} {'TARGET/KONTEN':<30} {'PROXY':<8}")
print("-" * 85)
for r in recs[:40]:
    t = r.get("type", "")
    n = r.get("name", "")
    c = r.get("content", "")
    p = "Orange" if r.get("proxied") else "Gray"
    print(f"{t:<8} {n:<35} {c[:28]:<30} {p:<8}")
if len(recs) > 40:
    print(f"... dan {len(recs) - 40} record lainnya.")
PY
                echo
                press_enter
                ;;
            5)
                if declare -F cftunnel_management_menu >/dev/null 2>&1; then
                    cftunnel_management_menu
                fi
                ;;
            6)
                echo
                read -r -p "$(echo -e "${C_PROMPT}  Yakin ingin menghapus kredensial Cloudflare dari VPS ini? [y/N]: ${C_RESET}")" confirm_del
                if [[ "$confirm_del" == "y" || "$confirm_del" == "Y" ]]; then
                    rm -f "$PGY_CF_CREDS_FILE"
                    echo
                    pgy_message OK "Kredensial Cloudflare berhasil dihapus dari VPS."
                fi
                press_enter
                ;;
            0)
                return 0
                ;;
            *)
                invalid_option
                ;;
        esac
    done
}
