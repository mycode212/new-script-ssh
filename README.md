<p align="center">
  <img src="https://img.shields.io/badge/ProgoCloud-SSH--SCRIPT-00d4ff?style=for-the-badge&logo=linux&logoColor=black" alt="Auto Script SSH By : ProgoCloud">
  <img src="https://img.shields.io/badge/Version-0.4.89-green?style=for-the-badge" alt="Version">
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

### 1. Manajemen Pengguna (User Management)
- **Operasi CRUD Akun Lengkap** — Buat akun, hapus, perpanjang (*renew* masa aktif), ubah password, batas login simultan (*max login* 1–10 device), dan kuota bandwidth per pengguna.
- **Bulk Account Generator** — Pembuatan banyak akun pengguna sekaligus secara otomatis dalam hitungan detik.
- **Trial Account Creator** — Pembuatan akun uji coba dengan durasi fleksibel (1–72 jam) yang dilengkapi auto-cleanup saat kedaluwarsa.
- **Lock & Unlock Akun** — Kunci akses akun pengguna seketika tanpa menghapus data profil.
- **Auto Expired Cleanup** — Pembersihan otomatis akun-akun yang telah habis masa aktifnya.
- **Account Details & Formatter** — Output detail akun lengkap siap salin untuk format SSH Direct, WebSocket Payload, SSL/SNI, Xray (VMess/VLESS/Trojan), dan OpenVPN.

### 2. Pelacakan Bandwidth & Pembatas Sesi
- **Per-PID I/O Traffic Tracking** — Perhitungan volume data presisi secara langsung dari `/proc/<pid>/io` per sesi aktif.
- **Quota Enforcer (GB)** — Pemutusan koneksi otomatis jika kuota data akun telah habis.
- **Multi-Login Limiter Daemon** — Pemantauan jumlah koneksi bersamaan (*concurrent sessions*) dengan auto-kill bila melebihi batas.
- **VNStat Real-time & History** — Tampilan statistik konsumsi bandwidth harian dan bulanan server.
- **Anti-Torrent & Anti-Abuse** — Aturan firewall IPTables otomatis untuk memblokir port dan traffic protokol BitTorrent/P2P.

### 3. OpenVPN Protocol Suite Terpadu
- **Multi-Method Listener**:
  - **Direct TCP** (`447`) & **Direct UDP** (`448`)
  - **HTTP CONNECT Proxy** (`449`) & **WebSocket WS** (`449`)
  - **WSS / TLS WebSocket** (`450`) & **SSL / Raw TLS** (`446`)
- **Web Documentation & Profile Portal** (`:1180/openvpn`) — Halaman web download profil `.ovpn` (Direct, Payload, WSS, SSL) dan dokumentasi panduan koneksi.
- **Otomatisasi Sertifikat PKI** — Pembuatan sertifikat CA, server, dan gateway TLS berbasis ECC/RSA dengan verifikasi chain otomatis.
- **Auto-Healing Permissions & Services** — Pemulihan mandiri izin file sertifikat (`640`), folder PKI (`750`), dan user service terisolasi (`tdzopenvpn`).

### 4. Edge Reverse-Proxy & WebSocket Stack
- **HAProxy + Nginx Unified Terminator** — Penggabungan SSL/TLS termination untuk Xray dan SSH WebSocket dalam satu port publik.
- **Split Payload & CDN Support** — Mendukung injeksi payload khusus Cloudflare CDN (`GET /cdn-cgi/trace`, `CF-RAY`, `Upgrade: websocket`).
- **Flexible Public Ports** — Port publik HTTP (default `2080` / `80`) dan TLS (default `442` / `443`).
- **WS-to-SSH Bridge Daemon** — Jembatan WebSocket berkinerja tinggi port `8890` dengan zero-copy buffer untuk transfer data berkecepatan tinggi.

