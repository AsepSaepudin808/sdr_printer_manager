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
    if (_extraFeed > 0) b.addAll(feed(_extraFeed));
    if (_autoCut) b.addAll(cut());
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

  static Uint8List imageEsc(img.Image src, PaperSize paperSize) {
    int maxW = switch (paperSize) {
      PaperSize.mm58 => 384,
      PaperSize.mm80 => 512,
      PaperSize.mm100 => 768,
    };

    img.Image resized = src;
    if (src.width > maxW) {
      resized = img.copyResize(src, width: maxW);
    }

    final List<int> bytes = [];
    final int width = resized.width;
    final int height = resized.height;
    final int widthBytes = (width + 7) ~/ 8;

    bytes.addAll([gsCmd, 0x76, 0x30, 0x00]);
    bytes.addAll([widthBytes % 256, widthBytes ~/ 256]);
    bytes.addAll([height % 256, height ~/ 256]);

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < widthBytes; x++) {
        int byte = 0;
        for (int b = 0; b < 8; b++) {
          int pixelX = x * 8 + b;
          if (pixelX < width) {
            final pixel = resized.getPixel(pixelX, y);
            if (pixel.luminance < 0.5) {
              byte |= (1 << (7 - b));
            }
          }
        }
        bytes.add(byte);
      }
    }
    return Uint8List.fromList(bytes);
  }

  // ── HELPER TEXT ─────────────────────────────────────────────────────────────

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

  static List<int> rowLR(String left, String right, PaperSize size) {
    final w = charsPerLine(size);

    if (right.length >= w) return txt(right.substring(0, w));

    int spaceLeft = w - right.length;
    if (left.length > spaceLeft) {
      left = '${left.substring(0, spaceLeft > 0 ? spaceLeft - 1 : 0)} ';
    }

    final space = w - left.length - right.length;
    final padding = space > 0 ? ' ' * space : '';
    return txt('$left$padding$right');
  }

  static String rp(int amount) {
    final s = amount.abs().toString();
    final buf = StringBuffer();
    int count = 0;
    for (int i = s.length - 1; i >= 0; i--) {
      if (count > 0 && count % 3 == 0) buf.write('.');
      buf.write(s[i]);
      count++;
    }
    final formatted = buf.toString().split('').reversed.join();
    return amount < 0 ? '-$formatted' : formatted;
  }

  static String fixLen(String s, int width) {
    if (s.length >= width) return s.substring(0, width);
    return s.padRight(width);
  }

  static String fixLenR(String s, int width) {
    if (s.length >= width) return s.substring(0, width);
    return s.padLeft(width);
  }

  static List<int> logoHeader(PaperSize size) {
    final List<int> b = [];
    b.addAll(align(1));
    b.addAll(bold(true));
    b.addAll(txt('dRetail Mart'));
    b.addAll(bold(false));
    b.addAll(txt('Printer Manager'));
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
  static Uint8List _buildFullReceipt(Map<String, dynamic> d, PaperSize size) {
    final List<int> b = [];

    b.addAll(init());
    _applyFontConfig(b); // Setel font dinamis sebelum mencetak text

    final company = d['company'] as Map<String, dynamic>? ?? {};
    final logoBase64 = company['logo'] as String? ?? '';
    if (logoBase64.isNotEmpty) {
      try {
        final bytes = base64Decode(
            logoBase64.contains(',') ? logoBase64.split(',')[1] : logoBase64);
        final image = img.decodeImage(bytes);
        if (image != null) {
          b.addAll(align(1));
          b.addAll(imageEsc(image, size));
          b.addAll(feed(1));
          b.addAll(align(0));
        }
      } catch (_) {}
    }

    final storeName = (company['name'] as String? ?? 'Toko').trim();
    final storePhone = company['phone'] as String? ?? '';
    final storeEmail = company['email'] as String? ?? '';

    b.addAll(align(1));
    b.addAll(bold(true));
    b.addAll(txt(storeName));
    b.addAll(bold(false));
    if (storePhone.isNotEmpty) b.addAll(txt(storePhone));
    if (storeEmail.isNotEmpty) b.addAll(txt(storeEmail));
    b.addAll(align(0));
    b.addAll(divider(size, char: '='));

    final orderName = d['name'] as String? ?? '-';
    final dateRaw = d['date'] as String? ?? '';
    final cashier = d['cashier'] as String? ?? '-';

    b.addAll(rowLR('No.', orderName, size));
    if (dateRaw.isNotEmpty) {
      b.addAll(rowLR('Tanggal', _formatDate(dateRaw), size));
    }
    b.addAll(rowLR('Kasir', cashier, size));
    b.addAll(divider(size));

    final lines = d['orderlines'] as List<dynamic>? ?? [];
    final w = charsPerLine(size);

    for (final line in lines) {
      final m = line as Map<String, dynamic>;
      final rawName = m['product_name'] as String? ?? '';
      final name = rawName.replaceAll('\n', ' ').trim();
      final qty = (m['qty'] ?? 1).toDouble();
      final unitPrice = (m['price'] ?? 0).toDouble();
      final subtotal = (m['price_with_tax'] ?? unitPrice * qty).toDouble();

      final discountAmt = (m['discount_amount'] ?? 0).toDouble();
      final discountPct = (m['discount'] ?? 0).toDouble();
      final discType =
          m['discount_type']?.toString() ?? (discountPct > 0 ? '%' : 'Rp');

      b.addAll(bold(true));
      int start = 0;
      while (start < name.length) {
        int end = start + w;
        if (end > name.length) end = name.length;
        b.addAll(txt(name.substring(start, end)));
        start += w;
      }
      b.addAll(bold(false));

      final qtyStr = '  ${_formatQty(qty)} x Rp ${rp(unitPrice.round())}';
      final subtotalStr = 'Rp ${rp(subtotal.round())}';
      b.addAll(rowLR(qtyStr, subtotalStr, size));

      // Diskon Item
      if (discountAmt > 0 || discountPct > 0) {
        String discLabel = discType == '%'
            ? '  Disc (${_formatQty(discountPct)}%)'
            : '  Disc (Rp)';
        double nominalAmt = discountAmt > 0
            ? discountAmt
            : (unitPrice * qty * (discountPct / 100));
        b.addAll(rowLR(discLabel, '-Rp ${rp(nominalAmt.round())}', size));
      }
    }

    b.addAll(divider(size));

    final subtotalVal = (d['total_without_tax'] ?? 0).toDouble();
    final taxVal = (d['total_tax'] ?? 0).toDouble();
    final totalVal = (d['total_with_tax'] ?? 0).toDouble();
    final paidVal = (d['total_paid'] ?? totalVal).toDouble();
    final changeVal = (d['change'] ?? (paidVal - totalVal)).toDouble();

    // Diskon Global
    final globalDiscType = d['global_discount_type']?.toString();
    final globalDiscAmt = (d['global_discount_amount'] ?? 0).toDouble();
    final globalDiscPct = (d['global_discount'] ?? 0).toDouble();
    final totalDiscount = (d['total_discount'] ?? 0).toDouble();

    b.addAll(rowLR('Subtotal', 'Rp ${rp(subtotalVal.round())}', size));

    if (globalDiscAmt > 0 || globalDiscPct > 0) {
      String gDiscLabel = globalDiscType == '%'
          ? 'Diskon Global (${_formatQty(globalDiscPct)}%)'
          : 'Diskon Global (Rp)';
      double gNominal = globalDiscAmt > 0 ? globalDiscAmt : totalDiscount;
      b.addAll(rowLR(gDiscLabel, '-Rp ${rp(gNominal.round())}', size));
    } else if (totalDiscount > 0) {
      b.addAll(rowLR('Total Diskon', '-Rp ${rp(totalDiscount.round())}', size));
    }

    if (taxVal > 0) {
      b.addAll(rowLR('Pajak', 'Rp ${rp(taxVal.round())}', size));
    }

    b.addAll(divider(size));
    b.addAll(bold(true));
    
    // For bold TOTAL, we reduce width by 1 because bold chars are physically slightly wider 
    // on MPT-II printers, causing 32-char lines to wrap the price to the next line.
    final totalStr = 'Rp ${rp(totalVal.round())}';
    int spaceTot = w - 5 - totalStr.length - 1; // 5 is length of 'TOTAL', -1 for bold offset
    if (spaceTot < 1) spaceTot = 1;
    b.addAll(txt('TOTAL${" " * spaceTot}$totalStr'));
    
    b.addAll(bold(false));
    b.addAll(divider(size));

    final payments = d['paymentlines'] as List<dynamic>? ?? [];
    for (final pay in payments) {
      final p = pay as Map<String, dynamic>;
      final payName = p['name'] as String? ?? 'Bayar';
      final payAmt = (p['amount'] ?? 0).toDouble();
      b.addAll(rowLR(payName, 'Rp ${rp(payAmt.round())}', size));
    }
    if (payments.isEmpty) {
      b.addAll(rowLR('Bayar', 'Rp ${rp(paidVal.round())}', size));
    }

    b.addAll(bold(true));
    b.addAll(rowLR('Kembali', 'Rp ${rp(changeVal.round())}', size));
    b.addAll(bold(false));
    b.addAll(divider(size, char: '='));

    final footer =
        d['footer_messages'] as String? ?? 'Terima kasih!\nSampai jumpa lagi.';
    b.addAll(align(1));
    for (final line in footer.split('\n')) {
      if (line.trim().isNotEmpty) b.addAll(txt(line.trim()));
    }
    b.addAll(align(0));

    b.addAll(poweredBy(size));
    b.addAll(finalize());
    return Uint8List.fromList(b);
  }

  // ── BASIC RECEIPT ────────────────────────────────────────────────────────────
  static Uint8List _buildBasicReceipt(Map<String, dynamic> d, PaperSize size) {
    final List<int> b = [];

    b.addAll(init());
    _applyFontConfig(b);

    final company = d['company'] as Map<String, dynamic>? ?? {};
    final storeName = (company['name'] as String? ?? 'Toko').trim();
    final orderName = d['name'] as String? ?? '-';
    final totalVal = (d['total_with_tax'] ?? 0).toDouble();
    final paidVal = (d['total_paid'] ?? totalVal).toDouble();
    final changeVal = (d['change'] ?? (paidVal - totalVal)).toDouble();
    final dateRaw = d['date'] as String? ?? '';

    b.addAll(align(1));
    b.addAll(bold(true));
    b.addAll(txt(storeName));
    b.addAll(bold(false));
    b.addAll(align(0));
    b.addAll(divider(size));

    b.addAll(rowLR('No.', orderName, size));
    if (dateRaw.isNotEmpty) b.addAll(rowLR('Tgl', _formatDate(dateRaw), size));
    b.addAll(divider(size));

    b.addAll(bold(true));
    b.addAll(rowLR('TOTAL', 'Rp ${rp(totalVal.round())}', size));
    b.addAll(bold(false));
    b.addAll(rowLR('Bayar', 'Rp ${rp(paidVal.round())}', size));
    b.addAll(rowLR('Kembali', 'Rp ${rp(changeVal.round())}', size));
    b.addAll(divider(size));

    b.addAll(align(1));
    b.addAll(txt('Terima kasih!'));
    b.addAll(align(0));

    b.addAll(poweredBy(size));
    b.addAll(finalize());
    return Uint8List.fromList(b);
  }

  // ── TEST PRINT PENDEK ────────────────────────────────────────────────────────
  static Uint8List buildTestShort(PaperSize size) {
    final List<int> b = [];
    final w = charsPerLine(size);
    final paperLabel = switch (size) {
      PaperSize.mm58 => '58mm',
      PaperSize.mm80 => '80mm',
      PaperSize.mm100 => '100mm'
    };
    final now = DateTime.now();
    final dateStr =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    b.addAll(init());
    _applyFontConfig(b);

    b.addAll(logoHeader(size));
    b.addAll(align(1));
    b.addAll(txt('-- TEST PRINT PENDEK --'));
    b.addAll(align(0));
    b.addAll(divider(size));

    // Tampilkan info Font yang dipakai pada Test Print
    final String fontLabel = _useFontB ? "Font B (Kecil)" : "Font A (Normal)";
    b.addAll(rowLR('Kertas', '$paperLabel (${w}kar)', size));
    b.addAll(rowLR('Mode', fontLabel, size));
    b.addAll(rowLR('Tanggal', dateStr, size));
    b.addAll(rowLR('Waktu', timeStr, size));
    b.addAll(divider(size));

    b.addAll(bold(true));
    b.addAll(rowLR('TOTAL', 'Rp ${rp(150000)}', size));
    b.addAll(bold(false));
    b.addAll(rowLR('Tunai', 'Rp ${rp(200000)}', size));
    b.addAll(rowLR('Kembali', 'Rp ${rp(50000)}', size));
    b.addAll(divider(size));

    b.addAll(align(1));
    b.addAll(bold(true));
    b.addAll(txt('*** Printer OK! ***'));
    b.addAll(bold(false));
    b.addAll(align(0));

    b.addAll(poweredBy(size));
    b.addAll(finalize());
    return Uint8List.fromList(b);
  }

  // ── TEST PRINT PANJANG ────────────────────────────────────────────────────────
  static Uint8List buildTestLong(PaperSize size) {
    final List<int> b = [];
    final w = charsPerLine(size);
    final paperLabel = switch (size) {
      PaperSize.mm58 => '58mm',
      PaperSize.mm80 => '80mm',
      PaperSize.mm100 => '100mm'
    };
    final now = DateTime.now();
    final dateStr =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    b.addAll(init());
    _applyFontConfig(b);

    b.addAll(logoHeader(size));

    b.addAll(align(1));
    b.addAll(txt('Jl. Contoh No. 123, Bandung'));
    b.addAll(txt('Telp: (022) 1234-5678'));
    b.addAll(align(0));
    b.addAll(divider(size, char: '='));

    b.addAll(rowLR('No.', 'TRX-20250502-001', size));
    b.addAll(rowLR('Tanggal', dateStr, size));
    b.addAll(rowLR('Waktu', timeStr, size));
    b.addAll(rowLR('Kasir', 'Admin', size));
    b.addAll(divider(size));

    const items = [
      ('Indomie Goreng', 3, 3500, 10500),
      ('Aqua 600ml', 2, 5000, 10000),
      ('Roti Tawar Sari Roti', 1, 18500, 18500),
      ('Susu Ultra 200ml', 4, 6500, 26000),
      ('Sabun Lifebuoy', 2, 12000, 24000),
      ('Kopi Kapal Api', 5, 2500, 12500),
    ];

    // Kolom dinamis berdasarkan lebar yang dipilih
    const int cQ = 4; // Qty
    final int cP = w >= 48 ? 11 : 8; // Harga
    final int cT = w >= 48 ? 12 : 9; // Total
    final int cN = w - cQ - cP - cT; // Sisa untuk nama Item

    b.addAll(bold(true));
    b.addAll(txt(
      '${fixLen("Item", cN)}'
      '${fixLenR("Qty", cQ)}'
      '${fixLenR("Harga", cP)}'
      '${fixLenR("Total", cT)}',
    ));
    b.addAll(bold(false));
    b.addAll(divider(size));

    for (final (name, qty, price, total) in items) {
      b.addAll(txt(
        '${fixLen(name, cN)}'
        '${fixLenR('${qty}x', cQ)}'
        '${fixLenR(rp(price), cP)}'
        '${fixLenR(rp(total), cT)}',
      ));
    }

    b.addAll(divider(size));

    const subtotal = 101500;
    const diskon = 5000;
    const total = 96500;
    const bayar = 100000;
    const kembali = 3500;

    b.addAll(rowLR('Subtotal', 'Rp ${rp(subtotal)}', size));
    b.addAll(rowLR('Diskon', '-Rp ${rp(diskon)}', size));
    b.addAll(rowLR('Pajak (0%)', 'Rp 0', size));
    b.addAll(divider(size));

    b.addAll(bold(true));
    b.addAll(rowLR('TOTAL', 'Rp ${rp(total)}', size));
    b.addAll(bold(false));
    b.addAll(divider(size));

    b.addAll(rowLR('Tunai', 'Rp ${rp(bayar)}', size));
    b.addAll(bold(true));
    b.addAll(rowLR('Kembali', 'Rp ${rp(kembali)}', size));
    b.addAll(bold(false));
    b.addAll(divider(size, char: '='));

    final String fontLabel = _useFontB ? "Font B" : "Font A";
    b.addAll(align(1));
    b.addAll(txt('[ Test $paperLabel - $w kar - $fontLabel ]'));
    b.addAll(divider(size));
    b.addAll(txt('Terima kasih telah berbelanja'));
    b.addAll(align(0));

    b.addAll(poweredBy(size));
    b.addAll(finalize());
    return Uint8List.fromList(b);
  }

  // ── CONVERT TEXT KE ESCPOS ──────────────────────────────────────────────────

  static Uint8List textToEscPos(String text, PaperSize size) {
    final List<int> b = [];
    b.addAll(init());
    _applyFontConfig(b);
    for (int i = 0; i < text.length; i++) {
      int c = text.codeUnitAt(i);
      b.add(c < 256 ? c : 0x3F);
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
    if (qty == qty.roundToDouble()) return qty.round().toString();
    return qty.toStringAsFixed(2);
  }
}
