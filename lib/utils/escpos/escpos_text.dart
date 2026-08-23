import 'dart:typed_data';

import 'escpos_commands.dart';
import 'escpos_config.dart';

class EscPosText {
  static const int lfCmd = 0x0A;

  static Uint8List txt(String s) {
    final bytes = <int>[];
    for (int i = 0; i < s.length; i++) {
      int c = s.codeUnitAt(i);
      bytes.add(c < 256 ? c : 0x3F);
    }
    bytes.add(lfCmd);
    return Uint8List.fromList(bytes);
  }

  static Uint8List divider(PaperSize size, {String char = '-', int? width}) {
    final w = width ?? charsPerLineFor(size);
    return txt(char * w);
  }

  static Uint8List rowLR(String left, String right, PaperSize size,
      {bool boldRight = false, int? width}) {
    final w = width ?? charsPerLineFor(size);
    if (right.length >= w) {
      return txt(right.substring(0, w));
    }
    int effectiveRightLen = right.length;
    if (boldRight) effectiveRightLen += 1;
    int spaceLeft = w - effectiveRightLen;
    if (left.length > spaceLeft) {
      left = '${left.substring(0, spaceLeft > 0 ? spaceLeft - 1 : 0)} ';
    }
    final space = w - left.length - effectiveRightLen;
    final padding = space > 0 ? ' ' * space : '';
    if (boldRight) {
      final bytes = <int>[];
      for (int i = 0; i < left.length; i++) {
        int c = left.codeUnitAt(i);
        bytes.add(c < 256 ? c : 0x3F);
      }
      for (int i = 0; i < padding.length; i++) {
        bytes.add(0x20);
      }
      bytes.addAll(EscPosCommands.bold(true));
      for (int i = 0; i < right.length; i++) {
        int c = right.codeUnitAt(i);
        bytes.add(c < 256 ? c : 0x3F);
      }
      bytes.addAll(EscPosCommands.bold(false));
      bytes.add(lfCmd);
      return Uint8List.fromList(bytes);
    }
    return txt('$left$padding$right');
  }

  static Uint8List sectionHeader(String label, PaperSize size) {
    final w = charsPerLineFor(size);
    final inner = ' $label ';
    final dashCount = ((w - inner.length) / 2).floor();
    final dashes = '-' * (dashCount > 0 ? dashCount : 1);
    String line = '$dashes$inner$dashes';
    if (line.length < w) {
      line = line + '-' * (w - line.length);
    } else if (line.length > w) {
      line = line.substring(0, w);
    }
    return txt(line);
  }

  static String sectionHeaderLine(String label, PaperSize size, String char) {
    final w = charsPerLineFor(size);
    final inner = label;
    final dashCount = ((w - inner.length) / 2).floor();
    final dashes = char * (dashCount > 0 ? dashCount : 1);
    String line = '$dashes$inner$dashes';
    if (line.length < w) {
      line = line + char * (w - line.length);
    } else if (line.length > w) {
      line = line.substring(0, w);
    }
    return line;
  }

  static String rp(int amount,
      {String symbol = 'Rp', int decimals = 0, bool positionAfter = false}) {
    String prefix = symbol;
    String suffix = '';
    int value = amount.abs();
    if (decimals > 0) {
      final divisor = _pow10(decimals);
      final whole = (value ~/ divisor);
      final frac = (value % divisor).toString().padLeft(decimals, '0');
      final wholeStr = _formatWithDot(whole);
      // Match Odoo: '.' thousands separator, ',' decimal separator (id_ID locale).
      final result = '$wholeStr,$frac';
      if (positionAfter) {
        suffix = ' $symbol';
        return amount < 0 ? '-$result$suffix' : '$result$suffix';
      }
      return amount < 0 ? '-$prefix$result' : '$prefix$result';
    }
    final formatted = _formatWithDot(value);
    if (positionAfter) {
      suffix = ' $symbol';
      return amount < 0 ? '-$formatted$suffix' : '$formatted$suffix';
    }
    return amount < 0 ? '-$prefix$formatted' : '$prefix$formatted';
  }

  static String currencyFmt(double amount, Map<String, dynamic> currency) {
    final symbol = currency['symbol'] as String? ?? 'Rp';
    final decimals = currency['decimal_places'] as int? ?? 0;
    final positionAfter =
        (currency['position'] as String? ?? 'before') == 'after';
    return rp(amount.round(),
        symbol: symbol, decimals: decimals, positionAfter: positionAfter);
  }

  static String fixLen(String s, int width) =>
      s.length >= width ? s.substring(0, width) : s.padRight(width);

  static String fixLenR(String s, int width) =>
      s.length >= width ? s.substring(0, width) : s.padLeft(width);

