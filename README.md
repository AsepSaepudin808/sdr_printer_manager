# 🖨️ dPrinter Mart

**Versi 1.0.2** | Package: `id.dprinter.mart` | Min SDK: Android 5.0+ (API 21)

Aplikasi Android berbasis **Flutter** yang berfungsi sebagai **Local Print Server** untuk menjembatani sistem kasir **Odoo 18 POS** dengan **Printer Thermal Bluetooth**, tanpa memerlukan perangkat keras IoT Box.

---

## ✨ Fitur Utama

| Fitur | Deskripsi |
|-------|-----------|
| 🚀 **Bypass IoT Box** | Mengubah HP/Tablet Android menjadi print server mandiri |
| 🧾 **Full & Basic Receipt** | Dua mode struk — lengkap dan ringkas |
| 📊 **Session Summary** | Laporan ringkasan sesi kasir (Gross Sales, DPP, PPN, Pembayaran, Kas) |
| 💰 **Cash Drawer** | Kontrol laci kasir otomatis sebelum/sesudah cetak |
| 🔄 **Print Queue** | Antrian otomatis dengan retry saat koneksi kembali |
| ⚡ **Auto-Print** | Cetak otomatis setelah validasi pembayaran di Odoo POS |
| 📝 **Free Text Print** | Cetak teks bebas langsung dari aplikasi |
| 🖼️ **Image Print** | Cetak gambar dari galeri ke printer thermal |
| 📑 **PDF Print** | Render dan cetak dokumen PDF halaman per halaman |
| 🔄 **HTTP Server Background** | Server berjalan di port `8080`, tetap aktif saat di-minimize |
| 🌐 **Multi-Bahasa** | Mendukung Bahasa Indonesia dan English |

---

## 🏗️ Arsitektur Sistem

```
┌─────────────────────────────────────────────────────────────────┐
│                        SKEMA 1: Standalone                      │
│                     (1 Perangkat - RECOMMENDED)                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│    ┌──────────────┐              ┌─────────────────────────┐    │
│    │   Tablet/HP  │              │      dPrinter Mart      │    │
│    │              │              │                         │    │
│    │ ┌──────────┐ │   HTTP       │  ┌─────────────────┐    │    │
│    │ │  Odoo    │ │─────────────▶│  │ HTTP Server     │    │    │
│    │ │  POS     │ │ localhost    │  │ Port: 8080      │    │    │
│    │ └──────────┘ │   :8080      │  └────────┬────────┘    │    │
│    └──────────────┘              │           │             │    │
│                                  │           ▼             │    │
│                                  │   ┌─────────────────┐   │    │
│                                  │   │  Bluetooth      │   │    │
│                                  │   │  Service        │   │    │
│                                  │   └────────┬────────┘   │    │
│                                  └────────────┼────────────┘    │
│                                               │                 │
│                                               ▼                 │
│                                        ┌─────────────┐          │
│                                        │   Printer   │          │
│                                        │   Thermal   │          │
│                                        │   Bluetooth │          │
│                                        └─────────────┘          │
└─────────────────────────────────────────────────────────────────┘
```

### Alur Kerja

1. **Odoo POS** mengirim `POST /print` dengan payload JSON ke HTTP Server
2. **dPrinter Mart** mem-parsing JSON dan konversi ke **ESC/POS bytes**
3. Data dikirim ke **Printer Thermal** via Bluetooth
4. Status sukses/error dikembalikan ke Odoo POS secara realtime

---

## 📱 Persyaratan Perangkat

### Spesifikasi Minimum

| Komponen | Minimum | Direkomendasikan |
|----------|---------|------------------|
| **Android Version** | 5.0 Lollipop (API 21) | Android 10+ (API 29) |
| **RAM** | 2 GB | 3 GB atau lebih |
| **Penyimpanan** | 100 MB | 200 MB atau lebih |
| **Bluetooth** | Bluetooth 4.0 (BLE) | Bluetooth 5.0+ |

### Kompatibilitas Android Version

