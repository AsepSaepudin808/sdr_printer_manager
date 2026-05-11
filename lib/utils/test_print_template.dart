import 'dart:typed_data';
import 'escpos_helper.dart';

class TestPrintTemplate {
  static Uint8List buildTestShort(PaperSize size) {
    final List<int> b = [];
    final w = EscPosHelper.charsPerLine(size);
    final now = DateTime.now();
    final dateStr =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    b.addAll(EscPosHelper.init());
    b.addAll(EscPosHelper.logoHeader(size));
    b.addAll(EscPosHelper.align(1));
    b.addAll(EscPosHelper.txt('-- TEST PRINT PENDEK --'));
    b.addAll(EscPosHelper.align(0));
    b.addAll(EscPosHelper.divider(size));

    b.addAll(EscPosHelper.rowLR('Kertas', '${size.paperLabel} ($w kar)', size));
    b.addAll(EscPosHelper.rowLR('Tgl', dateStr, size));
    b.addAll(EscPosHelper.rowLR('Jam', timeStr, size));
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
    final now = DateTime.now();
    final dateStr =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    b.addAll(EscPosHelper.init());
    b.addAll(EscPosHelper.logoHeader(size));

    b.addAll(EscPosHelper.align(1));
    b.addAll(EscPosHelper.txt('Jl. Contoh No. 123, Bdg'));
    b.addAll(EscPosHelper.txt('Telp: (022) 1234-5678'));
    b.addAll(EscPosHelper.align(0));
    b.addAll(EscPosHelper.divider(size, char: '='));

    b.addAll(EscPosHelper.rowLR('No.',
        'TRX-${now.millisecondsSinceEpoch.toString().substring(7)}', size));
    b.addAll(EscPosHelper.rowLR('Tgl', '$dateStr $timeStr', size));
    b.addAll(EscPosHelper.rowLR('Kasir', 'Admin', size));
    b.addAll(EscPosHelper.divider(size));

    const items = [
      _Item('Indomie Goreng', 3.0, 3500.0, 10500.0, 0.0, 0.0),
      _Item('Aqua 600ml', 2.0, 5000.0, 10000.0, 0.0, 0.0),
      _Item('Roti Tawar', 1.0, 18500.0, 18500.0, 0.0, 0.0),
      _Item('Susu Ultra 200ml', 4.0, 6500.0, 26000.0, 2000.0, 0.0),
      _Item('Sabun Lifebuoy', 2.0, 12000.0, 24000.0, 0.0, 10.0),
      _Item('Kopi Kapal Api', 5.0, 2500.0, 12500.0, 0.0, 0.0),
    ];

    for (final item in items) {
      b.addAll(EscPosHelper.bold(true));
      int start = 0;
      while (start < item.name.length) {
        int end = start + w;
        if (end > item.name.length) end = item.name.length;
        String lineName = item.name.substring(start, end);
        if (start > 0) lineName = lineName.trimLeft();
        b.addAll(EscPosHelper.txt(lineName));
        start += w;
      }
      b.addAll(EscPosHelper.bold(false));

      final qtyFormatted = item.qty == item.qty.roundToDouble()
          ? item.qty.round().toString()
          : item.qty.toStringAsFixed(2);
      final qtyStr = '$qtyFormatted x ${EscPosHelper.rp(item.price.round())}';
      final totalStr = 'Rp ${EscPosHelper.rp(item.total.round())}';
      b.addAll(EscPosHelper.rowLR(qtyStr, totalStr, size, boldRight: true));

      if (item.discAmt > 0 || item.discPct > 0) {
        final discLabel = item.discPct > 0
            ? 'Disc($qtyFormatted x ${item.discPct}%)'
            : 'Disc(Rp)';
        final nominalAmt = item.discAmt > 0
            ? item.discAmt
            : (item.price * item.qty * (item.discPct / 100));
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
    b.addAll(EscPosHelper.txt('[ Test ${size.paperLabel} - $w kar ]'));
    b.addAll(EscPosHelper.divider(size));
    b.addAll(EscPosHelper.txt('Terima kasih telah berbelanja'));
    b.addAll(EscPosHelper.align(0));

    b.addAll(EscPosHelper.poweredBy(size));
    b.addAll(EscPosHelper.finalize());
    return Uint8List.fromList(b);
  }
}

class _Item {
  final String name;
  final double qty;
  final double price;
  final double total;
  final double discAmt;
  final double discPct;
  const _Item(
      this.name, this.qty, this.price, this.total, this.discAmt, this.discPct);
}

extension PaperSizeLabel on PaperSize {
  String get paperLabel {
    switch (this) {
      case PaperSize.mm58:
        return '58mm';
      case PaperSize.mm80:
        return '80mm';
      case PaperSize.mm100:
        return '100mm';
    }
  }
}
