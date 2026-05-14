import 'dart:typed_data';
import 'dart:convert';
import 'package:image/image.dart' as img;

enum PaperSize {
  mm58,
  mm80,
  mm100,
}

class EscPosHelper {
  static const int escCmd = 0x1B;
  static const int gsCmd = 0x1D;
  static const int lfCmd = 0x0A;
  static int _customCharsPerLine = 0;
  static int _extraFeed = 3;
  static bool _autoCut = false;
  static bool _useFontB = false; // Pengaturan dinamis untuk Font B
  static void setCustomCharsPerLine(int value) => _customCharsPerLine = value;
  static void setExtraFeed(int value) => _extraFeed = value;
  static void setAutoCut(bool value) => _autoCut = value;
  static void setUseFontB(bool value) => _useFontB = value;
  static int defaultCharsPerLine(PaperSize size) => switch (size) {
        PaperSize.mm58 => 32, // Standar hardware 58mm Font A adalah 32
        PaperSize.mm80 => 48,
        PaperSize.mm100 => 64,
      };
  static int charsPerLine(PaperSize size) =>
      _customCharsPerLine > 0 ? _customCharsPerLine : defaultCharsPerLine(size);
  static List<int> finalize() {
    final List<int> b = [];
    if (_extraFeed > 0) {
      b.addAll(feed(_extraFeed));
    }
    if (_autoCut) {
      b.addAll(cut());
    }
    return b;
  }

  // ── COMMANDS DASAR ──────────────────────────────────────────────────────────
  static Uint8List init() => Uint8List.fromList([escCmd, 0x40]);
  static Uint8List cut() => Uint8List.fromList([gsCmd, 0x56, 0x41, 0x00]);
  static Uint8List bold(bool on) =>
      Uint8List.fromList([escCmd, 0x45, on ? 1 : 0]);
  static Uint8List align(int a) => Uint8List.fromList([escCmd, 0x61, a]);
  static Uint8List feed(int n) => Uint8List.fromList([escCmd, 0x64, n]);
  // Command untuk mengubah ukuran font: Font B (huruf lebih kecil)
  static Uint8List setFontB(bool on) =>
      Uint8List.fromList([escCmd, 0x21, on ? 1 : 0]);

  // Double-height + double-width untuk nama toko (GS ! n)
  // n=0x11 = double height+width, n=0x00 = normal
  static Uint8List doubleSize(bool on) =>
      Uint8List.fromList([0x1D, 0x21, on ? 0x11 : 0x00]);

