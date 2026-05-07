import 'dart:typed_data';
import 'escpos_helper.dart';

class TestPrintTemplate {
  static Uint8List buildTestShort(PaperSize size) {
    final List<int> b = [];
    final w = EscPosHelper.charsPerLine(size);
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

    b.addAll(EscPosHelper.init());

    // Manual font config since _useFontB is private in helper,
    // but we can just use the public method if we expose it or let helper handle it.
    // Actually, we can just use EscPosHelper.textToEscPos for simple things,
    // but here we construct it manually.

    b.addAll(EscPosHelper.logoHeader(size));
    b.addAll(EscPosHelper.align(1));
    b.addAll(EscPosHelper.txt('-- TEST PRINT PENDEK --'));
    b.addAll(EscPosHelper.align(0));
    b.addAll(EscPosHelper.divider(size));

    b.addAll(EscPosHelper.rowLR('Kertas', '$paperLabel (${w}kar)', size));
    b.addAll(EscPosHelper.rowLR('Tanggal', dateStr, size));
    b.addAll(EscPosHelper.rowLR('Waktu', timeStr, size));
    b.addAll(EscPosHelper.divider(size));

    b.addAll(EscPosHelper.bold(true));
    b.addAll(
        EscPosHelper.rowLR('TOTAL', 'Rp ${EscPosHelper.rp(150000)}', size));
    b.addAll(EscPosHelper.bold(false));
    b.addAll(
        EscPosHelper.rowLR('Tunai', 'Rp ${EscPosHelper.rp(200000)}', size));
    b.addAll(
        EscPosHelper.rowLR('Kembali', 'Rp ${EscPosHelper.rp(50000)}', size));
    b.addAll(EscPosHelper.divider(size));

    b.addAll(EscPosHelper.align(1));
    b.addAll(EscPosHelper.bold(true));
    b.addAll(EscPosHelper.txt('*** Printer OK! ***'));
    b.addAll(EscPosHelper.bold(false));
    b.addAll(EscPosHelper.align(0));

    b.addAll(EscPosHelper.poweredBy(size));
    b.addAll(EscPosHelper.finalize());
    return Uint8List.fromList(b);
  }

  static Uint8List buildTestLong(PaperSize size) {
    final List<int> b = [];
    final w = EscPosHelper.charsPerLine(size);
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

    b.addAll(EscPosHelper.init());

    b.addAll(EscPosHelper.logoHeader(size));

    b.addAll(EscPosHelper.align(1));
    b.addAll(EscPosHelper.txt('Jl. Contoh No. 123, Bandung'));
    b.addAll(EscPosHelper.txt('Telp: (022) 1234-5678'));
    b.addAll(EscPosHelper.align(0));
    b.addAll(EscPosHelper.divider(size, char: '='));

    b.addAll(EscPosHelper.rowLR('No.', 'TRX-20250502-001', size));
    b.addAll(EscPosHelper.rowLR('Tanggal', '$dateStr $timeStr', size));
    b.addAll(EscPosHelper.rowLR('Kasir', 'Admin', size));
    b.addAll(EscPosHelper.divider(size));

    const items = [
      ('Indomie Goreng', 3.0, 3500.0, 10500.0, 0.0, 0.0),
      ('Aqua 600ml', 2.0, 5000.0, 10000.0, 0.0, 0.0),
      ('Roti Tawar Sari Roti', 1.0, 18500.0, 18500.0, 0.0, 0.0),
      (
        'Susu Ultra 200ml (Promo)',
        4.0,
        6500.0,
        26000.0,
        2000.0,
        0.0
      ), // With discount amount
      ('Sabun Lifebuoy', 2.0, 12000.0, 24000.0, 0.0, 10.0), // With 10% discount
      ('Kopi Kapal Api', 5.0, 2500.0, 12500.0, 0.0, 0.0),
    ];

    for (final (name, qty, price, total, discAmt, discPct) in items) {
      // Print product name with bold, wrapping to next line if necessary
      b.addAll(EscPosHelper.bold(true));
      int start = 0;
      while (start < name.length) {
        int end = start + w;
        if (end > name.length) end = name.length;
        String lineName = name.substring(start, end);
        if (start > 0) lineName = lineName.trimLeft();
        b.addAll(EscPosHelper.txt(lineName));
        start += w;
      }
      b.addAll(EscPosHelper.bold(false));

      // Format qty as double or int
      final qtyFormatted = qty == qty.roundToDouble()
          ? qty.round().toString()
          : qty.toStringAsFixed(2);
      final qtyStr = '$qtyFormatted x Rp ${EscPosHelper.rp(price.round())}';
      final subtotalStr = 'Rp ${EscPosHelper.rp(total.round())}';
      b.addAll(EscPosHelper.rowLR(qtyStr, subtotalStr, size, boldRight: true));

      // Print discount if any
      if (discAmt > 0 || discPct > 0) {
        String discLabel = discPct > 0
            ? 'Disc(${qtyFormatted == "1" ? "" : "1x "}$discPct%)'
            : 'Disc(Rp)';
        double nominalAmt =
            discAmt > 0 ? discAmt : (price * qty * (discPct / 100));
        b.addAll(EscPosHelper.rowLR(
            discLabel, 'Rp ${EscPosHelper.rp(nominalAmt.round())}', size));
      }
    }

    b.addAll(EscPosHelper.divider(size));

    const subtotal = 101500;
    const diskonGlobal = 5000;
    const pajak = 0;
    const total = 96500;
    const bayar = 100000;
    const kembali = 3500;

    const displaySubtotal = subtotal + diskonGlobal;
    b.addAll(EscPosHelper.rowLR(
        'Subtotal', 'Rp ${EscPosHelper.rp(displaySubtotal)}', size));
    b.addAll(EscPosHelper.rowLR(
        'Total Diskon', 'Rp ${EscPosHelper.rp(diskonGlobal)}', size));
    b.addAll(EscPosHelper.rowLR('Pajak (0%)', 'Rp $pajak', size));
    b.addAll(EscPosHelper.divider(size));

    b.addAll(EscPosHelper.bold(true));
    final totalStr = 'Rp ${EscPosHelper.rp(total)}';
    int spaceTot = w - 5 - totalStr.length - 1;
    if (spaceTot < 1) spaceTot = 1;
    b.addAll(EscPosHelper.txt('TOTAL${" " * spaceTot}$totalStr'));
    b.addAll(EscPosHelper.bold(false));

    b.addAll(EscPosHelper.divider(size));

    b.addAll(EscPosHelper.rowLR('Tunai', 'Rp ${EscPosHelper.rp(bayar)}', size));
    b.addAll(EscPosHelper.bold(true));
    b.addAll(
        EscPosHelper.rowLR('Kembali', 'Rp ${EscPosHelper.rp(kembali)}', size));
    b.addAll(EscPosHelper.bold(false));
    b.addAll(EscPosHelper.divider(size, char: '='));

    b.addAll(EscPosHelper.align(1));
    b.addAll(EscPosHelper.txt('[ Test $paperLabel - $w kar ]'));
    b.addAll(EscPosHelper.divider(size));
    b.addAll(EscPosHelper.txt('Terima kasih telah berbelanja'));
    b.addAll(EscPosHelper.align(0));

    b.addAll(EscPosHelper.poweredBy(size));
    b.addAll(EscPosHelper.finalize());
    return Uint8List.fromList(b);
  }
}
