import 'dart:convert';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'escpos_commands.dart';
import 'escpos_config.dart';
import 'escpos_helpers.dart';
import 'escpos_image.dart';
import 'escpos_text.dart';

// ═══════════════════════════════════════════════════════════════════════════
// OrderReceiptBuilder
//   POS order receipt — full + basic variants.
//   buildFull: header + logo + items with prices + totals + payments + change
//     buildBasic: header + logo + items with qty only (no prices)
// ═══════════════════════════════════════════════════════════════════════════
//
//   buildFull(data, size)  → Full receipt: header + items + prices +
//                             discount + totals + payments + change
//   buildBasic(data, size) → Basic receipt: header + items + qty only
//                             (no prices, for receipt printers that cannot
//                             render numeric output)
class OrderReceiptBuilder {
  final EscPosConfig config;
  const OrderReceiptBuilder(this.config);

  // ──── Dispatcher ─────────────────────────────────────────────────────────
  Uint8List buildFull(Map<String, dynamic> d, PaperSize size) =>
      _buildFull(d, size);
  Uint8List buildBasic(Map<String, dynamic> d, PaperSize size) =>
      _buildBasic(d, size);

  void _applyFontConfig(List<int> b) {
    b.addAll(EscPosCommands.setFontB(config.useFontB));
  }

  // ──── Full receipt builder ───────────────────────────────────────────────
  Uint8List _buildFull(Map<String, dynamic> d, PaperSize size) {
    final List<int> b = [];
    b.addAll(EscPosCommands.init());
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

    _renderLogo(b, logoBase64, size);
    b.addAll(EscPosCommands.feed(1));

    b.addAll(EscPosCommands.align(1));
    b.addAll(EscPosCommands.bold(true));
    final w = config.customCharsPerLine > 0
        ? config.customCharsPerLine
        : EscPosCommands.defaultCharsPerLine(size);
    final maxChars = w ~/ 2;
    final truncatedName = storeName.length > maxChars
        ? storeName.substring(0, maxChars)
        : storeName;
    b.addAll(EscPosCommands.doubleSize(true));
    b.addAll(EscPosText.txt(truncatedName));
    b.addAll(EscPosCommands.doubleSize(false));
    b.addAll(EscPosCommands.bold(false));

    if (storePhone.isNotEmpty) {
      b.addAll(EscPosText.txt('Telp : $storePhone'));
    }
    if (storeEmail.isNotEmpty) {
      b.addAll(EscPosText.txt(storeEmail));
    }

    if (receiptHeader.isNotEmpty) {
      b.addAll(EscPosCommands.align(1));
      b.addAll(EscPosText.txt(receiptHeader));
      b.addAll(EscPosCommands.align(0));
    }

    b.addAll(EscPosText.divider(size, char: '='));

    final orderNumberClean = orderName
        .toString()
        .replaceFirst(RegExp(r'^Order\s*', caseSensitive: false), '');
    final dateFormatted =
        dateRaw.isNotEmpty ? EscPosText.formatDateShort(dateRaw) : '';
    final datePart = dateFormatted.contains(' ')
        ? dateFormatted.split(' ')[0]
        : dateFormatted;
    final timePart =
        dateFormatted.contains(' ') ? dateFormatted.split(' ')[1] : '';
    b.addAll(EscPosText.rowLR('Receipt Number:', orderNumberClean, size));
    b.addAll(EscPosText.rowLR('Date          :', datePart, size));
    b.addAll(EscPosText.rowLR('Time          :', timePart, size));
    b.addAll(EscPosText.rowLR('Cashier       :', cashier, size));
    b.addAll(EscPosText.divider(size, char: '='));

    final currency = company['currency'] as Map<String, dynamic>? ??
        {'symbol': 'Rp', 'decimal_places': 0};
    final symbol = currency['symbol'] as String? ?? 'Rp';
    final decimals = currency['decimal_places'] as int? ?? 0;
    final positionAfter =
        (currency['position'] as String? ?? 'before') == 'after';
    final thousandsSep = (d['thousands_sep'] as String?) ??
        (currency['thousands_sep'] as String?) ??
        '.';
    final decimalPoint = (d['decimal_point'] as String?) ??
        (currency['decimal_point'] as String?) ??
        ',';

    b.addAll(EscPosCommands.bold(true));
    b.addAll(EscPosText.sectionHeader('DETAIL ITEM', size));
    b.addAll(EscPosCommands.bold(false));
    b.addAll(EscPosCommands.setFontB(true));
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

      b.addAll(EscPosCommands.align(0));
      final nameLines = EscPosText.wordWrap(name, w);
      for (final nl in nameLines) {
        b.addAll(EscPosText.txt(nl));
      }

      final qtyStr =
          '${EscPosText.formatQty(qty)} x ${EscPosText.rp(unitPrice.round(), symbol: symbol, decimals: decimals, positionAfter: positionAfter, thousandsSep: thousandsSep, decimalPoint: decimalPoint)}';
      final totalStr = EscPosText.rp(subtotal.round(),
          symbol: symbol,
          decimals: decimals,
          positionAfter: positionAfter,
          thousandsSep: thousandsSep,
          decimalPoint: decimalPoint);
      b.addAll(EscPosText.rowLR(qtyStr, totalStr, size, boldRight: true));

      if (discountType == '%' && discountPct > 0 && discountAmt > 0) {
        final discLabel = '  Disc(${EscPosText.formatQty(discountPct)}%)';
        final discStr = EscPosText.rp(-discountAmt.round(),
            symbol: symbol,
            decimals: decimals,
            positionAfter: positionAfter,
            thousandsSep: thousandsSep,
            decimalPoint: decimalPoint);
        b.addAll(EscPosText.rowLR(discLabel, discStr, size));
      } else if (discountType == 'Rp' && discountAmt > 0) {
        const discLabel = '  Disc(Rp)';
        final discStr = EscPosText.rp(-discountAmt.round(),
            symbol: symbol,
            decimals: decimals,
            positionAfter: positionAfter,
            thousandsSep: thousandsSep,
            decimalPoint: decimalPoint);
        b.addAll(EscPosText.rowLR(discLabel, discStr, size));
      }

      if (customerNote.isNotEmpty) {
        b.addAll(EscPosText.txt('  * $customerNote'));
      }
    }