  // Hanya double-height (GS ! 0x01)
  static Uint8List doubleHeight(bool on) =>
      Uint8List.fromList([0x1D, 0x21, on ? 0x01 : 0x00]);
  static Uint8List imageEsc(img.Image src, PaperSize paperSize) {
    // Logo dibatasi 50% lebar kertas agar proporsional dan tidak terlalu dominan.
    // Lebar kertas penuh (dots): 58mm=384, 80mm=576, 100mm=768
    // 50% dari lebar penuh: 58mm=192, 80mm=288, 100mm=384
    int maxW = switch (paperSize) {
      PaperSize.mm58 => 192,
      PaperSize.mm80 => 288,
      PaperSize.mm100 => 384,
    };
    img.Image resized = src;

    // Convert RGBA to RGB first (handle transparency)
    // Bug fix: variabel pixel 'p' tidak pernah didefinisikan sebelumnya,
    // sehingga alpha blending gagal dan loop tidak berjalan sama sekali.
    // Perbaikan: gunakan src.getPixel(x, y) untuk mendapatkan pixel.
    if (src.numChannels == 4) {
      // RGBA to RGB: flatten to white background
      final rgbImage =
          img.Image(width: src.width, height: src.height, numChannels: 3);
      for (int y = 0; y < src.height; y++) {
        for (int x = 0; x < src.width; x++) {
          final p =
              src.getPixel(x, y); // <-- FIX: definisikan pixel dari sumber
          final r = p.r.toInt();
          final g = p.g.toInt();
          final bVal = p.b.toInt();
          final a = p.a.toInt();
          // Alpha blend with white background: white * (1-alpha) + color * alpha
          final double alpha = a / 255.0;
          final int blendedR =
              (r * alpha + 255 * (1 - alpha)).round().clamp(0, 255);
          final int blendedG =
              (g * alpha + 255 * (1 - alpha)).round().clamp(0, 255);
          final int blendedB =
              (bVal * alpha + 255 * (1 - alpha)).round().clamp(0, 255);
          rgbImage.setPixelRgb(x, y, blendedR, blendedG, blendedB);
        }
      }
      resized = rgbImage;
    }

    // Resize if larger than max width
    if (resized.width > maxW) {
      resized = img.copyResize(resized, width: maxW);
    }

    final int imgWidth = resized.width;
    final int imgHeight = resized.height;
    final int widthBytes = (imgWidth + 7) ~/ 8;

    // ── Step 1: Build grayscale float buffer untuk Floyd-Steinberg dithering ──
    // Ini jauh lebih baik dari simple threshold karena detail logo tetap terjaga.
    // Simple threshold (< 0.5) menyebabkan area abu2 dan gradient menjadi
    // sepenuhnya hitam atau putih tanpa transisi, sehingga detail logo hilang.
    final List<double> gray = List<double>.filled(imgWidth * imgHeight, 0.0);
    for (int y = 0; y < imgHeight; y++) {
      for (int x = 0; x < imgWidth; x++) {
        final pixel = resized.getPixel(x, y);
        // Luminance perceptual (Rec. 601)
        gray[y * imgWidth + x] =
            (0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b) / 255.0;
      }
    }

    // ── Step 2: Floyd-Steinberg dithering in-place ────────────────────────────
    // Error didistribusikan ke tetangga kanan, bawah-kiri, bawah, bawah-kanan
    // sehingga halftone alami terbentuk dan detail gambar tetap terlihat.
    final List<bool> bw = List<bool>.filled(imgWidth * imgHeight, false);
    for (int y = 0; y < imgHeight; y++) {
      for (int x = 0; x < imgWidth; x++) {
        final idx = y * imgWidth + x;
        final oldVal = gray[idx].clamp(0.0, 1.0);
        final newVal = oldVal < 0.5 ? 0.0 : 1.0; // quantize
        bw[idx] = newVal == 0.0; // true = pixel hitam (cetak)
        final err = oldVal - newVal;
        // Distribusi error (Floyd-Steinberg weights: 7/16, 3/16, 5/16, 1/16)
        if (x + 1 < imgWidth) {
          gray[idx + 1] += err * (7.0 / 16.0);
        }
        if (y + 1 < imgHeight) {
          if (x - 1 >= 0) {
            gray[(y + 1) * imgWidth + (x - 1)] += err * (3.0 / 16.0);
          }
          gray[(y + 1) * imgWidth + x] += err * (5.0 / 16.0);
          if (x + 1 < imgWidth) {
            gray[(y + 1) * imgWidth + (x + 1)] += err * (1.0 / 16.0);
          }
        }
      }
    }

    // ── Step 3: Pack bits dan buat ESC/POS raster command ─────────────────────
    final List<int> output = [];
    // ESC/POS raster bit image command: GS v 0 m xL xH yL yH [data]
    output.addAll([gsCmd, 0x76, 0x30, 0x00]); // m=0 (normal density)
    output.addAll([widthBytes % 256, widthBytes ~/ 256]); // xL, xH
    output.addAll([imgHeight % 256, imgHeight ~/ 256]); // yL, yH

    for (int y = 0; y < imgHeight; y++) {
      for (int byteX = 0; byteX < widthBytes; byteX++) {
        int byte = 0;
        for (int bit = 0; bit < 8; bit++) {
          final pixelX = byteX * 8 + bit;
          if (pixelX >= imgWidth) {
            continue;
          }
          if (bw[y * imgWidth + pixelX]) {
            byte |= 1 << (7 - bit);
          }
        }
        output.add(byte);
      }
    }

    return Uint8List.fromList(output);
  }

  // ── HELPER TEXT ─────────────────────────────────────────────────────────────

  /// Word-wrap: pecah string panjang menjadi List<String> dengan lebar max [w].
  /// Memotong di batas kata (spasi), bukan di tengah kata, sehingga tidak
  /// terjadi "Minuman Teh 35\n0 ml" yang terlihat buruk di struk.
  static List<String> _wordWrap(String text, int w) {
    final words = text.split(' ');
    final lines = <String>[];
    final buf = StringBuffer();
    for (final word in words) {
      if (word.isEmpty) {
        continue;
      }
      if (buf.isEmpty) {
        buf.write(word);
      } else if (buf.length + 1 + word.length <= w) {
        buf.write(' ');
        buf.write(word);
      } else {
        lines.add(buf.toString());
        buf.clear();
        buf.write(word);
      }
    }
    if (buf.isNotEmpty) {
      lines.add(buf.toString());
    }
    return lines.isEmpty ? [''] : lines;
  }

  static List<int> txt(String s) {
    final bytes = <int>[];
    for (int i = 0; i < s.length; i++) {
      int c = s.codeUnitAt(i);
      bytes.add(c < 256 ? c : 0x3F);
    }
    bytes.add(lfCmd);
    return bytes;
  }

  static List<int> divider(PaperSize size, {String char = '-'}) {
    final w = charsPerLine(size);
    return txt(char * w);
  }

  static List<int> rowLR(String left, String right, PaperSize size,
      {bool boldRight = false}) {
    final w = charsPerLine(size);
    if (right.length >= w) {
      return txt(right.substring(0, w));
    }
    int effectiveRightLen = right.length;
    // Bold characters are slightly wider on MPT-II, so we reserve 1 extra space to prevent wrap
    if (boldRight) {
      effectiveRightLen += 1;
    }
    int spaceLeft = w - effectiveRightLen;
    if (left.length > spaceLeft) {
      left = '${left.substring(0, spaceLeft > 0 ? spaceLeft - 1 : 0)} ';
    }
    final space = w - left.length - effectiveRightLen;
    final padding = space > 0 ? ' ' * space : '';
    if (boldRight) {
      final bytes = <int>[];
      for (int i = 0; i < left.length; i++) {
        int c = left.codeUnitAt(i);
        bytes.add(c < 256 ? c : 0x3F);
      }
      for (int i = 0; i < padding.length; i++) {
        bytes.add(0x20); // space
      }
      bytes.addAll(bold(true));
      for (int i = 0; i < right.length; i++) {
        int c = right.codeUnitAt(i);
        bytes.add(c < 256 ? c : 0x3F);
      }
      bytes.addAll(bold(false));
      bytes.add(lfCmd);
      return bytes;
    }
    return txt('$left$padding$right');
  }

