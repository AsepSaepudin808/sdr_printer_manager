import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/printer_device.dart';
import '../utils/escpos_helper.dart';

export 'logs_provider.dart' show logsProvider, LogsNotifier;

// ─── SERVER STATE ─────────────────────────────────────────────────────────
class ServerState {
  final bool running;
  final int port;
  final bool connecting;
  const ServerState(
      {this.running = false, this.port = 8080, this.connecting = false});

  ServerState copyWith({bool? running, int? port, bool? connecting}) =>
      ServerState(
        running: running ?? this.running,
        port: port ?? this.port,
        connecting: connecting ?? this.connecting,
      );
}

class ServerStateNotifier extends Notifier<ServerState> {
  @override
  ServerState build() => const ServerState();

  void setRunning(bool v) => state = state.copyWith(running: v);
  void setPort(int v) => state = state.copyWith(port: v);
  void setConnecting(bool v) => state = state.copyWith(connecting: v);
}

final serverStateProvider =
    NotifierProvider<ServerStateNotifier, ServerState>(ServerStateNotifier.new);

// ─── PRINT STATE ──────────────────────────────────────────────────────────
class PrintState {
  final bool isPrinting;
  final String status;
  const PrintState({this.isPrinting = false, this.status = ''});

  PrintState copyWith({bool? isPrinting, String? status}) => PrintState(
        isPrinting: isPrinting ?? this.isPrinting,
        status: status ?? this.status,
      );
}

class PrintStateNotifier extends Notifier<PrintState> {
  @override
  PrintState build() => const PrintState();

  void setIsPrinting(bool v) => state = state.copyWith(isPrinting: v);
  void setStatus(String v) => state = state.copyWith(status: v);
}

final printStateProvider =
    NotifierProvider<PrintStateNotifier, PrintState>(PrintStateNotifier.new);

// ─── PRINT COUNT ──────────────────────────────────────────────────────────
final printCountProvider =
    NotifierProvider<PrintCountNotifier, int>(PrintCountNotifier.new);

class PrintCountNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void set(int count) => state = count;
  void increment() => state = state + 1;
  void reset() => state = 0;
}

// ─── PRINTER CONFIG ───────────────────────────────────────────────────────
class PrinterConfig {
  final PrinterDevice? printer;
  final bool btConnected;
  final PaperSize paperSize;
  final CashDrawerMode cashDrawerMode;
  final bool sessionSummaryCashDrawer;
  final bool printQris;
  final bool autoStart;

  const PrinterConfig({
    this.printer,
    this.btConnected = false,
    this.paperSize = PaperSize.mm80,
    this.cashDrawerMode = CashDrawerMode.off,
    this.sessionSummaryCashDrawer = false,
    this.printQris = true,
    this.autoStart = false,
  });

  PrinterConfig copyWith({
    PrinterDevice? printer,
    bool? btConnected,
    PaperSize? paperSize,
    CashDrawerMode? cashDrawerMode,
    bool? sessionSummaryCashDrawer,
    bool? printQris,
    bool? autoStart,
  }) =>
      PrinterConfig(
        printer: printer ?? this.printer,
        btConnected: btConnected ?? this.btConnected,
        paperSize: paperSize ?? this.paperSize,
        cashDrawerMode: cashDrawerMode ?? this.cashDrawerMode,
        sessionSummaryCashDrawer:
            sessionSummaryCashDrawer ?? this.sessionSummaryCashDrawer,
        printQris: printQris ?? this.printQris,
        autoStart: autoStart ?? this.autoStart,
      );
}

class PrinterConfigNotifier extends Notifier<PrinterConfig> {
  @override
  PrinterConfig build() => const PrinterConfig();

  void setPrinter(PrinterDevice? v) => state = state.copyWith(printer: v);
  void setBtConnected(bool v) => state = state.copyWith(btConnected: v);
  void setPaperSize(PaperSize v) => state = state.copyWith(paperSize: v);
  void setCashDrawerMode(CashDrawerMode v) =>
      state = state.copyWith(cashDrawerMode: v);
  void setSessionSummaryCashDrawer(bool v) =>
      state = state.copyWith(sessionSummaryCashDrawer: v);
  void setPrintQris(bool v) => state = state.copyWith(printQris: v);
  void setAutoStart(bool v) => state = state.copyWith(autoStart: v);
}

final printerConfigProvider =
    NotifierProvider<PrinterConfigNotifier, PrinterConfig>(
        PrinterConfigNotifier.new);

// ─── UI STATE ─────────────────────────────────────────────────────────────
class UiState {
  final int tabIndex;
  final DateTimeRange? historyDateRange;
  const UiState({this.tabIndex = 0, this.historyDateRange});

  UiState copyWith({int? tabIndex, DateTimeRange? historyDateRange}) => UiState(
        tabIndex: tabIndex ?? this.tabIndex,
        historyDateRange: historyDateRange ?? this.historyDateRange,
      );
}

class UiStateNotifier extends Notifier<UiState> {
  @override
  UiState build() => const UiState();

  void setTabIndex(int v) => state = state.copyWith(tabIndex: v);
  void setHistoryDateRange(DateTimeRange? v) =>
      state = state.copyWith(historyDateRange: v);
}

final uiStateProvider =
    NotifierProvider<UiStateNotifier, UiState>(UiStateNotifier.new);
