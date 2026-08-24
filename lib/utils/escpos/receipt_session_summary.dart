import 'dart:typed_data';

import 'escpos_commands.dart';
import 'escpos_config.dart';
import 'escpos_helpers.dart';
import 'escpos_text.dart';

// ═══════════════════════════════════════════════════════════════════════════
// SessionSummaryReceiptBuilder
//   End-of-session report.
//     build: full session summary with header, product breakdown
//            (Font B + condensed, bullet prefix), sales summary,
//            payment method, cash drawer, balance checks.
// ═══════════════════════════════════════════════════════════════════════════
//
//   build(data, size) → Session summary report with header, product
//                        breakdown by category (Font B + condensed mode,
//                        bullet `* ` prefix, integer prices), sales summary,
//                        payment method, cash drawer, balance checks.
//
class SessionSummaryReceiptBuilder {
  final EscPosConfig config;
  const SessionSummaryReceiptBuilder(this.config);

  // ──── Main builder ───────────────────────────────────────────────────────
  Uint8List build(Map<String, dynamic> data, PaperSize size) {
    final List<int> b = [];
    b.addAll(EscPosCommands.init());
    b.addAll(EscPosCommands.setFontB(config.useFontB));
    final now = DateTime.now();

    final company = data['company'] as Map<String, dynamic>? ?? {};
    final currency = company['currency'] as Map<String, dynamic>? ??
        {'symbol': 'Rp', 'decimal_places': 0};
    final symbol = currency['symbol'] as String? ?? 'Rp';
    final decimals = currency['decimal_places'] as int? ?? 0;
    final positionAfter =
        (currency['position'] as String? ?? 'before') == 'after';
    final thousandsSep = (data['thousands_sep'] as String?) ??
        (currency['thousands_sep'] as String?) ??
        '.';
    final decimalPoint = (data['decimal_point'] as String?) ??
        (currency['decimal_point'] as String?) ??
        ',';
    final w = config.customCharsPerLine > 0
        ? config.customCharsPerLine
        : EscPosCommands.defaultCharsPerLine(size);

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

    b.addAll(EscPosText.divider(size, char: '-'));

    _buildProductSection(b, data, size, symbol, decimals, positionAfter,
        thousandsSep, decimalPoint);

    _emitSection(b, 'SALES SUMMARY', size);
    _emitSalesSummary(b, data, symbol, decimals, positionAfter, thousandsSep,
        decimalPoint, size);

    if ((data['refund_amount'] ?? 0).toDouble() > 0) {
      _emitSection(b, 'RETURNS/REFUNDS', size);
      b.addAll(EscPosText.rowLR(
          'Total Refund Amount',
          EscPosText.formatMoney((data['refund_amount'] ?? 0).toDouble(),
              symbol: symbol,
              decimals: decimals,
              positionAfter: positionAfter,
              thousandsSep: thousandsSep,
              decimalPoint: decimalPoint),
          size));
    }

    _emitSection(b, 'PAYMENT METHOD', size);
    final payments = data['payments'] as List<dynamic>? ?? [];
    for (final pay in payments) {
      final p = pay as Map<String, dynamic>;
      final payName = (p['method'] as String? ?? 'Payment').toUpperCase();
      final payAmt = (p['amount'] ?? 0).toDouble();
      b.addAll(EscPosText.rowLR(
          payName,
          EscPosText.formatMoney(payAmt,
              symbol: symbol,
              decimals: decimals,
              positionAfter: positionAfter,
              thousandsSep: thousandsSep,
              decimalPoint: decimalPoint),
          size));
    }
    b.addAll(EscPosText.txt('.' * w));
    b.addAll(EscPosCommands.bold(true));
    b.addAll(EscPosText.rowLR(
        'Total Payment',
        EscPosText.formatMoney((data['total_payment_amount'] ?? 0).toDouble(),
            symbol: symbol,
            decimals: decimals,
            positionAfter: positionAfter,
            thousandsSep: thousandsSep,
            decimalPoint: decimalPoint),
        size));
    b.addAll(EscPosCommands.bold(false));

    _emitSection(b, 'CASH DRAWER SUMMARY', size);
    final startingCash = (data['starting_cash'] ?? 0).toDouble();
    final cashSales = (data['cash_sales'] ?? 0).toDouble();
    final cashIn = (data['cash_in'] ?? 0).toDouble();
    final cashOut = (data['cash_out'] ?? 0).toDouble();
    final expectedCash = (data['expected_cash'] ?? 0).toDouble();

    b.addAll(EscPosText.rowLR(
        'Opening Cash',
        EscPosText.formatMoney(startingCash,
            symbol: symbol,
            decimals: decimals,
            positionAfter: positionAfter,
            thousandsSep: thousandsSep,
            decimalPoint: decimalPoint),
        size));
    b.addAll(EscPosText.rowLR(
        '(+) Cash Sales',
        EscPosText.formatMoney(cashSales,
            symbol: symbol,
            decimals: decimals,
            positionAfter: positionAfter,
            thousandsSep: thousandsSep,
            decimalPoint: decimalPoint),
        size));
    if (cashIn > 0) {
      b.addAll(EscPosText.rowLR(
          '(+) Cash In',
          EscPosText.formatMoney(cashIn,
              symbol: symbol,
              decimals: decimals,
              positionAfter: positionAfter,
              thousandsSep: thousandsSep,
              decimalPoint: decimalPoint),
          size));
    }
    if (cashOut > 0) {
      b.addAll(EscPosText.rowLR(
          '(-) Cash Out',
          EscPosText.formatMoney(-cashOut,
              symbol: symbol,
              decimals: decimals,
              positionAfter: positionAfter,
              thousandsSep: thousandsSep,
              decimalPoint: decimalPoint),
          size));
    }
    b.addAll(EscPosText.txt('.' * w));
    b.addAll(EscPosCommands.bold(true));
    b.addAll(EscPosText.rowLR(
        'Total',
        EscPosText.formatMoney(expectedCash,
            symbol: symbol,
            decimals: decimals,
            positionAfter: positionAfter,
            thousandsSep: thousandsSep,
            decimalPoint: decimalPoint),
        size));
    b.addAll(EscPosCommands.bold(false));

    _emitSection(b, 'SESSION TRANSACTIONS', size);
    b.addAll(EscPosText.rowLR(
        'Total Transactions', '${data['total_transactions'] ?? 0}', size));
    b.addAll(EscPosText.rowLR(
        'Sales Transactions', '${data['sales_transactions'] ?? 0}', size));
    b.addAll(EscPosText.rowLR(
        'Returns/Refunds', '${data['refund_transactions'] ?? 0}', size));
    b.addAll(EscPosText.rowLR(
        'Items Sold', '${data['total_qty_sold'] ?? 0}', size));

    final countedCash = (data['counted_cash'] ?? 0).toDouble();
    final differenceCash = (data['difference_cash'] ?? 0).toDouble();
    final totalCreditAmount = (data['total_credit_amount'] ?? 0).toDouble();

    b.addAll(EscPosText.txt('=' * w));
    b.addAll(EscPosCommands.bold(true));
    b.addAll(EscPosText.rowLR(
        'Expected Balance :',
        EscPosText.formatMoney(expectedCash,
            symbol: symbol,
            decimals: decimals,
            positionAfter: positionAfter,
            thousandsSep: thousandsSep,
            decimalPoint: decimalPoint),
        size));
    b.addAll(EscPosText.rowLR(
        'Closing Balance :',
        EscPosText.formatMoney(countedCash,
            symbol: symbol,
            decimals: decimals,
            positionAfter: positionAfter,
            thousandsSep: thousandsSep,
            decimalPoint: decimalPoint),
        size));
    b.addAll(EscPosText.rowLR(
        'Difference :',
        EscPosText.formatMoney(differenceCash,
            symbol: symbol,
            decimals: decimals,
            positionAfter: positionAfter,
            thousandsSep: thousandsSep,
            decimalPoint: decimalPoint),
        size));
    b.addAll(EscPosCommands.bold(false));

    if (totalCreditAmount > 0) {
      b.addAll(EscPosText.txt('.' * w));
      b.addAll(EscPosText.rowLR(
          '* Credit(piutang) :',
          EscPosText.formatMoney(totalCreditAmount,
              symbol: symbol,
              decimals: decimals,
              positionAfter: positionAfter,
              thousandsSep: thousandsSep,
              decimalPoint: decimalPoint),
          size));
    }

    b.addAll(EscPosText.txt('=' * w));

    b.addAll(EscPosCommands.feed(1));
    b.addAll(EscPosCommands.align(1));
    b.addAll(EscPosCommands.bold(true));
    b.addAll(EscPosText.txt('Powered by dRetail'));
    b.addAll(EscPosCommands.bold(false));
    final printDt = data['print_date'] as String? ??
        '${now.day.toString().padLeft(2, '0')}/'
            '${now.month.toString().padLeft(2, '0')}/'
            '${now.year.toString().substring(2)} '
            '${now.hour.toString().padLeft(2, '0')}:'
            '${now.minute.toString().padLeft(2, '0')}';
    b.addAll(EscPosText.txt(printDt));
    b.addAll(EscPosCommands.align(0));

    b.addAll(EscPosReceiptHelpers.finalize(config));
    return Uint8List.fromList(b);
  }

