<p align="center">
  <img src="https://img.shields.io/badge/ProgoCloud-SSH--SCRIPT-00d4ff?style=for-the-badge&logo=linux&logoColor=black" alt="Auto Script SSH By : ProgoCloud">
  <img src="https://img.shields.io/badge/Version-0.9.0-green?style=for-the-badge" alt="Version">
  <img src="https://img.shields.io/badge/Platform-Linux-blue?style=for-the-badge&logo=linux" alt="Platform">
  <img src="https://img.shields.io/badge/Shell-Bash-4EAA25?style=for-the-badge&logo=gnubash&logoColor=white" alt="Bash">
</p>

<h1 align="center">Auto Script SSH By : ProgoCloud</h1>

<p align="center">
  <b>Advanced, Modular & High-Performance SSH Tunnel & VPN Management System for Linux VPS</b><br>
  Developed & maintained by <b>ProgoCloud</b> • Copyright © 2026 By <b>MKDev</b>
</p>

<p align="center">
  <a href="https://github.com/mycode212/new-script-ssh/stargazers"><img src="https://img.shields.io/github/stars/mycode212/new-script-ssh?style=social" alt="Stars"></a>
  <a href="https://github.com/mycode212/new-script-ssh/releases"><img src="https://img.shields.io/badge/Release-Stable-brightgreen" alt="Release"></a>
  <a href="https://t.me/progocloud"><img src="https://img.shields.io/badge/Telegram-@progocloud-2CA5E0?style=flat-square&logo=telegram" alt="Telegram"></a>
  <a href="https://autoscript-license-3xj.pages.dev"><img src="https://img.shields.io/badge/License_Portal-ProgoCloud-00d4ff?style=flat-square" alt="License Portal"></a>
</p>

---

## 📖 Ringkasan (Overview)

**Auto Script SSH By : ProgoCloud** adalah sistem manajemen VPN, SSH tunneling, dan proxy gateway serba guna yang dirancang khusus untuk server Linux VPS (Debian / Ubuntu). Script ini menghadirkan antarmuka CLI terminal interaktif modern berkinerja tinggi, dilengkapi sistem manajemen akun multi-protokol, pembatas kuota bandwidth & multi-login presisi, integrasi Cloudflare CDN & WARP, pengujian kecepatan (Ookla Speedtest & Game Ping Diagnostic), REST API Daemon mandiri untuk integrasi bot/web reseller, serta auto-healing pada sertifikat dan layanan sistem.

Arsitektur sistem dibangun secara modular di bawah `/pgy-lib/opt/` (`opt/pgy-lib/`), menjamin kestabilan tinggi, pembaruan aplikasi *atomic* tanpa merusak konfigurasi aktif (*zero downtime updates*), dan keamanan data pengguna yang terisolasi.

---

## 🚀 Fitur Unggulan

### 1. Cloudflare Automation Hub (DNS, Subdomain, SlowDNS & Tunnel)
- **1-Click Auto Pointing Subdomain VPS** — Buat dan arahkan `A` Record ke IP VPS secara instan via Cloudflare API tanpa perlu membuka browser/dashboard Cloudflare.
- **1-Click Auto Setup SlowDNS (DNSTT)** — Pembuatan otomatis record `A` (`ns-sg2.domain.com`) dan record `NS` (`tun-sg2.domain.com`) secara simultan.
- **Auto Zone Discovery & Switcher** — Mendeteksi otomatis domain-domain yang terdaftar di akun Cloudflare dan memilih domain utama yang diinginkan.
- **Zero Trust HTTPS Tunnel** — Expose OpenVPN Web Portal (`localhost:1180`) dan REST API Daemon (`localhost:8780`) dengan aman tanpa membuka port publik di firewall.
- **Kredensial Terpusat & Aman** — Token Cloudflare disimpan terlindungi (`chmod 600`) di `/etc/pgytunnel/cf_creds.conf` dan digunakan bersama untuk semua modul.