  static String formatQty(double qty, [int precision = 2]) {
    if (qty == qty.roundToDouble()) {
      return qty.round().toString();
    }
    return qty.toStringAsFixed(precision);
  }

  static String formatDateShort(String raw) {
    try {
      if (raw.isEmpty) return '';
      final dt = DateTime.parse(raw);
      if (dt.isUtc) {
        return '${dt.toLocal().day.toString().padLeft(2, '0')}/'
            '${dt.toLocal().month.toString().padLeft(2, '0')}/'
            '${dt.toLocal().year} '
            '${dt.toLocal().hour.toString().padLeft(2, '0')}:'
            '${dt.toLocal().minute.toString().padLeft(2, '0')}';
      }
      return '${dt.day.toString().padLeft(2, '0')}/'
          '${dt.month.toString().padLeft(2, '0')}/'
          '${dt.year} '
          '${dt.hour.toString().padLeft(2, '0')}:'
          '${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      final s = raw.trim();
      final isoCandidate = s
          .replaceFirst(
              RegExp(r'^(\d{1,2})[\/\-](\d{1,2})[\/\-](\d{4})'), r'$3-$2-$1')
          .replaceFirst(
              RegExp(r'^(\d{4})[\/\-](\d{1,2})[\/\-](\d{1,2})'), r'$1-$2-$3');
      try {
        final dt2 = DateTime.parse(isoCandidate);
        return '${dt2.day.toString().padLeft(2, '0')}/'
            '${dt2.month.toString().padLeft(2, '0')}/'
            '${dt2.year} '
            '${dt2.hour.toString().padLeft(2, '0')}:'
            '${dt2.minute.toString().padLeft(2, '0')}';
      } catch (_) {
        return raw;
      }
    }
  }

  static String storeNameDoubleSize(String name, int w) {
    final maxChars = w ~/ 2;
    final truncated =
        name.length > maxChars ? name.substring(0, maxChars) : name;
    return '\x1D\x21\x11$truncated\x1D\x21\x00';
  }

  static List<String> wordWrap(String text, int w) {
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

  static List<String> wordWrapWordBoundary(String text, int w) {
    if (w <= 0) return [text];
    final lines = <String>[];
    int pos = 0;
    while (pos < text.length) {
      if (pos + w >= text.length) {
        lines.add(text.substring(pos));
        break;
      }
      int breakAt = pos + w;
      int sp = text.lastIndexOf(' ', breakAt);
      if (sp > pos) {
        lines.add(text.substring(pos, sp));
        pos = sp + 1;
      } else {
        lines.add(text.substring(pos, breakAt));
        pos = breakAt;
      }
    }
    return lines.isEmpty ? [''] : lines;
  }

  static int _pow10(int exp) {
    int result = 1;
    for (int i = 0; i < exp; i++) {
      result *= 10;
    }
    return result;
  }

  static String _formatWithDot(int value) {
    final s = value.toString();
    final buf = StringBuffer();
    int count = 0;
    for (int i = s.length - 1; i >= 0; i--) {
      if (count > 0 && count % 3 == 0) buf.write('.');
      buf.write(s[i]);
      count++;
    }
    return buf.toString().split('').reversed.join();
  }

  static String formatMoney(
    num amount, {
    String symbol = 'Rp',
    int decimals = 0,
    bool positionAfter = false,
    String thousandsSep = '.',
    String decimalPoint = ',',
  }) {
    final absAmount = amount.abs();
    final divisor = decimals > 0 ? _pow10(decimals) : 1;
    final valueScaled = (absAmount * divisor).round();
    final neg = amount < 0;
    String prefix = '';
    String suffix = '';
    if (positionAfter) {
      suffix = ' $symbol';
    } else {
      prefix = symbol;
    }
    if (decimals <= 0) {
      final out = _formatWithCustomThousands(valueScaled, thousandsSep);
      return neg ? '-$prefix$out$suffix' : '$prefix$out$suffix';
    }
    final whole = valueScaled ~/ divisor;
    final frac = (valueScaled % divisor).toString().padLeft(decimals, '0');
    final out =
        '${_formatWithCustomThousands(whole, thousandsSep)}$decimalPoint$frac';
    return neg ? '-$prefix$out$suffix' : '$prefix$out$suffix';
  }

  static String _formatWithCustomThousands(int value, String thousandsSep) {
    final s = value.toString();
    final buf = StringBuffer();
    int count = 0;
    for (int i = s.length - 1; i >= 0; i--) {
      if (count > 0 && count % 3 == 0) buf.write(thousandsSep);
      buf.write(s[i]);
      count++;
    }
    return buf.toString().split('').reversed.join();
  }

  static int charsPerLineFor(PaperSize size) =>
      EscPosCommands.defaultCharsPerLine(size);
}