  static String rp(int amount) {
    final s = amount.abs().toString();
    final buf = StringBuffer();
    int count = 0;
    for (int i = s.length - 1; i >= 0; i--) {
      if (count > 0 && count % 3 == 0) {
        buf.write('.');
      }
      buf.write(s[i]);
      count++;
    }
    final formatted = buf.toString().split('').reversed.join();
    return amount < 0 ? '-$formatted' : formatted;
  }

  static String fixLen(String s, int width) {
    if (s.length >= width) {
      return s.substring(0, width);
    }
    return s.padRight(width);
  }

  static String fixLenR(String s, int width) {
    if (s.length >= width) {
      return s.substring(0, width);
    }
    return s.padLeft(width);
  }

  static List<int> logoHeader(PaperSize size) {
    final List<int> b = [];
    final label = size == PaperSize.mm58
        ? 'dRetail Mart'
        : size == PaperSize.mm80
            ? 'dRetail Mart'
            : 'dRetail Mart';
    b.addAll(align(1));
    b.addAll(bold(true));
    b.addAll(txt(label));
    b.addAll(bold(false));
    b.addAll(divider(size));
    b.addAll(align(0));
    return b;
  }

  static List<int> poweredBy(PaperSize size) {
    final List<int> b = [];
    b.addAll(align(1));
    b.addAll(feed(1));
    b.addAll(txt('Powered by dRetail'));
    b.addAll(align(0));
    return b;
  }

  static void _applyFontConfig(List<int> b) {
    b.addAll(setFontB(_useFontB));
  }

  // ── BUILD DARI DATA ORDER ODOO ──────────────────────────────────────────────
  static Uint8List buildFromOdooData(
    Map<String, dynamic> data,
    PaperSize size, {
    bool basic = false,
  }) {
    if (basic) {
      return _buildBasicReceipt(data, size);
    }
    return _buildFullReceipt(data, size);
  }