### 2. Manajemen Pengguna (User Management)
- **Operasi CRUD Akun Lengkap** — Buat akun, hapus, perpanjang (*renew* masa aktif), ubah password, batas login simultan (*max login* 1–10 device), dan kuota bandwidth per pengguna.
- **Bulk Account Generator** — Pembuatan banyak akun pengguna sekaligus secara otomatis dalam hitungan detik.
- **Trial Account Creator** — Pembuatan akun uji coba dengan durasi fleksibel (1–72 jam) yang dilengkapi auto-cleanup saat kedaluwarsa.
- **Lock & Unlock Akun** — Kunci akses akun pengguna seketika tanpa menghapus data profil.
- **Auto Expired Cleanup** — Pembersihan otomatis akun-akun yang telah habis masa aktifnya.
- **Account Details & Formatter** — Output detail akun lengkap siap salin untuk format SSH Direct, WebSocket Payload, SSL/SNI, Xray (VMess/VLESS/Trojan), dan OpenVPN.

### 3. Pelacakan Bandwidth & Pembatas Sesi
- **Per-PID I/O Traffic Tracking** — Perhitungan volume data presisi secara langsung dari `/proc/<pid>/io` per sesi aktif.
- **Quota Enforcer (GB)** — Pemutusan koneksi otomatis jika kuota data akun telah habis.
- **Multi-Login Limiter Daemon** — Pemantauan jumlah koneksi bersamaan (*concurrent sessions*) dengan auto-kill bila melebihi batas.
- **VNStat Real-time & History** — Tampilan statistik konsumsi bandwidth harian dan bulanan server.
- **Anti-Torrent & Anti-Abuse** — Aturan firewall IPTables otomatis untuk memblokir port dan traffic protokol BitTorrent/P2P.

### 4. OpenVPN Protocol Suite Terpadu
- **Multi-Method Listener**:
  - **Direct TCP** (`447`) & **Direct UDP** (`448`)
  - **HTTP CONNECT Proxy** (`449`) & **WebSocket WS** (`449`)
  - **WSS / TLS WebSocket** (`450`) & **SSL / Raw TLS** (`446`)
- **Web Documentation & Profile Portal** (`:1180/openvpn`) — Halaman web download profil `.ovpn` (Direct, Payload, WSS, SSL) dan dokumentasi panduan koneksi.
- **Otomatisasi Sertifikat PKI** — Pembuatan sertifikat CA, server, dan gateway TLS berbasis ECC/RSA dengan verifikasi chain otomatis.
- **Auto-Healing Permissions & Services** — Pemulihan mandiri izin file sertifikat (`640`), folder PKI (`750`), dan user service terisolasi (`tdzopenvpn`).

### 5. Xray Multi-Protocol Core & Anti-Adblock
- **Multi-Inbounds** — VMess WS/gRPC, VLESS WS/gRPC, Trojan WS/gRPC.
- **Sinkronisasi Otomatis** — Sinkronisasi otomatis ke `/etc/xray/config.json` saat akun dibuat/dihapus via CLI atau REST API.
- **Server-Side Adblocker** — Pemblokiran otomatis domain iklan, malware, dan tracker.
- **Cloudflare WARP Outbound** — Bypass pembatasan streaming Netflix, Disney+, OpenAI/ChatGPT via Wireproxy SOCKS5 port `40000`.

### 6. Speedtest & Network Benchmark
- **Official Ookla Speedtest CLI** — Pengujian bandwidth download, upload, ping, dan jitter riil dengan binary resmi Ookla Linux (x86_64 / arm64).
- **Multi-Region Benchmark** — Uji latensi dan kecepatan terarah ke server Indonesia, Singapura, Malaysia, Jepang, dan Amerika Serikat.
- **Game Server Diagnostic** — Pengecekan latensi & jitter khusus untuk Mobile Legends (MLBB), PUBG Mobile, Valorant / Riot Games, dan Free Fire (Garena).
- **Continuous Ping & Packet Loss Monitor** — Pemantauan stabilitas jaringan real-time.

