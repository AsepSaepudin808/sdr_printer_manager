import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'escpos_commands.dart';
import 'escpos_config.dart';
import 'escpos_helpers.dart';
import 'escpos_image.dart';
import 'escpos_text.dart';

// ═══════════════════════════════════════════════════════════════════════════
// QrisReceiptBuilder
//   PAC QRIS payment receipt.
//     build: merchant name + QR bitmap + total + order ID.
// ═══════════════════════════════════════════════════════════════════════════
//
//   build(data, size) → QRIS receipt with merchant name (priority chain),
//                        Scan QRIS to pay text, QR bitmap, total, order
//                        ID + date (split on own lines to avoid 58mm
//                        truncation).
//
class QrisReceiptBuilder {
  final EscPosConfig config;
  const QrisReceiptBuilder(this.config);

  // ──── Main builder ───────────────────────────────────────────────────────
  Uint8List build(Map<String, dynamic> data, PaperSize size) {
    final List<int> b = [];
    b.addAll(EscPosCommands.init());
    b.addAll(EscPosCommands.setFontB(config.useFontB));

    final merchantName = (data['merchant_name'] as String? ?? '').trim();
    final storeName = (data['store_name'] as String? ?? '').trim();
    final displayName = merchantName.isNotEmpty
        ? merchantName
        : (storeName.isNotEmpty ? storeName : 'PAC QRIS');
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
        data['date_str'] as String? ?? EscPosReceiptHelpers.currentDateTime();

    b.addAll(EscPosCommands.align(1));
    b.addAll(EscPosCommands.bold(true));
    b.addAll(EscPosText.txt(displayName.toUpperCase()));
    b.addAll(EscPosCommands.bold(false));
    b.addAll(EscPosCommands.feed(1));
    b.addAll(EscPosText.txt('Scan QRIS to pay'));
    b.addAll(EscPosText.divider(size));

    _renderQrImage(b, qrImageBase64, size);
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

    final w = EscPosCommands.defaultCharsPerLine(size);
    const idLabel = 'ID :';
    final idLine = idLabel.length + orderId.length;
    final idFits = idLine <= w;
    if (idFits) {
      final idPadding = ' ' * (w - idLabel.length - orderId.length);
      b.addAll(EscPosText.txt('$idLabel$idPadding$orderId'));
    } else {
      final idFirst = orderId.substring(0, 22);
      final idRest = orderId.substring(22);
      b.addAll(EscPosText.txt('$idLabel$idFirst'));
      b.addAll(EscPosText.txt(idRest));
    }
    final datePadding = ' ' * (w - 'Date :'.length - dateStr.length);
    b.addAll(EscPosText.txt('Date :$datePadding$dateStr'));
    b.addAll(EscPosText.divider(size));

    b.addAll(EscPosCommands.align(1));
    b.addAll(EscPosText.txt('Powered by dRetail'));
    b.addAll(EscPosCommands.align(0));

    b.addAll(EscPosReceiptHelpers.finalize(config));
    return Uint8List.fromList(b);
  }

  // ──── QR image renderer ──────────────────────────────────────────────────
  // Decode base64 → resize to ~85% of paper width → emit as ESC/POS bitmap.
  void _renderQrImage(List<int> b, String qrImageBase64, PaperSize size) {
    final int qrMaxW = (EscPosCommands.paperMaxWidth(size) * 0.85).round();
    if (qrImageBase64.isEmpty) {
      b.addAll(EscPosText.txt('[ QR CODE ]'));
      return;
    }
    try {
      final rawBase64 = qrImageBase64.contains(',')
          ? qrImageBase64.split(',')[1]
          : qrImageBase64;
      final imgBytes = base64Decode(rawBase64);
      final qrImage = img.decodeImage(imgBytes);
      if (qrImage == null) {
        b.addAll(EscPosText.txt('[ QR CODE ]'));
        return;
      }
      final qrCropped = EscPosImage.cropWhiteBorder(qrImage);
      final qrResized =
          img.copyResize(qrCropped, width: qrMaxW, height: qrMaxW);
      b.addAll(EscPosImage.esc(qrResized, size));
    } catch (_) {
      b.addAll(EscPosText.txt('[ QR CODE ]'));
    }
  }
}