  // ── FULL RECEIPT ────────────────────────────────────────────────────────────
  // Berdasarkan desain Odoo 18:
  // - Logo + Header (nama, telp, tax id, email, website)
  // - Slogan/Custom Header
  // - Kasir info
  // - Orderlines (dengan harga, subtotal, diskon, customer note)
  // - Tax breakdown (DPP + PPN)
  // - TOTAL, Payment, Change
  // - Diskon Total
  // - QR Code info
  // - Footer + Order reference + date
  static Uint8List _buildFullReceipt(Map<String, dynamic> d, PaperSize size) {
    final List<int> b = [];
    b.addAll(init());
    _applyFontConfig(b);
    final company = d['company'] as Map<String, dynamic>? ?? {};
    final logoBase64 = company['logo'] as String? ?? '';
    final storeName = (company['name'] as String? ?? 'Toko').trim();
    final storePhone = company['phone'] as String? ?? '';
    final storeEmail = company['email'] as String? ?? '';
    final storeStreet = company['street'] as String? ?? '';
    final orderName = d['name'] as String? ?? '-';
    final dateRaw = d['date'] as String? ?? '';
    final cashier = d['cashier'] as String? ?? '-';
    final footer =
        d['footer_messages'] as String? ?? 'Terima kasih!\nSampai jumpa lagi.';

    // ── LOGO (centered, max 50% lebar kertas) ────────────────────────────
    if (logoBase64.isNotEmpty) {
      try {
        final bytes = base64Decode(
            logoBase64.contains(',') ? logoBase64.split(',')[1] : logoBase64);
        final image = img.decodeImage(bytes);
        if (image != null) {
          b.addAll(align(1)); // center
          b.addAll(imageEsc(image, size));
          b.addAll(align(0));
        }
      } catch (_) {}
    }

    // ── HEADER: Nama Toko (CENTERED, ukuran font DINAMIS) ───────────────────
    // Logika: doubleSize jika nama muat dalam setengah lebar kertas,
    // normal bold jika nama lebih panjang — sehingga selalu 1 baris & tetap bold.
    b.addAll(align(1));
    b.addAll(bold(true));
    final storeNameW = charsPerLine(size);
    final halfW = storeNameW ~/ 2;
    if (storeName.length <= halfW) {
      // Nama pendek → double-size (2x lebar & tinggi), sangat mencolok
      b.addAll(doubleSize(true));
      b.addAll(txt(storeName));
      b.addAll(doubleSize(false));
    } else {
      // Nama panjang → normal size tapi bold, dijamin 1 baris
      b.addAll(txt(storeName));
    }
    b.addAll(bold(false));

    // ── Info kontak toko (CENTERED, font normal) ──────────────────────────
    if (storePhone.isNotEmpty) {
      b.addAll(txt('Tel: $storePhone'));
    }
    if (company['vat'] != null && (company['vat'] as String).isNotEmpty) {
      b.addAll(txt('Tax ID: ${company['vat']}'));
    }
    if (storeEmail.isNotEmpty) {
      b.addAll(txt(storeEmail));
    }
    if (company['website'] != null &&
        (company['website'] as String).isNotEmpty) {
      b.addAll(txt(company['website'] as String));
    }
    if (storeStreet.isNotEmpty) {
      for (final line in storeStreet.split('\n')) {
        if (line.trim().isNotEmpty) {
          b.addAll(txt(line.trim()));
        }
      }
    }
    b.addAll(align(0));

    // ── CUSTOM HEADER / SLOGAN ───────────────────────────────────────────────
    // POIN 2: Nilai bisa kosong → jika kosong, garis "----" di atas TIDAK
    // ditampilkan dan konten Reff langsung mengikuti tanpa celah kosong.
    final customHeader = (d['receipt_header'] as String? ?? '').trim();
    if (customHeader.isNotEmpty) {
      b.addAll(divider(size, char: '-'));
      b.addAll(align(1));
      b.addAll(txt(customHeader));
      b.addAll(align(0));
    }

    b.addAll(divider(size, char: '-'));

    final orderNumberClean = orderName
        .toString()
        .replaceFirst(RegExp(r'^Order\s*', caseSensitive: false), '');
    final dateFormatted = dateRaw.isNotEmpty ? _formatDate(dateRaw) : '';

    b.addAll(rowLR('Reff        :', orderNumberClean, size));
    b.addAll(rowLR('Tanggal     :', dateFormatted, size));
    b.addAll(rowLR('Kasir       :', cashier, size));

    b.addAll(divider(size, char: '='));

    // ── ORDERLINES (dengan harga, diskon, customer note) ─────────────────
    final lines = d['orderlines'] as List<dynamic>? ?? [];
    for (final line in lines) {
      final m = line as Map<String, dynamic>;
      final rawName = m['product_name'] as String? ?? '';
      final name = rawName.replaceAll('\n', ' ').trim();
      final qty = (m['qty'] ?? 1).toDouble();
      final unitPrice = (m['price'] ?? 0).toDouble();
      final subtotal = (m['price_with_tax'] ?? unitPrice * qty).toDouble();
      final discountPct = (m['discount'] ?? 0).toDouble();
      final customerNote = m['customer_note'] as String? ?? '';

      // Nama produk: word-wrap agar tidak terpotong di tengah kata
      final w = charsPerLine(size);
      final nameLines = _wordWrap(name, w);
      b.addAll(bold(true));
      for (final nl in nameLines) {
        b.addAll(txt(nl));
      }
      b.addAll(bold(false));

      // Baris qty × harga = subtotal (indent 2 spasi, subtotal bold-right + "Rp")
      final qtyStr = '${_formatQty(qty)} Pcs x Rp ${rp(unitPrice.round())}';
      final subtotalStr = 'Rp ${rp(subtotal.round())}';
      b.addAll(rowLR('  $qtyStr', subtotalStr, size, boldRight: true));

      // Diskon per item
      if (discountPct > 0) {
        b.addAll(rowLR('  Disc(${_formatQty(discountPct)}%)', '', size));
      }

      // Customer note
      if (customerNote.isNotEmpty) {
        b.addAll(txt('  * $customerNote'));
      }
    }
    b.addAll(divider(size, char: '-'));

    // ── TAX BREAKDOWN ──────────────────────────────────────────────────────
    final subtotalVal = (d['total_without_tax'] ?? 0).toDouble();
    final taxVal = (d['total_tax'] ?? 0).toDouble();
    final totalVal = (d['total_with_tax'] ?? 0).toDouble();
    final paidVal = (d['total_paid'] ?? totalVal).toDouble();
    final changeVal = (d['change'] ?? (paidVal - totalVal)).toDouble();
    final totalDiscount = (d['total_discount'] ?? 0).toDouble();

    // ── TAX LINES ────────────────────────────────────────────────────────────
    // POIN 4: "Dasar Pengenaan Pajak" → singkatan "DPP" agar muat di baris
    // POIN 5: semua nominal wajib ada prefix "Rp"
    if (subtotalVal > 0) {
      b.addAll(rowLR('DPP', 'Rp ${rp(subtotalVal.round())}', size));
    }
    // POIN 6: hapus divider '-' di bawah PPN (tidak perlu, terlalu ramai)
    if (taxVal > 0) {
      b.addAll(rowLR('PPN 11% on ${rp(subtotalVal.round())}',
          'Rp ${rp(taxVal.round())}', size));
    }
    // Tidak ada divider di sini (POIN 6)

    // ── TOTAL ─────────────────────────────────────────────────────────────
    // POIN 7: tidak ada '===' di atas maupun di bawah TOTAL
    // POIN 9: tidak ada jarak antar TOTAL/Payment/CHANGE, dibedakan via bold
    b.addAll(divider(size, char: '-'));
    b.addAll(doubleHeight(true));
    b.addAll(bold(true));
    b.addAll(rowLR('TOTAL', 'Rp ${rp(totalVal.round())}', size));
    b.addAll(bold(false));
    b.addAll(doubleHeight(false));

    // ── PAYMENT METHOD ────────────────────────────────────────────────────
    // POIN 9: langsung di bawah TOTAL tanpa divider
    final payments = d['paymentlines'] as List<dynamic>? ?? [];
    for (final pay in payments) {
      final p = pay as Map<String, dynamic>;
      final payName = p['name'] as String? ?? 'Cash';
      final payAmt = (p['amount'] ?? 0).toDouble();
      b.addAll(rowLR(payName, 'Rp ${rp(payAmt.round())}', size));
    }
    if (payments.isEmpty && paidVal > 0) {
      b.addAll(rowLR('Cash', 'Rp ${rp(paidVal.round())}', size));
    }

    // POIN 8: tidak ada divider '-' di bawah Cash
    // POIN 9: CHANGE langsung mengikuti tanpa jarak
    b.addAll(bold(true));
    b.addAll(rowLR('CHANGE', 'Rp ${rp(changeVal.round())}', size));
    b.addAll(bold(false));

    // ── DISKON TOTAL ──────────────────────────────────────────────────────
    if (totalDiscount > 0) {
      b.addAll(rowLR('Diskon Total', 'Rp ${rp(totalDiscount.round())}', size));
    }

    // ── QR CODE / PORTAL INFO ─────────────────────────────────────────────
    // Unique code dan portal URL jika ada
    if (d['unique_code'] != null || d['portal_url'] != null) {
      b.addAll(divider(size, char: '-'));
      b.addAll(align(1));
      b.addAll(txt('Need an invoice for your purchase?'));
      // QR placeholder jika ada
      b.addAll(txt('[QR CODE]'));
      if (d['unique_code'] != null) {
        b.addAll(txt('Unique Code: ${d['unique_code']}'));
      }
      if (d['portal_url'] != null) {
        b.addAll(txt('Portal URL: ${d['portal_url']}'));
      }
      b.addAll(align(0));
    }

    // ── FOOTER (CENTERED) ────────────────────────────────────────────────────
    // Jika footer kosong, tidak ada feed maupun teks, sehingga tidak ada
    // baris kosong yang percuma sebelum "Powered by dRetail".
    b.addAll(divider(size, char: '='));
    final footerLines =
        footer.split('\n').where((l) => l.trim().isNotEmpty).toList();
    if (footerLines.isNotEmpty) {
      b.addAll(feed(1));
      b.addAll(align(1));
      for (final line in footerLines) {
        b.addAll(txt(line.trim()));
      }
      b.addAll(align(0));
    }

    // ── EXPECTED DELIVERY (CENTERED, JIKA ADA) ─────────────────────────────
    if (d['shipping_date'] != null &&
        (d['shipping_date'] as String).isNotEmpty) {
      b.addAll(align(1));
      b.addAll(txt('Expected delivery: ${d['shipping_date']}'));
      b.addAll(align(0));
    }

    // ── POWERED BY ────────────────────────────────────────────────────────────
    // Jika footer kosong, feed(1) tetap memberi jarak yang cukup.
    // Jika footer ada isinya, feed(1) di atas sudah cukup memisahkan keduanya.
    b.addAll(feed(1));
    b.addAll(align(1));
    b.addAll(bold(true));
    b.addAll(txt('Powered by dRetail'));
    b.addAll(bold(false));
    b.addAll(align(0));

    b.addAll(finalize());
    return Uint8List.fromList(b);
  }

