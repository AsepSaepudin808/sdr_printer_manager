import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'escpos/escpos_commands.dart';
import 'escpos/escpos_config.dart';
import 'escpos/escpos_image.dart';
import 'escpos/escpos_text.dart';

export 'escpos/escpos_config.dart' show PaperSize, CashDrawerMode;

class EscPosHelper {
  // ─── STATELESS COMMANDS ─────────────────────────────────────────────

  static Uint8List init() => EscPosCommands.init();
  static Uint8List cut() => EscPosCommands.cut();
  static Uint8List bold(bool on) => EscPosCommands.bold(on);
  static Uint8List align(int a) => EscPosCommands.align(a);
  static Uint8List feed(int n) => EscPosCommands.feed(n);
  static Uint8List setFontB(bool on) => EscPosCommands.setFontB(on);
  static Uint8List doubleSize(bool on) => EscPosCommands.doubleSize(on);
  static Uint8List doubleHeight(bool on) => EscPosCommands.doubleHeight(on);
  static Uint8List openCashDrawer() => EscPosCommands.openCashDrawer();

  // ─── STATELESS HELPERS ──────────────────────────────────────────────

  static int defaultCharsPerLine(PaperSize size) =>
      EscPosCommands.defaultCharsPerLine(size);

  static int paperMaxWidth(PaperSize size) =>
      EscPosCommands.paperMaxWidth(size);

  static Uint8List imageEsc(img.Image src, PaperSize size) =>
      EscPosImage.esc(src, size);

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
  static String rp(num amount,
          {String symbol = 'Rp',
          int decimals = 0,
          bool positionAfter = false,
          String thousandsSep = '.',
          String decimalPoint = ','}) =>
      EscPosText.rp(amount,
          symbol: symbol,
          decimals: decimals,
          positionAfter: positionAfter,
          thousandsSep: thousandsSep,
          decimalPoint: decimalPoint);
  static String currencyFmt(double amount, Map<String, dynamic> currency) =>
      EscPosText.currencyFmt(amount, currency);
  static String fixLen(String s, int width) => EscPosText.fixLen(s, width);
  static String fixLenR(String s, int width) => EscPosText.fixLenR(s, width);
  static String formatQty(double qty, [int precision = 2]) =>
      EscPosText.formatQty(qty, precision);
  static String formatDateShort(String raw) => EscPosText.formatDateShort(raw);
  static List<String> wordWrap(String text, int w) =>
      EscPosText.wordWrap(text, w);

  // ─── STATEFUL COMMANDS ─────────────────────────────────────────────
  static int charsPerLine(PaperSize size) =>
      throw _stateRemoved('charsPerLine');

  static List<int> finalize() => throw _stateRemoved('finalize');

  static Uint8List buildFromOdooData(
    Map<String, dynamic> data,
    PaperSize size, {
    bool basic = false,
  }) =>
      throw _stateRemoved('buildFromOdooData');

  static Uint8List textToEscPos(
    String text,
    PaperSize size, {
    bool isBold = false,
    int alignMode = 0,
  }) =>
      throw _stateRemoved('textToEscPos');

  static Uint8List buildSessionSummary(
          Map<String, dynamic> data, PaperSize size) =>
      throw _stateRemoved('buildSessionSummary');

  static Uint8List buildQRISReceipt(
          Map<String, dynamic> data, PaperSize size) =>
      throw _stateRemoved('buildQRISReceipt');

  // ─── STATEFUL CONFIG ──────────────────────────────────────────────
  static void setCustomCharsPerLine(int v) =>
      throw _stateRemoved('setCustomCharsPerLine');
  static void setExtraFeed(int v) => throw _stateRemoved('setExtraFeed');
  static void setAutoCut(bool v) => throw _stateRemoved('setAutoCut');
  static void setUseFontB(bool v) => throw _stateRemoved('setUseFontB');
  static void setCashDrawerMode(CashDrawerMode mode) =>
      throw _stateRemoved('setCashDrawerMode');
  static void setSessionSummaryCashDrawer(bool v) =>
      throw _stateRemoved('setSessionSummaryCashDrawer');

  static int get customCharsPerLineSetting =>
      throw _stateRemoved('customCharsPerLineSetting');
  static int get extraFeedSetting => throw _stateRemoved('extraFeedSetting');
  static bool get autoCutSetting => throw _stateRemoved('autoCutSetting');
  static bool get useFontBSetting => throw _stateRemoved('useFontBSetting');
  static CashDrawerMode get cashDrawerModeSetting =>
      throw _stateRemoved('cashDrawerModeSetting');
  static bool get sessionSummaryCashDrawerSetting =>
      throw _stateRemoved('sessionSummaryCashDrawerSetting');

  static StateError _stateRemoved(String name) => StateError(
      'EscPosHelper.$name() dihapus — mutable global state sudah dihapus. '
      'Gunakan EscPosFormatter dari escposFormatterProvider, atau '
      'printConfigProvider/printerConfigProvider untuk update config.');
}