    if (globalDiscountLineAmt > 0) {
      final globalDiscStr = EscPosText.rp(-globalDiscountLineAmt.round(),
          symbol: symbol,
          decimals: decimals,
          positionAfter: positionAfter,
          thousandsSep: thousandsSep,
          decimalPoint: decimalPoint);
      b.addAll(EscPosCommands.bold(true));
      b.addAll(
          EscPosText.rowLR('Discount', globalDiscStr, size, boldRight: true));
      b.addAll(EscPosCommands.bold(false));
    }

    b.addAll(EscPosCommands.setFontB(false));

    final subtotalVal = (d['total_without_tax'] ?? 0).toDouble();
    final taxVal = (d['total_tax'] ?? 0).toDouble();
    final totalVal = (d['total_with_tax'] ?? 0).toDouble();
    final paidVal = (d['total_paid'] ?? totalVal).toDouble();
    final changeVal = (d['change'] ?? (paidVal - totalVal)).toDouble();
    final allDiscount = (d['total_discount'] ?? 0).toDouble();
    final dppVal = subtotalVal - allDiscount;

    b.addAll(EscPosText.divider(size, char: '='));
    b.addAll(EscPosText.rowLR(
        'Total Belanja',
        EscPosText.rp(subtotalVal.round(),
            symbol: symbol,
            decimals: decimals,
            positionAfter: positionAfter,
            thousandsSep: thousandsSep,
            decimalPoint: decimalPoint),
        size));
    if (allDiscount > 0) {
      b.addAll(EscPosText.rowLR(
          'Total Diskon',
          EscPosText.rp(-allDiscount.round(),
              symbol: symbol,
              decimals: decimals,
              positionAfter: positionAfter,
              thousandsSep: thousandsSep,
              decimalPoint: decimalPoint),
          size));
    }

