🚀 RELEASE NOTES: dPrinter Mart v1.0.2 (25 Mei 2026)

---

## 📌 Apa yang Baru di v1.0.2

### 🆕 Fitur Baru

#### 1. Antrian Cetak (Print Queue)
Cetak tidak berhasil karena printer mati atau terputus? Sekarang tidak perlu khawatir!
- Job cetak yang gagal akan otomatis masuk antrian
- Saat koneksi kembali, job akan dicetak otomatis
- Jika tetap gagal setelah 3x percobaan, baru akan ditandai gagal
- Jumlah antrian terlihat di dashboard

#### 2. Cash Drawer Support
- Buka laci kasir otomatis sebelum atau sesudah cetak
- Cocok untuk alur kasir yang butuh laci terbuka saat pembayaran

#### 3. Unit Tests
- 43 tes otomatis untuk memastikan fungsi cetak bekerja dengan benar
- Setiap perubahan kode baru akan diuji sebelum dirilis

---

## 🔧 Perbaikan & Peningkatan

### Upgrade ke Riverpod State Management
- Struktur project lebih rapi dan mudah dikembangkan
- Aplikasi lebih stabil dengan error handling yang lebih baik
- Responsif saat switching antar tab dan lebih efisien dalam penggunaan memori
- Konsistensi data antar fitur lebih terjamin

### Perbaikan Bluetooth
- Koneksi printer lebih stabil dengan sistem retry otomatis hingga 3x
- Pesan error lebih jelas jika koneksi gagal
- Timeout lebih optimal untuk berbagai kondisi jaringan

### Cleanup & Refactoring
- File yang tidak terpakai sudah dihapus
- Kode dipisah-pisah agar tidak campur aduk
- 8 komponen widget reusable baru untuk modularitas

---

## 📝 Catatan Upgrade

**Untuk upgrade dari v1.0.1:**
- Pastikan printer Bluetooth sudah ter-pair dengan perangkat
- Port default masih 8080 (bisa diubah di pengaturan)
- Antrian cetak tidak otomatis migrasi dari versi lama

**Tips:**
- Aktifkan Auto-Start agar server langsung aktif saat buka aplikasi
- Gunakan Test Print untuk cek koneksi sebelum digunakan

---

## 📥 Download

APK dPrinter Mart v1.0.2:
https://drive.google.com/drive/folders/1pOkfdMvTN6aLepIp5EtWG5cM5sGkgwWt

Panduan & Dokumentasi:
https://drive.google.com/drive/folders/1B55JHtoyIgKmt9SwJa-eMoLblGfqt0ay

---

**Tim dRetail Mart**
*Build with ❤️ for better retail experience*