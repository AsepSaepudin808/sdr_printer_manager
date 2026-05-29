🚀 RELEASE NOTES: dPrinter Mart v1.0.2 (26 Mei 2026)

---

⚙️ *---- Application Profile ----*
*Spesifikasi Teknis Aplikasi:*
• *Nama Aplikasi:* dPrinter Mart (id.dretail.sdr_printer_manager)
• *Versi Aplikasi:* v1.0.2 (Version Code: 13)
• *Framework:* Flutter (Android Native Service)

---

📄 *---- Overview Product ----*
*Tentang dPrinter Mart:*
Aplikasi Android berbasis Flutter yang berfungsi sebagai Local Print Server mandiri. Aplikasi ini dirancang khusus sebagai middleware untuk menjembatani dRetail Mart dengan Printer Thermal Bluetooth secara langsung, menghilangkan ketergantungan pada hardware tambahan seperti IoT Box.

---

## 🔄 *Perubahan & Peningkatan Utama*

### ⚡ 1. Performa Tab Switching - Instant Navigation
*Masalah:* Perpindahan antar tab terasa lambat dan judul tab bertumpuk saat switching cepat.
*Solusi:* Mengganti `AnimatedSwitcher` dengan `IndexedStack` untuk caching tab content.
*Hasil:* Tab switching sekarang instant tanpa delay atau animasi fade.

### 🌐 2. Multi-Language System - Reactive Localization
*Masalah:*
- 40+ string hardcoded di berbagai file (tidak bisa diterjemahkan)
- Sistem `S.isEn ? 'English' : 'Indonesia'` tidak scale ke bahasa lain (ms, th, zh, ar)
- Perpindahan bahasa memerlukan restart aplikasi

*Solusi:*
- Centralized semua string ke `strings.dart`
- Membuat `LangNotifier extends ChangeNotifier` untuk reactive rebuild
- `ListenableBuilder` wrapper di root app

*Hasil:* UI berubah secara real-time saat bahasa dipilih, tanpa restart aplikasi.

### 🛠️ 3. Refactoring & Code Quality
*Yang dilakukan:*
- Upgrade state management ke Riverpod
- Ekstrak 8 reusable widget components
- Hapus file unused
- Standarisasi naming conventions

*Hasil:* Project lebih maintainable dan mudah dikembangkan.

---

## 🆕 *Fitur Baru*

### 💰 1. Cash Drawer Integration
Fitur buka laci kasir otomatis untuk alur kasir modern.

*Konfigurasi:*
- *Off:* Cash drawer tidak aktif
- *Open Before Print:* Laci terbuka sebelum proses cetak
- *Open After Print:* Laci terbuka setelah proses cetak selesai

*Opsi Tambahan:*
- Trigger laci pada Session Summary Report

### 📊 2. Filter Tanggal di Statistik
Filter riwayat cetak berdasarkan rentang tanggal tertentu untuk analisis yang lebih granular.

### 🎨 3. Tab Alignment Text Enhancements
Toolbar format teks dengan 4 mode alignment:
- Rata Kiri
- Rata Tengah
- Rata Kanan
- Rata Kiri Kanan (Justify)

---

## 🐛 *Perbaikan Bug*

### Bluetooth
- Sistem retry otomatis hingga 3x attempt saat koneksi terputus
- Pesan error lebih informatif
- Timeout handling lebih optimal

### UI/UX
- Smooth scroll physics di berbagai list
- Consistent spacing dan padding
- Loading states yang lebih jelas

---

## 📝 *Daftar File yang Diubah*

| File | Perubahan |
|------|----------|
| `lib/main.dart` | ListenableBuilder wrapper, S.load() initialization |
| `lib/utils/strings.dart` | 40+ string baru, LangNotifier class |
| `lib/screens/main_shell.dart` | IndexedStack, S.strings replacement |
| `lib/screens/scan_screen.dart` | S.strings replacement |
| `lib/screens/log_screen.dart` | S.strings replacement |
| `lib/screens/text_tab.dart` | S.strings replacement, alignment toolbar |
| `lib/screens/widgets/test_print_card.dart` | S.strings replacement |
| `lib/screens/widgets/port_card.dart` | S.strings replacement |

---

## 📥 *Download & Dokumentasi*

*Link Download APK dPrinter Mart V1.0.2:*
https://drive.google.com/drive/folders/1pOkfdMvTN6aLepIp5EtWG5cM5sGkgwWt

*Dokumentasi & Panduan Quick Start Guide:*
https://drive.google.com/drive/folders/1B55JHtoyIgKmt9SwJa-eMoLblGfqt0ay

---

**Tim dRetail Mart**
*Build with ❤️ for better retail experience*