| Versi | API | Status |
|-------|-----|--------|
| Android 5.0 - 5.1 (Lollipop) | 21-22 | ✅ Supported |
| Android 6.0 (Marshmallow) | 23 | ✅ Supported |
| Android 7.0 - 8.1 (Nougat/Oreo) | 24-27 | ✅ Supported |
| Android 9.0 (Pie) | 28 | ✅ Supported |
| Android 10.0 | 29 | ✅ Supported |
| Android 11.0 | 30 | ✅ Supported |
| Android 12.0 | 31 | ✅ Supported |
| Android 13.0 | 33 | ✅ Supported |
| Android 14.0 - 16.0 | 34-36 | ✅ Supported |

### Printer yang Kompatibel

- ✅ Printer Thermal Bluetooth dengan dukungan **ESC/POS**
- ✅ Lebar kertas: **58mm**, **80mm**, atau **100mm**

**Contoh Printer:** Epson TM-82III/TM-88IV, Star TSP100, GPrinter GP-5890X, Xprinter XP-80

---

## 📋 Izin Android

| Izin | API | Keterangan |
|------|-----|------------|
| `BLUETOOTH` / `BLUETOOTH_ADMIN` | 18+ | Scan & koneksi Bluetooth klasik |
| `BLUETOOTH_CONNECT` / `BLUETOOTH_SCAN` | 31+ | Bluetooth pada Android 12+ |
| `NEARBY_WIFI_DEVICES` | 33+ | Penemuan perangkat Android 13+ |
| `ACCESS_FINE_LOCATION` | 18+ | **Wajib** untuk scan Bluetooth |
| `INTERNET` / `ACCESS_NETWORK_STATE` | 1+ | HTTP Server & komunikasi POS |
| `FOREGROUND_SERVICE` | 28+ | Menjaga server aktif di background |
| `FOREGROUND_SERVICE_CONNECTED_DEVICE` | 34+ | Foreground service untuk device |
| `WAKE_LOCK` | 1+ | Menjaga CPU aktif saat printing |
| `POST_NOTIFICATIONS` | 33+ | Notifikasi foreground service |
| `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` | 23+ | Nonaktifkan battery optimization |

> ⚠️ **Catatan:** Izin Lokasi **wajib** karena Android memerlukan lokasi untuk scan Bluetooth. Ini adalah persyaratan sistem operasi.
>
> 🚨 **Background Service:** Aplikasi menggunakan Foreground Service untuk menjaga HTTP server tetap aktif saat di-minimize. Ini diperlukan agar print job dari Odoo POS tetap dapat diproses.

---

## 📂 Struktur Proyek

```
sdr_printer_manager/
├── pubspec.yaml
├── lib/
│   ├── main.dart                    # Entry point aplikasi
│   ├── models/
│   │   ├── printer_device.dart     # Model perangkat printer
│   │   └── print_history.dart      # Model riwayat cetak
│   ├── providers/
│   │   ├── app_state_provider.dart    # State aplikasi
│   │   ├── bluetooth_provider.dart    # Provider Bluetooth
│   │   ├── server_provider.dart       # Provider HTTP server
│   │   ├── history_provider.dart      # Provider riwayat
│   │   ├── logs_provider.dart         # Provider log aktivitas
│   │   └── print_queue_provider.dart  # Provider antrian cetak
│   ├── services/
│   │   ├── bluetooth_service.dart     # Koneksi Bluetooth + retry
│   │   ├── print_server_service.dart   # HTTP Server (port 8080)
│   │   ├── print_queue_service.dart    # Manajemen antrian offline
│   │   ├── print_history_service.dart  # Simpan riwayat cetak
│   │   └── foreground_service_helper.dart  # Foreground service
│   ├── screens/
│   │   ├── main_shell.dart         # Main shell + navigasi
│   │   ├── scan_screen.dart        # Scan perangkat Bluetooth
│   │   ├── settings_screen.dart    # Pengaturan aplikasi
│   │   ├── printer_settings_screen.dart  # Pengaturan printer
│   │   ├── log_screen.dart         # Layar riwayat log
│   │   ├── text_tab.dart           # Tab cetak teks bebas
│   │   ├── image_tab.dart          # Tab cetak gambar
│   │   ├── pdf_tab.dart # Tab cetak PDF
│   │   └── widgets/                # Komponen UI reusable
│   │       ├── status_card.dart
│   │       ├── printer_card.dart
│   │       ├── stats_row.dart
│   │       ├── port_card.dart
│   │       ├── test_print_card.dart
│   │       ├── log_card.dart
│   │       └── auto_start_card.dart
│   └── utils/
│       ├── escpos_helper.dart      # Builder perintah ESC/POS
│       ├── test_print_template.dart   # Template print test
│       ├── strings.dart # String localization
│       ├── constants.dart          # Konstanta aplikasi
│       └── colors.dart            # Warna tema aplikasi
├── android/
│   └── app/src/main/kotlin/
│       ├── MainActivity.kt # Activity utama
│       ├── SdrPrintService.kt     # Android Print Service
│       └── SdrForegroundService.kt  # Foreground Service
└── test/
    └── escpos_helper_test.dart    # Unit tests ESC/POS
```

