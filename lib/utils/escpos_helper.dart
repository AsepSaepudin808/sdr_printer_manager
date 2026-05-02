import 'dart:typed_data';

enum PaperSize {
  mm58, // 32 karakter per baris
  mm80, // 48 karakter per baris
}

class EscPosHelper {
  static const int escCmd = 0x1B;
  static const int gsCmd  = 0x1D;
  static const int lfCmd  = 0x0A;

  static int charsPerLine(PaperSize size) =>
      size == PaperSize.mm58 ? 32 : 48;

  // ── COMMANDS DASAR ───────────────────────────────────────────────

  static Uint8List init() =>
      Uint8List.fromList([escCmd, 0x40]);

  static Uint8List cut() =>
      Uint8List.fromList([gsCmd, 0x56, 0x41, 0x00]);

  static Uint8List bold(bool on) =>
      Uint8List.fromList([escCmd, 0x45, on ? 1 : 0]);

  static Uint8List align(int a) =>
      Uint8List.fromList([escCmd, 0x61, a]);

  static Uint8List feed(int n) =>
      Uint8List.fromList([escCmd, 0x64, n]);

  static Uint8List textSize(int w, int h) =>
      Uint8List.fromList([gsCmd, 0x21, ((w - 1) << 4) | (h - 1)]);

  static Uint8List underline(bool on) =>
      Uint8List.fromList([escCmd, 0x2D, on ? 1 : 0]);

  // ── HELPER TEXT ──────────────────────────────────────────────────

  static List<int> text(String s) => s.codeUnits;
  static List<int> newline() => [lfCmd];

  static List<int> divider(PaperSize size, {String char = '-'}) {
    final w = charsPerLine(size);
    return ('${char * w}\n').codeUnits;
  }

  static List<int> rowLeftRight(
      String left, String right, PaperSize size) {
    final w = charsPerLine(size);
    final space = w - left.length - right.length;
    if (space <= 0) return ('$left $right\n').codeUnits;
    return ('$left${' ' * space}$right\n').codeUnits;
  }

  static String padRight(String s, int width) =>
      s.length >= width ? s.substring(0, width) : s.padRight(width);

  static String padLeft(String s, int width) =>
      s.length >= width ? s.substring(0, width) : s.padLeft(width);

  // ── CONVERT TEXT KE ESCPOS ───────────────────────────────────────

  static Uint8List textToEscPos(String text, PaperSize size) {
    final List<int> bytes = [];
    bytes.addAll(init());
    bytes.addAll(text.codeUnits);
    bytes.addAll(feed(3));
    bytes.addAll(cut());
    return Uint8List.fromList(bytes);
  }

  // ── TEST PRINT PENDEK ────────────────────────────────────────────

  static Uint8List buildTestShort(PaperSize size) {
    final List<int> b = [];
    final w = charsPerLine(size);
    final paperLabel = size == PaperSize.mm58 ? '58mm' : '80mm';
    final now = DateTime.now();
    final dateStr =
        '${now.day.toString().padLeft(2, '0')}/'
        '${now.month.toString().padLeft(2, '0')}/'
        '${now.year}  '
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}';

    b.addAll(init());

    b.addAll(align(1));
    b.addAll(textSize(2, 2));
    b.addAll(bold(true));
    b.addAll(text('dRetail\n'));
    b.addAll(textSize(1, 1));
    b.addAll(bold(false));
    b.addAll(text('PRINTER MANAGER\n'));
    b.addAll(align(0));
    b.addAll(divider(size));

    b.addAll(align(1));
    b.addAll(bold(true));
    b.addAll(text('-- TEST PRINT PENDEK --\n'));
    b.addAll(bold(false));
    b.addAll(align(0));
    b.addAll(rowLeftRight('Kertas', '$paperLabel (${w}kar)', size));
    b.addAll(rowLeftRight('Waktu', dateStr, size));
    b.addAll(divider(size));

    b.addAll(bold(true));
    b.addAll(rowLeftRight('TOTAL', 'Rp 150.000', size));
    b.addAll(bold(false));
    b.addAll(rowLeftRight('Tunai', 'Rp 200.000', size));
    b.addAll(rowLeftRight('Kembali', 'Rp 50.000', size));
    b.addAll(divider(size));

    b.addAll(align(1));
    b.addAll(bold(true));
    b.addAll(text('Printer OK!\n'));
    b.addAll(bold(false));
    b.addAll(text('Terima kasih\n'));

