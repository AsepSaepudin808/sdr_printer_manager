import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'escpos/escpos_commands.dart';
import 'escpos/escpos_config.dart';
import 'escpos/escpos_image.dart';
import 'escpos/escpos_receipts.dart';
import 'escpos/escpos_text.dart';

/// Re-export enums agar import lama `import '../utils/escpos_helper.dart'
/// show PaperSize, CashDrawerMode` tetap jalan.
export 'escpos/escpos_config.dart' show PaperSize, CashDrawerMode;

/// Backward-compat facade. JANGAN pakai langsung di kode baru —
/// pakai class di sub-folder `escpos/` ([EscPosCommands], [EscPosText],
/// [EscPosImage], [EscPosFormatter]) yang stateless / instance-based.
///
/// File ini tetap ada untuk kompatibilitas 226 call site lama
/// (`EscPosHelper.methodName()`). State mutable yang dipakai di sini
/// dikonversi ke [EscPosConfig] lewat [formatter].
class EscPosHelper {
  static EscPosConfig _config = const EscPosConfig();

  // ─── CONFIG SETTERS (backward compat) ───────────────────────────────

  static void setCustomCharsPerLine(int v) =>
      _config = _config.copyWith(customCharsPerLine: v);
  static void setExtraFeed(int v) =>
      _config = _config.copyWith(extraFeed: v);
  static void setAutoCut(bool v) => _config = _config.copyWith(autoCut: v);
  static void setUseFontB(bool v) =>
      _config = _config.copyWith(useFontB: v);
  static void setCashDrawerMode(CashDrawerMode mode) =>
      _config = _config.copyWith(cashDrawerMode: mode);
  static void setSessionSummaryCashDrawer(bool v) =>
      _config = _config.copyWith(sessionSummaryCashDrawer: v);

  // ─── CONFIG GETTERS (backward compat) ───────────────────────────────

  static int get customCharsPerLineSetting => _config.customCharsPerLine;
  static int get extraFeedSetting => _config.extraFeed;
  static bool get autoCutSetting => _config.autoCut;
  static bool get useFontBSetting => _config.useFontB;
  static CashDrawerMode get cashDrawerModeSetting =>
      _config.cashDrawerMode;
  static bool get sessionSummaryCashDrawerSetting =>
      _config.sessionSummaryCashDrawer;

  // ─── STATELESS COMMANDS (delegate) ──────────────────────────────────

  static Uint8List openCashDrawer() => EscPosCommands.openCashDrawer();

  static int defaultCharsPerLine(PaperSize size) =>
      EscPosCommands.defaultCharsPerLine(size);

  static int paperMaxWidth(PaperSize size) =>
      EscPosCommands.paperMaxWidth(size);

  static int charsPerLine(PaperSize size) =>
      formatter.charsPerLine(size);

  static List<int> finalize() => formatter.finalize();

  static Uint8List init() => EscPosCommands.init();
  static Uint8List cut() => EscPosCommands.cut();
  static Uint8List bold(bool on) => EscPosCommands.bold(on);
  static Uint8List align(int a) => EscPosCommands.align(a);
  static Uint8List feed(int n) => EscPosCommands.feed(n);
  static Uint8List setFontB(bool on) => EscPosCommands.setFontB(on);
  static Uint8List doubleSize(bool on) => EscPosCommands.doubleSize(on);
  static Uint8List doubleHeight(bool on) =>
      EscPosCommands.doubleHeight(on);

  static Uint8List imageEsc(img.Image src, PaperSize size) =>
      EscPosImage.esc(src, size);

  // ─── TEXT HELPERS (delegate) ────────────────────────────────────────

  static Uint8List txt(String s) => EscPosText.txt(s);
  static Uint8List divider(PaperSize size, {String char = '-'}) =>
      EscPosText.divider(size, char: char);
  static Uint8List rowLR(String left, String right, PaperSize size,
          {bool boldRight = false}) =>
      EscPosText.rowLR(left, right, size, boldRight: boldRight);
  static Uint8List sectionHeader(String label, PaperSize size) =>
      EscPosText.sectionHeader(label, size);
  static String sectionHeaderLine(String label, PaperSize size, String char) =>
      EscPosText.sectionHeaderLine(label, size, char);
  static String rp(int amount,
          {String symbol = 'Rp',
          int decimals = 0,
          bool positionAfter = false}) =>
      EscPosText.rp(amount,
          symbol: symbol, decimals: decimals, positionAfter: positionAfter);
  static String currencyFmt(double amount, Map<String, dynamic> currency) =>
      EscPosText.currencyFmt(amount, currency);
  static String fixLen(String s, int width) => EscPosText.fixLen(s, width);
  static String fixLenR(String s, int width) => EscPosText.fixLenR(s, width);
  static String formatQty(double qty, [int precision = 2]) =>
      EscPosText.formatQty(qty, precision);
  static String formatDateShort(String raw) =>
      EscPosText.formatDateShort(raw);
  static List<String> wordWrap(String text, int w) =>
      EscPosText.wordWrap(text, w);

  // ─── RECEIPT BUILDERS (delegate ke formatter instance) ─────────────

  static Uint8List buildFromOdooData(
    Map<String, dynamic> data,
    PaperSize size, {
    bool basic = false,
  }) =>
      formatter.buildFromOdooData(data, size, basic: basic);

  static Uint8List textToEscPos(
    String text,
    PaperSize size, {
    bool isBold = false,
    int alignMode = 0,
  }) =>
      formatter.textToEscPos(text, size,
          isBold: isBold, alignMode: alignMode);

  static Uint8List buildSessionSummary(
          Map<String, dynamic> data, PaperSize size) =>
      formatter.buildSessionSummary(data, size);

  static Uint8List buildQRISReceipt(
          Map<String, dynamic> data, PaperSize size) =>
      formatter.buildQRISReceipt(data, size);

  // ─── INSTANCE AKSES (untuk kode baru) ────────────────────────────────

  static EscPosFormatter get formatter => EscPosFormatter(_config);
  static EscPosConfig get config => _config;
}