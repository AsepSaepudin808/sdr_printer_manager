import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'escpos_helper.dart';

/// Logo asset path for test print templates
const _logoPath = 'assets/images/logo_print.png';

class TestPrintTemplate {
  /// Cached logo image (loaded asynchronously at startup)
  static img.Image? _cachedLogo;
  static bool _logoLoaded = false;

  /// Load logo image from Flutter assets (synchronous after first load)
  static img.Image? _loadLogo() {
    return _cachedLogo;
  }

  /// Preload logo into cache - call this once at app startup
  static Future<void> preloadLogo() async {
    if (_logoLoaded) return;
    try {
      final ByteData data = await rootBundle.load(_logoPath);
      final Uint8List bytes = data.buffer.asUint8List();
      _cachedLogo = img.decodeImage(bytes);
    } catch (e) {
      // Silently fail if logo cannot be loaded
    }
    _logoLoaded = true;
  }

  /// Check if logo is available
  static bool get hasLogo => _cachedLogo != null;

  /// Add logo to the buffer if available
  static void _addLogo(List<int> b, PaperSize size) {
    final logo = _loadLogo();
    if (logo != null) {
      b.addAll(EscPosHelper.align(1));
      b.addAll(EscPosHelper.imageEsc(logo, size));
      b.addAll(EscPosHelper.align(0));
    }
  }

