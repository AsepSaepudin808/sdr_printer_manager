import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/printer_device.dart';
import '../utils/escpos_helper.dart';

// Re-export logsProvider for backward compatibility
export 'logs_provider.dart' show logsProvider, LogsNotifier;

class AppState {
  final int tabIndex;
  final bool serverRunning;
  final int serverPort;
  final PrinterDevice? printer;
  final int printCount;
  final bool autoStart;
  final bool connecting;
  final bool btConnected;
  final PaperSize paperSize;
  final CashDrawerMode cashDrawerMode;
  final bool sessionSummaryCashDrawer;
  final bool isPrinting;
  final String printStatus;
  final DateTimeRange? historyDateRange;
  final bool isKeyboardVisible;

  const AppState({
    this.tabIndex = 0,
    this.serverRunning = false,
    this.serverPort = 8080,
    this.printer,
    this.printCount = 0,
    this.autoStart = false,
    this.connecting = false,
    this.btConnected = false,
    this.paperSize = PaperSize.mm80,
    this.cashDrawerMode = CashDrawerMode.off,
    this.sessionSummaryCashDrawer = false,
    this.isPrinting = false,
    this.printStatus = '',
    this.historyDateRange,
    this.isKeyboardVisible = false,
  });

  AppState copyWith({
    int? tabIndex,
    bool? serverRunning,
    int? serverPort,
    PrinterDevice? printer,
    int? printCount,
    bool? autoStart,
    bool? connecting,
    bool? btConnected,
    PaperSize? paperSize,
    CashDrawerMode? cashDrawerMode,
    bool? sessionSummaryCashDrawer,
    bool? isPrinting,
    String? printStatus,
    DateTimeRange? historyDateRange,
    bool? isKeyboardVisible,
  }) {
    return AppState(
      tabIndex: tabIndex ?? this.tabIndex,
      serverRunning: serverRunning ?? this.serverRunning,
      serverPort: serverPort ?? this.serverPort,
      printer: printer ?? this.printer,
      printCount: printCount ?? this.printCount,
      autoStart: autoStart ?? this.autoStart,
      connecting: connecting ?? this.connecting,
      btConnected: btConnected ?? this.btConnected,
      paperSize: paperSize ?? this.paperSize,
      cashDrawerMode: cashDrawerMode ?? this.cashDrawerMode,
      sessionSummaryCashDrawer: sessionSummaryCashDrawer ?? this.sessionSummaryCashDrawer,
      isPrinting: isPrinting ?? this.isPrinting,
      printStatus: printStatus ?? this.printStatus,
      historyDateRange: historyDateRange ?? this.historyDateRange,
      isKeyboardVisible: isKeyboardVisible ?? this.isKeyboardVisible,
    );
  }
}

class AppStateNotifier extends Notifier<AppState> {
  @override
  AppState build() => const AppState();

  void setTabIndex(int index) => state = state.copyWith(tabIndex: index);
  void setServerRunning(bool running) => state = state.copyWith(serverRunning: running);
  void setServerPort(int port) => state = state.copyWith(serverPort: port);
  void setPrinter(PrinterDevice? printer) => state = state.copyWith(printer: printer);
  void setPrintCount(int count) => state = state.copyWith(printCount: count);
  void incrementPrintCount() => state = state.copyWith(printCount: state.printCount + 1);
  void setAutoStart(bool autoStart) => state = state.copyWith(autoStart: autoStart);
  void setConnecting(bool connecting) => state = state.copyWith(connecting: connecting);
  void setBtConnected(bool connected) => state = state.copyWith(btConnected: connected);
  void setPaperSize(PaperSize size) => state = state.copyWith(paperSize: size);
  void setCashDrawerMode(CashDrawerMode mode) => state = state.copyWith(cashDrawerMode: mode);
  void setSessionSummaryCashDrawer(bool value) => state = state.copyWith(sessionSummaryCashDrawer: value);
  void setIsPrinting(bool printing) => state = state.copyWith(isPrinting: printing);
  void setPrintStatus(String status) => state = state.copyWith(printStatus: status);
  void setHistoryDateRange(DateTimeRange? range) => state = state.copyWith(historyDateRange: range);
  void setKeyboardVisible(bool visible) => state = state.copyWith(isKeyboardVisible: visible);
}

final appStateProvider = NotifierProvider<AppStateNotifier, AppState>(AppStateNotifier.new);