  // ──── Section header helper ──────────────────────────────────────────────
  // Emits centered `--- LABEL ---` block used by every section.
  void _emitSection(List<int> b, String label, PaperSize size) {
    b.addAll(EscPosCommands.align(1));
    b.addAll(EscPosCommands.bold(true));
    b.addAll(EscPosText.txt(EscPosText.sectionHeaderLine('', size, '-')));
    b.addAll(EscPosText.txt(EscPosText.sectionHeaderLine(label, size, '-')));
    b.addAll(EscPosText.txt(EscPosText.sectionHeaderLine('', size, '-')));
    b.addAll(EscPosCommands.bold(false));
    b.addAll(EscPosCommands.align(0));
  }

  // ──── Sales summary rows ─────────────────────────────────────────────────
  void _emitSalesSummary(
    List<int> b,
    Map<String, dynamic> data,
    String symbol,
    int decimals,
    bool positionAfter,
    String thousandsSep,
    String decimalPoint,
    PaperSize size,
  ) {
    final grossSales = (data['gross_sales'] ?? 0).toDouble();
    final totalDiscount = (data['total_discount'] ?? 0).toDouble();
    final refundUntaxed = (data['refund_amount_untaxed'] ?? 0).toDouble();
    final netSalesBeforeTax = (data['net_sales_before_tax'] ?? 0).toDouble();
    final totalTaxes = (data['total_taxes'] ?? 0).toDouble();
    final totalSales = (data['total_sales'] ?? 0).toDouble();
    final w = config.customCharsPerLine > 0
        ? config.customCharsPerLine
        : EscPosCommands.defaultCharsPerLine(size);

    b.addAll(EscPosText.rowLR(
        'Gross Sales',
        EscPosText.formatMoney(grossSales,
            symbol: symbol,
            decimals: decimals,
            positionAfter: positionAfter,
            thousandsSep: thousandsSep,
            decimalPoint: decimalPoint),
        size));
    b.addAll(EscPosText.rowLR(
        'Discounts',
        EscPosText.formatMoney(-totalDiscount,
            symbol: symbol,
            decimals: decimals,
            positionAfter: positionAfter,
            thousandsSep: thousandsSep,
            decimalPoint: decimalPoint),
        size));
    b.addAll(EscPosText.rowLR(
        'Returns/Refunds',
        EscPosText.formatMoney(-refundUntaxed,
            symbol: symbol,
            decimals: decimals,
            positionAfter: positionAfter,
            thousandsSep: thousandsSep,
            decimalPoint: decimalPoint),
        size));
    b.addAll(EscPosText.txt('.' * w));
    b.addAll(EscPosText.rowLR(
        'Net Sales',
        EscPosText.formatMoney(netSalesBeforeTax,
            symbol: symbol,
            decimals: decimals,
            positionAfter: positionAfter,
            thousandsSep: thousandsSep,
            decimalPoint: decimalPoint),
        size));
    b.addAll(EscPosText.rowLR(
        'Tax',
        EscPosText.formatMoney(totalTaxes,
            symbol: symbol,
            decimals: decimals,
            positionAfter: positionAfter,
            thousandsSep: thousandsSep,
            decimalPoint: decimalPoint),
        size));
    b.addAll(EscPosText.txt('.' * w));
    b.addAll(EscPosCommands.bold(true));
    b.addAll(EscPosText.rowLR(
        'Total Sales',
        EscPosText.formatMoney(totalSales,
            symbol: symbol,
            decimals: decimals,
            positionAfter: positionAfter,
            thousandsSep: thousandsSep,
            decimalPoint: decimalPoint),
        size));
    b.addAll(EscPosCommands.bold(false));
  }

