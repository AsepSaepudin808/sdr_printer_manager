/// Immutable configuration for ESC/POS output generation.
/// Digunakan oleh [EscPosFormatter] untuk menentukan perilaku cetak
/// (font, cut, extra feed, cash drawer, dst).
class EscPosConfig {
  final int customCharsPerLine;
  final int extraFeed;
  final bool autoCut;
  final bool useFontB;
  final CashDrawerMode cashDrawerMode;
  final bool sessionSummaryCashDrawer;

  const EscPosConfig({
    this.customCharsPerLine = 0,
    this.extraFeed = 3,
    this.autoCut = false,
    this.useFontB = false,
    this.cashDrawerMode = CashDrawerMode.off,
    this.sessionSummaryCashDrawer = false,
  });

  EscPosConfig copyWith({
    int? customCharsPerLine,
    int? extraFeed,
    bool? autoCut,
    bool? useFontB,
    CashDrawerMode? cashDrawerMode,
    bool? sessionSummaryCashDrawer,
  }) =>
      EscPosConfig(
        customCharsPerLine: customCharsPerLine ?? this.customCharsPerLine,
        extraFeed: extraFeed ?? this.extraFeed,
        autoCut: autoCut ?? this.autoCut,
        useFontB: useFontB ?? this.useFontB,
        cashDrawerMode: cashDrawerMode ?? this.cashDrawerMode,
        sessionSummaryCashDrawer:
            sessionSummaryCashDrawer ?? this.sessionSummaryCashDrawer,
      );
}

enum PaperSize { mm58, mm80, mm100 }

enum CashDrawerMode { off, openAfterPrint, openBeforePrint }