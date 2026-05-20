import 'dart:typed_data';
import 'dart:convert';
import 'package:image/image.dart' as img;

enum PaperSize {
  mm58,
  mm80,
  mm100,
}

enum CashDrawerMode {
  off,
  openAfterPrint,
  openBeforePrint,
}

class EscPosHelper {
  static const int escCmd = 0x1B;
  static const int gsCmd = 0x1D;
  static const int lfCmd = 0x0A;
  static int _customCharsPerLine = 0;
  static int _extraFeed = 3;
  static bool _autoCut = false;
  static bool _useFontB = false;
  static CashDrawerMode _cashDrawerMode = CashDrawerMode.off;
  static bool _sessionSummaryCashDrawer = false;

  static void setCustomCharsPerLine(int value) => _customCharsPerLine = value;
  static void setExtraFeed(int value) => _extraFeed = value;
  static void setAutoCut(bool value) => _autoCut = value;
  static void setUseFontB(bool value) => _useFontB = value;
  static void setCashDrawerMode(CashDrawerMode mode) => _cashDrawerMode = mode;
  static void setSessionSummaryCashDrawer(bool value) => _sessionSummaryCashDrawer = value;

  static int get customCharsPerLineSetting => _customCharsPerLine;
  static int get extraFeedSetting => _extraFeed;
  static bool get autoCutSetting => _autoCut;
  static bool get useFontBSetting => _useFontB;
  static CashDrawerMode get cashDrawerModeSetting => _cashDrawerMode;
  static bool get sessionSummaryCashDrawerSetting => _sessionSummaryCashDrawer;

  /// Opens the cash drawer using ESC/POS command.
  /// Standard command: ESC p 0 25 250 (0x1B 0x70 0x00 0x19 0xFA)
  static Uint8List openCashDrawer() =>
      Uint8List.fromList([escCmd, 0x70, 0x00, 0x19, 0xFA]);