  // ──── Product breakdown ──────────────────────────────────────────────────
  void _buildProductSection(
    List<int> b,
    Map<String, dynamic> d,
    PaperSize size,
    String symbol,
    int currencyDecimals,
    bool positionAfter,
    String thousandsSep,
    String decimalPoint,
  ) {
    final hasProductGroups = d['has_product_groups'] == true;
    final productGroups = d['product_groups'] as List<dynamic>? ?? [];
    final productLines = d['product_lines'] as List<dynamic>? ?? [];
    final hasProducts = hasProductGroups || productLines.isNotEmpty;
    if (!hasProducts) return;

    final qtyPrecision = d['qty_precision'] as int? ?? 2;
    final w = EscPosText.charsPerLineFor(size);
    final sectionWidth = size == PaperSize.mm58 ? 42 : 64;

    b.addAll(EscPosCommands.align(1));
    b.addAll(EscPosCommands.bold(true));
    if (hasProductGroups) {
      b.addAll(EscPosText.sectionHeader('PRODUCTS BY CATEGORY', size));
    } else {
      b.addAll(EscPosText.sectionHeader('PRODUCTS SOLD', size));
    }
    b.addAll(EscPosCommands.bold(false));
    b.addAll(EscPosCommands.align(0));
    b.addAll(EscPosCommands.selectFontB());
    b.addAll(EscPosCommands.setSize(0x01));

    if (hasProductGroups) {
      for (final group in productGroups) {
        final g = group as Map<String, dynamic>;
        final categoryName = (g['category_name'] as String? ?? '-').trim();
        final items = g['items'] as List<dynamic>? ?? [];
        final categoryTax = (g['category_tax'] ?? 0).toDouble();
        final categorySubtotal = (g['category_subtotal'] ?? 0).toDouble();

        b.addAll(EscPosText.divider(size, char: '-', width: sectionWidth));
        b.addAll(EscPosCommands.bold(true));
        b.addAll(EscPosText.txt(categoryName.isEmpty ? '-' : categoryName));
        b.addAll(EscPosCommands.bold(false));

        b.addAll(EscPosText.divider(size, char: '-', width: sectionWidth));
        b.addAll(EscPosText.txt(_productHeaderLine(size, w)));
        b.addAll(EscPosText.divider(size, char: '-', width: sectionWidth));

        for (final item in items) {
          _printProductRow(b, item as Map<String, dynamic>, size, w,
              qtyPrecision, thousandsSep, decimalPoint);
        }

        b.addAll(EscPosText.divider(size, char: '.', width: sectionWidth));
        b.addAll(EscPosText.rowLR(
            'Total Tax',
            EscPosText.formatMoney(categoryTax,
                symbol: symbol,
                decimals: currencyDecimals,
                positionAfter: positionAfter,
                thousandsSep: thousandsSep,
                decimalPoint: decimalPoint),
            size,
            width: sectionWidth));
        b.addAll(EscPosCommands.bold(true));
        b.addAll(EscPosText.rowLR(
            'Subtotal ${categoryName.isEmpty ? '-' : categoryName}',
            EscPosText.formatMoney(categorySubtotal,
                symbol: symbol,
                decimals: currencyDecimals,
                positionAfter: positionAfter,
                thousandsSep: thousandsSep,
                decimalPoint: decimalPoint),
            size,
            width: sectionWidth));
        b.addAll(EscPosCommands.bold(false));
      }
    } else {
      final productLinesTax = (d['product_lines_tax'] ?? 0).toDouble();

      b.addAll(EscPosText.divider(size, char: '-', width: sectionWidth));
      b.addAll(EscPosText.txt(_productHeaderLine(size, w)));
      b.addAll(EscPosText.divider(size, char: '-', width: sectionWidth));

      for (final item in productLines) {
        _printProductRow(b, item as Map<String, dynamic>, size, w, qtyPrecision,
            thousandsSep, decimalPoint);
      }

      b.addAll(EscPosText.divider(size, char: '.', width: sectionWidth));
      b.addAll(EscPosText.rowLR(
          'Total Tax',
          EscPosText.formatMoney(productLinesTax,
              symbol: symbol,
              decimals: currencyDecimals,
              positionAfter: positionAfter,
              thousandsSep: thousandsSep,
              decimalPoint: decimalPoint),
          size,
          width: sectionWidth));
    }

    b.addAll(EscPosCommands.setSize(0x00));
    b.addAll(EscPosCommands.selectFontA());

    final grandTotal = (d['grand_total'] ?? 0).toDouble();
    b.addAll(EscPosText.divider(size, char: '='));
    b.addAll(EscPosCommands.bold(true));
    b.addAll(EscPosText.rowLR(
        'GRAND TOTAL',
        EscPosText.formatMoney(grandTotal,
            symbol: symbol,
            decimals: currencyDecimals,
            positionAfter: positionAfter,
            thousandsSep: thousandsSep,
            decimalPoint: decimalPoint),
        size,
        boldRight: true));
    b.addAll(EscPosCommands.bold(false));
  }