  // ── BASIC RECEIPT ────────────────────────────────────────────────────────────
  // Berdasarkan desain Odoo 18:
  // Basic Receipt menampilkan:
  // - Logo + Header (nama, telp, tax id, email, website, slogan)
  // - Order info (Reff, Tanggal, Kasir)
  // - Orderlines (tanpa harga - nama + qty + customer note)
  // - Footer + Order reference + date
  // Yang DIHILANGKAN:
  // - Detail pajak, harga, diskon
  // - Payment lines, change
  // - QR code, portal URL
  static Uint8List _buildBasicReceipt(Map<String, dynamic> d, PaperSize size) {
    final List<int> b = [];
    b.addAll(init());
    _applyFontConfig(b);
    final company = d['company'] as Map<String, dynamic>? ?? {};
    final logoBase64 = company['logo'] as String? ?? '';
    final storeName = (company['name'] as String? ?? 'Toko').trim();
    final storePhone = company['phone'] as String? ?? '';
    final storeEmail = company['email'] as String? ?? '';
    final storeStreet = company['street'] as String? ?? '';
    final orderName = d['name'] as String? ?? '-';
    final dateRaw = d['date'] as String? ?? '';
    final cashier = d['cashier'] as String? ?? '-';
    final footer =
        d['footer_messages'] as String? ?? 'Terima kasih!\nSampai jumpa lagi.';

    // ── LOGO (centered, max 50% lebar kertas) ──────────────────────────
    if (logoBase64.isNotEmpty) {
      try {
        final bytes = base64Decode(
            logoBase64.contains(',') ? logoBase64.split(',')[1] : logoBase64);
        final image = img.decodeImage(bytes);
        if (image != null) {
          b.addAll(align(1)); // center
          b.addAll(imageEsc(image, size));
          b.addAll(align(0));
        }
      } catch (_) {}
    }

    // ── HEADER: Nama Toko (CENTERED, ukuran font DINAMIS) ───────────────────
    b.addAll(align(1));
    b.addAll(bold(true));
    final storeNameW = charsPerLine(size);
    final halfW = storeNameW ~/ 2;
    if (storeName.length <= halfW) {
      b.addAll(doubleSize(true));
      b.addAll(txt(storeName));
      b.addAll(doubleSize(false));
    } else {
      b.addAll(txt(storeName));
    }
    b.addAll(bold(false));

    // ── Info kontak toko (CENTERED, font normal) ──────────────────────────
    if (storePhone.isNotEmpty) {
      b.addAll(txt('Tel: $storePhone'));
    }
    // Tax ID jika ada
    if (company['vat'] != null && (company['vat'] as String).isNotEmpty) {
      b.addAll(txt('Tax ID: ${company['vat']}'));
    }
    if (storeEmail.isNotEmpty) {
      b.addAll(txt(storeEmail));
    }
    // Website jika ada
    if (company['website'] != null &&
        (company['website'] as String).isNotEmpty) {
      b.addAll(txt(company['website'] as String));
    }
    if (storeStreet.isNotEmpty) {
      for (final line in storeStreet.split('\n')) {
        if (line.trim().isNotEmpty) {
          b.addAll(txt(line.trim()));
        }
      }
    }
    b.addAll(align(0));

    // ── CUSTOM HEADER / SLOGAN ───────────────────────────────────────────────
    // POIN 2: Kosong → tidak ada garis "----" dan tidak ada celah kosong.
    final customHeader = (d['receipt_header'] as String? ?? '').trim();
    if (customHeader.isNotEmpty) {
      b.addAll(divider(size, char: '-'));
      b.addAll(align(1));
      b.addAll(txt(customHeader));
      b.addAll(align(0));
    }

    b.addAll(divider(size, char: '-'));

    // ── ORDER INFO ROWS (Reff, Tanggal, Kasir) ──────────────────────────────
    final orderNumberClean = orderName
        .toString()
        .replaceFirst(RegExp(r'^Order\s*', caseSensitive: false), '');
    final dateFormatted = dateRaw.isNotEmpty ? _formatDate(dateRaw) : '';

    // Reff row: "Reff        :" left, "Order XXXX-XXX-XXXX" right
    b.addAll(rowLR('Reff        :', orderNumberClean, size));
    // Tanggal row: "Tanggal     :" left, "DD/MM/YYYY HH:mm" right
    b.addAll(rowLR('Tanggal     :', dateFormatted, size));
    // Kasir row: "Kasir       :" left, "Nama Kasir" right
    b.addAll(rowLR('Kasir       :', cashier, size));

    b.addAll(divider(size, char: '='));

    // ── ORDERLINES (tanpa harga - nama + qty + customer note) ──────────
    final lines = d['orderlines'] as List<dynamic>? ?? [];
    if (lines.isNotEmpty) {
      for (final line in lines) {
        final m = line as Map<String, dynamic>;
        final rawName = m['product_name'] as String? ?? '';
        final name = rawName.replaceAll('\n', ' ').trim();
        final qty = (m['qty'] ?? 1).toDouble();
        final customerNote = m['customer_note'] as String? ?? '';

        // Nama produk: word-wrap agar tidak terpotong di tengah kata
        final w = charsPerLine(size);
        final nameLines = _wordWrap(name, w);
        b.addAll(bold(true));
        for (final nl in nameLines) {
          b.addAll(txt(nl));
        }
        b.addAll(bold(false));

        // Qty dengan satuan
        final qtyStr = '${_formatQty(qty)} Pcs';
        b.addAll(txt('  $qtyStr'));

        // Customer note
        if (customerNote.isNotEmpty) {
          b.addAll(txt('  * $customerNote'));
        }
      }
      b.addAll(divider(size, char: '='));
    }

    // ── FOOTER (CENTERED) ────────────────────────────────────────────────────────
    // Jika footer kosong, tidak ada feed maupun teks.
    b.addAll(divider(size, char: '='));
    final footerLines =
        footer.split('\n').where((l) => l.trim().isNotEmpty).toList();
    if (footerLines.isNotEmpty) {
      b.addAll(feed(1));
      b.addAll(align(1));
      for (final line in footerLines) {
        b.addAll(txt(line.trim()));
      }
      b.addAll(align(0));
    }

    // ── EXPECTED DELIVERY (CENTERED, JIKA ADA) ─────────────────────────────
    if (d['shipping_date'] != null &&
        (d['shipping_date'] as String).isNotEmpty) {
      b.addAll(align(1));
      b.addAll(txt('Expected delivery: ${d['shipping_date']}'));
      b.addAll(align(0));
    }

    // ── POWERED BY ────────────────────────────────────────────────────────────
    b.addAll(feed(1));
    b.addAll(align(1));
    b.addAll(bold(true));
    b.addAll(txt('Powered by dRetail'));
    b.addAll(bold(false));
    b.addAll(align(0));

    b.addAll(finalize());
    return Uint8List.fromList(b);
  }

