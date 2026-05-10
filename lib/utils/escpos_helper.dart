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
      PaperSize.mm80 => 576,
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

  static List<int> rowLR(String left, String right, PaperSize size,
      {bool boldRight = false}) {
    final w = charsPerLine(size);
    if (right.length >= w) return txt(right.substring(0, w));
    int effectiveRightLen = right.length;
    // Bold characters are slightly wider on MPT-II, so we reserve 1 extra space to prevent wrap
    if (boldRight) effectiveRightLen += 1;
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
    b.addAll(txt('dRetail'));
    b.addAll(bold(false));
    b.addAll(txt('Print Service'));
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
    final storeStreet = company['street'] as String? ?? '';
    b.addAll(align(1));
    b.addAll(bold(true));
    b.addAll(txt(storeName));
    b.addAll(bold(false));
    if (storePhone.isNotEmpty) b.addAll(txt(storePhone));
    if (storeEmail.isNotEmpty) b.addAll(txt(storeEmail));
    // Street address: cetak per-baris, tetap rata tengah
    if (storeStreet.isNotEmpty) {
      for (final line in storeStreet.split('\n')) {
        if (line.trim().isNotEmpty) b.addAll(txt(line.trim()));
      }
    }
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
      final discountAmt = (m['discount_amount'] ?? 0).toDouble();
      final discountPct = (m['discount'] ?? 0).toDouble();
      final discType =
          m['discount_type']?.toString() ?? (discountPct > 0 ? '%' : 'Rp');
      final basePrice = (m['price'] ?? 0).toDouble();
      final origPrice = (m['original_price'] ?? 0).toDouble();
      final unitPrice = (origPrice > basePrice) ? origPrice : basePrice;
      final subtotal = (origPrice > basePrice)
          ? (unitPrice * qty)
          : (m['price_with_tax'] ?? unitPrice * qty).toDouble();
      b.addAll(bold(true));
      int start = 0;
      while (start < name.length) {
        int end = start + w;
        if (end > name.length) end = name.length;
        String lineName = name.substring(start, end);
        if (start > 0) lineName = lineName.trimLeft();
        b.addAll(txt(lineName));
        start += w;
      }
      b.addAll(bold(false));
      final qtyStr = '${_formatQty(qty)} x Rp ${rp(unitPrice.round())}';
      final subtotalStr = 'Rp ${rp(subtotal.round())}';
      b.addAll(rowLR(qtyStr, subtotalStr, size, boldRight: true));
      // Diskon Item
      if (discountAmt > 0 || discountPct > 0) {
        bool isPercent = discType == '%' ||
            discType == 'percentage' ||
            (discountPct > 0 && discountAmt == 0);
        String discLabel =
            isPercent ? 'Disc(${_formatQty(discountPct)}%)' : 'Disc(Rp)';
        double nominalAmt = discountAmt > 0
            ? discountAmt
            : (basePrice * qty * (discountPct / 100));
        if (discountAmt <= 0 && discountPct > 0) {
          nominalAmt = unitPrice * qty * (discountPct / 100);
        }
        b.addAll(rowLR(discLabel, 'Rp ${rp(nominalAmt.round())}', size));
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
    final displaySubtotal = subtotalVal + totalDiscount;
    b.addAll(rowLR('Subtotal', 'Rp ${rp(displaySubtotal.round())}', size));
    if (globalDiscAmt > 0 || globalDiscPct > 0) {
      String gDiscLabel = globalDiscType == '%'
          ? 'Diskon Global (${_formatQty(globalDiscPct)}%)'
          : 'Diskon Global (Rp)';
      double gNominal = globalDiscAmt > 0 ? globalDiscAmt : totalDiscount;
      b.addAll(rowLR(gDiscLabel, 'Rp ${rp(gNominal.round())}', size));
    } else if (totalDiscount > 0) {
      b.addAll(rowLR('Total Diskon', 'Rp ${rp(totalDiscount.round())}', size));
    }
    if (taxVal > 0) {
      b.addAll(rowLR('Pajak', 'Rp ${rp(taxVal.round())}', size));
    }
    b.addAll(divider(size));
    b.addAll(bold(true));
    final totalStr = 'Rp ${rp(totalVal.round())}';
    int spaceTot = w - 5 - totalStr.length - 1;
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
    final storePhone = company['phone'] as String? ?? '';
    final storeStreet = company['street'] as String? ?? '';
    final orderName = d['name'] as String? ?? '-';
    final totalVal = (d['total_with_tax'] ?? 0).toDouble();
    final paidVal = (d['total_paid'] ?? totalVal).toDouble();
    final changeVal = (d['change'] ?? (paidVal - totalVal)).toDouble();
    final dateRaw = d['date'] as String? ?? '';
    final footer = d['footer_messages'] as String? ?? 'Terima kasih!\nSampai jumpa lagi.';
    b.addAll(align(1));
    b.addAll(bold(true));
    b.addAll(txt(storeName));
    b.addAll(bold(false));
    if (storePhone.isNotEmpty) b.addAll(txt(storePhone));
    if (storeStreet.isNotEmpty) {
      for (final line in storeStreet.split('\n')) {
        if (line.trim().isNotEmpty) b.addAll(txt(line.trim()));
      }
    }
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
    for (final line in footer.split('\n')) {
      if (line.trim().isNotEmpty) b.addAll(txt(line.trim()));
    }
    b.addAll(align(0));
    b.addAll(poweredBy(size));
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
      if (isBold) b.addAll(bold(true));
      final line = lines[i];
      for (int j = 0; j < line.length; j++) {
        int c = line.codeUnitAt(j);
        b.add(c < 256 ? c : 0x3F);
      }
      if (isBold) b.addAll(bold(false));
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
    if (qty == qty.roundToDouble()) return qty.round().toString();
    return qty.toStringAsFixed(2);
  }
}
