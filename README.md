<p align="center">
  <img src="https://img.shields.io/badge/ProgoCloud-SSH--SCRIPT-00d4ff?style=for-the-badge&logo=linux&logoColor=black" alt="Auto Script SSH By : ProgoCloud">
  <img src="https://img.shields.io/badge/Version-2.1.0-green?style=for-the-badge" alt="Version">
  <img src="https://img.shields.io/badge/Platform-Linux-blue?style=for-the-badge&logo=linux" alt="Platform">
  <img src="https://img.shields.io/badge/Shell-Bash-4EAA25?style=for-the-badge&logo=gnubash&logoColor=white" alt="Bash">
</p>

<h1 align="center">Auto Script SSH By : ProgoCloud</h1>

<p align="center">
  <b>Advanced & Modular SSH Tunnel Management System for Linux VPS</b><br>
  Developed & maintained by <b>ProgoCloud</b>
</p>

<p align="center">
  <a href="https://github.com/mycode212/new-script-ssh/stargazers"><img src="https://img.shields.io/github/stars/mycode212/new-script-ssh?style=social" alt="Stars"></a>
  <a href="https://github.com/mycode212/new-script-ssh/releases"><img src="https://img.shields.io/badge/Release-Stable-brightgreen" alt="Release"></a>
  <a href="https://t.me/progocloud"><img src="https://img.shields.io/badge/Telegram-@progocloud-2CA5E0?style=flat-square&logo=telegram" alt="Telegram"></a>
  <a href="https://autoscript-license-3xj.pages.dev"><img src="https://img.shields.io/badge/License_Portal-ProgoCloud-00d4ff?style=flat-square" alt="License Portal"></a>
</p>

---

## Overview

**Auto Script SSH By : ProgoCloud** adalah sistem manajemen VPN & SSH tunneling modular berkinerja tinggi untuk server Linux VPS (Debian/Ubuntu). Script ini menyediakan dashboard CLI interaktif untuk mengelola akun SSH/OpenVPN, pemantauan kuota & bandwidth real-time, perlindungan lisensi IP server, serta penerapan multi-protokol tunneling dalam satu antarmuka terintegrasi.

Arsitektur sistem dibangun secara modular di bawah pustaka `/pgy-lib/opt/` untuk memastikan stabilitas tinggi, pembaruan atomic tanpa mengganggu konfigurasi server, serta perlindungan akun dan data pengguna yang aman.

---

## Fitur Utama

### 1. Manajemen Pengguna (User Management)
- **Operasi CRUD Akun** — Buat, hapus, perpanjang (*renew*), ubah password, batas login simultan (*max login*), dan kuota bandwidth per pengguna.
- **Bulk Create Users** — Pembuatan banyak akun sekaligus secara otomatis.
- **Trial Accounts** — Pembuatan akun uji coba (1–72 jam) dengan auto-cleanup dan pemantauan sisa durasi aktif.
- **Lock & Unlock Akun** — Kunci akses akun secara instan tanpa menghapus data profil pengguna.
- **Pembersihan Akun Kedaluwarsa** — Hapus seluruh akun yang telah expired dengan satu klik.

### 2. Pemantauan Bandwidth & Batas Kuota
- **Pelacakan Traffic I/O Real-Time** — Perhitungan presisi per-PID proses koneksi via `/proc/<pid>/io`.
- **Batas Kuota Bandwidth (GB)** — Putus dan tolak koneksi otomatis jika kuota data telah habis.
- **Live Traffic Monitor & VNStat** — Tampilan konsumsi data harian dan bulanan.
- **Anti-Torrent Protection** — Aturan firewall IPTables otomatis untuk memblokir aktivitas BitTorrent.

### 3. Dynamic Post-Auth SSH Banners
- **Banner Status Cerdas** — Pesan personal dinamis sesuai status akun (*Active, Expired, Quota Ended, Locked, Session Full*).
- **DarkTunnel & HTTP Custom Optimized** — Kompatibilitas format HTML banner untuk berbagai aplikasi tunnel Android/PC.
- **Post-Auth PAM Hook** — Informasi akun hanya dikirimkan setelah autentikasi password sukses demi menjaga privasi.

### 4. Protokol Tunneling & Proxy Stack
- **Direct SSH** — OpenSSH pada port 22 dengan optimasi kestabilan koneksi.
- **OpenVPN Protocol Suite** — Dukungan direct UDP/TCP, HTTP CONNECT proxy, WebSocket payload, WSS/SNI, dan SSL/SNI.
- **BadVPN / UDPGW** — Port 7300 untuk koneksi gaming dan panggilan suara (VoIP).
- **SlowDNS / DNSTT** — Tunneling berbasis DNS pada port UDP 53.
- **ZiVPN** — UDP direct listener port 5667 dan rentang port forwarding 6000–19999.
- **HAProxy Edge & Nginx SSL** — Reverse-proxy edge stack dengan port publik HTTP (2080) dan TLS/HTTPS (442).
- **WS-to-SSH Bridge** — Jembatan WebSocket ke SSH port 8890 untuk payload injeksi HTTP kustom.

