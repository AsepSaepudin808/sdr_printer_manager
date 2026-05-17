import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'escpos_helper.dart';

const _logoPath = 'assets/images/logo_print.png';

class TestPrintTemplate {
  static img.Image? _cachedLogo;
  static bool _logoLoaded = false;

  static img.Image? _loadLogo() => _cachedLogo;

  static Future<void> preloadLogo() async {
    if (_logoLoaded) return;
    try {
      final ByteData data = await rootBundle.load(_logoPath);
      final Uint8List bytes = data.buffer.asUint8List();
      _cachedLogo = img.decodeImage(bytes);
    } catch (e) {
      // LOGO NOT FOUND
    }
    _logoLoaded = true;
  }

  static bool get hasLogo => _cachedLogo != null;

  static void _addLogo(List<int> b, PaperSize size) {
    final logo = _loadLogo();
    if (logo != null) {
      b.addAll(EscPosHelper.align(1));
      b.addAll(EscPosHelper.imageEsc(logo, size));
      b.addAll(EscPosHelper.align(0));
    }
  }

  // ===========================================================================
  // ========================= PRINT SHORT RECEIPT =============================
  // ===========================================================================
  static Uint8List buildTestShort(PaperSize size) {
    final List<int> b = [];
    final now = DateTime.now();
    final dateStr =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    b.addAll(EscPosHelper.init());

    _addLogo(b, size);
    b.addAll(EscPosHelper.feed(1));

    // STORE NAME
    b.addAll(EscPosHelper.align(1));
    b.addAll(EscPosHelper.bold(true));
    final halfW = EscPosHelper.charsPerLine(size) ~/ 2;
    if ('dRetail Mart'.length <= halfW) {
      b.addAll(EscPosHelper.doubleSize(true));
      b.addAll(EscPosHelper.txt('dRetail Mart'));
      b.addAll(EscPosHelper.doubleSize(false));
    } else {
      b.addAll(EscPosHelper.txt('dRetail Mart'));
    }
    b.addAll(EscPosHelper.bold(false));

    // CONTACT INFO
    b.addAll(EscPosHelper.txt('Jl. Sudirman No. 45, Jakarta'));
    b.addAll(EscPosHelper.txt('Telp: (021) 1234-5678'));
    b.addAll(EscPosHelper.txt('info@dretail.id'));
    b.addAll(EscPosHelper.align(0));
    b.addAll(EscPosHelper.divider(size, char: '='));

    // ORDER INFO
    b.addAll(
        EscPosHelper.rowLR('Ref         :', 'TRX-${_genTrxId(now)}', size));
    b.addAll(EscPosHelper.rowLR('Tanggal     :', dateStr, size));
    b.addAll(EscPosHelper.rowLR('Waktu       :', timeStr, size));
    b.addAll(EscPosHelper.rowLR('Kasir       :', 'Kasir-01', size));
    b.addAll(EscPosHelper.divider(size, char: '='));

    b.addAll(EscPosHelper.bold(true));
    b.addAll(EscPosHelper.sectionHeader('DETAIL ITEM', size));
    b.addAll(EscPosHelper.bold(false));

    // ITEMS
    const shortItems = [
      _ItemWithDisc('Indomie Goreng', 2.0, 3500.0, 7000.0, 0.0, 0.0),
      _ItemWithDisc('Aqua 600ml', 3.0, 4000.0, 12000.0, 1000.0, 0.0),
      _ItemWithDisc('Roti Tawar', 1.0, 15000.0, 15000.0, 0.0, 10.0),
    ];

    for (final item in shortItems) {
      b.addAll(EscPosHelper.bold(true));
      b.addAll(EscPosHelper.txt(item.name));
      b.addAll(EscPosHelper.bold(false));
      final qtyStr =
          '${item.qty.round()} Pcs x Rp${EscPosHelper.rp(item.price.round())}';
      final totalStr = 'Rp ${EscPosHelper.rp(item.total.round())}';
      b.addAll(EscPosHelper.rowLR(qtyStr, totalStr, size, boldRight: true));

      if (item.discAmt > 0) {
        b.addAll(EscPosHelper.rowLR('  Disc(Rp)',
            'Rp -${EscPosHelper.rp(item.discAmt.round())}', size));
      } else if (item.discPct > 0) {
        final discCalc = (item.price * item.qty * (item.discPct / 100));
        b.addAll(EscPosHelper.rowLR('  Disc(${item.discPct.toInt()}%)',
            'Rp -${EscPosHelper.rp(discCalc.round())}', size));
      }
    }

    b.addAll(EscPosHelper.divider(size, char: '='));

    // FINANCIAL SUMMARY
    const subtotal = 34000;
    const totalDiskonItem = 2500;
    const dpp = subtotal - totalDiskonItem;
    final pajak = (dpp * 11 / 100).round();
    final total = dpp + pajak;
    const bayar = 50000;
    final kembali = bayar - total;

    b.addAll(EscPosHelper.rowLR(
        'Total Belanja', 'Rp ${EscPosHelper.rp(subtotal)}', size));
    if (totalDiskonItem > 0) {
      b.addAll(EscPosHelper.rowLR(
          'Total Diskon', 'Rp -${EscPosHelper.rp(totalDiskonItem)}', size));
    }
    b.addAll(EscPosHelper.divider(size, char: '.'));
    b.addAll(EscPosHelper.rowLR('DPP', 'Rp ${EscPosHelper.rp(dpp)}', size));
    b.addAll(
        EscPosHelper.rowLR('PPN 11%', 'Rp ${EscPosHelper.rp(pajak)}', size));
    b.addAll(EscPosHelper.divider(size, char: '-'));

    b.addAll(EscPosHelper.doubleHeight(true));
    b.addAll(EscPosHelper.bold(true));
    b.addAll(EscPosHelper.rowLR(
        'TOTAL BAYAR', 'Rp ${EscPosHelper.rp(total)}', size));
    b.addAll(EscPosHelper.bold(false));
    b.addAll(EscPosHelper.doubleHeight(false));

    // PAYMENT
    b.addAll(EscPosHelper.rowLR('Cash', 'Rp ${EscPosHelper.rp(bayar)}', size));
    b.addAll(EscPosHelper.bold(true));
    b.addAll(
        EscPosHelper.rowLR('CHANGE', 'Rp ${EscPosHelper.rp(kembali)}', size));
    b.addAll(EscPosHelper.bold(false));

    // RECEIPT FOOTER
    b.addAll(EscPosHelper.divider(size, char: '='));
    b.addAll(EscPosHelper.align(1));
    b.addAll(EscPosHelper.bold(true));
    b.addAll(EscPosHelper.txt('Terima kasih atas kunjungan Anda'));
    b.addAll(EscPosHelper.bold(false));
    b.addAll(EscPosHelper.txt('Barang yang sudah dibeli'));
    b.addAll(EscPosHelper.txt('tidak dapat dikembalikan'));
    b.addAll(EscPosHelper.align(0));

    // POWERED BY
    b.addAll(EscPosHelper.feed(1));
    b.addAll(EscPosHelper.align(1));
    b.addAll(EscPosHelper.bold(true));
    b.addAll(EscPosHelper.txt('Powered by dRetail'));
    b.addAll(EscPosHelper.bold(false));
    b.addAll(EscPosHelper.align(0));

    // PRINTER SETTINGS INFO
    b.addAll(EscPosHelper.txt(''));
    b.addAll(EscPosHelper.divider(size, char: '='));
    b.addAll(EscPosHelper.align(1));
    b.addAll(EscPosHelper.bold(true));
    b.addAll(EscPosHelper.txt('CURRENT SETTINGS'));
    b.addAll(EscPosHelper.bold(false));
    b.addAll(EscPosHelper.txt(_settingsInfo(size, 'SHORT')));
    b.addAll(EscPosHelper.align(0));

    b.addAll(EscPosHelper.finalize());
    return Uint8List.fromList(b);
  }

