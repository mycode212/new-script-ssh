# 📖 Panduan Lengkap Instalasi & Konfigurasi Script VPS

**Auto Script SSH By : ProgoCloud** (Versi: `0.9.9`)  
*Panduan langkah demi langkah dari server baru (Fresh VPS) hingga siap digunakan untuk produksi dan integrasi bot/panel reseller.*

---

## 🖥️ 1. Persyaratan Sistem (System Requirements)

Pastikan server VPS Anda memenuhi kriteria berikut:
* **Sistem Operasi**: 
  * Ubuntu 20.04, 22.04, 24.04 LTS (64-bit / ARM64)
  * Debian 10, 11, 12 (64-bit / ARM64)
* **Status VPS**: Fresh Install (Server baru / OS baru di-install ulang).
* **Hak Akses**: User **`root`** (`sudo -i`).
* **Spesifikasi Minimal**:
  * RAM: 512 MB (Disarankan 1 GB atau lebih).
  * Storage: 10 GB disk space.
  * Port 80, 443, 22 terbuka (tidak diblokir oleh security group / firewall cloud provider).

---

## 🔑 2. Pendaftaran Lisensi IP VPS

Sebelum menjalankan instalasi, pastikan IP Publik VPS Anda telah terdaftar dan berstatus aktif pada portal lisensi resmi ProgoCloud:
* 🌐 **Portal Lisensi**: [https://autoscript-license-3xj.pages.dev](https://autoscript-license-3xj.pages.dev)
* 💬 **Support Telegram**: [@progocloud](https://t.me/progocloud)

---

## ⚡ 3. Langkah Instalasi (Quick 1-Line Command)

### Langkah A: Login ke VPS via SSH
Buka terminal (Putty, Termius, atau Terminal Linux/macOS) dan login sebagai root:
```bash
ssh root@IP_VPS_ANDA
```

### Langkah B: Jalankan Perintah Instalasi 1-Baris
Salin dan jalankan perintah berikut:
```bash
apt update -y && apt install -y curl wget git && curl -fsSL https://raw.githubusercontent.com/mycode212/new-script-ssh/main/install.sh | bash
```

> **Alternatif via Git Clone (Manual):**
> ```bash
> git clone https://github.com/mycode212/new-script-ssh.git /opt/pgy-source
> cd /opt/pgy-source && bash install.sh
> ```

### Langkah C: Proses Instalasi Berjalan Otomatis
Proses instalasi akan berjalan sekitar 1–3 menit meliputi:
1. Validasi IP ke Server Lisensi ProgoCloud.
2. Pengunduhan & kompilasi binary (HAProxy, Nginx, Xray Core, BadVPN, Wireproxy WARP, Ookla Speedtest).
3. Pembuatan konfigurasi TLS PKI OpenVPN & WebSocket Bridge.
4. Pengaturan firewall IPTables anti-torrent.
5. Pembuatan shortcut perintah **`menu`** dan **`pgy`**.

---

## 🚀 4. Langkah Konfigurasi Pasca Instalasi (Urutan Wajib)

Setelah proses instalasi selesai, ketik **`menu`** di terminal untuk membuka antarmuka utama. Ikuti urutan konfigurasi berikut agar seluruh fitur berjalan optimal:

```
                  URUTAN KONFIGURASI YANG DISARANKAN
  ┌─────────────────────────────────────────────────────────────────┐
  │  Langkah 1: Setup Kredensial Cloudflare API                     │
  │  Langkah 2: 1-Click Subdomain VPS & Terbitkan Sertifikat SSL    │
  │  Langkah 3: 1-Click Setup Cloudflare Zero Trust Tunnel          │
  │  Langkah 4: Aktifkan REST API Daemon & Xray Multi-Protocol      │
  │  Langkah 5: Siap Digunakan (Buat Akun / Hubungkan Bot Reseller) │
  └─────────────────────────────────────────────────────────────────┘
```

---

### 🌐 Langkah 1: Setup Kredensial Cloudflare API
1. Pada menu utama, ketik **`7`** untuk membuka menu **Domain & SSL Cert**.
2. Pilih **`[ 6] Cloudflare Automation Hub (DNS & Zone)`** → Pilih **`[ 2] Setup / Perbarui Kredensial Cloudflare API`**.
3. Pilih metode **`1` (API Token)**.
4. Masukkan **Cloudflare API Token** Anda (pastikan memiliki izin *Zone:Read* dan *Zone.DNS:Edit*).
5. Script otomatis mendeteksi semua domain pada akun Anda dan memilih domain utama (misal: `arjunacloud.app`).

---

### 🌐 Langkah 2: 1-Click Auto Pointing Subdomain VPS & SSL
1. Di menu **Domain & SSL Cert**, pilih **`[ 1] 1-Click Auto Pointing Subdomain VPS (Cloudflare)`**.
2. Masukkan prefix subdomain Anda (contoh: ketik **`sg2`**).
3. Pilih mode proxy:
   * **`[ 1] DNS Only (Gray Cloud)`** — *(Direkomendasikan untuk stabilitas SSH Direct, OpenVPN, dan Xray).*
   * **`[ 2] Proxied CDN (Orange Cloud)`** — *(Untuk WebSocket CDN port 80/443 bug kuota).*
4. Script otomatis membuat record `A` di Cloudflare (`sg2.arjunacloud.app -> IP_VPS`).
5. Pilih **`[ 2] Issue / Renew Let's Encrypt SSL`** untuk menerbitkan sertifikat SSL HTTPS resmi pada domain tersebut.

---

### 🛡️ Langkah 3: 1-Click Cloudflare Zero Trust Tunnel
*(Wajib dikonfigurasi agar OpenVPN Web Portal dan REST API dapat diakses via HTTPS tanpa port non-standar terblokir Cloudflare CDN).*

1. Di menu Domain & SSL, pilih **`[ 7] Cloudflare Tunnel (Zero Trust HTTPS)`**.
2. Pilih **`[ 1] Otomatis Buat Tunnel & Domain (Cloudflare API 1-Click)`**.
3. Tekan **`Y`** untuk menggunakan kredensial Cloudflare yang tersimpan di Langkah 1.
4. Script akan secara otomatis:
   * Membuat Tunnel baru di akun Cloudflare Anda.
   * Mengarahkan `vpn.domain.com` ➔ `localhost:1180` (OpenVPN Web Portal).
   * Mengarahkan `api.domain.com` ➔ `localhost:8780` (REST API Daemon).
   * Membuat record CNAME di Cloudflare dan menjalankan daemon `cloudflared.service`.

---

### 🤖 Langkah 4: Aktifkan REST API Daemon (Integrasi Bot / Web)
1. Kembali ke menu utama, pilih **`[16] REST API Manager`**.
2. Pilih **`[ 1] Toggle Enable / Disable API Daemon`** untuk mengaktifkan daemon.
3. Pilih **`[ 2] Lihat Detail Kredensial (API Key & Port)`** untuk menyalin **API Key** Anda.
4. Pilih **`[ 6] Testing & Integrasi cURL`** untuk melihat contoh perintah request JSON (SSH, OpenVPN, Xray VMess/VLESS/Trojan).

---

### 📡 Langkah 5: Setup SlowDNS / DNSTT (Opsional - Bypass Kuota DNS)
1. Pada menu utama, pilih **`[ 5] Install or View DNSTT (Port 53)`**.
2. Pilih target forwarding (SSH Port 22 atau V2Ray Port 8787).
3. Karena Cloudflare API sudah aktif, pilih **`[ 1] 1-Click Otomatis Buat Record di Cloudflare`**.
4. Script langsung membuatkan:
   * `A` Record: `ns-sg2.domain.com` ➔ `IP_VPS`
   * `NS` Record: `tun-sg2.domain.com` ➔ `ns-sg2.domain.com`
5. SlowDNS langsung aktif dan menampilkan Public Key DNSTT Anda.

---

## 📱 5. Ringkasan Perintah Penting (CLI Shortcuts)

| Perintah | Fungsi |
|---|---|
| **`menu`** | Membuka Dashboard Menu Utama ProgoCloud |
| **`pgy`** | Shortcut alternatif untuk membuka menu |
| **`pgy-update`** | Memperbarui script ke versi terbaru secara instan |
| **`pgy_api_service.py`** | Binary daemon REST API port `8780` |

---

## 🗑️ 6. Cara Uninstall Total (Clean Removal)

Jika ingin membersihkan seluruh instalasi dan mengembalikan VPS ke kondisi awal (fresh):
1. Ketik **`menu`** di terminal.
2. Pilih **`[12] System Uninstall & Total Cleanup`**.
3. Konfirmasi dengan mengetik **`y`**.
4. Script akan:
   * Menghentikan dan menghapus semua background service (`cloudflared`, `xray`, `haproxy`, `nginx`, `wireproxy`, `pgy-api`, dll).
   * Menghapus Tunnel dan CNAME remote di akun Cloudflare secara bersih.
   * Menghapus folder konfigurasi `/etc/pgytunnel`, `/etc/xray`, `/etc/wireproxy`, dan `/usr/local/bin/*`.
   * Mengembalikan konfigurasi `/etc/ssh/sshd_config` dan aturan firewall IPTables asli.

---

## 🤝 7. Bantuan & Dukungan Komunitas

Jika mengalami kendala saat instalasi atau konfigurasi:
* 💬 **Grup & Channel Telegram**: [@progocloud](https://t.me/progocloud)
* 🌐 **Website Resmi**: [https://autoscript-license-3xj.pages.dev](https://autoscript-license-3xj.pages.dev)
* 🐛 **Laporkan Bug / Request Fitur**: [GitHub Issues](https://github.com/mycode212/new-script-ssh/issues)