### 7. ProgoCloud REST API Daemon (Micro HTTP Service)
- **Micro Python 3 Daemon** — Layanan REST API ringan port `8780` (<15MB RAM) tanpa dependensi library eksternal.
- **Keamanan Kriptografis** — Autentikasi token `X-API-Key` 32-karakter, IP Whitelisting ACL, dan Rate Limiter 60 req/menit.
- **Otomatisasi Reseller & Billing Bot** — Endpoint JSON lengkap untuk pembuatan akun instan, perpanjangan masa aktif (*renew*), kunci/buka user, hapus user, cek profil akun, dan status resource VPS real-time.

---

## 🌐 Panduan Cloudflare Automation Hub & REST API

> [!IMPORTANT]
> **URUTAN KONFIGURASI WAJIB:**  
> **Sebelum mengaktifkan atau mengintegrasikan REST API Daemon ke Bot Telegram / Web Panel, pastikan Anda telah mengatur Kredensial Cloudflare & Tunnel terlebih dahulu.**  
> Hal ini memastikan endpoint REST API (`https://api.domain.com`) dan OpenVPN Web Portal (`https://vpn.domain.com`) dapat diakses melalui koneksi HTTPS yang aman tanpa terhalang oleh pemblokiran port non-standar (`:8780` dan `:1180`) pada Cloudflare CDN Proxy.

### 1. Cara Konfigurasi Cloudflare Tunnel (1-Click Auto API)

1. Buka terminal VPS, ketik **`menu`** → Pilih **`[ 7] Domain & SSL Cert`** → Pilih **`[ 6] Cloudflare Tunnel`**.
2. Pilih **`[ 1] Otomatis Buat Tunnel & Domain (Cloudflare API 1-Click)`**.
3. Masukkan **API Token Cloudflare** (atau Global API Key + Email) dan **Domain Utama** Anda (misal: `arjunacloud.app`).
4. Script akan secara otomatis:
   - Membuat Tunnel baru di akun Cloudflare Anda.
   - Mengarahkan `vpn.domain.com` ➔ `localhost:1180` (OpenVPN Web Portal).
   - Mengarahkan `api.domain.com` ➔ `localhost:8780` (ProgoCloud REST API Daemon).
   - Membuat DNS CNAME Record di Cloudflare berstatus Proxied.
   - Menginstal dan menjalankan `cloudflared.service` di VPS.

---

### 2. Dokumentasi Endpoint ProgoCloud REST API

Setelah Cloudflare Tunnel aktif, buka menu **`[16] REST API Manager`** untuk mengaktifkan daemon dan melihat **API Key** Anda.

Semua request wajib menyertakan header:
`X-API-Key: <KUNCI_API_ANDA>`

#### A. Cek Status Resource VPS (GET)
```bash
curl -s -H "X-API-Key: YOUR_SECRET_KEY" \
  https://api.domain.com/api/v1/system/status
```
**Contoh Respon JSON:**
```json
{
  "status": "success",
  "data": {
    "hostname": "sg2",
    "uptime": "5 days, 12:30",
    "cpu_percent": 14.5,
    "cpu_cores": 2,
    "ram_used_mb": 420,
    "ram_total_mb": 2048,
    "ram_percent": 20.5,
    "disk_used_gb": 12.4,
    "disk_total_gb": 50.0,
    "disk_percent": 24.8,
    "script_version": "0.4.89",
    "active_users_total": 48
  }
}
```

#### B. Buat Akun SSH Baru (POST)
```bash
curl -s -X POST -H "Content-Type: application/json" \
  -H "X-API-Key: YOUR_SECRET_KEY" \
  -d '{"username":"client01","password":"password123","days":30,"max_login":2,"quota_gb":50}' \
  https://api.domain.com/api/v1/user/create
```

#### C. Perpanjang Masa Aktif Akun (POST)
```bash
curl -s -X POST -H "Content-Type: application/json" \
  -H "X-API-Key: YOUR_SECRET_KEY" \
  -d '{"username":"client01","days":30}' \
  https://api.domain.com/api/v1/user/renew
```

