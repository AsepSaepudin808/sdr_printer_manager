import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'escpos_commands.dart';
import 'escpos_config.dart';
import 'escpos_image.dart';
import 'escpos_text.dart';

class EscPosFormatter {
  final EscPosConfig config;

  const EscPosFormatter(this.config);

  int charsPerLine(PaperSize size) => config.customCharsPerLine > 0
      ? config.customCharsPerLine
      : EscPosCommands.defaultCharsPerLine(size);

  List<int> finalize() {
    final List<int> b = [];
    if (config.extraFeed > 0) {
      b.addAll(EscPosCommands.feed(config.extraFeed));
    }
    if (config.autoCut) {
      b.addAll(EscPosCommands.cut());
    }
    return b;
  }

  void _applyFontConfig(List<int> b) {
    b.addAll(EscPosCommands.setFontB(config.useFontB));
  }

  Uint8List buildFromOdooData(
    Map<String, dynamic> data,
    PaperSize size, {
    bool basic = false,
  }) =>
      basic ? _buildBasicReceipt(data, size) : _buildFullReceipt(data, size);

  Uint8List textToEscPos(
    String text,
    PaperSize size, {
    bool isBold = false,
    int alignMode = 0,
  }) {
    final List<int> b = [];
    b.addAll(EscPosCommands.init());
    _applyFontConfig(b);

    final lines = text.split('\n');
    for (int i = 0; i < lines.length; i++) {
      b.addAll(EscPosCommands.align(alignMode));
      if (isBold) {
        b.addAll(EscPosCommands.bold(true));
      }
      final line = lines[i];
      for (int j = 0; j < line.length; j++) {
        int c = line.codeUnitAt(j);
        b.add(c < 256 ? c : 0x3F);
      }
      if (isBold) {
        b.addAll(EscPosCommands.bold(false));
      }
      b.add(0x0A);
    }
    b.addAll(finalize());
    return Uint8List.fromList(b);
  }

