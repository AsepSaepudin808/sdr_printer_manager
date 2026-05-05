import 'dart:typed_data';

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

  static void setCustomCharsPerLine(int value) => _customCharsPerLine = value;
  static void setExtraFeed(int value) => _extraFeed = value;
  static void setAutoCut(bool value) => _autoCut = value;

  static int defaultCharsPerLine(PaperSize size) => switch (size) {
        PaperSize.mm58 => 32,
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

  // ── HELPER TEXT ─────────────────────────────────────────────────────────────

  static List<int> txt(String s) => '$s\n'.codeUnits;

  static List<int> divider(PaperSize size, {String char = '-'}) {
    final w = charsPerLine(size);
    return ('${char * w}\n').codeUnits;
  }

  static List<int> rowLR(String left, String right, PaperSize size) {
    final w = charsPerLine(size);
    final maxLeft = w - right.length - 1;
    final l = left.length > maxLeft ? left.substring(0, maxLeft) : left;
    final space = w - l.length - right.length;
    final padding = space > 0 ? ' ' * space : ' ';
    return ('$l$padding$right\n').codeUnits;
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

  // ── BUILD DARI DATA ORDER ODOO (format: odoo_json) ─────────────────────────
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

    final company = d['company'] as Map<String, dynamic>? ?? {};
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

    final colName = switch (size) {
      PaperSize.mm58 => 18,
      PaperSize.mm80 => 22,
      PaperSize.mm100 => 30
    };
    final colQty = switch (size) {
      PaperSize.mm58 => 4,
      PaperSize.mm80 => 4,
      PaperSize.mm100 => 5
    };
    final colPrice = switch (size) {
      PaperSize.mm58 => 9,
      PaperSize.mm80 => 11,
      PaperSize.mm100 => 14
    };
    final colTotal = switch (size) {
      PaperSize.mm58 => 11,
      PaperSize.mm80 => 11,
      PaperSize.mm100 => 15
    };

    b.addAll(bold(true));
    b.addAll(txt(
      '${fixLen("Nama Produk", colName)}'
      '${fixLenR("Qty", colQty)}'
      '${fixLenR("Harga", colPrice)}'
      '${fixLenR("Total", colTotal)}',
    ));
    b.addAll(bold(false));
    b.addAll(divider(size));

    for (final line in lines) {
      final m = line as Map<String, dynamic>;
      final name = m['product_name'] as String? ?? '';
      final qty = (m['qty'] ?? 1).toDouble();
      final unitPrice = (m['price'] ?? 0).toDouble();
      final subtotal = (m['price_with_tax'] ?? unitPrice * qty).toDouble();

      b.addAll(txt(
        '${fixLen(name, colName)}'
        '${fixLenR(_formatQty(qty), colQty)}'
        '${fixLenR(rp(unitPrice.round()), colPrice)}'
        '${fixLenR(rp(subtotal.round()), colTotal)}',
      ));
    }

    b.addAll(divider(size));

    final subtotalVal = (d['total_without_tax'] ?? 0).toDouble();
    final taxVal = (d['total_tax'] ?? 0).toDouble();
    final discountVal = (d['total_discount'] ?? 0).toDouble();
    final totalVal = (d['total_with_tax'] ?? 0).toDouble();
    final paidVal = (d['total_paid'] ?? totalVal).toDouble();
    final changeVal = (d['change'] ?? (paidVal - totalVal)).toDouble();

    if (discountVal > 0) {
      b.addAll(rowLR('Subtotal', 'Rp ${rp(subtotalVal.round())}', size));
      b.addAll(rowLR('Diskon', '-Rp ${rp(discountVal.round())}', size));
    }
    if (taxVal > 0) {
      b.addAll(rowLR('Pajak', 'Rp ${rp(taxVal.round())}', size));
    }

    b.addAll(divider(size));
    b.addAll(bold(true));
    b.addAll(rowLR('TOTAL', 'Rp ${rp(totalVal.round())}', size));
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

    b.addAll(feed(4));
    b.addAll(cut());
    return Uint8List.fromList(b);
  }

  // ── BASIC RECEIPT ────────────────────────────────────────────────────────────
  static Uint8List _buildBasicReceipt(Map<String, dynamic> d, PaperSize size) {
    final List<int> b = [];

    b.addAll(init());

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

    b.addAll(feed(4));
    b.addAll(cut());
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
    final dateStr = '${now.day.toString().padLeft(2, '0')}/'
        '${now.month.toString().padLeft(2, '0')}/'
        '${now.year}';
    final timeStr = '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}';

    b.addAll(init());
    b.addAll(logoHeader(size));
    b.addAll(align(1));
    b.addAll(txt('-- TEST PRINT PENDEK --'));
    b.addAll(align(0));
    b.addAll(divider(size));
    b.addAll(rowLR('Kertas', '$paperLabel (${w}kar)', size));
    b.addAll(rowLR('Tanggal', dateStr, size));
    b.addAll(rowLR('Waktu', timeStr, size));
    b.addAll(divider(size));

    final totalLine = rowLR('TOTAL', 'Rp ${rp(150000)}', size);
    final tunaiLine = rowLR('Tunai', 'Rp ${rp(200000)}', size);
    final kembaliLine = rowLR('Kembali', 'Rp ${rp(50000)}', size);

    b.addAll(bold(true));
    b.addAll(totalLine);
    b.addAll(bold(false));
    b.addAll(tunaiLine);
    b.addAll(kembaliLine);
    b.addAll(divider(size));

    b.addAll(align(1));
    b.addAll(bold(true));
    b.addAll(txt('*** Printer OK! ***'));
    b.addAll(bold(false));
    b.addAll(txt('Terima kasih'));
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
    final dateStr = '${now.day.toString().padLeft(2, '0')}/'
        '${now.month.toString().padLeft(2, '0')}/'
        '${now.year}';
    final timeStr = '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}';

    b.addAll(init());
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

    final items = [
      ('Indomie Goreng', 3, 3500, 10500),
      ('Aqua 600ml', 2, 5000, 10000),
      ('Roti Tawar Sari Roti', 1, 18500, 18500),
      ('Susu Ultra 200ml', 4, 6500, 26000),
      ('Sabun Lifebuoy', 2, 12000, 24000),
      ('Kopi Kapal Api', 5, 2500, 12500),
    ];

    final cN = switch (size) {
      PaperSize.mm58 => 18,
      PaperSize.mm80 => 22,
      PaperSize.mm100 => 30
    };
    final cQ = switch (size) {
      PaperSize.mm58 => 4,
      PaperSize.mm80 => 4,
      PaperSize.mm100 => 5
    };
    final cP = switch (size) {
      PaperSize.mm58 => 9,
      PaperSize.mm80 => 11,
      PaperSize.mm100 => 14
    };
    final cT = switch (size) {
      PaperSize.mm58 => 11,
      PaperSize.mm80 => 11,
      PaperSize.mm100 => 15
    };

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

    b.addAll(align(1));
    b.addAll(txt('[ Test $paperLabel - $w kar/baris ]'));
    b.addAll(divider(size));
    b.addAll(txt('Terima kasih telah berbelanja'));
    b.addAll(bold(true));
    b.addAll(txt('di dRetail Mart!'));
    b.addAll(bold(false));
    b.addAll(txt(''));
    b.addAll(txt('Barang yang sudah dibeli'));
    b.addAll(txt('tidak dapat dikembalikan'));
    b.addAll(txt(''));
    b.addAll(txt('Powered by dRetail POS'));
    b.addAll(finalize());
    return Uint8List.fromList(b);
  }

  // ── CONVERT TEXT KE ESCPOS ──────────────────────────────────────────────────

  static Uint8List textToEscPos(String text, PaperSize size) {
    final List<int> b = [];
    b.addAll(init());
    b.addAll(text.codeUnits);
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