#### D. Kunci / Buka Akun Pengguna (POST)
```bash
# Kunci Akun (Lock)
curl -s -X POST -H "Content-Type: application/json" \
  -H "X-API-Key: YOUR_SECRET_KEY" \
  -d '{"username":"client01"}' \
  https://api.domain.com/api/v1/user/lock

# Buka Akun (Unlock)
curl -s -X POST -H "Content-Type: application/json" \
  -H "X-API-Key: YOUR_SECRET_KEY" \
  -d '{"username":"client01"}' \
  https://api.domain.com/api/v1/user/unlock
```

#### E. Hapus Akun Pengguna (POST)
```bash
curl -s -X POST -H "Content-Type: application/json" \
  -H "X-API-Key: YOUR_SECRET_KEY" \
  -d '{"username":"client01"}' \
  https://api.domain.com/api/v1/user/delete
```

#### F. Ambil Daftar & Detail Akun (GET)
```bash
# Daftar Semua Pengguna
curl -s -H "X-API-Key: YOUR_SECRET_KEY" \
  https://api.domain.com/api/v1/user/list

# Detail Profil Pengguna Tertentu
curl -s -H "X-API-Key: YOUR_SECRET_KEY" \
  https://api.domain.com/api/v1/user/info/client01
```

#### G. Endpoint Akun Xray (VMess, VLESS, Trojan Multi-Protocol)

REST API menyediakan endpoint lengkap untuk manajemen akun Xray dengan auto-generate subscription link (VMess WS, VMess gRPC, VLESS WS, VLESS gRPC, Trojan WS, Trojan gRPC):

```bash
# 1. Buat Akun Xray Baru (POST)
# Protocol opsi: "all" (semua protokol), "vmess", "vless", "trojan"
curl -s -X POST -H "Content-Type: application/json" \
  -H "X-API-Key: YOUR_SECRET_KEY" \
  -d '{
    "username": "xclient01",
    "protocol": "all",
    "days": 30,
    "quota_gb": 50
  }' \
  https://api.domain.com/api/v1/xray/create

# 2. Perpanjang Masa Aktif Akun Xray (POST)
curl -s -X POST -H "Content-Type: application/json" \
  -H "X-API-Key: YOUR_SECRET_KEY" \
  -d '{"username":"xclient01","days":30}' \
  https://api.domain.com/api/v1/xray/renew

# 3. Hapus Akun Xray (POST)
curl -s -X POST -H "Content-Type: application/json" \
  -H "X-API-Key: YOUR_SECRET_KEY" \
  -d '{"username":"xclient01"}' \
  https://api.domain.com/api/v1/xray/delete

# 4. Ambil Daftar Semua Akun Xray (GET)
curl -s -H "X-API-Key: YOUR_SECRET_KEY" \
  https://api.domain.com/api/v1/xray/list

# 5. Detail Akun & Link Konfigurasi Klien (GET)
curl -s -H "X-API-Key: YOUR_SECRET_KEY" \
  https://api.domain.com/api/v1/xray/info/xclient01
```

**Format Respon Pembuatan Akun Xray (`POST /api/v1/xray/create`):**
```json
{
  "success": true,
  "message": "Xray account created successfully",
  "data": {
    "username": "xclient01",
    "protocol": "all",
    "uuid": "4f18d7b3-2b6e-44d5-91f8-08d447a11e1f",
    "exp_ts": 1743513600,
    "expiry": "2026-11-01 15:00:00",
    "quota_gb": 50,
    "server_ip": "103.1.2.3",
    "server_host": "vpn.arjunacloud.app",
    "port": 443,
    "tls": true,
    "links": {
      "vmess_ws": "vmess://eyJhZGQiOiAidnBuLmFyanVuYWNsb3VkLmFwcCIsICJwb3J0IjogIjQ0MyIsICJpZCI6IC...=",
      "vmess_grpc": "vmess://eyJhZGQiOiAidnBuLmFyanVuYWNsb3VkLmFwcCIsICJwb3J0IjogIjQ0MyIsICJpZCI6IC...=",
      "vless_ws": "vless://4f18d7b3-2b6e-44d5-91f8-08d447a11e1f@vpn.arjunacloud.app:443?path=%2Fvless&security=tls&encryption=none&type=ws&sni=vpn.arjunacloud.app#ProgoCloud-VLess-xclient01",
      "vless_grpc": "vless://4f18d7b3-2b6e-44d5-91f8-08d447a11e1f@vpn.arjunacloud.app:443?mode=gun&security=tls&encryption=none&type=grpc&serviceName=vless-grpc&sni=vpn.arjunacloud.app#ProgoCloud-VLess-gRPC-xclient01",
      "trojan_ws": "trojan://4f18d7b3-2b6e-44d5-91f8-08d447a11e1f@vpn.arjunacloud.app:443?path=%2Ftrojan&security=tls&type=ws&sni=vpn.arjunacloud.app#ProgoCloud-Trojan-xclient01",
      "trojan_grpc": "trojan://4f18d7b3-2b6e-44d5-91f8-08d447a11e1f@vpn.arjunacloud.app:443?mode=gun&security=tls&type=grpc&serviceName=trojan-grpc&sni=vpn.arjunacloud.app#ProgoCloud-Trojan-gRPC-xclient01"
    }
  }
}
```