  // ── CONVERT TEXT KE ESCPOS ──────────────────────────────────────────────────
  static Uint8List textToEscPos(String text, PaperSize size,
      {bool isBold = false, int alignMode = 0}) {
    final List<int> b = [];
    b.addAll(init());
    _applyFontConfig(b);
    // Split by newline to apply alignment and bolding per-line for better consistency
    final lines = text.split('\n');
    for (int i = 0; i < lines.length; i++) {
      b.addAll(align(alignMode));
      if (isBold) {
        b.addAll(bold(true));
      }
      final line = lines[i];
      for (int j = 0; j < line.length; j++) {
        int c = line.codeUnitAt(j);
        b.add(c < 256 ? c : 0x3F);
      }
      if (isBold) {
        b.addAll(bold(false));
      }
      b.add(lfCmd);
    }
    b.addAll(finalize());
    return Uint8List.fromList(b);
  }

  // ── HELPERS INTERNAL ─────────────────────────────────────────────────────────
  static String _formatDate(String raw) {
    try {
      final dt = DateTime.parse(raw).toLocal();
      return '${dt.day.toString().padLeft(2, '0')}/'
          '${dt.month.toString().padLeft(2, '0')}/'
          '${dt.year} '
          '${dt.hour.toString().padLeft(2, '0')}:'
          '${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return raw.length > 16 ? raw.substring(0, 16) : raw;
    }
  }