  // ──── Product list header ────────────────────────────────────────────────
  // Column widths follow Odoo QWeb 38/25/13/25 ratio.
  String _productHeaderLine(PaperSize size, int w) {
    final int colProd, colPrice, colQty, colTotal;
    if (size == PaperSize.mm58) {
      colProd = 16;
      colPrice = 10;
      colQty = 6;
      colTotal = 10;
    } else {
      colProd = 24;
      colPrice = 16;
      colQty = 8;
      colTotal = 16;
    }

    String padC(String s, int len) {
      if (s.length >= len) return s.substring(0, len);
      final totalPad = len - s.length;
      final left = totalPad ~/ 2;
      final right = totalPad - left;
      return ' ' * left + s + ' ' * right;
    }

    String padL(String s, int len) => s.length >= len
        ? s.substring(s.length - len)
        : ' ' * (len - s.length) + s;

    final prodHeader = 'PRODUCT'.length > colProd
        ? 'PRODUCT'.substring(0, colProd)
        : 'PRODUCT'.padRight(colProd);
    return '$prodHeader'
        '${padC('PRICE', colPrice)}'
        '${padC('QTY', colQty)}'
        '${padL('TOTAL', colTotal)}';
  }

  // ──── Product row printer ────────────────────────────────────────────────
  // Continuation lines for long names — no financial data on those lines.
  void _printProductRow(
    List<int> b,
    Map<String, dynamic> item,
    PaperSize size,
    int w,
    int qtyPrecision,
    String thousandsSep,
    String decimalPoint,
  ) {
    final productName = (item['product_name'] as String? ?? '-').trim();
    final priceUnit = (item['price_unit'] ?? 0).toDouble();
    final qtySold = (item['qty_sold'] ?? 0).toDouble();
    final qtyRefunded = (item['qty_refunded'] ?? 0).toDouble();
    final amountSold = (item['amount_sold'] ?? 0).toDouble();
    final amountRefunded = (item['amount_refunded'] ?? 0).toDouble();
    final qtyNet = qtySold - qtyRefunded;
    final amountNet = amountSold - amountRefunded;

    final int colProd, colPrice, colQty, colTotal;
    if (size == PaperSize.mm58) {
      colProd = 16;
      colPrice = 10;
      colQty = 6;
      colTotal = 10;
    } else {
      colProd = 24;
      colPrice = 16;
      colQty = 8;
      colTotal = 16;
    }

    final priceStr = EscPosReceiptHelpers.formatProductListAmount(priceUnit.round(),
        thousandsSep: thousandsSep, decimalPoint: decimalPoint);
    final totalStr = EscPosReceiptHelpers.formatProductListAmount(amountNet.round(),
        thousandsSep: thousandsSep, decimalPoint: decimalPoint);
    final qtyStr = qtyNet.toStringAsFixed(qtyPrecision);

    String padC(String s, int len) {
      if (s.length >= len) return s.substring(0, len);
      final totalPad = len - s.length;
      final left = totalPad ~/ 2;
      final right = totalPad - left;
      return ' ' * left + s + ' ' * right;
    }

    String padL(String s, int len) => s.length >= len
        ? s.substring(s.length - len)
        : ' ' * (len - s.length) + s;

    final nameLines = EscPosReceiptHelpers.nameLinesSafe(productName, colProd - 2);
    final firstLineRaw = nameLines.first;
    final firstLine = firstLineRaw.length > (colProd - 2)
        ? firstLineRaw.substring(0, colProd - 2)
        : firstLineRaw.padRight(colProd - 2);
    final financialBlock = padC(priceStr, colPrice) +
        padC(qtyStr, colQty) +
        padL(totalStr, colTotal);

    b.addAll(EscPosText.txt('* $firstLine$financialBlock'));

    for (int i = 1; i < nameLines.length; i++) {
      final cont = nameLines[i].length > colProd
          ? nameLines[i].substring(0, colProd)
          : nameLines[i].padRight(colProd);
      b.addAll(EscPosText.txt('  $cont'));
    }
  }
}