### 5. Keamanan & Lisensi Terintegrasi
- **License Guard ProgoCloud** — Validasi otomatis IP publik VPS ke server lisensi resmi ProgoCloud sebelum instalasi dan setiap kali mengakses menu.
- **Domain & SSL Certificate Manager** — Penerbitan dan pembaruan otomatis sertifikat SSL Let's Encrypt (Certbot), sertifikat kustom, atau self-signed.
- **Auto-Reboot Task** — Penjadwalan reboot harian otomatis pada pukul 00:00.
- **Backup & Restore Telegram Bot** — Pencadangan otomatis database akun langsung ke bot Telegram Anda.

---

## Port Default Layanan

| Port | Protokol | Keterangan Layanan |
|---|---|---|
| `22` | TCP | OpenSSH Server |
| `7300` | UDP | BadVPN / UDPGW (Gaming Port) |
| `53` | UDP | SlowDNS / DNSTT Server |
| `5667` | UDP | ZiVPN Server |
| `6000–19999` | UDP | ZiVPN Port Range Forwarding |
| `2080` | TCP / HTTP | HAProxy Edge Public HTTP / WS |
| `442` | TCP / TLS | HAProxy Edge Public HTTPS / SSL |
| `8770` | TCP / HTTP | Nginx Internal Proxy |
| `8771` | TCP / TLS | Nginx Internal TLS Proxy |
| `8890` | TCP | WebSocket-to-SSH Bridge Daemon |
| `1180` | HTTP / HTTPS | OpenVPN Web Documentation & Profile Portal |

---

## Supported OS & Architectures

Auto Script SSH By : ProgoCloud dirancang dan dioptimalkan untuk VPS Linux keluarga Debian/Ubuntu berbasis **APT** dan **systemd**.

### 1. Sistem Operasi yang Didukung

| Distribusi Linux | Versi yang Didukung | Status Rekomendasi |
|---|---|---|
| **Ubuntu Server** | 20.04 (Focal), 22.04 (Jammy), 24.04 (Noble) & versi lebih baru | **Sangat Direkomendasikan (LTS)** |
| **Debian** | Debian 11 (Bullseye), Debian 12 (Bookworm) & versi lebih baru | **Sangat Direkomendasikan (Stable)** |
| **Kali Linux** | Rolling Releases (berbasis systemd) | Kompatibel |
| **Armbian / DietPi** | Versi berbasis Debian / Ubuntu | Kompatibel |

### 2. Arsitektur CPU

| Arsitektur | Alias | Status Dukungan |
|---|---|---|
| **x86_64 / 64-bit Intel/AMD** | `amd64`, `x86_64` | **Dukungan Penuh (Semua Protokol)** |
| **ARM 64-bit** | `arm64`, `aarch64` | **Dukungan Penuh** |
| **ARM 32-bit** | `armv7l`, `armhf` | Kompatibel untuk modul inti SSH |

### 3. Persyaratan Minimum VPS
- **Akses:** Wajib hak akses penuh sebagai **root** (`sudo -i`).
- **RAM:** Minimum 512 MB (Disarankan 1 GB atau lebih).
- **Penyimpanan:** Minimum 2 GB ruang kosong.
- **Jaringan:** IP VPS publik statis dengan koneksi internet aktif.

---

## Installation

**One-line install (as root):**

```bash
bash <(curl -Ls https://raw.githubusercontent.com/mycode212/new-script-ssh/main/install.sh)
```

**Manual install:**

```bash
curl -LO https://raw.githubusercontent.com/mycode212/new-script-ssh/main/install.sh
chmod +x install.sh
./install.sh
```

After installation, type **`menu`** or **`pgy`** to launch the management interface.

---

## Pembaruan Script (Update)

Untuk memperbarui pustaka modul dan fitur terbaru tanpa menghapus akun atau konfigurasi yang sudah ada:

```bash
pgy-update
```
atau melalui **`menu → 23) Update Script`**.

---

## Manajemen Lisensi

- **Pemeriksaan Status Lisensi:**
  ```bash
  pgy-license-check status
  ```
- **Portal Aktivasi / Perpanjangan:** [https://autoscript-license-3xj.pages.dev](https://autoscript-license-3xj.pages.dev)
- **Layanan Bantuan & Support:** [Telegram @progocloud](https://t.me/progocloud)

---

## Uninstaller (Hapus Script)

Untuk menghapus script secara menyeluruh:

```bash
menu → 99) Uninstall Script
```

Proses uninstaller akan membersihkan seluruh layanan background, aturan firewall, dan pustaka sistem secara bersih.

---

## Copyright & License

&copy; **ProgoCloud**. All rights reserved.  
Repository: [https://github.com/mycode212/new-script-ssh](https://github.com/mycode212/new-script-ssh)  
Layanan & Dukungan: [https://t.me/progocloud](https://t.me/progocloud)