  static String _formatQty(double qty) {
    if (qty == qty.roundToDouble()) {
      return qty.round().toString();
    }
    return qty.toStringAsFixed(2);
  }

  // ── SESSION SUMMARY REPORT ─────────────────────────────────────────────────
  static Uint8List buildSessionSummary(Map<String, dynamic> d, PaperSize size) {
    final List<int> b = [];
    b.addAll(init());
    _applyFontConfig(b);

    // ── HEADER ────────────────────────────────────────────────────────────────
    b.addAll(align(1));
    b.addAll(bold(true));
    b.addAll(setFontB(false)); // Font normal untuk header
    b.addAll(txt('SESSION SUMMARY REPORT'));
    b.addAll(bold(false));
    b.addAll(divider(size, char: '='));
    b.addAll(divider(size, char: '-'));

    // ── SESSION INFO ────────────────────────────────────────────────────────
    final posName = d['pos_name'] as String? ?? '-';
    final sessionName = d['session_name'] as String? ?? '-';
    final cashierName = d['cashier_name'] as String? ?? '-';
    final startAt = d['start_at'] as String? ?? '-';
    final stopAt = d['stop_at'] as String? ?? '-';

    b.addAll(align(0));
    b.addAll(rowLR('PoS Name', posName, size));
    b.addAll(rowLR('Session ID', sessionName, size));
    b.addAll(rowLR('Cashier', cashierName, size));
    b.addAll(rowLR('Opening Date', startAt, size));
    b.addAll(rowLR('Closing Date', stopAt, size));

    // ── SALES SUMMARY ───────────────────────────────────────────────────────
    b.addAll(divider(size, char: '-'));
    b.addAll(align(1));
    b.addAll(bold(true));
    b.addAll(txt('------ SALES SUMMARY ------'));
    b.addAll(bold(false));
    b.addAll(align(0));

    final grossSales = (d['gross_sales'] ?? 0).toDouble();
    final totalDiscount = (d['total_discount'] ?? 0).toDouble();
    final refundUntaxed = (d['refund_amount_untaxed'] ?? 0).toDouble();
    final netSalesBeforeTax = (d['net_sales_before_tax'] ?? 0).toDouble();
    final totalTaxes = (d['total_taxes'] ?? 0).toDouble();
    final totalSales = (d['total_sales'] ?? 0).toDouble();

    b.addAll(rowLR('Gross Sales', 'Rp ${rp(grossSales.round())}', size));
    b.addAll(rowLR('Discounts', '-Rp ${rp(totalDiscount.round())}', size));
    b.addAll(
        rowLR('Returns/Refunds', '-Rp ${rp(refundUntaxed.round())}', size));
    b.addAll(divider(size, char: '.'));
    b.addAll(rowLR('Net Sales', 'Rp ${rp(netSalesBeforeTax.round())}', size));
    b.addAll(rowLR('Taxes', 'Rp ${rp(totalTaxes.round())}', size));
    b.addAll(divider(size, char: '.'));
    b.addAll(bold(true));
    b.addAll(rowLR('Total Sales', 'Rp ${rp(totalSales.round())}', size));
    b.addAll(bold(false));

    // ── RETURNS/REFUNDS ──────────────────────────────────────────────────────
    final refundAmount = (d['refund_amount'] ?? 0).toDouble();
    if (refundAmount > 0) {
      b.addAll(divider(size, char: '-'));
      b.addAll(align(1));
      b.addAll(bold(true));
      b.addAll(txt('----- RETURNS/REFUNDS -----'));
      b.addAll(bold(false));
      b.addAll(align(0));
      b.addAll(
          rowLR('Total Refund Amount', 'Rp ${rp(refundAmount.round())}', size));
    }

    // ── PAYMENT METHOD ───────────────────────────────────────────────────────
    b.addAll(divider(size, char: '-'));
    b.addAll(align(1));
    b.addAll(bold(true));
    b.addAll(txt('------ PAYMENT METHOD -----'));
    b.addAll(bold(false));
    b.addAll(align(0));

    final payments = d['payments'] as List<dynamic>? ?? [];
    for (final pay in payments) {
      final p = pay as Map<String, dynamic>;
      final payName = (p['method'] as String? ?? 'Payment').toUpperCase();
      final payAmt = (p['amount'] ?? 0).toDouble();
      b.addAll(rowLR(payName, 'Rp ${rp(payAmt.round())}', size));
    }
    final totalPayment = (d['total_payment_amount'] ?? 0).toDouble();
    b.addAll(divider(size, char: '.'));
    b.addAll(bold(true));
    b.addAll(rowLR('Total Payments', 'Rp ${rp(totalPayment.round())}', size));
    b.addAll(bold(false));

    // ── CASH DRAWER SUMMARY ─────────────────────────────────────────────────
    final startingCash = (d['starting_cash'] ?? 0).toDouble();
    final cashSales = (d['cash_sales'] ?? 0).toDouble();
    final cashIn = (d['cash_in'] ?? 0).toDouble();
    final cashOut = (d['cash_out'] ?? 0).toDouble();
    final expectedCash = (d['expected_cash'] ?? 0).toDouble();

    b.addAll(divider(size, char: '-'));
    b.addAll(align(1));
    b.addAll(bold(true));
    b.addAll(txt('--- CASH DRAWER SUMMARY ---'));
    b.addAll(bold(false));
    b.addAll(align(0));

    b.addAll(rowLR('Opening Cash', 'Rp ${rp(startingCash.round())}', size));
    b.addAll(rowLR('(+) Cash Sales', 'Rp ${rp(cashSales.round())}', size));
    if (cashIn > 0) {
      b.addAll(rowLR('(+) Cash In', 'Rp ${rp(cashIn.round())}', size));
    }
    if (cashOut > 0) {
      b.addAll(rowLR('(-) Cash Out', 'Rp ${rp(cashOut.round())}', size));
    }
    b.addAll(divider(size, char: '.'));
    b.addAll(bold(true));
    b.addAll(rowLR('Total', 'Rp ${rp(expectedCash.round())}', size));
    b.addAll(bold(false));

    // ── SESSION TRANSACTIONS ────────────────────────────────────────────────
    final totalTransactions = d['total_transactions'] ?? 0;
    final salesTransactions = d['sales_transactions'] ?? 0;
    final refundTransactions = d['refund_transactions'] ?? 0;
    final totalQtySold = d['total_qty_sold'] ?? 0;

    b.addAll(divider(size, char: '-'));
    b.addAll(align(1));
    b.addAll(bold(true));
    b.addAll(txt('-- SESSION TRANSACTIONS --'));
    b.addAll(bold(false));
    b.addAll(align(0));

    b.addAll(rowLR('Total Transactions', totalTransactions.toString(), size));
    b.addAll(rowLR('Sales Transactions', salesTransactions.toString(), size));
    b.addAll(rowLR('Returns/Refunds', refundTransactions.toString(), size));
    b.addAll(rowLR('Items Sold', totalQtySold.toString(), size));

    // ── EXPECTED VS CLOSING BALANCE ───────────────────────────────────────
    final countedCash = (d['counted_cash'] ?? 0).toDouble();
    final differenceCash = (d['difference_cash'] ?? 0).toDouble();
    final totalCreditAmount = (d['total_credit_amount'] ?? 0).toDouble();

    b.addAll(divider(size, char: '='));
    b.addAll(bold(true));
    b.addAll(
        rowLR('Expected Balance:', 'Rp ${rp(expectedCash.round())}', size));
    b.addAll(rowLR('Closing Balance:', 'Rp ${rp(countedCash.round())}', size));
    b.addAll(bold(false));

    final diffStr = differenceCash >= 0
        ? 'Rp ${rp(differenceCash.round())}'
        : '-Rp ${rp(differenceCash.abs().round())}';
    if (differenceCash != 0) {
      b.addAll(bold(true));
      b.addAll(rowLR('Difference:', diffStr, size));
      b.addAll(bold(false));
    }

    // Credit info if any
    if (totalCreditAmount > 0) {
      b.addAll(divider(size, char: '.'));
      b.addAll(rowLR(
          '* Credit(piutang):', 'Rp ${rp(totalCreditAmount.round())}', size));
    }

    // ── FOOTER ─────────────────────────────────────────────────────────────
    b.addAll(divider(size, char: '='));
    b.addAll(align(1));
    final printDate = d['print_date'] as String? ??
        _formatDate(DateTime.now().toIso8601String());
    b.addAll(txt('Printed at: $printDate'));
    b.addAll(txt('Powered by dRetail'));
    b.addAll(align(0));

    b.addAll(finalize());
    return Uint8List.fromList(b);
  }
}