  // PRINT LONG RECEIPT
  static Uint8List buildTestLong(PaperSize size) {
    final List<int> b = [];
    final w = EscPosHelper.charsPerLine(size);
    final now = DateTime.now();
    final dateStr =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    b.addAll(EscPosHelper.init());

    _addLogo(b, size);
    b.addAll(EscPosHelper.feed(1));

    // STORE NAME
    b.addAll(EscPosHelper.align(1));
    b.addAll(EscPosHelper.bold(true));
    final halfW = w ~/ 2;
    if ('dRetail Mart'.length <= halfW) {
      b.addAll(EscPosHelper.doubleSize(true));
      b.addAll(EscPosHelper.txt('dRetail Mart'));
      b.addAll(EscPosHelper.doubleSize(false));
    } else {
      b.addAll(EscPosHelper.txt('dRetail Mart'));
    }
    b.addAll(EscPosHelper.bold(false));

    // CONTACT INFO
    b.addAll(EscPosHelper.txt('Jl. Sudirman No. 45, Jakarta'));
    b.addAll(EscPosHelper.txt('Telp: (021) 1234-5678'));
    b.addAll(EscPosHelper.txt('info@dretail.id'));
    b.addAll(EscPosHelper.align(0));
    b.addAll(EscPosHelper.divider(size, char: '='));

    // ORDER INFO
    b.addAll(
        EscPosHelper.rowLR('Ref         :', 'TRX-${_genTrxId(now)}', size));
    b.addAll(EscPosHelper.rowLR('Tanggal     :', dateStr, size));
    b.addAll(EscPosHelper.rowLR('Waktu       :', timeStr, size));
    b.addAll(EscPosHelper.rowLR('Kasir       :', 'Kasir-01 (Admin)', size));
    b.addAll(EscPosHelper.divider(size, char: '='));

    b.addAll(EscPosHelper.bold(true));
    b.addAll(EscPosHelper.sectionHeader('DETAIL ITEM', size));
    b.addAll(EscPosHelper.bold(false));

    // ITEMS
    const longItems = [
      _ItemWithDisc('Indomie Goreng', 3.0, 3500.0, 10500.0, 0.0, 0.0),
      _ItemWithDisc('Aqua 600ml', 4.0, 4000.0, 16000.0, 0.0, 5.0),
      _ItemWithDisc('Roti Tawar Large', 1.0, 18500.0, 18500.0, 500.0, 0.0),
      _ItemWithDisc('Susu Ultra 200ml', 6.0, 6500.0, 39000.0, 0.0, 0.0),
      _ItemWithDisc('Sabun Lifebuoy 100g', 2.0, 12000.0, 24000.0, 0.0, 10.0),
      _ItemWithDisc('Kopi Kapal Api 10gr', 5.0, 2500.0, 12500.0, 0.0, 0.0),
      _ItemWithDisc('Mie Sedaap Goreng', 2.0, 3800.0, 7600.0, 380.0, 0.0),
      _ItemWithDisc('Teh Pucuk Harum 350ml', 3.0, 5000.0, 15000.0, 0.0, 0.0),
    ];

    for (final item in longItems) {
      b.addAll(EscPosHelper.bold(true));
      final nameLines = _wordWrap(item.name, w);
      for (final line in nameLines) {
        b.addAll(EscPosHelper.txt(line));
      }
      b.addAll(EscPosHelper.bold(false));

      final qtyStr =
          '${item.qty.round()} Pcs x Rp${EscPosHelper.rp(item.price.round())}';
      final totalStr = 'Rp ${EscPosHelper.rp(item.total.round())}';
      b.addAll(EscPosHelper.rowLR(qtyStr, totalStr, size, boldRight: true));

      if (item.discAmt > 0) {
        b.addAll(EscPosHelper.rowLR('  Disc(Rp)',
            'Rp -${EscPosHelper.rp(item.discAmt.round())}', size));
      } else if (item.discPct > 0) {
        final discCalc = (item.price * item.qty * (item.discPct / 100));
        b.addAll(EscPosHelper.rowLR('  Disc(${item.discPct.toInt()}%)',
            'Rp -${EscPosHelper.rp(discCalc.round())}', size));
      }
    }

    // GLOBAL DISCOUNT
    const globalDiscPct = 10;
    const globalDiscAmt = 14310;
    b.addAll(EscPosHelper.bold(true));
    b.addAll(EscPosHelper.txt('Discount Bill'));
    b.addAll(EscPosHelper.bold(false));
    b.addAll(EscPosHelper.rowLR('  Disc($globalDiscPct%)',
        'Rp -${EscPosHelper.rp(globalDiscAmt)}', size));

    b.addAll(EscPosHelper.divider(size, char: '='));

    // FINANCIAL SUMMARY
    const subtotal = 143100;
    const totalDiskonItem = 3880;
    const totalDiskonNota = 0;
    const totalDiskon = totalDiskonItem + totalDiskonNota + globalDiscAmt;
    const dpp = subtotal - totalDiskon;
    final pajak = (dpp * 11 / 100).round();
    final total = dpp + pajak;
    const bayarTunai = 200000;
    const bayarQr = 0;
    final kembali = bayarTunai + bayarQr - total;

    b.addAll(EscPosHelper.rowLR(
        'Total Belanja', 'Rp ${EscPosHelper.rp(subtotal)}', size));
    b.addAll(EscPosHelper.rowLR(
        'Total Diskon', 'Rp -${EscPosHelper.rp(totalDiskon)}', size));
    b.addAll(EscPosHelper.divider(size, char: '.'));
    b.addAll(EscPosHelper.rowLR('DPP', 'Rp ${EscPosHelper.rp(dpp)}', size));
    b.addAll(
        EscPosHelper.rowLR('PPN 11%', 'Rp ${EscPosHelper.rp(pajak)}', size));
    b.addAll(EscPosHelper.divider(size, char: '-'));

    b.addAll(EscPosHelper.doubleHeight(true));
    b.addAll(EscPosHelper.bold(true));
    b.addAll(EscPosHelper.rowLR(
        'TOTAL BAYAR', 'Rp ${EscPosHelper.rp(total)}', size));
    b.addAll(EscPosHelper.bold(false));
    b.addAll(EscPosHelper.doubleHeight(false));

    // PAYMENT
    if (bayarTunai > 0) {
      b.addAll(EscPosHelper.rowLR(
          'Cash', 'Rp ${EscPosHelper.rp(bayarTunai)}', size));
    }
    if (bayarQr > 0) {
      b.addAll(
          EscPosHelper.rowLR('QRIS', 'Rp ${EscPosHelper.rp(bayarQr)}', size));
    }
    b.addAll(EscPosHelper.bold(true));
    b.addAll(
        EscPosHelper.rowLR('CHANGE', 'Rp ${EscPosHelper.rp(kembali)}', size));
    b.addAll(EscPosHelper.bold(false));

    // RECEIPT FOOTER
    b.addAll(EscPosHelper.divider(size, char: '='));
    b.addAll(EscPosHelper.align(1));
    b.addAll(EscPosHelper.bold(true));
    b.addAll(EscPosHelper.txt('Terima kasih atas kunjungan Anda'));
    b.addAll(EscPosHelper.bold(false));
    b.addAll(EscPosHelper.txt('Barang yang sudah dibeli'));
    b.addAll(EscPosHelper.txt('tidak dapat dikembalikan'));
    b.addAll(EscPosHelper.align(0));

    // POWERED BY
    b.addAll(EscPosHelper.feed(1));
    b.addAll(EscPosHelper.align(1));
    b.addAll(EscPosHelper.bold(true));
    b.addAll(EscPosHelper.txt('Powered by dRetail'));
    b.addAll(EscPosHelper.bold(false));
    b.addAll(EscPosHelper.align(0));

    // PRINTER SETTINGS INFO
    b.addAll(EscPosHelper.txt(''));
    b.addAll(EscPosHelper.divider(size, char: '='));
    b.addAll(EscPosHelper.align(1));
    b.addAll(EscPosHelper.bold(true));
    b.addAll(EscPosHelper.txt('CURRENT SETTINGS'));
    b.addAll(EscPosHelper.bold(false));
    b.addAll(EscPosHelper.txt(_settingsInfo(size, 'FULL')));
    b.addAll(EscPosHelper.align(0));

    b.addAll(EscPosHelper.finalize());
    return Uint8List.fromList(b);
  }