  Uint8List buildSessionSummary(
      Map<String, dynamic> data, PaperSize size) {
    final List<int> b = [];
    b.addAll(EscPosCommands.init());
    _applyFontConfig(b);
    final now = DateTime.now();

    final company = data['company'] as Map<String, dynamic>? ?? {};
    final currency = company['currency'] as Map<String, dynamic>? ??
        {'symbol': 'Rp', 'decimal_places': 0};
    final symbol = currency['symbol'] as String? ?? 'Rp';
    final decimals = currency['decimal_places'] as int? ?? 0;
    final positionAfter =
        (currency['position'] as String? ?? 'before') == 'after';
    final w = charsPerLine(size);

    b.addAll(EscPosCommands.align(1));
    b.addAll(EscPosCommands.bold(true));
    b.addAll(EscPosText.txt('SESSION SUMMARY REPORT'));
    b.addAll(EscPosCommands.bold(false));
    b.addAll(EscPosText.txt('=' * w));
    b.addAll(EscPosText.txt('-' * w));

    final posName = data['pos_name'] as String? ?? '-';
    final sessionName = data['session_name'] as String? ?? '-';
    final cashierName = data['cashier_name'] as String? ?? '-';
    final startAt = data['start_at'] as String? ?? '-';
    final stopAt = data['stop_at'] as String? ?? '-';

    b.addAll(EscPosCommands.align(0));
    b.addAll(EscPosText.rowLR('PoS Name :', posName, size));
    b.addAll(EscPosText.rowLR('Session ID :', sessionName, size));
    b.addAll(EscPosText.rowLR('Cashier :', cashierName, size));
    b.addAll(EscPosText.rowLR('Opening :', startAt, size));
    b.addAll(EscPosText.rowLR('Closing :', stopAt, size));

    _buildSessionProductSection(
        b, data, size, symbol, decimals, positionAfter);

    b.addAll(EscPosCommands.align(1));
    b.addAll(EscPosCommands.bold(true));
    b.addAll(EscPosText.txt(EscPosText.sectionHeaderLine('', size, '-')));
    b.addAll(EscPosText.txt(
        EscPosText.sectionHeaderLine('SALES SUMMARY', size, '-')));
    b.addAll(EscPosText.txt(EscPosText.sectionHeaderLine('', size, '-')));
    b.addAll(EscPosCommands.bold(false));
    b.addAll(EscPosCommands.align(0));

    final grossSales = (data['gross_sales'] ?? 0).toDouble();
    final totalDiscount = (data['total_discount'] ?? 0).toDouble();
    final refundUntaxed = (data['refund_amount_untaxed'] ?? 0).toDouble();
    final netSalesBeforeTax = (data['net_sales_before_tax'] ?? 0).toDouble();
    final totalTaxes = (data['total_taxes'] ?? 0).toDouble();
    final totalSales = (data['total_sales'] ?? 0).toDouble();

    b.addAll(EscPosText.rowLR(
        'Gross Sales',
        EscPosText.rp(grossSales.round(),
            symbol: symbol,
            decimals: decimals,
            positionAfter: positionAfter),
        size));
    b.addAll(EscPosText.rowLR(
        'Discounts',
        EscPosText.rp(-totalDiscount.round(),
            symbol: symbol,
            decimals: decimals,
            positionAfter: positionAfter),
        size));
    b.addAll(EscPosText.rowLR(
        'Returns/Refunds',
        EscPosText.rp(-refundUntaxed.round(),
            symbol: symbol,
            decimals: decimals,
            positionAfter: positionAfter),
        size));
    b.addAll(EscPosText.txt('.' * w));
    b.addAll(EscPosText.rowLR(
        'Net Sales',
        EscPosText.rp(netSalesBeforeTax.round(),
            symbol: symbol,
            decimals: decimals,
            positionAfter: positionAfter),
        size));
    b.addAll(EscPosText.rowLR(
        'Tax',
        EscPosText.rp(totalTaxes.round(),
            symbol: symbol,
            decimals: decimals,
            positionAfter: positionAfter),
        size));
    b.addAll(EscPosText.txt('.' * w));
    b.addAll(EscPosCommands.bold(true));
    b.addAll(EscPosText.rowLR(
        'Total Sales',
        EscPosText.rp(totalSales.round(),
            symbol: symbol,
            decimals: decimals,
            positionAfter: positionAfter),
        size));
    b.addAll(EscPosCommands.bold(false));

    b.addAll(EscPosCommands.align(1));
    b.addAll(EscPosCommands.bold(true));
    b.addAll(EscPosText.txt(EscPosText.sectionHeaderLine('', size, '-')));
    b.addAll(EscPosText.txt(
        EscPosText.sectionHeaderLine('RETURNS/REFUNDS', size, '-')));
    b.addAll(EscPosText.txt(EscPosText.sectionHeaderLine('', size, '-')));
    b.addAll(EscPosCommands.bold(false));
    b.addAll(EscPosCommands.align(0));

    final refundAmount = (data['refund_amount'] ?? 0).toDouble();
    b.addAll(EscPosText.rowLR(
        'Total Refund Amount',
        EscPosText.rp(refundAmount.round(),
            symbol: symbol,
            decimals: decimals,
            positionAfter: positionAfter),
        size));

    b.addAll(EscPosCommands.align(1));
    b.addAll(EscPosCommands.bold(true));
    b.addAll(EscPosText.txt(EscPosText.sectionHeaderLine('', size, '-')));
    b.addAll(EscPosText.txt(
        EscPosText.sectionHeaderLine('PAYMENT METHOD', size, '-')));
    b.addAll(EscPosText.txt(EscPosText.sectionHeaderLine('', size, '-')));
    b.addAll(EscPosCommands.bold(false));
    b.addAll(EscPosCommands.align(0));

    final payments = data['payments'] as List<dynamic>? ?? [];
    for (final pay in payments) {
      final p = pay as Map<String, dynamic>;
      final payName = (p['method'] as String? ?? 'Payment').toUpperCase();
      final payAmt = (p['amount'] ?? 0).toDouble();
      b.addAll(EscPosText.rowLR(
          payName,
          EscPosText.rp(payAmt.round(),
              symbol: symbol,
              decimals: decimals,
              positionAfter: positionAfter),
          size));
    }
    final totalPayment = (data['total_payment_amount'] ?? 0).toDouble();
    b.addAll(EscPosText.txt('.' * w));
    b.addAll(EscPosCommands.bold(true));
    b.addAll(EscPosText.rowLR(
        'Total Payment',
        EscPosText.rp(totalPayment.round(),
            symbol: symbol,
            decimals: decimals,
            positionAfter: positionAfter),
        size));
    b.addAll(EscPosCommands.bold(false));

    b.addAll(EscPosCommands.align(1));
    b.addAll(EscPosCommands.bold(true));
    b.addAll(EscPosText.txt(EscPosText.sectionHeaderLine('', size, '-')));
    b.addAll(EscPosText.txt(
        EscPosText.sectionHeaderLine('CASH DRAWER SUMMARY', size, '-')));
    b.addAll(EscPosText.txt(EscPosText.sectionHeaderLine('', size, '-')));
    b.addAll(EscPosCommands.bold(false));
    b.addAll(EscPosCommands.align(0));

    final startingCash = (data['starting_cash'] ?? 0).toDouble();
    final cashSales = (data['cash_sales'] ?? 0).toDouble();
    final cashIn = (data['cash_in'] ?? 0).toDouble();
    final cashOut = (data['cash_out'] ?? 0).toDouble();
    final expectedCash = (data['expected_cash'] ?? 0).toDouble();

    b.addAll(EscPosText.rowLR(
        'Opening Cash',
        EscPosText.rp(startingCash.round(),
            symbol: symbol,
            decimals: decimals,
            positionAfter: positionAfter),
        size));
    b.addAll(EscPosText.rowLR(
        '(+) Cash Sales',
        EscPosText.rp(cashSales.round(),
            symbol: symbol,
            decimals: decimals,
            positionAfter: positionAfter),
        size));
    if (cashIn > 0) {
      b.addAll(EscPosText.rowLR(
          '(+) Cash In',
          EscPosText.rp(cashIn.round(),
              symbol: symbol,
              decimals: decimals,
              positionAfter: positionAfter),
          size));
    }
    if (cashOut > 0) {
      b.addAll(EscPosText.rowLR(
          '(-) Cash Out',
          EscPosText.rp(-cashOut.round(),
              symbol: symbol,
              decimals: decimals,
              positionAfter: positionAfter),
          size));
    }
    b.addAll(EscPosText.txt('.' * w));
    b.addAll(EscPosCommands.bold(true));
    b.addAll(EscPosText.rowLR(
        'Total',
        EscPosText.rp(expectedCash.round(),
            symbol: symbol,
            decimals: decimals,
            positionAfter: positionAfter),
        size));
    b.addAll(EscPosCommands.bold(false));

    b.addAll(EscPosCommands.align(1));
    b.addAll(EscPosCommands.bold(true));
    b.addAll(EscPosText.txt(EscPosText.sectionHeaderLine('', size, '-')));
    b.addAll(EscPosText.txt(
        EscPosText.sectionHeaderLine('SESSION TRANSACTIONS', size, '-')));
    b.addAll(EscPosText.txt(EscPosText.sectionHeaderLine('', size, '-')));
    b.addAll(EscPosCommands.bold(false));
    b.addAll(EscPosCommands.align(0));

    final totalTransactions = data['total_transactions'] ?? 0;
    final salesTransactions = data['sales_transactions'] ?? 0;
    final refundTransactions = data['refund_transactions'] ?? 0;
    final totalQtySold = data['total_qty_sold'] ?? 0;

    b.addAll(EscPosText.rowLR('Total Transactions', '$totalTransactions', size));
    b.addAll(EscPosText.rowLR('Sales Transactions', '$salesTransactions', size));
    b.addAll(EscPosText.rowLR('Returns/Refunds', '$refundTransactions', size));
    b.addAll(EscPosText.rowLR('Items Sold', '$totalQtySold', size));

    final countedCash = (data['counted_cash'] ?? 0).toDouble();
    final differenceCash = (data['difference_cash'] ?? 0).toDouble();
    final totalCreditAmount = (data['total_credit_amount'] ?? 0).toDouble();

    b.addAll(EscPosText.txt('=' * w));
    b.addAll(EscPosCommands.bold(true));
    b.addAll(EscPosText.rowLR(
        'Expected Balance :',
        EscPosText.rp(expectedCash.round(),
            symbol: symbol,
            decimals: decimals,
            positionAfter: positionAfter),
        size));
    b.addAll(EscPosText.rowLR(
        'Closing Balance :',
        EscPosText.rp(countedCash.round(),
            symbol: symbol,
            decimals: decimals,
            positionAfter: positionAfter),
        size));
    b.addAll(EscPosText.rowLR(
        'Difference :',
        EscPosText.rp(differenceCash.round(),
            symbol: symbol,
            decimals: decimals,
            positionAfter: positionAfter),
        size));
    b.addAll(EscPosCommands.bold(false));

    if (totalCreditAmount > 0) {
      b.addAll(EscPosText.txt('.' * w));
      b.addAll(EscPosText.rowLR(
          '* Credit(piutang) :',
          EscPosText.rp(totalCreditAmount.round(),
              symbol: symbol,
              decimals: decimals,
              positionAfter: positionAfter),
          size));
    }

    b.addAll(EscPosText.txt('=' * w));

    b.addAll(EscPosCommands.feed(1));
    b.addAll(EscPosCommands.align(1));
    b.addAll(EscPosCommands.bold(true));
    b.addAll(EscPosText.txt('Powered by dRetail'));
    b.addAll(EscPosCommands.bold(false));
    final printDt = data['print_date'] as String? ??
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year.toString().substring(2)} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    b.addAll(EscPosText.txt(printDt));
    b.addAll(EscPosCommands.align(0));

