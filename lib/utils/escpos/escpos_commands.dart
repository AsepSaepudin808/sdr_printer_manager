import 'dart:typed_data';

import 'escpos_config.dart';

class EscPosCommands {
  static const int escCmd = 0x1B;
  static const int gsCmd = 0x1D;
  static const int lfCmd = 0x0A;

  static Uint8List init() => Uint8List.fromList([escCmd, 0x40]);
  static Uint8List cut() => Uint8List.fromList([gsCmd, 0x56, 0x41, 0x00]);
  static Uint8List bold(bool on) =>
      Uint8List.fromList([escCmd, 0x45, on ? 1 : 0]);
  static Uint8List align(int a) => Uint8List.fromList([escCmd, 0x61, a]);
  static Uint8List feed(int n) => Uint8List.fromList([escCmd, 0x64, n]);
  static Uint8List setFontB(bool on) =>
      Uint8List.fromList([escCmd, 0x21, on ? 1 : 0]);
  static Uint8List setSize(int n) =>
      Uint8List.fromList([escCmd, 0x21, n & 0xFF]);
  static Uint8List selectFontA() => Uint8List.fromList([escCmd, 0x4D, 0x00]);
  static Uint8List selectFontB() => Uint8List.fromList([escCmd, 0x4D, 0x01]);
  static Uint8List doubleSize(bool on) =>
      Uint8List.fromList([0x1D, 0x21, on ? 0x11 : 0x00]);
  static Uint8List doubleHeight(bool on) =>
      Uint8List.fromList([0x1D, 0x21, on ? 0x01 : 0x00]);

  static Uint8List setCharSize(int n) =>
      Uint8List.fromList([0x1D, 0x21, n & 0xFF]);

  static Uint8List setSmallFont() => Uint8List.fromList([escCmd, 0x21, 0x01]);
  static Uint8List setNormalFont() => Uint8List.fromList([escCmd, 0x21, 0x00]);

  static Uint8List openCashDrawer() =>
      Uint8List.fromList([escCmd, 0x70, 0x00, 0x19, 0xFA]);

  static Uint8List setUnderline(bool on) =>
      Uint8List.fromList([escCmd, 0x2D, on ? 1 : 0]);
  static Uint8List setCondensed(bool on) =>
      Uint8List.fromList([escCmd, on ? 0x0F : 0x14]);

  static int defaultCharsPerLine(PaperSize size) => switch (size) {
        PaperSize.mm58 => 32,
        PaperSize.mm80 => 48,
        PaperSize.mm100 => 64,
      };

  static int paperMaxWidth(PaperSize size) => switch (size) {
        PaperSize.mm58 => 384,
        PaperSize.mm80 => 576,
        PaperSize.mm100 => 768,
      };
}