  static String _genTrxId(DateTime now) {
    final id = now.millisecondsSinceEpoch.toString();
    return id.substring(id.length - 6);
  }

  static List<String> _wordWrap(String text, int w) {
    final words = text.split(' ');
    final lines = <String>[];
    final buf = StringBuffer();
    for (final word in words) {
      if (word.isEmpty) continue;
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
    if (buf.isNotEmpty) lines.add(buf.toString());
    return lines.isEmpty ? [''] : lines;
  }

  static String _settingsInfo(PaperSize size, String type) {
    final paperLabel = switch (size) {
      PaperSize.mm58 => '58mm',
      PaperSize.mm80 => '80mm',
      PaperSize.mm100 => '100mm',
    };

    final customChars = EscPosHelper.customCharsPerLineSetting;
    final extraFeed = EscPosHelper.extraFeedSetting;
    final autoCut = EscPosHelper.autoCutSetting ? 'Ya' : 'Tidak';
    final fontB = EscPosHelper.useFontBSetting ? 'Font-B' : 'Font-A';

    final charsInfo = customChars > 0
        ? '$customChars (custom)'
        : '${size == PaperSize.mm58 ? 32 : size == PaperSize.mm80 ? 48 : 64} (default)';

    return '$paperLabel | $charsInfo kar | Feed:$extraFeed | Cut:$autoCut | $fontB';
  }
}

class _ItemWithDisc {
  final String name;
  final double qty;
  final double price;
  final double total;
  final double discAmt;
  final double discPct;
  const _ItemWithDisc(
      this.name, this.qty, this.price, this.total, this.discAmt, this.discPct);
}