    b.addAll(feed(3));
    b.addAll(cut());
    return Uint8List.fromList(b);
  }

  // ── TEST PRINT PANJANG ───────────────────────────────────────────

  static Uint8List buildTestLong(PaperSize size) {
    final List<int> b = [];
    final w = charsPerLine(size);
    final paperLabel = size == PaperSize.mm58 ? '58mm' : '80mm';
    final now = DateTime.now();
    final dateStr =
        '${now.day.toString().padLeft(2, '0')}/'
        '${now.month.toString().padLeft(2, '0')}/'
        '${now.year}';
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}';

    b.addAll(init());

    // ── HEADER ──
    b.addAll(align(1));
    b.addAll(textSize(2, 2));
    b.addAll(bold(true));
    b.addAll(text('dRetail Mart\n'));
    b.addAll(textSize(1, 1));
    b.addAll(bold(false));
    b.addAll(text('Jl. Contoh No. 123, Bandung\n'));
    b.addAll(text('Telp: (022) 1234-5678\n'));
    b.addAll(align(0));
    b.addAll(divider(size, char: '='));

    // ── INFO TRANSAKSI ──
    b.addAll(rowLeftRight('No.', 'TRX-20250502-001', size));
    b.addAll(rowLeftRight('Tanggal', dateStr, size));
    b.addAll(rowLeftRight('Waktu', timeStr, size));
    b.addAll(rowLeftRight('Kasir', 'Admin', size));
    b.addAll(divider(size));

    // ── HEADER KOLOM ──
    b.addAll(bold(true));
    if (size == PaperSize.mm58) {
      b.addAll(text('Item                 Qty  Total\n'));
    } else {
      b.addAll(
          text('Item                     Qty    Harga        Total\n'));
    }
    b.addAll(bold(false));
    b.addAll(divider(size));

    // ── ITEM-ITEM ──
    final items = [
      {'name': 'Indomie Goreng',      'qty': 3, 'price': 3500,  'total': 10500},
      {'name': 'Aqua 600ml',          'qty': 2, 'price': 5000,  'total': 10000},
      {'name': 'Roti Tawar Sari Roti','qty': 1, 'price': 18500, 'total': 18500},
      {'name': 'Susu Ultra 200ml',    'qty': 4, 'price': 6500,  'total': 26000},
      {'name': 'Sabun Lifebuoy',      'qty': 2, 'price': 12000, 'total': 24000},
      {'name': 'Kopi Kapal Api',      'qty': 5, 'price': 2500,  'total': 12500},
    ];

    for (final item in items) {
      final name  = item['name']  as String;
      final qty   = item['qty']   as int;
      final price = item['price'] as int;
      final total = item['total'] as int;

      if (size == PaperSize.mm58) {
        final shortName = name.length > w ? name.substring(0, w) : name;
        b.addAll(text('$shortName\n'));
        final detail = '  ${qty}x${_formatRp(price)}';
        b.addAll(rowLeftRight(detail, _formatRp(total), size));
      } else {
        final shortName = padRight(name, 24);
        final qtyStr    = padLeft('${qty}x', 5);
        final priceStr  = padLeft(_formatRp(price), 10);
        final totalStr  = padLeft(_formatRp(total), 12);
        b.addAll(text('$shortName$qtyStr$priceStr$totalStr\n'));
      }
    }

    b.addAll(divider(size));

    // ── SUBTOTAL ──
    const subtotal = 101500;
    const diskon   = 5000;
    const pajak    = 0;
    const total    = 96500;
    const bayar    = 100000;
    const kembali  = 3500;

    b.addAll(rowLeftRight('Subtotal',   _formatRp(subtotal), size));
    b.addAll(rowLeftRight('Diskon',     '-${_formatRp(diskon)}', size));
    b.addAll(rowLeftRight('Pajak (0%)', _formatRp(pajak), size));
    b.addAll(divider(size));

    b.addAll(bold(true));
    b.addAll(textSize(1, 2));
    b.addAll(rowLeftRight('TOTAL', 'Rp ${_formatRp(total)}', size));
    b.addAll(textSize(1, 1));
    b.addAll(bold(false));
    b.addAll(divider(size));

    b.addAll(rowLeftRight('Tunai',    'Rp ${_formatRp(bayar)}', size));
    b.addAll(bold(true));
    b.addAll(rowLeftRight('Kembali',  'Rp ${_formatRp(kembali)}', size));
    b.addAll(bold(false));
    b.addAll(divider(size, char: '='));

    // ── INFO TEST ──
    b.addAll(align(1));
    b.addAll(text('[ Test $paperLabel - ${w} karakter/baris ]\n'));
    b.addAll(divider(size));

    // ── FOOTER ──
    b.addAll(align(1));
    b.addAll(text('Terima kasih telah berbelanja\n'));
    b.addAll(bold(true));
    b.addAll(text('di dRetail Mart!\n'));
    b.addAll(bold(false));
    b.addAll(text('\n'));
    b.addAll(text('Barang yang sudah dibeli\n'));
    b.addAll(text('tidak dapat dikembalikan\n'));
    b.addAll(text('\n'));
    b.addAll(text('Powered by dRetail POS\n'));

    b.addAll(feed(4));
    b.addAll(cut());
    return Uint8List.fromList(b);
  }

  // ── FORMAT RUPIAH ────────────────────────────────────────────────

  static String _formatRp(int amount) {
    final s = amount.toString();
    final buffer = StringBuffer();
    int count = 0;
    for (int i = s.length - 1; i >= 0; i--) {
      if (count > 0 && count % 3 == 0) buffer.write('.');
      buffer.write(s[i]);
      count++;
    }
    return buffer.toString().split('').reversed.join();
  }
}