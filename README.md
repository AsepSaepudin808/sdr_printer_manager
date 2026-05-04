# 🖨️ SDR Printer Manager

Aplikasi Android berbasis **Flutter** yang bertindak sebagai *Local Print Server* (Virtual IoT Box) untuk menjembatani sistem kasir **Odoo 18 Point of Sale (POS)** dengan **Printer Thermal Bluetooth**. Dibuat khusus untuk kebutuhan operasional dRetail Mart.

Sistem ini memungkinkan kasir mencetak struk secara **langsung (Direct Print)** dari *browser* ke printer thermal tanpa memerlukan perangkat keras Odoo IoT Box yang mahal.

---

## ✨ Fitur Utama

- 🚀 **Bypass Odoo IoT Box:** Mengubah HP/Tablet Android menjadi pelayan cetak (*Print Server*) mandiri.
- ⚡ **Auto-Print & Manual Print:** Mendukung cetak otomatis setelah validasi pembayaran, maupun cetak ulang manual (Full / Basic Receipt).
- 📡 **Smart Error Notification:** Jika aplikasi tertutup atau printer mati, Odoo POS tidak akan *crash/hang*, melainkan memunculkan popup notifikasi *Error* merah.
- 🔄 **Seamless Background Process:** Aplikasi dapat di-*minimize* dan berjalan di latar belakang tanpa mengganggu layar kasir.
- 🧻 **Auto-Scaling Layout (58mm & 80mm):** Menggunakan ESC/POS *byte commands* asli yang secara otomatis menyesuaikan kerapatan karakter printer (Optimal untuk printer seperti Panda BT, Eppos, dll).

---

## 🛠️ Topologi & Skema Penggunaan

Aplikasi ini mendukung 2 skema operasional tergantung pada perangkat keras di toko Anda.

```mermaid
graph TD
    subgraph SKEMA 1: Standalone (1 Perangkat)
        direction TB
        Tab[Tablet Kasir Android]
        Tab -->|Membuka| Web1(Odoo POS Browser)
        Tab -->|Berjalan di Background| App1(SDR Printer Manager)
        Web1 -->|HTTP POST localhost:8080| App1
        App1 -->|Bluetooth| P1((Printer Thermal))
    end

    subgraph SKEMA 2: Client-Server (2 Perangkat)
        direction TB
        PC[PC / Laptop Kasir Utama]
        HP[HP Android Khusus Print Server]
        
        PC -->|Membuka| Web2(Odoo POS Browser)
        HP -->|Berjalan| App2(SDR Printer Manager)
        
        Web2 -->|HTTP POST IP_Lokal:8080 via WiFi| App2
        App2 -->|Bluetooth| P2((Printer Thermal))
    end
    
    classDef hardware fill:#2d3436,stroke:#1346A0,stroke-width:2px,color:#fff;
    classDef software fill:#06C270,stroke:#000,stroke-width:1px,color:#fff;
    classDef web fill:#7B2FBE,stroke:#000,stroke-width:1px,color:#fff;
    
    class Tab,PC,HP,P1,P2 hardware;
    class App1,App2 software;
    class Web1,Web2 web;