    b.addAll(finalize());
    return Uint8List.fromList(b);
  }

  Uint8List buildQRISReceipt(
      Map<String, dynamic> data, PaperSize size) {
    final List<int> b = [];
    b.addAll(EscPosCommands.init());
    _applyFontConfig(b);

    final storeName = (data['store_name'] as String? ?? '').trim();
    final formattedAmount = (data['formatted_amount'] as String? ?? '')
        .replaceAll(' ', ' ')
        .replaceAll(RegExp(r'[^ -~]'), '');
    final rawAmount = data['amount'] ?? 0;
    final String amount = formattedAmount.isNotEmpty
        ? formattedAmount
        : EscPosText.rp((rawAmount as num).round());
    final orderId =
        data['order_id'] as String? ?? data['pac_order_id'] as String? ?? '-';
    final qrImageBase64 = data['qr_image_base64'] as String? ?? '';
    final dateStr =
        data['date_str'] as String? ?? _currentDateTime();

    b.addAll(EscPosCommands.align(1));
    if (storeName.isNotEmpty) {
      b.addAll(EscPosCommands.bold(true));
      b.addAll(EscPosText.txt(storeName.toUpperCase()));
      b.addAll(EscPosCommands.bold(false));
    }
    b.addAll(EscPosText.txt('Scan QRIS to pay'));
    b.addAll(EscPosText.divider(size));

    final int qrMaxW = (EscPosCommands.paperMaxWidth(size) * 0.85).round();
    if (qrImageBase64.isNotEmpty) {
      try {
        final rawBase64 = qrImageBase64.contains(',')
            ? qrImageBase64.split(',')[1]
            : qrImageBase64;
        final imgBytes = base64Decode(rawBase64);
        final qrImage = img.decodeImage(imgBytes);
        if (qrImage != null) {
          final qrCropped = EscPosImage.cropWhiteBorder(qrImage);
          final qrResized =
              img.copyResize(qrCropped, width: qrMaxW, height: qrMaxW);
          b.addAll(EscPosImage.esc(qrResized, size));
        } else {
          b.addAll(EscPosText.txt('[ QR CODE ]'));
        }
      } catch (_) {
        b.addAll(EscPosText.txt('[ QR CODE ]'));
      }
    } else {
      b.addAll(EscPosText.txt('[ QR CODE ]'));
    }
    b.addAll(EscPosCommands.align(0));
    b.addAll(EscPosCommands.feed(1));

    b.addAll(EscPosCommands.align(1));
    b.addAll(EscPosText.txt('TOTAL BAYAR'));
    b.addAll(EscPosCommands.bold(true));
    b.addAll(EscPosCommands.doubleSize(true));
    b.addAll(EscPosText.txt(amount));
    b.addAll(EscPosCommands.doubleSize(false));
    b.addAll(EscPosCommands.bold(false));
    b.addAll(EscPosCommands.align(0));
    b.addAll(EscPosText.divider(size));

    b.addAll(EscPosText.rowLR('Order   :', orderId, size));
    b.addAll(EscPosText.rowLR('Tanggal :', dateStr, size));
    b.addAll(EscPosText.divider(size));

    b.addAll(EscPosCommands.align(1));
    b.addAll(EscPosText.txt('Powered by dRetail'));
    b.addAll(EscPosCommands.align(0));

    b.addAll(finalize());
    return Uint8List.fromList(b);
  }

  Uint8List _buildFullReceipt(Map<String, dynamic> d, PaperSize size) {
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

    if (logoBase64.isNotEmpty) {
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

    b.addAll(EscPosCommands.feed(1));

    b.addAll(EscPosCommands.align(1));
    b.addAll(EscPosCommands.bold(true));
    final w = charsPerLine(size);
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
    b.addAll(EscPosText.rowLR('Ref         :', orderNumberClean, size));
    b.addAll(EscPosText.rowLR('Tanggal     :', dateFormatted, size));
    b.addAll(EscPosText.rowLR('Kasir       :', cashier, size));
    b.addAll(EscPosText.divider(size, char: '='));

    final currency = company['currency'] as Map<String, dynamic>? ??
        {'symbol': 'Rp', 'decimal_places': 0};
    final symbol = currency['symbol'] as String? ?? 'Rp';
    final decimals = currency['decimal_places'] as int? ?? 0;

    b.addAll(EscPosCommands.bold(true));
    b.addAll(EscPosText.sectionHeader('DETAIL ITEM', size));
    b.addAll(EscPosCommands.bold(false));

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
      b.addAll(EscPosCommands.bold(true));
      final nameLines = EscPosText.wordWrap(name, w);
      for (final nl in nameLines) {
        b.addAll(EscPosText.txt(nl));
      }
      b.addAll(EscPosCommands.bold(false));

      final uom = (m['uom'] as String? ?? '').trim();
      final uomLabel = uom.isNotEmpty ? uom : 'Pcs';
      final qtyStr =
          '${EscPosText.formatQty(qty)} $uomLabel x ${EscPosText.rp(unitPrice.round(), symbol: symbol, decimals: decimals)}';
      final totalStr =
          EscPosText.rp(subtotal.round(), symbol: symbol, decimals: decimals);
      b.addAll(EscPosText.rowLR(qtyStr, totalStr, size, boldRight: true));

      if (discountType == '%' && discountPct > 0 && discountAmt > 0) {
        final discLabel = '  Disc(${EscPosText.formatQty(discountPct)}%)';
        final discStr = EscPosText.rp(-discountAmt.round(),
            symbol: symbol, decimals: decimals);
        b.addAll(EscPosText.rowLR(discLabel, discStr, size));
      } else if (discountType == 'Rp' && discountAmt > 0) {
        const discLabel = '  Disc(Rp)';
        final discStr = EscPosText.rp(-discountAmt.round(),
            symbol: symbol, decimals: decimals);
        b.addAll(EscPosText.rowLR(discLabel, discStr, size));
      }

      if (customerNote.isNotEmpty) {
        b.addAll(EscPosText.txt('  * $customerNote'));
      }
    }

    if (globalDiscountLineAmt > 0) {
      final globalDiscStr = EscPosText.rp(-globalDiscountLineAmt.round(),
          symbol: symbol, decimals: decimals);
      b.addAll(EscPosCommands.bold(true));
      b.addAll(EscPosText.rowLR('Discount', globalDiscStr, size,
          boldRight: true));
      b.addAll(EscPosCommands.bold(false));
    }

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
            symbol: symbol, decimals: decimals),
        size));
    if (allDiscount > 0) {
      b.addAll(EscPosText.rowLR(
          'Total Diskon',
          EscPosText.rp(-allDiscount.round(),
              symbol: symbol, decimals: decimals),
          size));
    }

    b.addAll(EscPosText.divider(size, char: '.'));
    if (taxVal > 0) {
      b.addAll(EscPosText.rowLR(
          'DPP',
          EscPosText.rp(dppVal.round(),
              symbol: symbol, decimals: decimals),
          size));
      b.addAll(EscPosText.rowLR(
          'PPN 11%',
          EscPosText.rp(taxVal.round(),
              symbol: symbol, decimals: decimals),
          size));
    }

    b.addAll(EscPosText.divider(size, char: '-'));
    b.addAll(EscPosCommands.doubleHeight(true));
    b.addAll(EscPosCommands.bold(true));
    b.addAll(EscPosText.rowLR(
        'TOTAL BAYAR',
        EscPosText.rp(totalVal.round(),
            symbol: symbol, decimals: decimals),
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
              symbol: symbol, decimals: decimals),
          size));
    }
    if (payments.isEmpty && paidVal > 0) {
      b.addAll(EscPosText.rowLR(
          'Cash',
          EscPosText.rp(paidVal.round(),
              symbol: symbol, decimals: decimals),
          size));
    }

    b.addAll(EscPosCommands.bold(true));
    b.addAll(EscPosText.rowLR(
        'CHANGE',
        EscPosText.rp(changeVal.round(),
            symbol: symbol, decimals: decimals),
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
    if (receiptFooter.isNotEmpty) {
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

    b.addAll(EscPosCommands.feed(1));
    b.addAll(EscPosCommands.align(1));
    b.addAll(EscPosCommands.bold(true));
    b.addAll(EscPosText.txt('Powered by dRetail'));
    b.addAll(EscPosCommands.bold(false));
    final now = DateTime.now();
    final printDt =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year.toString().substring(2)} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    b.addAll(EscPosText.txt(printDt));
    b.addAll(EscPosCommands.align(0));

    b.addAll(finalize());
    return Uint8List.fromList(b);
  }

  Uint8List _buildBasicReceipt(Map<String, dynamic> d, PaperSize size) {
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

    if (logoBase64.isNotEmpty) {
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

    b.addAll(EscPosCommands.align(1));
    b.addAll(EscPosCommands.bold(true));
    final w = charsPerLine(size);
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
    b.addAll(EscPosText.rowLR('Ref         :', orderNumberClean, size));
    b.addAll(EscPosText.rowLR('Tanggal     :', dateFormatted, size));
    b.addAll(EscPosText.rowLR('Kasir       :', cashier, size));
    b.addAll(EscPosText.divider(size, char: '='));

    b.addAll(EscPosCommands.bold(true));
    b.addAll(EscPosText.sectionHeader('DETAIL ITEM', size));
    b.addAll(EscPosCommands.bold(false));

    final lines = d['orderlines'] as List<dynamic>? ?? [];
    for (final line in lines) {
      final m = line as Map<String, dynamic>;
      final rawName = m['product_name'] as String? ?? '';
      final name = rawName.replaceAll('\n', ' ').trim();
      final qty = (m['qty'] ?? 1).toDouble();
      final customerNote = m['customer_note'] as String? ?? '';

      final uom = (m['uom'] as String? ?? '').trim();
      final uomLabel = uom.isNotEmpty ? uom : 'Pcs';
      final qtyStr = '${EscPosText.formatQty(qty)} $uomLabel';

      b.addAll(EscPosCommands.bold(true));
      final nameLines =
          EscPosText.wordWrap(name, w - qtyStr.length - 1);
      for (int i = 0; i < nameLines.length; i++) {
        if (i == 0) {
          b.addAll(EscPosText.rowLR(nameLines[i], qtyStr, size));
        } else {
          b.addAll(EscPosText.txt(nameLines[i]));
        }
      }
      b.addAll(EscPosCommands.bold(false));

      if (customerNote.isNotEmpty) {
        b.addAll(EscPosText.txt('  * $customerNote'));
      }
    }
    b.addAll(EscPosText.divider(size, char: '='));

    if (receiptFooter.isNotEmpty) {
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

    b.addAll(EscPosCommands.align(1));
    b.addAll(EscPosCommands.bold(true));
    b.addAll(EscPosText.txt('Powered by dRetail'));
    b.addAll(EscPosCommands.bold(false));
    final now = DateTime.now();
    final printDt =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year.toString().substring(2)} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    b.addAll(EscPosText.txt(printDt));
    b.addAll(EscPosCommands.align(0));

    b.addAll(finalize());
    return Uint8List.fromList(b);
  }

  void _buildSessionProductSection(
    List<int> b,
    Map<String, dynamic> d,
    PaperSize size,
    String symbol,
    int decimals,
    bool positionAfter,
  ) {
    final hasProductGroups = d['has_product_groups'] == true;
    final productGroups = d['product_groups'] as List<dynamic>? ?? [];
    final productLines = d['product_lines'] as List<dynamic>? ?? [];
    final hasProducts = hasProductGroups || productLines.isNotEmpty;
    if (!hasProducts) return;

    final qtyPrecision = d['qty_precision'] as int? ?? 2;

    b.addAll(EscPosCommands.align(1));
    b.addAll(EscPosCommands.bold(true));
    if (hasProductGroups) {
      b.addAll(EscPosText.sectionHeader('PRODUCTS BY CATEGORY', size));
    } else {
      b.addAll(EscPosText.sectionHeader('PRODUCTS SOLD', size));
    }
    b.addAll(EscPosCommands.bold(false));
    b.addAll(EscPosCommands.align(0));

    if (hasProductGroups) {
      for (final group in productGroups) {
        final g = group as Map<String, dynamic>;
        final categoryName = (g['category_name'] as String? ?? '-').trim();
        final items = g['items'] as List<dynamic>? ?? [];
        final categoryTax = (g['category_tax'] ?? 0).toDouble();
        final categorySubtotal = (g['category_subtotal'] ?? 0).toDouble();

        b.addAll(EscPosCommands.bold(true));
        b.addAll(EscPosText.txt(categoryName.isEmpty ? '-' : categoryName));
        b.addAll(EscPosCommands.bold(false));

        for (final item in items) {
          _printSessionProductRow(b, item as Map<String, dynamic>, size,
              symbol, decimals, positionAfter, qtyPrecision);
        }

        b.addAll(EscPosText.divider(size, char: '.'));
        b.addAll(EscPosText.rowLR(
            'Total Tax',
            EscPosText.rp(categoryTax.round(),
                symbol: symbol,
                decimals: decimals,
                positionAfter: positionAfter),
            size));
        b.addAll(EscPosCommands.bold(true));
        b.addAll(EscPosText.rowLR(
            'Subtotal ${categoryName.isEmpty ? '-' : categoryName}',
            EscPosText.rp(categorySubtotal.round(),
                symbol: symbol,
                decimals: decimals,
                positionAfter: positionAfter),
            size));
        b.addAll(EscPosCommands.bold(false));
      }
    } else {
      final productLinesTax = (d['product_lines_tax'] ?? 0).toDouble();
      for (final item in productLines) {
        _printSessionProductRow(b, item as Map<String, dynamic>, size,
            symbol, decimals, positionAfter, qtyPrecision);
      }
      b.addAll(EscPosText.divider(size, char: '.'));
      b.addAll(EscPosText.rowLR(
          'Total Tax',
          EscPosText.rp(productLinesTax.round(),
              symbol: symbol,
              decimals: decimals,
              positionAfter: positionAfter),
          size));
    }

    final grandTotal = (d['grand_total'] ?? 0).toDouble();
    b.addAll(EscPosText.divider(size, char: '='));
    b.addAll(EscPosCommands.bold(true));
    b.addAll(EscPosText.rowLR(
        'GRAND TOTAL',
        EscPosText.rp(grandTotal.round(),
            symbol: symbol,
            decimals: decimals,
            positionAfter: positionAfter),
        size,
        boldRight: true));
    b.addAll(EscPosCommands.bold(false));
    b.addAll(EscPosText.divider(size, char: '='));
  }

  void _printSessionProductRow(
    List<int> b,
    Map<String, dynamic> item,
    PaperSize size,
    String symbol,
    int decimals,
    bool positionAfter,
    int qtyPrecision,
  ) {
    final productName = (item['product_name'] as String? ?? '-').trim();
    final priceUnit = (item['price_unit'] ?? 0).toDouble();
    final qtySold = (item['qty_sold'] ?? 0).toDouble();
    final qtyRefunded = (item['qty_refunded'] ?? 0).toDouble();
    final amountSold = (item['amount_sold'] ?? 0).toDouble();
    final amountRefunded = (item['amount_refunded'] ?? 0).toDouble();
    final qtyNet = qtySold - qtyRefunded;
    final amountNet = amountSold - amountRefunded;

    final w = charsPerLine(size);
    b.addAll(EscPosCommands.bold(true));
    final nameLines =
        EscPosText.wordWrap('• ${productName.isEmpty ? '-' : productName}', w);
    for (final line in nameLines) {
      b.addAll(EscPosText.txt(line));
    }
    b.addAll(EscPosCommands.bold(false));

    final qtyStr = EscPosText.formatQty(qtyNet, qtyPrecision);
    final priceStr = EscPosText.rp(priceUnit.round(),
        symbol: symbol, decimals: decimals, positionAfter: positionAfter);
    final totalStr = EscPosText.rp(amountNet.round(),
        symbol: symbol, decimals: decimals, positionAfter: positionAfter);
    b.addAll(EscPosText.rowLR('$qtyStr x $priceStr', totalStr, size,
        boldRight: true));
  }

  String _currentDateTime() {
    final now = DateTime.now();
    return '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }
}