---

## 🔌 Daftar Port Layanan

| Port | Protokol | Keterangan Layanan |
|---|---|---|
| `22` | TCP | OpenSSH Server Utama |
| `80` / `2080` | TCP / HTTP | HAProxy Edge Public HTTP / WebSocket (WS) |
| `443` / `442` | TCP / TLS | HAProxy Edge Public HTTPS / SSL / TLS |
| `446` | TCP / TLS | OpenVPN Direct SSL / SNI Method |
| `447` | TCP | OpenVPN Official TCP Server |
| `448` | UDP | OpenVPN Official UDP Server |
| `449` | TCP / HTTP | OpenVPN HTTP Proxy & WebSocket Method |
| `450` | TCP / TLS | OpenVPN WSS / SNI Method |
| `1180` | HTTP / HTTPS | OpenVPN Web Documentation & Profile Portal (Direct / Tunnel) |
| `8780` | TCP / HTTP | ProgoCloud REST API Daemon (Direct / Tunnel) |
| `7300` | UDP | BadVPN / UDPGW (Gaming & VoIP) |
| `53` | UDP | SlowDNS / DNSTT Server |
| `5667` | UDP | ZiVPN Server Direct |
| `6000–19999` | UDP | ZiVPN Port Range Forwarding |
| `8890` | TCP | WS-to-SSH Bridge Daemon (Internal) |
| `8770` / `8771` | TCP | Nginx Internal Cleartext & TLS Proxy |
| `10443` | TCP / SSL | HAProxy Internal Decryptor |
| `40000` | TCP / SOCKS5 | Cloudflare WARP / Wireproxy Outbound |

---

## ⚠️ Informasi Penting & Perhatian Khusus

Sebelum menggunakan dan mengonfigurasi layanan di VPS Anda, perhatikan poin-poin penting berikut:

### 1. Integrasi Cloudflare DNS & Proxy
- **Untuk SSH WebSocket CDN / Bug Kuota (Port 80 & 443):**
  - Subdomain di Cloudflare **WAJIB berstatus Proxied (Awan Oranye)**.
  - Di dashboard Cloudflare: Masuk ke **Network** → Pastikan opsi **WebSockets** bernilai **ON (Enabled)**.
- **Untuk OpenVPN Portal (Port 1180) & REST API (Port 8780):**
  - Cloudflare CDN gratisan tidak mendukung port non-standar `:1180` dan `:8780`.
  - **Gunakan Cloudflare Tunnel** via menu `[ 7] Domain & SSL` → `[ 6] Cloudflare Tunnel` → `[ 1] Otomatis Buat Tunnel & Domain`. Kedua layanan akan otomatis aktif di port HTTPS standar tanpa perlu membuka port di firewall.

### 2. Pengaturan Port Edge (HAProxy)
- Secara default, Edge HTTP/TLS berada di port `2080` & `442`. Jika Anda ingin menggunakan port standar `80` & `443` untuk WebSocket/CDN:
  - Buka `menu` → **[ 4] Port Management** → Pilih **Change Public Edge Ports** ke `80` & `443`.