### 5. Multi-Protokol VPN & Akselerasi
- **Cloudflare WARP Suite & Wireproxy** — Outbound routing SOCKS5 port `40000` untuk membuka blokir streaming (Netflix, Disney+, ChatGPT, dll.) serta dukungan lisensi WARP+.
- **Xray / V2Ray Core** — Protokol VMess, VLESS, dan Trojan dengan transportasi WebSocket dan gRPC.
- **SlowDNS / DNSTT** — Tunneling berbasis DNS pada port UDP `53` untuk bypass firewall ketat.
- **BadVPN / UDPGW** — Port UDP `7300` teroptimasi untuk stabilitas game online dan panggilan suara (VoIP/WhatsApp).
- **ZiVPN UDP** — Port direct UDP `5667` dan forwarding range `6000–19999`.

### 6. Speedtest & Network Benchmark (Fitur Baru v0.1.51)
- **Official Ookla Speedtest CLI** — Pengujian bandwidth download, upload, ping, dan jitter riil dengan binary resmi Ookla Linux (x86_64 / arm64).
- **Multi-Region Benchmark** — Uji latensi dan kecepatan terarah ke server Indonesia, Singapura, Malaysia, Jepang, dan Amerika Serikat.
- **Game Server Diagnostic** — Pengecekan latensi & jitter khusus untuk Mobile Legends (MLBB), PUBG Mobile, Valorant / Riot Games, dan Free Fire (Garena).
- **Continuous Ping & Packet Loss Monitor** — Pemantauan stabilitas jaringan real-time.

### 7. ProgoCloud REST API Daemon (Fitur Baru v0.1.51)
- **Micro Python 3 Daemon** — Layanan REST API ringan port `8780` (<15MB RAM) tanpa dependensi library eksternal.
- **Keamanan Kriptografis** — Autentikasi token `X-API-Key` 32-karakter, IP Whitelisting ACL, dan Rate Limiter 60 req/menit.
- **Otomatisasi Reseller & Billing Bot** — Endpoint JSON lengkap untuk pembuatan akun instan, perpanjangan masa aktif (*renew*), kunci/buka user, hapus user, cek profil akun, dan status resource VPS real-time.

### 8. Keamanan, Lisensi, & Backup
- **ProgoCloud License Guard** — Validasi otomatis IP publik VPS ke server lisensi resmi ProgoCloud.
- **Domain & SSL Certificate Manager** — Penerbitan sertifikat SSL otomatis via Let's Encrypt (Certbot), sertifikat custom, atau self-signed.
- **Cloud Backup to Telegram** — Pencadangan database akun terenkripsi yang langsung dikirimkan ke Bot Telegram pribadi Anda.
- **Scheduled Auto-Reboot** — Pemeliharaan otomatis dengan reboot server terjadwal setiap pukul 00:00 WIB.

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
| `1180` | HTTP / HTTPS | OpenVPN Web Documentation & Profile Portal |
| `8780` | TCP / HTTP | ProgoCloud REST API & Webhook Daemon |
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
- **Untuk Portal OpenVPN (Port 1180):**
  - Cloudflare CDN gratisan tidak mendukung port non-standar `:1180`.
  - **Solusi Rekomendasi:**
    - **Opsi 1 (Cloudflare Tunnel - Terbaik):** Pasang `cloudflared` dan hubungkan subdomain (misal `vpn.domain.com`) ke `http://localhost:1180`. Portal dapat diakses via `https://vpn.domain.com` secara full-proxy tanpa port.
    - **Opsi 2 (2 Subdomain):** Gunakan subdomain kedua berstatus **DNS Only (Awan Abu-abu)** khusus untuk membuka `https://subdomain:1180/openvpn/`, atau buka langsung via IP VPS `https://IP_VPS:1180/openvpn/`.

### 2. Pengaturan Port Edge (HAProxy)
- Secara default, Edge HTTP/TLS berada di port `2080` & `442`. Jika Anda ingin menggunakan port standar `80` & `443` untuk WebSocket/CDN:
  - Buka `menu` → **[ 5] Protocol Gateway & Edge Settings** → Pilih **Change Public Edge Ports** ke `80` & `443`.
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