    b.addAll(EscPosText.divider(size, char: '.'));
    if (taxVal > 0) {
      b.addAll(EscPosText.rowLR(
          'DPP',
          EscPosText.rp(dppVal.round(),
              symbol: symbol,
              decimals: decimals,
              positionAfter: positionAfter,
              thousandsSep: thousandsSep,
              decimalPoint: decimalPoint),
          size));
      b.addAll(EscPosText.rowLR(
          'PPN 11%',
          EscPosText.rp(taxVal.round(),
              symbol: symbol,
              decimals: decimals,
              positionAfter: positionAfter,
              thousandsSep: thousandsSep,
              decimalPoint: decimalPoint),
          size));
    }

    b.addAll(EscPosText.divider(size, char: '-'));
    b.addAll(EscPosCommands.doubleHeight(true));
    b.addAll(EscPosCommands.bold(true));
    b.addAll(EscPosText.rowLR(
        'TOTAL BAYAR',
        EscPosText.rp(totalVal.round(),
            symbol: symbol,
            decimals: decimals,
            positionAfter: positionAfter,
            thousandsSep: thousandsSep,
            decimalPoint: decimalPoint),
        size));
    b.addAll(EscPosCommands.bold(false));
    b.addAll(EscPosCommands.doubleHeight(false));

    final payments = d['paymentlines'] as List<dynamic>? ?? [];
    for (final pay in payments) {
      final p = pay as Map<String, dynamic>;
      final payName = p['name'] as String? ?? 'Cash';
      final payAmt = (p['amount'] ?? 0).toDouble();
      b.addAll(EscPosText.rowLR(
          payName,
          EscPosText.rp(payAmt.round(),
              symbol: symbol,
              decimals: decimals,
              positionAfter: positionAfter,
              thousandsSep: thousandsSep,
              decimalPoint: decimalPoint),
          size));
    }
    if (payments.isEmpty && paidVal > 0) {
      b.addAll(EscPosText.rowLR(
          'Cash',
          EscPosText.rp(paidVal.round(),
              symbol: symbol,
              decimals: decimals,
              positionAfter: positionAfter,
              thousandsSep: thousandsSep,
              decimalPoint: decimalPoint),
          size));
    }

    b.addAll(EscPosCommands.bold(true));
    b.addAll(EscPosText.rowLR(
        'CHANGE',
        EscPosText.rp(changeVal.round(),
            symbol: symbol,
            decimals: decimals,
            positionAfter: positionAfter,
            thousandsSep: thousandsSep,
            decimalPoint: decimalPoint),
        size));
    b.addAll(EscPosCommands.bold(false));

    if (d['unique_code'] != null || d['portal_url'] != null) {
      b.addAll(EscPosText.divider(size, char: '-'));
      b.addAll(EscPosCommands.align(1));
      b.addAll(EscPosText.txt('Need an invoice for your purchase?'));
      b.addAll(EscPosText.txt('[QR CODE]'));
      if (d['unique_code'] != null) {
        b.addAll(EscPosText.txt('Unique Code: ${d['unique_code']}'));
      }
      if (d['portal_url'] != null) {
        b.addAll(EscPosText.txt('Portal URL: ${d['portal_url']}'));
      }
      b.addAll(EscPosCommands.align(0));
    }

