import 'escpos_commands.dart';
import 'escpos_config.dart';
import 'escpos_text.dart';

// ═══════════════════════════════════════════════════════════════════════════
// EscPosReceiptHelpers
//   Cross-cutting static helpers (shared by 3 receipt files).
// ═══════════════════════════════════════════════════════════════════════════

class EscPosReceiptHelpers {
  // ──── Finalizer (trailer) ────────────────────────────────────────────────
  // Extra feed + auto-cut ops; dipanggil terakhir sebelum return bytes.
  static List<int> finalize(EscPosConfig config) {
    final List<int> b = [];
    if (config.extraFeed > 0) {
      b.addAll(EscPosCommands.feed(config.extraFeed));
    }
    if (config.autoCut) {
      b.addAll(EscPosCommands.cut());
    }
    return b;
  }

  // ──── Date / time formatters ─────────────────────────────────────────────
  // Format dd/MM/yyyy HH:mm dan dd/MM/yy HH:mm untuk receipt footer.
  static String currentDateTime() {
    final now = DateTime.now();
    return '${now.day.toString().padLeft(2, '0')}/'
        '${now.month.toString().padLeft(2, '0')}/'
        '${now.year} '
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}';
  }

  static String currentDateTimeShort() {
    final now = DateTime.now();
    return '${now.day.toString().padLeft(2, '0')}/'
        '${now.month.toString().padLeft(2, '0')}/'
        '${now.year.toString().substring(2)} '
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}';
  }

  // ──── Product-list amount ────────────────────────────────────────────────
  // Integer only, tanpa symbol; dipanggil untuk kolom PRICE/TOTAL product list.
  static String formatProductListAmount(
    num amount, {
    required String thousandsSep,
    required String decimalPoint,
  }) {
    return _formatThousandsOnly(amount.round(), thousandsSep);
  }

  static String _formatThousandsOnly(int value, String thousandsSep) {
    final s = value.abs().toString();
    final buf = StringBuffer();
    int count = 0;
    for (int i = s.length - 1; i >= 0; i--) {
      if (count > 0 && count % 3 == 0) buf.write(thousandsSep);
      buf.write(s[i]);
      count++;
    }
    final out = buf.toString().split('').reversed.join();
    return value < 0 ? '-$out' : out;
  }

  // ──── Word wrap ──────────────────────────────────────────────────────────
  // Bungkus defensif wordWrapWordBoundary; fallback list 1 elemen.
  static List<String> nameLinesSafe(String text, int col) {
    if (col <= 0 || text.isEmpty) return [text];
    return EscPosText.wordWrapWordBoundary(text, col);
  }
}
