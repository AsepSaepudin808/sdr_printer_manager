# 🖨️ SDR Printer Manager

Aplikasi Android berbasis **Flutter** yang bertindak sebagai *Local Print Server* (Virtual IoT Box) untuk menjembatani sistem kasir **Odoo 18 Point of Sale (POS)** dengan **Printer Thermal Bluetooth**. Dibuat khusus untuk kebutuhan operasional dRetail Mart.

Sistem ini memungkinkan kasir mencetak struk secara **langsung (Direct Print)** dari *browser* ke printer thermal tanpa memerlukan perangkat keras Odoo IoT Box yang mahal.

---

## ✨ Fitur Utama

- 🚀 **Bypass Odoo IoT Box:** Mengubah HP/Tablet Android menjadi pelayan cetak (*Print Server*) mandiri.
- ⚡ **Auto-Print & Manual Print:** Mendukung cetak otomatis setelah validasi pembayaran, maupun cetak ulang manual (Full / Basic Receipt).
- 📡 **Smart Error Notification:** Jika aplikasi tertutup atau printer mati, Odoo POS tidak akan *crash/hang*, melainkan memunculkan popup notifikasi *Error* merah.
- 🔄 **Seamless Background Process:** Aplikasi dapat di-*minimize* dan berjalan di latar belakang tanpa mengganggu layar kasir.
- 🧻 **Auto-Scaling Layout:** Menggunakan ESC/POS *byte commands* asli yang secara otomatis menyesuaikan kerapatan karakter printer (Optimal untuk printer thermal 58mm & 80mm).

---

## 🛠️ Topologi & Skema Penggunaan

Aplikasi ini sangat fleksibel dan mendukung 2 skema operasional:

```mermaid
graph TD
    subgraph Skema_1 ["SKEMA 1: Standalone (1 Perangkat)"]
        T1["📱 Tablet/HP Kasir"] --> W1("🌐 Odoo POS (Browser)")
        T1 --> A1("⚙️ SDR Printer Manager")
        W1 -- "Kirim JSON (localhost:8080)" --> A1
        A1 -- "Kirim Bytes (Bluetooth)" --> P1(("🖨️ Printer Panda BT"))
    end

    subgraph Skema_2 ["SKEMA 2: Client-Server (2 Perangkat)"]
        C2["💻 PC/Laptop Kasir"] --> W2("🌐 Odoo POS (Browser)")
        H2["📱 HP Android (Server)"] --> A2("⚙️ SDR Printer Manager")
        W2 -- "Kirim JSON (IP_Lokal:8080)" --> A2
        A2 -- "Kirim Bytes (Bluetooth)" --> P2(("🖨️ Printer Panda BT"))
    end
