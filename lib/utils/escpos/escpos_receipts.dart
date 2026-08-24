import 'dart:typed_data';

import 'escpos_commands.dart';
import 'escpos_config.dart';
import 'escpos_helpers.dart';
import 'receipt_order.dart';
import 'receipt_qris.dart';
import 'receipt_session_summary.dart';

// ═══════════════════════════════════════════════════════════════════════════
//
// Delegates to per-domain builder classes. New code should depend on the
// builder directly:
//   - OrderReceiptBuilder           → POS order (full + basic)
//   - SessionSummaryReceiptBuilder  → end-of-session report
//   - QrisReceiptBuilder            → PAC QRIS payment receipt
//
class EscPosFormatter {
  final EscPosConfig config;
  const EscPosFormatter(this.config);

  OrderReceiptBuilder get _orderBuilder => OrderReceiptBuilder(config);
  SessionSummaryReceiptBuilder get _sessionBuilder =>
      SessionSummaryReceiptBuilder(config);
  QrisReceiptBuilder get _qrisBuilder => QrisReceiptBuilder(config);

  // ──── Domain dispatcher ────────────────────────────────────────────
  // Forward ke builder sesuai jenis receipt.

  Uint8List buildFromOdooData(
    Map<String, dynamic> data,
    PaperSize size, {
    bool basic = false,
  }) =>
      basic
          ? _orderBuilder.buildBasic(data, size)
          : _orderBuilder.buildFull(data, size);

  Uint8List buildSessionSummary(Map<String, dynamic> data, PaperSize size) =>
      _sessionBuilder.build(data, size);

  Uint8List buildQRISReceipt(Map<String, dynamic> data, PaperSize size) =>
      _qrisBuilder.build(data, size);

  // ──── Raw text print (Text tab) ────────────────────────────────────
  // Generic ESC/POS text emitter; bukan domain-specific receipt.
  Uint8List textToEscPos(
    String text,
    PaperSize size, {
    bool isBold = false,
    int alignMode = 0,
  }) {
    final List<int> b = [];
    b.addAll(EscPosCommands.init());
    b.addAll(EscPosCommands.setFontB(config.useFontB));

    final lines = text.split('\n');
    for (int i = 0; i < lines.length; i++) {
      b.addAll(EscPosCommands.align(alignMode));
      if (isBold) {
        b.addAll(EscPosCommands.bold(true));
      }
      for (int j = 0; j < lines[i].length; j++) {
        int c = lines[i].codeUnitAt(j);
        b.add(c < 256 ? c : 0x3F);
      }
      if (isBold) {
        b.addAll(EscPosCommands.bold(false));
      }
      b.add(0x0A);
    }

    if (config.extraFeed > 0) {
      b.addAll(EscPosCommands.feed(config.extraFeed));
    }
    if (config.autoCut) {
      b.addAll(EscPosCommands.cut());
    }
    return Uint8List.fromList(b);
  }

  // ──── Legacy helpers (backward-compat) ────────────────────────────
  // Untuk callers lama (test_print_template.dart, text_tab.dart).
  // Kode baru langsung pakai EscPosCommands.defaultCharsPerLine dan
  // EscPosReceiptHelpers.finalize.

  int charsPerLine(PaperSize size) => config.customCharsPerLine > 0
      ? config.customCharsPerLine
      : EscPosCommands.defaultCharsPerLine(size);

  List<int> finalize() => EscPosReceiptHelpers.finalize(config);
}