---

## 📡 Endpoint HTTP Server

Server berjalan di **port 8080**:

| Method | Endpoint | Deskripsi |
|--------|----------|-----------|
| `GET` | `/status` | Status server & koneksi Bluetooth |
| `GET` | `/test-print?type=test_short` | Cetak test pendek |
| `GET` | `/test-print?type=test_long` | Cetak test lengkap |
| `POST` | `/print` | Cetak dengan format payload JSON |

### Format Payload `POST /print`

**1. Full Receipt:**
```json
{
  "format": "odoo_json",
  "data": {
    "name": "POS/2026/00123",
    "date": "2026-05-15T11:00:00Z",
    "cashier": "Kasir 1",
    "company": {
      "name": "dRetail Mart",
      "phone": "021-1234-5678",
      "currency": { "symbol": "Rp", "decimal_places": 0 }
    },
    "orderlines": [
      { "product_name": "Indomie Goreng", "qty": 2, "price": 3500 }
    ],
    "paymentlines": [{ "name": "Cash", "amount": 50000 }],
    "total_with_tax": 7000,
    "change": 43000
  }
}
```

**2. Session Summary:**
```json
{
  "format": "session_summary",
  "data": {
    "session_name": "POS/2026/0012",
    "gross_sales": 1500000,
    "total_taxes": 132450,
    "total_sales": 1650000,
    "payments": [{ "method": "CASH", "amount": 1000000 }]
  }
}
```

### Response
```json
{ "status": "ok", "message": "Print berhasil" }
```

---

## 🛠️ Teknologi

| Teknologi | Fungsi |
|-----------|--------|
| **Flutter ^3.5.0** | Framework |
| **flutter_riverpod ^3.3.1** | State management |
| **print_bluetooth_thermal** | Komunikasi Bluetooth |
| **shelf_router ^1.1.4** | HTTP Server (port 8080) |
| **pdfx ^2.6.0** | Render PDF |
| **image ^4.2.0** | Pemrosesan gambar thermal |
| **permission_handler ^11.3.1** | Manajemen izin Android |

---

## 🚀 Instalasi

### Prasyarat
- Flutter SDK `^3.5.0`
- Android Studio / VS Code
- Perangkat Android dengan USB Debugging aktif

### Build APK
```bash
# Install dependencies
flutter pub get

# Build release APK
flutter build apk --release
```

APK hasil build: `build/app/outputs/flutter-apk/app-release.apk`

---

## 📖 Panduan Penggunaan

### 1. Koneksi Printer
1. Buka **dPrinter Mart**
2. Pastikan **Bluetooth** dan **Lokasi** aktif
3. Ketuk **"Pilih"** pada kartu printer
4. Pilih printer thermal dari daftar

### 2. Aktifkan Server
1. Ketuk tombol **"Aktifkan Printer"**
2. Status berubah menjadi **"Printer Aktif"** (hijau)
3. URL Server: `http://192.168.1.100:8080`

### 3. Konfigurasi Odoo POS
1. Buka **POS > Configuration > Settings**
2. Aktifkan **SDR Direct Print**
3. Masukkan URL server
4. Simpan dan buka sesi POS

---

## 📦 Info Aplikasi

| Info | Nilai |
|------|-------|
| **Nama** | dPrinter Mart |
| **Package ID** | `id.dprinter.mart` |
| **Versi** | 1.0.2 |
| **Min SDK** | Android 5.0+ (API 21) |
| **Target SDK** | 36 |
| **HTTP Port** | 8080 |

---

## 📜 Lisensi

MIT License - © 2026 Sarana Digital Retail