  static Uint8List buildTestShort(PaperSize size) {
    final List<int> b = [];
    final now = DateTime.now();
    final dateStr =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    b.addAll(EscPosHelper.init());

    // Add logo image if available
    _addLogo(b, size);

    b.addAll(EscPosHelper.logoHeader(size));

    // Store info header
    b.addAll(EscPosHelper.align(1));
    b.addAll(EscPosHelper.txt('Jl. Sudirman No. 45, Jakarta'));
    b.addAll(EscPosHelper.txt('Telp: (021) 1234-5678'));
    b.addAll(EscPosHelper.align(0));
    b.addAll(EscPosHelper.divider(size, char: '='));

    // Transaction info
    b.addAll(EscPosHelper.rowLR('No. Struk', 'TRX-${_genTrxId(now)}', size));
    b.addAll(EscPosHelper.rowLR('Tanggal', dateStr, size));
    b.addAll(EscPosHelper.rowLR('Waktu', timeStr, size));
    b.addAll(EscPosHelper.rowLR('Kasir', 'Kasir-01', size));
    b.addAll(EscPosHelper.divider(size));

    // Sample items
    const items = [
      _Item('Indomie Goreng', 2.0, 3500.0, 7000.0),
      _Item('Aqua 600ml', 3.0, 4000.0, 12000.0),
      _Item('Roti Tawar', 1.0, 15000.0, 15000.0),
    ];

    b.addAll(EscPosHelper.align(1));
    b.addAll(EscPosHelper.bold(true));
    b.addAll(EscPosHelper.txt('-- PEMBELIAN --'));
    b.addAll(EscPosHelper.bold(false));
    b.addAll(EscPosHelper.align(0));

    for (final item in items) {
      b.addAll(EscPosHelper.bold(true));
      b.addAll(EscPosHelper.txt(item.name));
      b.addAll(EscPosHelper.bold(false));
      final qtyStr =
          '${item.qty.round()} x ${EscPosHelper.rp(item.price.round())}';
      final totalStr = 'Rp ${EscPosHelper.rp(item.total.round())}';
      b.addAll(EscPosHelper.rowLR(qtyStr, totalStr, size, boldRight: true));
    }

    b.addAll(EscPosHelper.divider(size));

    // Financial summary
    const subtotal = 34000;
    const pajak = 0;
    const total = subtotal + pajak;
    const bayar = 50000;
    const kembali = bayar - total;

    b.addAll(EscPosHelper.rowLR(
        'Subtotal', 'Rp ${EscPosHelper.rp(subtotal)}', size));
    if (pajak > 0) {
      b.addAll(EscPosHelper.rowLR(
          'Pajak (11%)', 'Rp ${EscPosHelper.rp(pajak)}', size));
    }
    b.addAll(EscPosHelper.divider(size));

    b.addAll(EscPosHelper.bold(true));
    b.addAll(EscPosHelper.doubleHeight(true));
    b.addAll(EscPosHelper.rowLR('TOTAL', 'Rp ${EscPosHelper.rp(total)}', size));
    b.addAll(EscPosHelper.doubleHeight(false));
    b.addAll(EscPosHelper.bold(false));

    b.addAll(EscPosHelper.divider(size));

    b.addAll(EscPosHelper.rowLR('Tunai', 'Rp ${EscPosHelper.rp(bayar)}', size));
    b.addAll(EscPosHelper.bold(true));
    b.addAll(EscPosHelper.rowLR(
        'Kembalian', 'Rp ${EscPosHelper.rp(kembali)}', size));
    b.addAll(EscPosHelper.bold(false));

    b.addAll(EscPosHelper.divider(size, char: '-'));

    // Footer
    b.addAll(EscPosHelper.align(1));
    b.addAll(EscPosHelper.txt('Terima kasih atas kunjungan Anda'));
    b.addAll(EscPosHelper.txt('Barang yang sudah dibeli'));
    b.addAll(EscPosHelper.txt('tidak dapat dikembalikan'));
    b.addAll(EscPosHelper.align(0));

    // Powered by dipindah ke atas settings info
    b.addAll(EscPosHelper.poweredBy(size));

    // Settings info strip (Dipindah ke paling bawah setelah Powered by dRetail)
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

  static Uint8List buildTestLong(PaperSize size) {
    final List<int> b = [];
    final w = EscPosHelper.charsPerLine(size);
    final now = DateTime.now();
    final dateStr =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    b.addAll(EscPosHelper.init());

    // Add logo image if available
    _addLogo(b, size);

    b.addAll(EscPosHelper.logoHeader(size));

    // Store info header
    b.addAll(EscPosHelper.align(1));
    b.addAll(EscPosHelper.bold(true));
    b.addAll(EscPosHelper.txt('dRetail Mart'));
    b.addAll(EscPosHelper.bold(false));
    b.addAll(EscPosHelper.txt('Jl. Sudirman No. 45, Jakarta Pusat'));
    b.addAll(EscPosHelper.txt('Telp: (021) 1234-5678'));
    b.addAll(EscPosHelper.txt('Email: info@dretail.id'));
    b.addAll(EscPosHelper.align(0));
    b.addAll(EscPosHelper.divider(size, char: '='));

    // Transaction info
    b.addAll(EscPosHelper.rowLR('No. Struk', 'TRX-${_genTrxId(now)}', size));
    b.addAll(EscPosHelper.rowLR('Tanggal', dateStr, size));
    b.addAll(EscPosHelper.rowLR('Waktu', timeStr, size));
    b.addAll(EscPosHelper.rowLR('Kasir', 'Kasir-01 (Admin)', size));
    b.addAll(EscPosHelper.divider(size, char: '='));

    // Items section
    b.addAll(EscPosHelper.align(1));
    b.addAll(EscPosHelper.bold(true));
    b.addAll(EscPosHelper.txt('-------- DETAIL ITEM --------'));
    b.addAll(EscPosHelper.bold(false));
    b.addAll(EscPosHelper.align(0));

    const items = [
      _ItemWithDisc('Indomie Goreng', 3.0, 3500.0, 10500.0, 500.0, 0.0),
      _ItemWithDisc('Aqua 600ml', 4.0, 4000.0, 16000.0, 0.0, 0.0),
      _ItemWithDisc('Roti Tawar Large', 1.0, 18500.0, 18500.0, 0.0, 5.0),
      _ItemWithDisc('Susu Ultra 200ml', 6.0, 6500.0, 39000.0, 2000.0, 0.0),
      _ItemWithDisc('Sabun Lifebuoy 100g', 2.0, 12000.0, 24000.0, 0.0, 10.0),
      _ItemWithDisc('Kopi Kapal Api 10gr', 5.0, 2500.0, 12500.0, 0.0, 0.0),
      _ItemWithDisc('Mie Sedaap Goreng', 2.0, 3800.0, 7600.0, 380.0, 0.0),
      _ItemWithDisc('Teh Pucuk Harum 350ml', 3.0, 5000.0, 15000.0, 0.0, 0.0),
    ];

    for (final item in items) {
      b.addAll(EscPosHelper.bold(true));
      // Word wrap for long names
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

      final qtyStr =
          '${item.qty.round()} x ${EscPosHelper.rp(item.price.round())}';
      final totalStr = 'Rp ${EscPosHelper.rp(item.total.round())}';
      b.addAll(EscPosHelper.rowLR(qtyStr, totalStr, size, boldRight: true));

      if (item.discAmt > 0) {
        b.addAll(EscPosHelper.rowLR(
            '  Diskon', 'Rp -${EscPosHelper.rp(item.discAmt.round())}', size));
      } else if (item.discPct > 0) {
        final discCalc = (item.price * item.qty * (item.discPct / 100));
        b.addAll(EscPosHelper.rowLR('  Disc(${item.discPct}%)',
            'Rp -${EscPosHelper.rp(discCalc.round())}', size));
      }
    }

    b.addAll(EscPosHelper.divider(size, char: '-'));

    // Financial summary
    const subtotal = 143100;
    const totalDiskonItem = 2880;
    const totalDiskonNota = 0;
    const dpp = subtotal - totalDiskonItem;
    const pajak = 0;
    const total = dpp + pajak;
    const bayarTunai = 150000;
    const bayarQr = 0;
    const kembali = bayarTunai + bayarQr - total;

    b.addAll(EscPosHelper.rowLR(
        'Total Belanja', 'Rp ${EscPosHelper.rp(subtotal)}', size));
    if (totalDiskonItem > 0) {
      b.addAll(EscPosHelper.rowLR(
          'Diskon Item', 'Rp -${EscPosHelper.rp(totalDiskonItem)}', size));
    }
    if (totalDiskonNota > 0) {
      b.addAll(EscPosHelper.rowLR(
          'Diskon Nota', 'Rp -${EscPosHelper.rp(totalDiskonNota)}', size));
    }
    b.addAll(EscPosHelper.divider(size, char: '.'));
    b.addAll(EscPosHelper.rowLR('DPP', 'Rp ${EscPosHelper.rp(dpp)}', size));
    if (pajak > 0) {
      b.addAll(
          EscPosHelper.rowLR('PPN 11%', 'Rp ${EscPosHelper.rp(pajak)}', size));
    }
    b.addAll(EscPosHelper.divider(size, char: '='));

    b.addAll(EscPosHelper.bold(true));
    b.addAll(EscPosHelper.doubleHeight(true));
    b.addAll(EscPosHelper.rowLR(
        'TOTAL BAYAR', 'Rp ${EscPosHelper.rp(total)}', size));
    b.addAll(EscPosHelper.doubleHeight(false));
    b.addAll(EscPosHelper.bold(false));

    b.addAll(EscPosHelper.divider(size));

    // Payment methods
    if (bayarTunai > 0) {
      b.addAll(EscPosHelper.rowLR(
          'Tunai', 'Rp ${EscPosHelper.rp(bayarTunai)}', size));
    }
    if (bayarQr > 0) {
      b.addAll(
          EscPosHelper.rowLR('QRIS', 'Rp ${EscPosHelper.rp(bayarQr)}', size));
    }
    b.addAll(EscPosHelper.bold(true));
    b.addAll(EscPosHelper.rowLR(
        'KEMBALIAN', 'Rp ${EscPosHelper.rp(kembali)}', size));
    b.addAll(EscPosHelper.bold(false));

    b.addAll(EscPosHelper.divider(size, char: '-'));

    // Footer
    b.addAll(EscPosHelper.align(1));
    b.addAll(EscPosHelper.bold(true));
    b.addAll(EscPosHelper.txt('Terima kasih atas kunjungan Anda'));
    b.addAll(EscPosHelper.bold(false));
    b.addAll(EscPosHelper.txt(''));
    b.addAll(EscPosHelper.txt('Barang yang sudah dibeli'));
    b.addAll(EscPosHelper.txt('tidak dapat dikembalikan'));
    b.addAll(EscPosHelper.txt('kecuali ada perjanjian khusus'));
    b.addAll(EscPosHelper.align(0));

    // Powered by dipindah ke atas settings info
    b.addAll(EscPosHelper.poweredBy(size));

    // Settings info strip (Dipindah ke paling bawah setelah Powered by dRetail)
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

  /// Generate realistic transaction ID from current time
  static String _genTrxId(DateTime now) {
    final id = now.millisecondsSinceEpoch.toString();
    return id.substring(id.length - 6);
  }

  /// Format settings info to show current printer settings
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

    // Format nicely within receipt width
    return '$paperLabel | $charsInfo kar | Feed:$extraFeed | Cut:$autoCut | $fontB';
  }
}

class _Item {
  final String name;
  final double qty;
  final double price;
  final double total;
  const _Item(this.name, this.qty, this.price, this.total);
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