  static int defaultCharsPerLine(PaperSize size) => switch (size) {
        PaperSize.mm58 => 32,
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

  // COMMANDS
  static Uint8List init() => Uint8List.fromList([escCmd, 0x40]);
  static Uint8List cut() => Uint8List.fromList([gsCmd, 0x56, 0x41, 0x00]);
  static Uint8List bold(bool on) =>
      Uint8List.fromList([escCmd, 0x45, on ? 1 : 0]);
  static Uint8List align(int a) => Uint8List.fromList([escCmd, 0x61, a]);
  static Uint8List feed(int n) => Uint8List.fromList([escCmd, 0x64, n]);
  static Uint8List setFontB(bool on) =>
      Uint8List.fromList([escCmd, 0x21, on ? 1 : 0]);
  static Uint8List doubleSize(bool on) =>
      Uint8List.fromList([0x1D, 0x21, on ? 0x11 : 0x00]);
  static Uint8List doubleHeight(bool on) =>
      Uint8List.fromList([0x1D, 0x21, on ? 0x01 : 0x00]);

  static Uint8List imageEsc(img.Image src, PaperSize paperSize) {
    int maxW = switch (paperSize) {
      PaperSize.mm58 => 192,
      PaperSize.mm80 => 288,
      PaperSize.mm100 => 384,
    };
    img.Image resized = src;

    if (src.numChannels == 4) {
      final rgbImage =
          img.Image(width: src.width, height: src.height, numChannels: 3);
      for (int y = 0; y < src.height; y++) {
        for (int x = 0; x < src.width; x++) {
          final p = src.getPixel(x, y);
          final r = p.r.toInt();
          final g = p.g.toInt();
          final bVal = p.b.toInt();
          final a = p.a.toInt();
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

    if (resized.width > maxW) {
      resized = img.copyResize(resized, width: maxW);
    }

    final int imgWidth = resized.width;
    final int imgHeight = resized.height;
    final int widthBytes = (imgWidth + 7) ~/ 8;

    final List<double> gray = List<double>.filled(imgWidth * imgHeight, 0.0);
    for (int y = 0; y < imgHeight; y++) {
      for (int x = 0; x < imgWidth; x++) {
        final pixel = resized.getPixel(x, y);
        gray[y * imgWidth + x] =
            (0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b) / 255.0;
      }
    }

    final List<bool> bw = List<bool>.filled(imgWidth * imgHeight, false);
    for (int y = 0; y < imgHeight; y++) {
      for (int x = 0; x < imgWidth; x++) {
        final idx = y * imgWidth + x;
        final oldVal = gray[idx].clamp(0.0, 1.0);
        final newVal = oldVal < 0.5 ? 0.0 : 1.0;
        bw[idx] = newVal == 0.0;
        final err = oldVal - newVal;
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

    final List<int> output = [];
    output.addAll([gsCmd, 0x76, 0x30, 0x00]);
    output.addAll([widthBytes % 256, widthBytes ~/ 256]);
    output.addAll([imgHeight % 256, imgHeight ~/ 256]);

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

  // HELPERS
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

  // SECTION HEADER
  static List<int> sectionHeader(String label, PaperSize size) {
    final w = charsPerLine(size);
    final inner = ' $label ';
    final dashCount = ((w - inner.length) / 2).floor();
    final dashes = '-' * (dashCount > 0 ? dashCount : 1);
    String line = '$dashes$inner$dashes';
    if (line.length < w) {
      line = line + '-' * (w - line.length);
    } else if (line.length > w) {
      line = line.substring(0, w);
    }
    return txt(line);
  }

  // SECTION HEADER LINE
  static String sectionHeaderLine(String label, PaperSize size, String char) {
    final w = charsPerLine(size);
    final inner = label;
    final dashCount = ((w - inner.length) / 2).floor();
    final dashes = char * (dashCount > 0 ? dashCount : 1);
    String line = '$dashes$inner$dashes';
    if (line.length < w) {
      line = line + char * (w - line.length);
    } else if (line.length > w) {
      line = line.substring(0, w);
    }
    return line;
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
        bytes.add(0x20);
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

  static String rp(int amount,
      {String symbol = 'Rp', int decimals = 0, bool positionAfter = false}) {
    String prefix = symbol;
    String suffix = '';
    int value = amount.abs();
    if (decimals > 0) {
      final divisor = _pow10(decimals);
      final whole = (value ~/ divisor);
      final frac = (value % divisor).toString().padLeft(decimals, '0');
      final wholeStr = _formatWithDot(whole);
      final result = '$wholeStr$frac';
      if (positionAfter) {
        suffix = ' $symbol';
        return amount < 0 ? '-$result$suffix' : '$result$suffix';
      }
      return amount < 0 ? '-$prefix$result' : '$prefix$result';
    }
    final formatted = _formatWithDot(value);
    if (positionAfter) {
      suffix = ' $symbol';
      return amount < 0 ? '-$formatted$suffix' : '$formatted$suffix';
    }
    return amount < 0 ? '-$prefix$formatted' : '$prefix$formatted';
  }

  static int _pow10(int exp) {
    int result = 1;
    for (int i = 0; i < exp; i++) {
      result *= 10;
    }
    return result;
  }

  static String _formatWithDot(int value) {
    final s = value.toString();
    final buf = StringBuffer();
    int count = 0;
    for (int i = s.length - 1; i >= 0; i--) {
      if (count > 0 && count % 3 == 0) {
        buf.write('.');
      }
      buf.write(s[i]);
      count++;
    }
    return buf.toString().split('').reversed.join();
  }

  static String currencyFmt(double amount, Map<String, dynamic> currency) {
    final symbol = currency['symbol'] as String? ?? 'Rp';
    final decimals = currency['decimal_places'] as int? ?? 0;
    final positionAfter =
        (currency['position'] as String? ?? 'before') == 'after';
    return rp(amount.round(),
        symbol: symbol, decimals: decimals, positionAfter: positionAfter);
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

  static String storeNameDoubleSize(String name, int w) {
    final maxChars = w ~/ 2;
    final truncated =
        name.length > maxChars ? name.substring(0, maxChars) : name;
    return '\x1D\x21\x11$truncated\x1D\x21\x00';
  }

  static List<int> logoHeader(PaperSize size) {
    final List<int> b = [];
    b.addAll(align(1));
    b.addAll(bold(true));
    b.addAll(txt('dRetail Mart'));
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

  // BUILD FROM ODOO ORDER DATA
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

  // PRINT FULL RECEIPT
  static Uint8List _buildFullReceipt(Map<String, dynamic> d, PaperSize size) {
    final List<int> b = [];
    b.addAll(init());
    _applyFontConfig(b);

    final company = d['company'] as Map<String, dynamic>? ?? {};
    final logoBase64 = company['logo'] as String? ?? '';
    final storeName = (company['name'] as String? ?? 'Toko').trim();
    final storePhone = company['phone'] as String? ?? '';
    final storeEmail = company['email'] as String? ?? '';
    final orderName = d['name'] as String? ?? '-';
    final dateRaw = d['date'] as String? ?? '';
    final cashier = d['cashier'] as String? ?? '-';
    final receiptHeader = (d['receipt_header'] as String? ?? '').trim();
    final receiptFooter = (d['receipt_footer'] as String? ?? '').trim();

    // LOGO
    if (logoBase64.isNotEmpty) {
      try {
        final bytes = base64Decode(
            logoBase64.contains(',') ? logoBase64.split(',')[1] : logoBase64);
        final image = img.decodeImage(bytes);
        if (image != null) {
          b.addAll(align(1));
          b.addAll(imageEsc(image, size));
          b.addAll(align(0));
        }
      } catch (_) {}
    }

    b.addAll(feed(1));

    // STORE NAME
    b.addAll(align(1));
    b.addAll(bold(true));
    final w = charsPerLine(size);
    final maxChars = w ~/ 2;
    final truncatedName = storeName.length > maxChars
        ? storeName.substring(0, maxChars)
        : storeName;
    b.addAll(doubleSize(true));
    b.addAll(txt(truncatedName));
    b.addAll(doubleSize(false));
    b.addAll(bold(false));

    // CONTACT INFO
    if (storePhone.isNotEmpty) {
      b.addAll(txt('Telp : $storePhone'));
    }
    if (storeEmail.isNotEmpty) {
      b.addAll(txt(storeEmail));
    }

    // RECEIPT HEADER
    if (receiptHeader.isNotEmpty) {
      b.addAll(align(1));
      b.addAll(txt(receiptHeader));
      b.addAll(align(0));
    }

    b.addAll(divider(size, char: '='));

    // ORDER INFO
    final orderNumberClean = orderName
        .toString()
        .replaceFirst(RegExp(r'^Order\s*', caseSensitive: false), '');
    final dateFormatted = dateRaw.isNotEmpty ? _formatDateShort(dateRaw) : '';
    b.addAll(rowLR('Ref         :', orderNumberClean, size));
    b.addAll(rowLR('Tanggal     :', dateFormatted, size));
    b.addAll(rowLR('Kasir       :', cashier, size));
    b.addAll(divider(size, char: '='));

    final currency = company['currency'] as Map<String, dynamic>? ??
        {'symbol': 'Rp', 'decimal_places': 0};
    final symbol = currency['symbol'] as String? ?? 'Rp';
    final decimals = currency['decimal_places'] as int? ?? 0;

    // SECTION HEADER
    b.addAll(bold(true));
    b.addAll(sectionHeader('DETAIL ITEM', size));
    b.addAll(bold(false));

    // ORDERLINES
    final lines = d['orderlines'] as List<dynamic>? ?? [];
    double globalDiscountLineAmt = 0;

    for (final line in lines) {
      final m = line as Map<String, dynamic>;
      final isGlobalDiscount = m['is_global_discount'] == true;

      if (isGlobalDiscount) {
        globalDiscountLineAmt +=
            (m['discount_amount'] ?? (m['price_with_tax'] ?? m['price'] ?? 0))
                .toDouble()
                .abs();
        continue;
      }

      final rawName = m['product_name'] as String? ?? '';
      final name = rawName.replaceAll('\n', ' ').trim();
      final qty = (m['qty'] ?? 1).toDouble();
      final unitPrice = (m['price'] ?? 0).toDouble();
      final subtotal = (m['price_with_tax'] ?? unitPrice * qty).toDouble();
      final discountPct = (m['discount'] ?? 0).toDouble();
      final discountAmt = (m['discount_amount'] ?? 0).toDouble();
      final discountType = m['discount_type'] as String? ?? '%';
      final customerNote = m['customer_note'] as String? ?? '';

      final w = charsPerLine(size);
      final nameLines = _wordWrap(name, w);
      b.addAll(bold(true));
      for (final nl in nameLines) {
        b.addAll(txt(nl));
      }
      b.addAll(bold(false));

      final uom = (m['uom'] as String? ?? '').trim();
      final uomLabel = uom.isNotEmpty ? uom : 'Pcs';
      final qtyStr =
          '${_formatQty(qty)} $uomLabel x ${rp(unitPrice.round(), symbol: symbol, decimals: decimals)}';
      final totalStr = rp(subtotal.round(), symbol: symbol, decimals: decimals);
      b.addAll(rowLR(qtyStr, totalStr, size, boldRight: true));

      if (discountType == '%' && discountPct > 0 && discountAmt > 0) {
        final discLabel = '  Disc(${_formatQty(discountPct)}%)';
        final discStr =
            rp(-discountAmt.round(), symbol: symbol, decimals: decimals);
        b.addAll(rowLR(discLabel, discStr, size));
      } else if (discountType == 'Rp' && discountAmt > 0) {
        const discLabel = '  Disc(Rp)';
        final discStr =
            rp(-discountAmt.round(), symbol: symbol, decimals: decimals);
        b.addAll(rowLR(discLabel, discStr, size));
      }

      if (customerNote.isNotEmpty) {
        b.addAll(txt('  * $customerNote'));
      }
    }

    // GLOBAL DISCOUNT
    if (globalDiscountLineAmt > 0) {
      final globalDiscStr = rp(-globalDiscountLineAmt.round(),
          symbol: symbol, decimals: decimals);
      b.addAll(bold(true));
      b.addAll(rowLR('Discount', globalDiscStr, size, boldRight: true));
      b.addAll(bold(false));
    }

    // FINANCIAL SUMMARY
    final subtotalVal = (d['total_without_tax'] ?? 0).toDouble();
    final taxVal = (d['total_tax'] ?? 0).toDouble();
    final totalVal = (d['total_with_tax'] ?? 0).toDouble();
    final paidVal = (d['total_paid'] ?? totalVal).toDouble();
    final changeVal = (d['change'] ?? (paidVal - totalVal)).toDouble();
    final allDiscount = (d['total_discount'] ?? 0).toDouble();
    final dppVal = subtotalVal - allDiscount;

    // TOTAL BELANJA
    b.addAll(divider(size, char: '='));
    b.addAll(rowLR('Total Belanja',
        rp(subtotalVal.round(), symbol: symbol, decimals: decimals), size));
    if (allDiscount > 0) {
      b.addAll(rowLR('Total Diskon',
          rp(-allDiscount.round(), symbol: symbol, decimals: decimals), size));
    }

    // DPP & PPN
    b.addAll(divider(size, char: '.'));
    if (taxVal > 0) {
      b.addAll(rowLR(
          'DPP', rp(dppVal.round(), symbol: symbol, decimals: decimals), size));
      b.addAll(rowLR('PPN 11%',
          rp(taxVal.round(), symbol: symbol, decimals: decimals), size));
    }

    // TOTAL BAYAR
    b.addAll(divider(size, char: '-'));
    b.addAll(doubleHeight(true));
    b.addAll(bold(true));
    b.addAll(rowLR('TOTAL BAYAR',
        rp(totalVal.round(), symbol: symbol, decimals: decimals), size));
    b.addAll(bold(false));
    b.addAll(doubleHeight(false));

    // PAYMENT
    final payments = d['paymentlines'] as List<dynamic>? ?? [];
    for (final pay in payments) {
      final p = pay as Map<String, dynamic>;
      final payName = p['name'] as String? ?? 'Cash';
      final payAmt = (p['amount'] ?? 0).toDouble();
      b.addAll(rowLR(payName,
          rp(payAmt.round(), symbol: symbol, decimals: decimals), size));
    }
    if (payments.isEmpty && paidVal > 0) {
      b.addAll(rowLR('Cash',
          rp(paidVal.round(), symbol: symbol, decimals: decimals), size));
    }

    // CHANGE
    b.addAll(bold(true));
    b.addAll(rowLR('CHANGE',
        rp(changeVal.round(), symbol: symbol, decimals: decimals), size));
    b.addAll(bold(false));

    // QR / PORTAL INFO
    if (d['unique_code'] != null || d['portal_url'] != null) {
      b.addAll(divider(size, char: '-'));
      b.addAll(align(1));
      b.addAll(txt('Need an invoice for your purchase?'));
      b.addAll(txt('[QR CODE]'));
      if (d['unique_code'] != null) {
        b.addAll(txt('Unique Code: ${d['unique_code']}'));
      }
      if (d['portal_url'] != null) {
        b.addAll(txt('Portal URL: ${d['portal_url']}'));
      }
      b.addAll(align(0));
    }

    // RECEIPT FOOTER
    b.addAll(divider(size, char: '='));
    if (receiptFooter.isNotEmpty) {
      b.addAll(align(1));
      b.addAll(bold(true));
      for (final line in receiptFooter.split('\n')) {
        if (line.trim().isNotEmpty) {
          b.addAll(txt(line.trim()));
        }
      }
      b.addAll(bold(false));
      b.addAll(align(0));
    }

    // POWERED BY
    b.addAll(feed(1));
    b.addAll(align(1));
    b.addAll(bold(true));
    b.addAll(txt('Powered by dRetail'));
    b.addAll(bold(false));
    final now = DateTime.now();
    final printDt =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year.toString().substring(2)} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    b.addAll(txt(printDt));
    b.addAll(align(0));

    b.addAll(finalize());
    return Uint8List.fromList(b);
  }

  // PRINT BASIC RECEIPT
  static Uint8List _buildBasicReceipt(Map<String, dynamic> d, PaperSize size) {
    final List<int> b = [];
    b.addAll(init());
    _applyFontConfig(b);

    final company = d['company'] as Map<String, dynamic>? ?? {};
    final logoBase64 = company['logo'] as String? ?? '';
    final storeName = (company['name'] as String? ?? 'Toko').trim();
    final storePhone = company['phone'] as String? ?? '';
    final storeEmail = company['email'] as String? ?? '';
    final orderName = d['name'] as String? ?? '-';
    final dateRaw = d['date'] as String? ?? '';
    final cashier = d['cashier'] as String? ?? '-';
    final receiptHeader = (d['receipt_header'] as String? ?? '').trim();
    final receiptFooter = (d['receipt_footer'] as String? ?? '').trim();

    // LOGO
    if (logoBase64.isNotEmpty) {
      try {
        final bytes = base64Decode(
            logoBase64.contains(',') ? logoBase64.split(',')[1] : logoBase64);
        final image = img.decodeImage(bytes);
        if (image != null) {
          b.addAll(align(1));
          b.addAll(imageEsc(image, size));
          b.addAll(align(0));
        }
      } catch (_) {}
    }

    // STORE NAME
    b.addAll(align(1));
    b.addAll(bold(true));
    final w = charsPerLine(size);
    final maxChars = w ~/ 2;
    final truncatedName = storeName.length > maxChars
        ? storeName.substring(0, maxChars)
        : storeName;
    b.addAll(doubleSize(true));
    b.addAll(txt(truncatedName));
    b.addAll(doubleSize(false));
    b.addAll(bold(false));

    // CONTACT INFO
    if (storePhone.isNotEmpty) {
      b.addAll(txt('Telp : $storePhone'));
    }
    if (storeEmail.isNotEmpty) {
      b.addAll(txt(storeEmail));
    }

    // RECEIPT HEADER
    if (receiptHeader.isNotEmpty) {
      b.addAll(align(1));
      b.addAll(txt(receiptHeader));
      b.addAll(align(0));
    }

    b.addAll(divider(size, char: '='));

    // ORDER INFO
    final orderNumberClean = orderName
        .toString()
        .replaceFirst(RegExp(r'^Order\s*', caseSensitive: false), '');
    final dateFormatted = dateRaw.isNotEmpty ? _formatDateShort(dateRaw) : '';
    b.addAll(rowLR('Ref         :', orderNumberClean, size));
    b.addAll(rowLR('Tanggal     :', dateFormatted, size));
    b.addAll(rowLR('Kasir       :', cashier, size));
    b.addAll(divider(size, char: '='));

    // SECTION HEADER
    b.addAll(bold(true));
    b.addAll(sectionHeader('DETAIL ITEM', size));
    b.addAll(bold(false));

    // ORDERLINES
    final lines = d['orderlines'] as List<dynamic>? ?? [];
    final linesPerPage = charsPerLine(size);
    for (final line in lines) {
      final m = line as Map<String, dynamic>;
      final rawName = m['product_name'] as String? ?? '';
      final name = rawName.replaceAll('\n', ' ').trim();
      final qty = (m['qty'] ?? 1).toDouble();
      final customerNote = m['customer_note'] as String? ?? '';

      final uom = (m['uom'] as String? ?? '').trim();
      final uomLabel = uom.isNotEmpty ? uom : 'Pcs';
      final qtyStr = '${_formatQty(qty)} $uomLabel';

      b.addAll(bold(true));
      final nameLines = _wordWrap(name, linesPerPage - qtyStr.length - 1);
      for (int i = 0; i < nameLines.length; i++) {
        if (i == 0) {
          b.addAll(rowLR(nameLines[i], qtyStr, size));
        } else {
          b.addAll(txt(nameLines[i]));
        }
      }
      b.addAll(bold(false));

      if (customerNote.isNotEmpty) {
        b.addAll(txt('  * $customerNote'));
      }
    }
    b.addAll(divider(size, char: '='));

    // RECEIPT FOOTER
    if (receiptFooter.isNotEmpty) {
      b.addAll(align(1));
      b.addAll(bold(true));
      for (final line in receiptFooter.split('\n')) {
        if (line.trim().isNotEmpty) {
          b.addAll(txt(line.trim()));
        }
      }
      b.addAll(bold(false));
      b.addAll(align(0));
    }

    // POWERED BY
    b.addAll(align(1));
    b.addAll(bold(true));
    b.addAll(txt('Powered by dRetail'));
    b.addAll(bold(false));
    final now = DateTime.now();
    final printDt =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year.toString().substring(2)} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    b.addAll(txt(printDt));
    b.addAll(align(0));

    b.addAll(finalize());
    return Uint8List.fromList(b);
  }

  // CONVERT TEXT TO ESCPOS
  static Uint8List textToEscPos(String text, PaperSize size,
      {bool isBold = false, int alignMode = 0}) {
    final List<int> b = [];
    b.addAll(init());
    _applyFontConfig(b);

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

  // INTERNAL HELPERS
  static String _formatQty(double qty) {
    if (qty == qty.roundToDouble()) {
      return qty.round().toString();
    }
    return qty.toStringAsFixed(2);
  }

  static String _formatDateShort(String raw) {
    try {
      if (raw.isEmpty) return '';
      final dt = DateTime.parse(raw);
      if (dt.isUtc) {
        return '${dt.toLocal().day.toString().padLeft(2, '0')}/'
            '${dt.toLocal().month.toString().padLeft(2, '0')}/'
            '${dt.toLocal().year} '
            '${dt.toLocal().hour.toString().padLeft(2, '0')}:'
            '${dt.toLocal().minute.toString().padLeft(2, '0')}';
      }
      return '${dt.day.toString().padLeft(2, '0')}/'
          '${dt.month.toString().padLeft(2, '0')}/'
          '${dt.year} '
          '${dt.hour.toString().padLeft(2, '0')}:'
          '${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      // Fallback: coba parse manual DD/MM/YYYY or DD-MM-YYYY
      final s = raw.trim();
      final isoCandidate = s
          .replaceFirst(RegExp(r'^(\d{1,2})[\/\-](\d{1,2})[\/\-](\d{4})'), r'$3-$2-$1')
          .replaceFirst(RegExp(r'^(\d{4})[\/\-](\d{1,2})[\/\-](\d{1,2})'), r'$1-$2-$3');
      try {
        final dt2 = DateTime.parse(isoCandidate);
        return '${dt2.day.toString().padLeft(2, '0')}/'
            '${dt2.month.toString().padLeft(2, '0')}/'
            '${dt2.year} '
            '${dt2.hour.toString().padLeft(2, '0')}:'
            '${dt2.minute.toString().padLeft(2, '0')}';
      } catch (_) {
        return raw; // Kembalikan apa adanya jika semua gagal
      }
    }
  }

  // SUMMARY REPORT SESSION
  static Uint8List buildSessionSummary(Map<String, dynamic> d, PaperSize size) {
    final List<int> b = [];
    b.addAll(init());
    _applyFontConfig(b);
    final now = DateTime.now();

    final company = d['company'] as Map<String, dynamic>? ?? {};
    final currency = company['currency'] as Map<String, dynamic>? ??
        {'symbol': 'Rp', 'decimal_places': 0};
    final symbol = currency['symbol'] as String? ?? 'Rp';
    final decimals = currency['decimal_places'] as int? ?? 0;
    final positionAfter =
        (currency['position'] as String? ?? 'before') == 'after';
    final w = charsPerLine(size);

    // REPORT TITLE
    b.addAll(align(1));
    b.addAll(bold(true));
    b.addAll(txt('SESSION SUMMARY REPORT'));
    b.addAll(bold(false));
    b.addAll(txt('=' * w));
    b.addAll(txt('-' * w));

    final posName = d['pos_name'] as String? ?? '-';
    final sessionName = d['session_name'] as String? ?? '-';
    final cashierName = d['cashier_name'] as String? ?? '-';
    final startAt = d['start_at'] as String? ?? '-';
    final stopAt = d['stop_at'] as String? ?? '-';

    // HEADER INFO
    b.addAll(align(0));
    b.addAll(rowLR('PoS Name :', posName, size));
    b.addAll(rowLR('Session ID :', sessionName, size));
    b.addAll(rowLR('Cashier :', cashierName, size));
    b.addAll(rowLR('Opening :', startAt, size));
    b.addAll(rowLR('Closing :', stopAt, size));

    // SALES SUMMARY
    b.addAll(align(1));
    b.addAll(bold(true));
    b.addAll(txt(sectionHeaderLine('', size, '-')));
    b.addAll(txt(sectionHeaderLine('SALES SUMMARY', size, '-')));
    b.addAll(txt(sectionHeaderLine('', size, '-')));
    b.addAll(bold(false));
    b.addAll(align(0));

    final grossSales = (d['gross_sales'] ?? 0).toDouble();
    final totalDiscount = (d['total_discount'] ?? 0).toDouble();
    final refundUntaxed = (d['refund_amount_untaxed'] ?? 0).toDouble();
    final netSalesBeforeTax = (d['net_sales_before_tax'] ?? 0).toDouble();
    final totalTaxes = (d['total_taxes'] ?? 0).toDouble();
    final totalSales = (d['total_sales'] ?? 0).toDouble();

    b.addAll(rowLR(
        'Gross Sales',
        rp(grossSales.round(), symbol: symbol, decimals: decimals, positionAfter: positionAfter),
        size));
    b.addAll(rowLR(
        'Discounts',
        rp(-totalDiscount.round(), symbol: symbol, decimals: decimals, positionAfter: positionAfter),
        size));
    b.addAll(rowLR(
        'Returns/Refunds',
        rp(-refundUntaxed.round(), symbol: symbol, decimals: decimals, positionAfter: positionAfter),
        size));
    b.addAll(txt('.' * w));
    b.addAll(rowLR(
        'Net Sales',
        rp(netSalesBeforeTax.round(), symbol: symbol, decimals: decimals, positionAfter: positionAfter),
        size));
    b.addAll(rowLR(
        'Tax',
        rp(totalTaxes.round(), symbol: symbol, decimals: decimals, positionAfter: positionAfter),
        size));
    b.addAll(txt('.' * w));
    b.addAll(bold(true));
    b.addAll(rowLR(
        'Total Sales',
        rp(totalSales.round(), symbol: symbol, decimals: decimals, positionAfter: positionAfter),
        size));
    b.addAll(bold(false));

    // RETURNS / REFUNDS
    b.addAll(align(1));
    b.addAll(bold(true));
    b.addAll(txt(sectionHeaderLine('', size, '-')));
    b.addAll(txt(sectionHeaderLine('RETURNS/REFUNDS', size, '-')));
    b.addAll(txt(sectionHeaderLine('', size, '-')));
    b.addAll(bold(false));
    b.addAll(align(0));

    final refundAmount = (d['refund_amount'] ?? 0).toDouble();
    b.addAll(rowLR(
        'Total Refund Amount',
        rp(refundAmount.round(), symbol: symbol, decimals: decimals, positionAfter: positionAfter),
        size));

    // PAYMENT METHOD
    b.addAll(align(1));
    b.addAll(bold(true));
    b.addAll(txt(sectionHeaderLine('', size, '-')));
    b.addAll(txt(sectionHeaderLine('PAYMENT METHOD', size, '-')));
    b.addAll(txt(sectionHeaderLine('', size, '-')));
    b.addAll(bold(false));
    b.addAll(align(0));

    final payments = d['payments'] as List<dynamic>? ?? [];
    for (final pay in payments) {
      final p = pay as Map<String, dynamic>;
      final payName = (p['method'] as String? ?? 'Payment').toUpperCase();
      final payAmt = (p['amount'] ?? 0).toDouble();
      b.addAll(rowLR(
          payName,
          rp(payAmt.round(), symbol: symbol, decimals: decimals, positionAfter: positionAfter),
          size));
    }
    final totalPayment = (d['total_payment_amount'] ?? 0).toDouble();
    b.addAll(txt('.' * w));
    b.addAll(bold(true));
    b.addAll(rowLR(
        'Total Payment',
        rp(totalPayment.round(), symbol: symbol, decimals: decimals, positionAfter: positionAfter),
        size));
    b.addAll(bold(false));

    // CASH DRAWER SUMMARY
    b.addAll(align(1));
    b.addAll(bold(true));
    b.addAll(txt(sectionHeaderLine('', size, '-')));
    b.addAll(txt(sectionHeaderLine('CASH DRAWER SUMMARY', size, '-')));
    b.addAll(txt(sectionHeaderLine('', size, '-')));
    b.addAll(bold(false));
    b.addAll(align(0));

    final startingCash = (d['starting_cash'] ?? 0).toDouble();
    final cashSales = (d['cash_sales'] ?? 0).toDouble();
    final cashIn = (d['cash_in'] ?? 0).toDouble();
    final cashOut = (d['cash_out'] ?? 0).toDouble();
    final expectedCash = (d['expected_cash'] ?? 0).toDouble();

    b.addAll(rowLR(
        'Opening Cash',
        rp(startingCash.round(), symbol: symbol, decimals: decimals, positionAfter: positionAfter),
        size));
    b.addAll(rowLR(
        '(+) Cash Sales',
        rp(cashSales.round(), symbol: symbol, decimals: decimals, positionAfter: positionAfter),
        size));
    if (cashIn > 0) {
      b.addAll(rowLR(
          '(+) Cash In',
          rp(cashIn.round(), symbol: symbol, decimals: decimals, positionAfter: positionAfter),
          size));
    }
    if (cashOut > 0) {
      b.addAll(rowLR(
          '(-) Cash Out',
          rp(-cashOut.round(), symbol: symbol, decimals: decimals, positionAfter: positionAfter),
          size));
    }
    b.addAll(txt('.' * w));
    b.addAll(bold(true));
    b.addAll(rowLR(
        'Total',
        rp(expectedCash.round(), symbol: symbol, decimals: decimals, positionAfter: positionAfter),
        size));
    b.addAll(bold(false));

    // SESSION TRANSACTIONS
    b.addAll(align(1));
    b.addAll(bold(true));
    b.addAll(txt(sectionHeaderLine('', size, '-')));
    b.addAll(txt(sectionHeaderLine('SESSION TRANSACTIONS', size, '-')));
    b.addAll(txt(sectionHeaderLine('', size, '-')));
    b.addAll(bold(false));
    b.addAll(align(0));

    final totalTransactions = d['total_transactions'] ?? 0;
    final salesTransactions = d['sales_transactions'] ?? 0;
    final refundTransactions = d['refund_transactions'] ?? 0;
    final totalQtySold = d['total_qty_sold'] ?? 0;

    b.addAll(rowLR('Total Transactions', '$totalTransactions', size));
    b.addAll(rowLR('Sales Transactions', '$salesTransactions', size));
    b.addAll(rowLR('Returns/Refunds', '$refundTransactions', size));
    b.addAll(rowLR('Items Sold', '$totalQtySold', size));

    // CLOSING BALANCE
    final countedCash = (d['counted_cash'] ?? 0).toDouble();
    final differenceCash = (d['difference_cash'] ?? 0).toDouble();
    final totalCreditAmount = (d['total_credit_amount'] ?? 0).toDouble();

    b.addAll(txt('=' * w));
    b.addAll(bold(true));
    b.addAll(rowLR(
        'Expected Balance :',
        rp(expectedCash.round(), symbol: symbol, decimals: decimals, positionAfter: positionAfter),
        size));
    b.addAll(rowLR(
        'Closing Balance :',
        rp(countedCash.round(), symbol: symbol, decimals: decimals, positionAfter: positionAfter),
        size));
    b.addAll(rowLR(
        'Difference :',
        rp(differenceCash.round(), symbol: symbol, decimals: decimals, positionAfter: positionAfter),
        size));
    b.addAll(bold(false));

    if (totalCreditAmount > 0) {
      b.addAll(txt('.' * w));
      b.addAll(rowLR(
          '* Credit(piutang) :',
          rp(totalCreditAmount.round(), symbol: symbol, decimals: decimals, positionAfter: positionAfter),
          size));
    }

    b.addAll(txt('=' * w));

    // POWERED BY
    b.addAll(feed(1));
    b.addAll(align(1));
    b.addAll(bold(true));
    b.addAll(txt('Powered by dRetail'));
    b.addAll(bold(false));
    final printDt = d['print_date'] as String? ??
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year.toString().substring(2)} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    b.addAll(txt(printDt));
    b.addAll(align(0));

    b.addAll(finalize());
    return Uint8List.fromList(b);
  }
}