- **PENTING:** Jangan mengubah port OpenVPN menjadi 80 atau 443 jika Edge HAProxy aktif pada port tersebut, karena akan terjadi bentrok (*port collision*).

### 3. Hak Akses VPS
- Seluruh instalasi, update, dan eksekusi script wajib dijalankan dengan akun **`root`** penuh (`sudo -i`).

---

## 💻 Sistem Operasi & Arsitektur yang Didukung

### 1. Sistem Operasi (Linux OS)

| Distribusi Linux | Versi yang Didukung | Status |
|---|---|---|
| **Ubuntu Server** | 20.04 (Focal), 22.04 (Jammy), 24.04 (Noble) & versi lebih baru | **Sangat Direkomendasikan (LTS)** |
| **Debian** | Debian 11 (Bullseye), Debian 12 (Bookworm) & versi lebih baru | **Sangat Direkomendasikan (Stable)** |
| **Kali Linux** | Rolling Releases (berbasis systemd) | Kompatibel |
| **Armbian / DietPi** | Berbasis Debian / Ubuntu | Kompatibel |

### 2. Arsitektur CPU

| Arsitektur | Alias | Status Dukungan |
|---|---|---|
| **x86_64 / Intel & AMD 64-bit** | `amd64`, `x86_64` | **Dukungan Penuh (Semua Modul)** |
| **ARM 64-bit** | `arm64`, `aarch64` | **Dukungan Penuh** |
| **ARM 32-bit** | `armv7l`, `armhf` | Kompatibel untuk modul inti SSH |

### 3. Spesifikasi Minimum VPS
- **RAM:** Minimum 512 MB (Disarankan 1 GB atau lebih).
- **Disk:** Minimum 2 GB ruang penyimpanan kosong.
- **Jaringan:** IP Publik Statis dengan akses internet terbuka.

---

## 📥 Panduan Instalasi (Installation)

**Instalasi Satu Baris (One-Line Installer sebagai root):**

```bash
bash <(curl -Ls https://raw.githubusercontent.com/mycode212/new-script-ssh/main/install.sh)
```

**Instalasi Manual:**

```bash
curl -LO https://raw.githubusercontent.com/mycode212/new-script-ssh/main/install.sh
chmod +x install.sh
./install.sh
```

Setelah instalasi selesai, cukup ketik **`menu`** atau **`pgy`** di terminal untuk membuka dashboard kontrol.

---

## 🔄 Pembaruan Script (Update)

Pembaruan modul script dapat dilakukan kapan saja secara otomatis tanpa menghapus akun pengguna, lisensi, atau konfigurasi:

```bash
pgy-update
```
*atau melalui antarmuka **`menu` → `[23] Update Script`**.*

Pembaruan menggunakan sistem **borderless animated spinner** yang transparan, cepat, dan aman.

---

## 🔑 Manajemen Lisensi & Layanan Bantuan

- **Cek Status Lisensi:**
  ```bash
  pgy-license-check status
  ```
- **Portal Lisensi Resmi:** [https://autoscript-license-3xj.pages.dev](https://autoscript-license-3xj.pages.dev)
- **Layanan Pelanggan & Pemesanan Lisensi:** [Telegram @progocloud](https://t.me/progocloud)

---

## 🗑️ Menghapus Script (Uninstall)

Untuk menghapus script dan membersihkan seluruh dependensi sistem:

```bash
menu → 99) Uninstall Script
```

Proses uninstaller akan menghentikan seluruh layanan background, menghapus aturan firewall, dan memulihkan konfigurasi sistem VPS ke kondisi awal.

---

## 📄 Hak Cipta & Lisensi

&copy; **ProgoCloud**. All rights reserved.  
Pengembang: **MKDev**  
Repository: [https://github.com/mycode212/new-script-ssh](https://github.com/mycode212/new-script-ssh)  
Komunitas & Bantuan: [https://t.me/progocloud](https://t.me/progocloud)