    b.addAll(EscPosText.divider(size, char: '='));
    _renderFooter(b, receiptFooter);
    b.addAll(EscPosReceiptHelpers.finalize(config));
    return Uint8List.fromList(b);
  }

  // ──── Basic receipt builder ──────────────────────────────────────────────
  Uint8List _buildBasic(Map<String, dynamic> d, PaperSize size) {
    final List<int> b = [];
    b.addAll(EscPosCommands.init());
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

    _renderLogo(b, logoBase64, size);

    b.addAll(EscPosCommands.align(1));
    b.addAll(EscPosCommands.bold(true));
    final w = config.customCharsPerLine > 0
        ? config.customCharsPerLine
        : EscPosCommands.defaultCharsPerLine(size);
    final maxChars = w ~/ 2;
    final truncatedName = storeName.length > maxChars
        ? storeName.substring(0, maxChars)
        : storeName;
    b.addAll(EscPosCommands.doubleSize(true));
    b.addAll(EscPosText.txt(truncatedName));
    b.addAll(EscPosCommands.doubleSize(false));
    b.addAll(EscPosCommands.bold(false));

    if (storePhone.isNotEmpty) {
      b.addAll(EscPosText.txt('Telp : $storePhone'));
    }
    if (storeEmail.isNotEmpty) {
      b.addAll(EscPosText.txt(storeEmail));
    }

    if (receiptHeader.isNotEmpty) {
      b.addAll(EscPosCommands.align(1));
      b.addAll(EscPosText.txt(receiptHeader));
      b.addAll(EscPosCommands.align(0));
    }

    b.addAll(EscPosText.divider(size, char: '='));

    final orderNumberClean = orderName
        .toString()
        .replaceFirst(RegExp(r'^Order\s*', caseSensitive: false), '');
    final dateFormatted =
        dateRaw.isNotEmpty ? EscPosText.formatDateShort(dateRaw) : '';
    final datePart = dateFormatted.contains(' ')
        ? dateFormatted.split(' ')[0]
        : dateFormatted;
    final timePart =
        dateFormatted.contains(' ') ? dateFormatted.split(' ')[1] : '';
    b.addAll(EscPosText.rowLR('Receipt Number:', orderNumberClean, size));
    b.addAll(EscPosText.rowLR('Date          :', datePart, size));
    b.addAll(EscPosText.rowLR('Time          :', timePart, size));
    b.addAll(EscPosText.rowLR('Cashier       :', cashier, size));
    b.addAll(EscPosText.divider(size, char: '='));

    b.addAll(EscPosCommands.bold(true));
    b.addAll(EscPosText.sectionHeader('DETAIL ITEM', size));
    b.addAll(EscPosCommands.bold(false));

    b.addAll(EscPosCommands.setFontB(true));
    final lines = d['orderlines'] as List<dynamic>? ?? [];
    for (final line in lines) {
      final m = line as Map<String, dynamic>;
      final rawName = m['product_name'] as String? ?? '';
      final name = rawName.replaceAll('\n', ' ').trim();
      final qty = (m['qty'] ?? 1).toDouble();
      final customerNote = m['customer_note'] as String? ?? '';

      final qtyStr = EscPosText.formatQty(qty);
      final nameLines = EscPosText.wordWrap(name, w - qtyStr.length - 1);
      for (int i = 0; i < nameLines.length; i++) {
        if (i == 0) {
          b.addAll(EscPosText.rowLR(nameLines[i], qtyStr, size));
        } else {
          b.addAll(EscPosText.txt(nameLines[i]));
        }
      }

      if (customerNote.isNotEmpty) {
        b.addAll(EscPosText.txt('  * $customerNote'));
      }
    }

    b.addAll(EscPosCommands.setFontB(false));
    b.addAll(EscPosText.divider(size, char: '='));

    _renderFooter(b, receiptFooter);
    b.addAll(EscPosReceiptHelpers.finalize(config));
    return Uint8List.fromList(b);
  }

  // ──── Shared private helpers ─────────────────────────────────────────────
  // Logo + receipt_footer

  void _renderLogo(List<int> b, String logoBase64, PaperSize size) {
    if (logoBase64.isEmpty) return;
    try {
      final bytes = base64Decode(
          logoBase64.contains(',') ? logoBase64.split(',')[1] : logoBase64);
      final image = img.decodeImage(bytes);
      if (image != null) {
        b.addAll(EscPosCommands.align(1));
        b.addAll(EscPosImage.esc(image, size));
        b.addAll(EscPosCommands.align(0));
      }
    } catch (_) {}
  }

  void _renderFooter(List<int> b, String receiptFooter) {
    if (receiptFooter.isEmpty) return;
    b.addAll(EscPosCommands.align(1));
    b.addAll(EscPosCommands.bold(true));
    for (final line in receiptFooter.split('\n')) {
      if (line.trim().isNotEmpty) {
        b.addAll(EscPosText.txt(line.trim()));
      }
    }
    b.addAll(EscPosCommands.bold(false));
    b.addAll(EscPosCommands.align(0));
  }
}
