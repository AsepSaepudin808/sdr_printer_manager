import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdfx/pdfx.dart';
import 'package:image/image.dart' as img;
import 'package:curved_navigation_bar/curved_navigation_bar.dart';

import '../providers/app_state_provider.dart';
import '../providers/bluetooth_provider.dart';
import '../providers/server_provider.dart';
import '../providers/history_provider.dart';
import '../services/print_server_service.dart';
import '../services/bluetooth_service.dart';
import '../services/foreground_service_helper.dart';
import '../models/printer_device.dart';
import '../models/print_history.dart';
import '../utils/escpos_helper.dart';
import '../utils/test_print_template.dart';
import '../utils/constants.dart';
import '../utils/colors.dart';
import '../utils/strings.dart';
import 'scan_screen.dart';
import 'log_screen.dart';
import 'settings_screen.dart';
import 'printer_settings_screen.dart';
import 'text_tab.dart';
import 'image_tab.dart';
import 'pdf_tab.dart';
import 'widgets/status_card.dart';
import 'widgets/printer_card.dart';
import 'widgets/stats_row.dart';
import 'widgets/port_card.dart';
import 'widgets/test_print_card.dart';
import 'widgets/log_card.dart';
import 'widgets/auto_start_card.dart';
import 'widgets/background_permissions_card.dart';
import 'widgets/onboarding_permissions_sheet.dart';

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});
  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  static const MethodChannel _printJobChannel =
      MethodChannel('id.dretail.sdr_printer_manager/print_job');

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final TextEditingController _portCtrl = TextEditingController();

  static const _primary = AppColors.primary;
  static const _dark = AppColors.dark;
  static const _success = AppColors.success;
  static const _danger = AppColors.danger;
  static const _bg = AppColors.background;

  // ─── Convenience getters ───────────────────────────────────────────────────
  AppState get _appState => ref.read(appStateProvider);
  AppStateNotifier get _appNotifier => ref.read(appStateProvider.notifier);

  SdrBluetoothService get _bt => ref.read(bluetoothServiceProvider);
  PrintServerService get _server => ref.read(printServerServiceProvider);

  bool get _serverRunning => _appState.serverRunning;
  int get _serverPort => _appState.serverPort;
  PrinterDevice? get _printer => _appState.printer;
  PaperSize get _paperSize => _appState.paperSize;
  CashDrawerMode get _cashDrawerMode => _appState.cashDrawerMode;
  bool get _sessionSummaryCashDrawer => _appState.sessionSummaryCashDrawer;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    _setupListeners();
    _setupPrintJobChannel();
    ref.read(historyNotifierProvider.notifier).load();
    TestPrintTemplate.preloadLogo();
    _checkPermissionsAndOnboard();
  }

  Future<void> _checkPermissionsAndOnboard() async {
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) {
      return;
    }

    final btStatus = await Permission.bluetoothConnect.status;
    final locStatus = await Permission.locationWhenInUse.status;
    final notifStatus = await Permission.notification.status;
    final batteryGranted =
        await Permission.ignoreBatteryOptimizations.isGranted;
    final autoStartAck =
        await ForegroundServiceHelper.isAutoStartAcknowledged();

    final allGranted = btStatus.isGranted &&
        locStatus.isGranted &&
        notifStatus.isGranted &&
        batteryGranted &&
        autoStartAck;

    if (allGranted) {
      return;
    }
    if (!mounted) {
      return;
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (_) => OnboardingPermissionsSheet(onComplete: () {}),
    );
  }

  void _setupPrintJobChannel() {
    _printJobChannel.setMethodCallHandler((call) async {
      if (call.method == 'onNewPrintJob') {
        final path = call.arguments['path'] as String?;
        final name = call.arguments['name'] as String?;
        if (path != null) {
          _processPdfJob(path, name ?? 'Document');
        }
      }
    });
    _printJobChannel.invokeMethod('getPendingPrintJob').then((result) {
      if (result != null) {
        final map = Map<String, dynamic>.from(result as Map);
        final path = map['path'] as String?;
        final name = map['name'] as String?;
        if (path != null) {
          _processPdfJob(path, name ?? 'Document');
        }
      }
    });
  }

  img.Image _enhanceForThermal(img.Image source) {
    img.Image out = img.grayscale(source);
    out = img.luminanceThreshold(out,
        threshold: AppConstants.defaultImageThreshold / 255.0);
    return out;
  }

  Future<void> _processPdfJob(String path, String name) async {
    final file = File(path);
    if (!await file.exists()) {
      _addLog('❌ File PDF tidak ditemukan: $path');
      return;
    }

    _appNotifier.setIsPrinting(true);
    _appNotifier.setPrintStatus('🖨️ Memproses $name...');
    _addLog('🖨️ Menerima Print Job: $name');

    final connected = await _bt.checkConnection();
    if (!connected) {
      final a = _bt.lastAddress ?? _printer?.address;
      if (a != null && a.isNotEmpty) {
        _addLog(S.reconnecting);
        _appNotifier.setPrintStatus(S.reconnecting);
        final reconOk = await _bt.connect(a);
        if (!reconOk) {
          _addLog(S.printerDisconnected);
          _appNotifier.setIsPrinting(false);
          _appNotifier.setPrintStatus(S.printerDisconnected);
          return;
        }
        _addLog(S.printerConnected);
        _appNotifier.setBtConnected(true);
      } else {
        _addLog(S.printerNotConnected);
        _appNotifier.setIsPrinting(false);
        _appNotifier.setPrintStatus(S.printerNotConnected);
        return;
      }
    }

    PdfDocument? document;
    try {
      final bytes = await file.readAsBytes();
      document = await PdfDocument.openData(bytes);
      final totalPages = document.pagesCount;
      final maxWidth = EscPosHelper.paperMaxWidth(_paperSize);

      for (int i = 1; i <= totalPages; i++) {
        if (!mounted) return;
        _appNotifier.setPrintStatus('🖨️ Mencetak halaman $i/$totalPages...');

        final page = await document.getPage(i);
        final pageImage = await page.render(
          width: maxWidth.toDouble(),
          height: (page.height * maxWidth / page.width),
          format: PdfPageImageFormat.png,
          backgroundColor: '#FFFFFF',
        );
        await page.close();

        if (pageImage == null) throw Exception('Gagal render halaman $i');

        final decoded = img.decodeImage(pageImage.bytes);
        if (decoded == null) throw Exception('Gagal decode image halaman $i');

        final processed = _enhanceForThermal(decoded);

        final List<int> buf = [];
        buf.addAll(EscPosHelper.init());
        buf.addAll(EscPosHelper.align(1));
        buf.addAll(EscPosHelper.imageEsc(processed, _paperSize));
        buf.addAll(EscPosHelper.feed(2));

        final ok = await _bt.sendRaw(Uint8List.fromList(buf));
        if (!ok) throw Exception('Printer gagal menerima data di halaman $i');
      }

      _addLog(S.printSuccess(name));
      _appNotifier.setPrintStatus(S.printSuccess(name));
      _appNotifier.incrementPrintCount();
      final p = await SharedPreferences.getInstance();
      await p.setInt('print_count', _appState.printCount);
      _recordHistory('pdf', name, true, 0);

      try {
        await file.delete();
      } catch (_) {}
    } catch (e) {
      _addLog('❌ Error mencetak $name: $e');
      _appNotifier.setPrintStatus('❌ Error: $e');
    } finally {
      await document?.close();
      _appNotifier.setIsPrinting(false);
    }
  }

  @override
  void dispose() {
    _portCtrl.dispose();
    _server.stop();
    _bt.disconnect();
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    final port = p.getInt('server_port') ?? 8080;
    _portCtrl.text = port.toString();
    _appNotifier.setServerPort(port);
    _appNotifier.setAutoStart(p.getBool('auto_start') ?? false);
    _appNotifier.setPrintCount(p.getInt('print_count') ?? 0);

    final ps = p.getString('paper_size') ?? 'mm80';
    final paperSize = ps == 'mm58'
        ? PaperSize.mm58
        : ps == 'mm100'
            ? PaperSize.mm100
            : PaperSize.mm80;
    _appNotifier.setPaperSize(paperSize);

    final customChars = p.getInt('chars_per_line') ?? 0;
    EscPosHelper.setCustomCharsPerLine(customChars);
    EscPosHelper.setExtraFeed(p.getInt('extra_feed') ?? 3);
    EscPosHelper.setAutoCut(p.getBool('auto_cut') ?? false);

    final savedCashDrawer = p.getString('cash_drawer_mode') ?? 'off';
    final cashDrawerMode = savedCashDrawer == 'after'
        ? CashDrawerMode.openAfterPrint
        : savedCashDrawer == 'before'
            ? CashDrawerMode.openBeforePrint
            : CashDrawerMode.off;
    _appNotifier.setCashDrawerMode(cashDrawerMode);
    EscPosHelper.setCashDrawerMode(cashDrawerMode);

    final sessionSummaryCashDrawer =
        p.getBool('session_summary_cash_drawer') ?? false;
    _appNotifier.setSessionSummaryCashDrawer(sessionSummaryCashDrawer);
    EscPosHelper.setSessionSummaryCashDrawer(sessionSummaryCashDrawer);

    final addr = p.getString('printer_address');
    final name = p.getString('printer_name');
    if (addr != null && name != null) {
      _appNotifier.setPrinter(PrinterDevice(address: addr, name: name));
    }

    if (_appState.autoStart && _printer != null) {
      await Future.delayed(const Duration(milliseconds: 800));
      _startServer();
    }
  }

  void _setupListeners() {
    _server.onLog = (m) {
      ref.read(logsProvider.notifier).add(m);
    };
    _server.onPrintSuccess = () async {
      _appNotifier.incrementPrintCount();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('print_count', _appState.printCount);
    };
    _server.onPrintJob = (type, label, success, dataSize) {
      _recordHistory(type, label, success, dataSize);
    };
    _server.onStatusChange = (r) => _appNotifier.setServerRunning(r);
  }

  void _addLog(String m) {
    ref.read(logsProvider.notifier).add(m);
  }

  Future<void> _startServer() async {
    if (_printer == null) {
      _toast(S.selectPrinterToast, err: true);
      return;
    }
    if (_serverRunning) {
      _toast(S.serverAlreadyRunning);
      return;
    }

    // ✅ Start foreground service untuk menjaga app tetap aktif
    await ForegroundServiceHelper.start();

    _appNotifier.setConnecting(true);
    final ok = await _bt.connect(_printer!.address);
    _appNotifier.setConnecting(false);
    if (!ok) {
      _addLog(S.printerConnectFail);
      _toast(S.printerConnectFail, err: true);
      return;
    }
    _appNotifier.setBtConnected(true);
    _addLog(S.printerConnected);
    _server.setCashDrawerMode(_cashDrawerMode);
    _server.setSessionSummaryCashDrawer(_sessionSummaryCashDrawer);
    try {
      await _server.start(
          port: _serverPort, bluetoothService: _bt, paperSize: _paperSize);
      _appNotifier.setServerRunning(true);
      _addLog(S.serverReady);
      _toast(S.printerReady);
    } catch (e) {
      _toast('${S.serverStartFailed}: $e', err: true);
      _appNotifier.setServerRunning(false);
    }
  }

  Future<void> _stopServer() async {
    await _server.stop();
    await _bt.disconnect();
    _appNotifier.setServerRunning(false);
    _appNotifier.setBtConnected(false);
    _addLog(S.printerStopped);
    // ✅ Stop foreground service saat server dihentikan
    await ForegroundServiceHelper.stop();
  }

  void _toast(String m, {bool err = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m),
      backgroundColor: err ? _danger : _success,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));
  }

  Future<void> _goScan() async {
    final r = await Navigator.push<PrinterDevice>(
        context, MaterialPageRoute(builder: (_) => const ScanScreen()));
    if (r != null) {
      _appNotifier.setPrinter(r);
      final p = await SharedPreferences.getInstance();
      await p.setString('printer_address', r.address);
      await p.setString('printer_name', r.name);
      _addLog('${S.printerSelected}: ${r.name}');
    }
  }

  Future<void> _goSettings() async {
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
    await S.load();
    final p = await SharedPreferences.getInstance();
    final ps = p.getString('paper_size') ?? 'mm80';
    final newSize = ps == 'mm58'
        ? PaperSize.mm58
        : ps == 'mm100'
            ? PaperSize.mm100
            : PaperSize.mm80;
    _appNotifier.setPaperSize(newSize);
    _server.setPaperSize(newSize);

    await ref.read(historyNotifierProvider.notifier).load();
    final newCount = p.getInt('print_count') ?? 0;
    _appNotifier.setPrintCount(newCount);
    if (newCount == 0 && ref.read(historyNotifierProvider).isEmpty) {
      ref.read(logsProvider.notifier).clear();
    }
  }

  Future<void> _goPrinterSettings() async {
    await Navigator.push(context,
        MaterialPageRoute(builder: (_) => const PrinterSettingsScreen()));
    await _loadPrefs();
    if (_serverRunning) {
      _server.setPaperSize(_paperSize);
      _server.setCashDrawerMode(_cashDrawerMode);
      _server.setSessionSummaryCashDrawer(_sessionSummaryCashDrawer);
    }
  }

  Future<void> _savePort() async {
    final v = int.tryParse(_portCtrl.text.trim());
    if (v == null || v < 1024 || v > 65535) {
      _toast(S.portInvalid, err: true);
      return;
    }
    final p = await SharedPreferences.getInstance();
    await p.setInt('server_port', v);
    _appNotifier.setServerPort(v);
    _toast('${S.portSaved}: $v');
  }

  Future<void> _doTestPrint(Uint8List data, String label) async {
    _appNotifier.setIsPrinting(true);
    _appNotifier.setPrintStatus('');
    _addLog('🖨️ Test print: $label (${data.length} bytes)');

    final connected = await _bt.checkConnection();
    if (!connected) {
      final a = _bt.lastAddress;
      if (a != null && a.isNotEmpty) {
        _addLog(S.reconnecting);
        _appNotifier.setPrintStatus(S.reconnecting);
        final reconOk = await _bt.connect(a);
        if (!reconOk) {
          _addLog(S.printerDisconnected);
          _appNotifier.setIsPrinting(false);
          _appNotifier.setPrintStatus(S.printerDisconnected);
          return;
        }
        _addLog(S.printerConnected);
        _appNotifier.setBtConnected(true);
      } else {
        _addLog(S.printerNotConnected);
        _appNotifier.setIsPrinting(false);
        _appNotifier.setPrintStatus(S.printerNotConnected);
        return;
      }
    }

    final ok = await _bt.sendRaw(data);
    if (ok) {
      _addLog(S.printSuccess(label));
      _appNotifier.setIsPrinting(false);
      _appNotifier.setPrintStatus(S.printSuccess(label));
      _recordHistory('test', label, true, data.length);
    } else {
      _addLog(S.printFail);
      _appNotifier.setIsPrinting(false);
      _appNotifier.setPrintStatus(S.printFail);
      _recordHistory('test', label, false, data.length);
    }
  }

  void _recordHistory(String type, String label, bool success, int dataSize) {
    final entry = PrintHistory(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: type,
      label: label,
      timestamp: DateTime.now(),
      success: success,
      dataSize: dataSize,
      source: 'pos',
    );
    ref.read(historyNotifierProvider.notifier).add(entry);
  }

  void _showPrintHistory() {
    // Use watch inside builder via Consumer
    final logs = ref.read(logsProvider);
    final w = EscPosHelper.charsPerLine(_paperSize);
    final paperLabel = switch (_paperSize) {
      PaperSize.mm58 => '58mm',
      PaperSize.mm80 => '80mm',
      PaperSize.mm100 => '100mm'
    };
    final printLogs = logs
        .where((l) =>
            l.contains('print') ||
            l.contains('Print') ||
            l.contains('cetak') ||
            l.contains('dicetak'))
        .toList();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                  child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              Row(children: [
                const Icon(Icons.analytics_rounded, color: _primary, size: 22),
                const SizedBox(width: 8),
                Text(S.printStatistics,
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: _dark)),
              ]),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: _primary.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  Expanded(
                      child: _statItem(
                          S.totalPrintedLabel,
                          '${_appState.printCount}',
                          Icons.receipt_long_rounded)),
                  Container(
                      width: 1,
                      height: 40,
                      color: _primary.withValues(alpha: 0.2)),
                  Expanded(
                      child: _statItem(
                          S.paper, paperLabel, Icons.description_rounded)),
                  Container(
                      width: 1,
                      height: 40,
                      color: _primary.withValues(alpha: 0.2)),
                  Expanded(
                      child: _statItem(
                          S.chars, '${w}kar', Icons.text_fields_rounded)),
                ]),
              ),
              const SizedBox(height: 16),
              Text(S.recentPrintActivity,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700, color: _dark)),
              const SizedBox(height: 8),
              if (printLogs.isEmpty)
                Center(
                    child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(S.noActivity,
                      style:
                          TextStyle(color: Colors.grey.shade400, fontSize: 13)),
                ))
              else
                ...printLogs.take(5).map((log) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                                log.contains('✅')
                                    ? Icons.check_circle_rounded
                                    : log.contains('❌')
                                        ? Icons.error_rounded
                                        : Icons.print_rounded,
                                size: 14,
                                color: log.contains('✅')
                                    ? _success
                                    : log.contains('❌')
                                        ? _danger
                                        : Colors.grey),
                            const SizedBox(width: 8),
                            Expanded(
                                child: Text(log,
                                    style: const TextStyle(
                                        fontSize: 11,
                                        fontFamily: 'monospace'))),
                          ]),
                    )),
              const SizedBox(height: 16),
            ]),
      ),
    );
  }

  Widget _statItem(String label, String value, IconData icon) {
    return Column(children: [
      Icon(icon, color: _primary, size: 18),
      const SizedBox(height: 4),
      Text(value,
          style: const TextStyle(
              fontSize: 14, fontWeight: FontWeight.w800, color: _dark)),
      Text(label, style: TextStyle(fontSize: 9, color: Colors.grey.shade500)),
    ]);
  }

  // ─── BUILD ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // Watch providers so UI rebuilds on state change
    final appState = ref.watch(appStateProvider);
    final logs = ref.watch(logsProvider);

    final titles = [S.home, S.freeText, S.statistics, S.printImage, S.printPdf];
    final isKeyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;

    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      systemNavigationBarColor: Colors.white,
      systemNavigationBarDividerColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
      statusBarColor: _primary,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ));

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: _bg,
      extendBody: false,
      resizeToAvoidBottomInset: true,
      drawerEnableOpenDragGesture: false,
      appBar: AppBar(
        backgroundColor: _primary,
        foregroundColor: Colors.white,
        title: AnimatedSwitcher(
          duration: const Duration(milliseconds: 150),
          transitionBuilder: (child, animation) {
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.3),
                  end: Offset.zero,
                ).animate(CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOut,
                )),
                child: child,
              ),
            );
          },
          layoutBuilder: (currentChild, previousChildren) {
            return Stack(
              alignment: Alignment.centerLeft,
              children: [
                ...previousChildren,
                if (currentChild != null) currentChild,
              ],
            );
          },
          child: Text(
            titles[appState.tabIndex],
            key: ValueKey(appState.tabIndex),
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
          ),
        ),
        elevation: 0,
        automaticallyImplyLeading: false,
        leadingWidth: 56,
        leading: GestureDetector(
          onTap: () => _scaffoldKey.currentState?.openDrawer(),
          behavior: HitTestBehavior.opaque,
          child: const SizedBox(
            width: 56,
            height: 56,
            child: Icon(Icons.menu_rounded, color: Colors.white, size: 26),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded,
                color: Colors.white, size: 24),
            onPressed: () {
              _toast(S.refreshed);
            },
          ),
        ],
      ),
      drawer: _buildDrawer(appState, logs),
      body: IndexedStack(
        index: appState.tabIndex,
        children: [
          _buildHomeTab(appState),
          TextTab(isKeyboardVisible: isKeyboardVisible),
          _buildStatsTab(appState),
          const ImageTab(),
          const PdfTab(),
        ],
      ),
      bottomNavigationBar: isKeyboardVisible ? null : _buildBottomBar(appState),
    );
  }

  Widget _buildDrawer(AppState appState, List<String> logs) {
    return Drawer(
      elevation: 16,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              _primary,
              _primary.withValues(alpha: 0.95),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(children: [
            DrawerHeader(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.print_rounded,
                      color: Colors.white, size: 32),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('dPrinter Mart',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.5)),
                        SizedBox(height: 4),
                        Text('Print Bridge for PoS',
                            style:
                                TextStyle(color: Colors.white70, fontSize: 13)),
                      ]),
                ),
              ]),
            ),
            Expanded(
                child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(children: [
                const SizedBox(height: 8),
                _drawerItem(Icons.home_rounded, S.home, () {
                  Navigator.pop(context);
                  _appNotifier.setTabIndex(0);
                }, isSelected: appState.tabIndex == 0),
                _drawerItem(Icons.history_rounded, S.activityHistory, () {
                  Navigator.pop(context);
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => LogScreen(logs: logs)));
                }),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Divider(color: Colors.white24, thickness: 1),
                ),
                _drawerItem(Icons.settings_rounded, S.settings, () async {
                  Navigator.pop(context);
                  await _goSettings();
                }),
                _drawerItem(Icons.print_outlined, S.printerSize, () async {
                  Navigator.pop(context);
                  await _goPrinterSettings();
                }),
                _drawerItem(Icons.info_outline_rounded, S.aboutApp, () {
                  Navigator.pop(context);
                  _showCustomAboutDialog(context);
                }),
              ]),
            )),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.bluetooth_rounded,
                      color: Colors.white70, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    appState.printer?.name ?? S.noPrinterSelected,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: RichText(
                textAlign: TextAlign.center,
                text: const TextSpan(
                  style: TextStyle(
                      fontSize: 11,
                      color: Colors.white70,
                      fontWeight: FontWeight.w400),
                  children: [
                    TextSpan(text: 'Powered by '),
                    TextSpan(
                        text: 'd',
                        style: TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.w700)),
                    TextSpan(text: 'Retail'),
                  ],
                ),
              ),
            ),
            _drawerItem(
                Icons.logout_rounded, S.exit, () => SystemNavigator.pop()),
            const SizedBox(height: 12),
          ]),
        ),
      ),
    );
  }

  Widget _drawerItem(IconData icon, String label, VoidCallback onTap,
      {bool isSelected = false, bool isDanger = false}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: isSelected
            ? Colors.white.withValues(alpha: 0.15)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Icon(icon,
            color: isDanger ? Colors.red.shade300 : Colors.white, size: 22),
        title: Text(
          label,
          style: TextStyle(
            color: isDanger ? Colors.red.shade300 : Colors.white,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            fontSize: 14,
          ),
        ),
        trailing: isSelected
            ? Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
              )
            : null,
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
    );
  }

  Widget _buildBottomBar(AppState appState) {
    // Dari docs curved_navigation_bar:
    //   backgroundColor = warna body di belakang lengkungan (harus = Scaffold backgroundColor)
    //   color           = warna bar itu sendiri
    // SafeArea(top:false) = padding bawah otomatis = tinggi system navBar Android
    // Hasilnya: navBar tidak tertimpa system navBar, background senada
    return SafeArea(
      top: false,
      child: CurvedNavigationBar(
        backgroundColor: _bg, // sama dengan Scaffold backgroundColor
        color: Colors.white,
        buttonBackgroundColor: _primary,
        height: 75,
        animationDuration: const Duration(milliseconds: 180),
        animationCurve: Curves.easeOut,
        index: appState.tabIndex,
        items: [
          _buildNavItem(Icons.home_rounded, appState.tabIndex == 0, 'Home'),
          _buildNavItem(
              Icons.description_rounded, appState.tabIndex == 1, 'Text'),
          _buildNavItem(
              Icons.insights_rounded, appState.tabIndex == 2, 'Stats'),
          _buildNavItem(Icons.image_rounded, appState.tabIndex == 3, 'Image'),
          _buildNavItem(
              Icons.picture_as_pdf_rounded, appState.tabIndex == 4, 'PDF'),
        ],
        onTap: (index) {
          _appNotifier.setTabIndex(index);
        },
      ),
    );
  }

  Widget _buildNavItem(IconData icon, bool isSelected, String label) {
    if (isSelected) {
      return Icon(icon, size: 28, color: Colors.white);
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 24, color: Colors.grey.shade400),
        const SizedBox(height: 3),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            color: Colors.grey.shade400,
          ),
        ),
      ],
    );
  }

  Widget _buildStatsTab(AppState appState) {
    final historyItems = ref.watch(historyNotifierProvider);
    final historyNotifier = ref.read(historyNotifierProvider.notifier);

    final totalSuccess = historyNotifier.successCount;
    final totalFail = historyNotifier.failCount;
    final todayCount = historyNotifier.todayCount;
    final totalBytes = historyNotifier.totalBytes;
    final byType = historyNotifier.countByType;
    final byDate = historyNotifier.countByDate;
    final rate = (totalSuccess + totalFail) > 0
        ? (totalSuccess / (totalSuccess + totalFail) * 100).toStringAsFixed(0)
        : '—';

    String formatBytes(int bytes) {
      if (bytes < 1024) return '${bytes}B';
      if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    }

    final typeInfo = <String, (String, Color, IconData)>{
      'receipt_full': (
        S.receiptFull,
        const Color(0xFF2BBCC4),
        Icons.receipt_long_rounded
      ),
      'receipt_basic': (
        S.receiptBasic,
        const Color(0xFF7B2FBE),
        Icons.receipt_rounded
      ),
      'session_summary': (
        S.sessionSummary,
        const Color(0xFFF59E0B),
        Icons.summarize_rounded
      ),
      'text': (S.textPrint, const Color(0xFF06C270), Icons.text_fields_rounded),
      'image': (S.imagePrint, const Color(0xFFEC4899), Icons.image_rounded),
      'pdf': (
        S.pdfPrint,
        const Color(0xFFEF4444),
        Icons.picture_as_pdf_rounded
      ),
      'test': (S.testPrintLabel, Colors.grey, Icons.bug_report_rounded),
      'escpos': ('ESC/POS', const Color(0xFF6366F1), Icons.code_rounded),
    };

    int maxDay = 1;
    for (final v in byDate.values) {
      if (v > maxDay) maxDay = v;
    }

    final historyDateRange = appState.historyDateRange;
    final filteredItems = historyDateRange != null
        ? historyItems.where((h) {
            final d = h.timestamp;
            return !d.isBefore(historyDateRange.start) &&
                d.isBefore(historyDateRange.end.add(const Duration(days: 1)));
          }).toList()
        : historyItems;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child:
                  const Icon(Icons.insights_rounded, color: _primary, size: 22),
            ),
            const SizedBox(width: 10),
            Text(S.statsTitle,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800, color: _dark)),
          ]),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
                child: _overviewCard(S.totalPrinted, '$totalSuccess',
                    Icons.print_rounded, _primary)),
            const SizedBox(width: 10),
            Expanded(
                child: _overviewCard(S.todayPrinted, '$todayCount',
                    Icons.today_rounded, const Color(0xFF7B2FBE))),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
                child: _overviewCard(S.successRate, '$rate%',
                    Icons.check_circle_outline_rounded, _success)),
            const SizedBox(width: 10),
            Expanded(
                child: _overviewCard(S.dataSent, formatBytes(totalBytes),
                    Icons.data_usage_rounded, const Color(0xFFF59E0B))),
          ]),
          const SizedBox(height: 20),
          _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.bar_chart_rounded, color: _primary, size: 18),
              const SizedBox(width: 8),
              Text(S.last7Days,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700, color: _dark)),
            ]),
            const SizedBox(height: 16),
            SizedBox(
              height: 100,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: byDate.entries.map((e) {
                  final fraction = maxDay > 0 ? e.value / maxDay : 0.0;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text('${e.value}',
                              style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: e.value > 0
                                      ? _primary
                                      : Colors.grey.shade400)),
                          const SizedBox(height: 4),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 500),
                            curve: Curves.easeOutCubic,
                            height: (fraction * 60).clamp(4.0, 60.0),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: e.value > 0
                                    ? [
                                        _primary,
                                        _primary.withValues(alpha: 0.6)
                                      ]
                                    : [
                                        Colors.grey.shade200,
                                        Colors.grey.shade200
                                      ],
                              ),
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(e.key,
                              style: TextStyle(
                                  fontSize: 9, color: Colors.grey.shade500)),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ])),
          const SizedBox(height: 16),
          if (byType.isNotEmpty) ...[
            _card(
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.category_rounded, color: _primary, size: 18),
                const SizedBox(width: 8),
                Text(S.printByType,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _dark)),
              ]),
              const SizedBox(height: 14),
              ...byType.entries.map((e) {
                final info = typeInfo[e.key];
                final label = info?.$1 ?? e.key;
                final color = info?.$2 ?? Colors.grey;
                final icon = info?.$3 ?? Icons.print_rounded;
                final fraction =
                    totalSuccess > 0 ? e.value / totalSuccess : 0.0;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(icon, size: 16, color: color),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Text(label,
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: _dark)),
                            const Spacer(),
                            Text('${e.value}',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: color)),
                          ]),
                          const SizedBox(height: 4),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: fraction,
                              backgroundColor: Colors.grey.shade100,
                              valueColor: AlwaysStoppedAnimation(color),
                              minHeight: 5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ]),
                );
              }),
            ])),
            const SizedBox(height: 16),
          ],
          Row(children: [
            const Icon(Icons.history_rounded, color: _primary, size: 18),
            const SizedBox(width: 8),
            Text(S.printHistory,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700, color: _dark)),
            const Spacer(),
            if (filteredItems.isNotEmpty)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('${filteredItems.length}',
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _primary)),
              ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: GestureDetector(
                onTap: () async {
                  final now = DateTime.now();
                  final picked = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2024),
                    lastDate: now,
                    initialDateRange: historyDateRange ??
                        DateTimeRange(
                          start: now.subtract(const Duration(days: 7)),
                          end: now,
                        ),
                    builder: (ctx, child) => Theme(
                      data: Theme.of(ctx).copyWith(
                        colorScheme: const ColorScheme.light(
                          primary: _primary,
                          onPrimary: Colors.white,
                          surface: Colors.white,
                        ),
                      ),
                      child: child!,
                    ),
                  );
                  if (picked != null) {
                    _appNotifier.setHistoryDateRange(picked);
                  }
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: historyDateRange != null
                          ? _primary
                          : Colors.grey.shade300,
                    ),
                  ),
                  child: Row(children: [
                    Icon(Icons.date_range_rounded,
                        size: 16,
                        color: historyDateRange != null
                            ? _primary
                            : Colors.grey.shade400),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        historyDateRange != null
                            ? '${historyDateRange.start.day}/${historyDateRange.start.month}/${historyDateRange.start.year}'
                                ' — ${historyDateRange.end.day}/${historyDateRange.end.month}/${historyDateRange.end.year}'
                            : S.filterByDate,
                        style: TextStyle(
                          fontSize: 11,
                          color: historyDateRange != null
                              ? _dark
                              : Colors.grey.shade400,
                          fontWeight: historyDateRange != null
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                    if (historyDateRange != null)
                      GestureDetector(
                        onTap: () => _appNotifier.setHistoryDateRange(null),
                        child: Icon(Icons.close_rounded,
                            size: 16, color: Colors.grey.shade400),
                      ),
                  ]),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          if (filteredItems.isEmpty)
            _card(Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.receipt_long_rounded,
                      size: 48, color: Colors.grey.shade300),
                  const SizedBox(height: 12),
                  Text(S.noHistoryYet,
                      style:
                          TextStyle(color: Colors.grey.shade400, fontSize: 13)),
                ]),
              ),
            ))
          else
            ...filteredItems.take(AppConstants.maxHistoryDisplayItems).map((h) {
              final info = typeInfo[h.type];
              final color = info?.$2 ?? Colors.grey;
              final icon = info?.$3 ?? Icons.print_rounded;
              final time =
                  '${h.timestamp.day}/${h.timestamp.month}/${h.timestamp.year} '
                  '${h.timestamp.hour.toString().padLeft(2, '0')}:'
                  '${h.timestamp.minute.toString().padLeft(2, '0')}';
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color:
                          (h.success ? color : _danger).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      h.success ? icon : Icons.error_outline_rounded,
                      size: 18,
                      color: h.success ? color : _danger,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(h.label,
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: _dark)),
                        const SizedBox(height: 2),
                        Row(children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(h.typeLabel,
                                style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                    color: color)),
                          ),
                          const SizedBox(width: 6),
                          if (h.dataSize > 0)
                            Text(formatBytes(h.dataSize),
                                style: TextStyle(
                                    fontSize: 9, color: Colors.grey.shade500)),
                        ]),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Icon(
                        h.success
                            ? Icons.check_circle_rounded
                            : Icons.cancel_rounded,
                        size: 16,
                        color: h.success ? _success : _danger,
                      ),
                      const SizedBox(height: 2),
                      Text(time,
                          style: TextStyle(
                              fontSize: 9, color: Colors.grey.shade400)),
                    ],
                  ),
                ]),
              );
            }),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _overviewCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value,
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800, color: color)),
              Text(label,
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
            ],
          ),
        ),
      ]),
    );
  }

  // ─── HOME TAB ──────────────────────────────────────────────────────────────
  Widget _buildHomeTab(AppState appState) {
    const double bottomPad = 16.0;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, bottomPad),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        StatusCard(
          appState: appState,
          onCopyUrl: () => _toast(S.urlCopied),
        ),
        const SizedBox(height: 14),
        const BackgroundPermissionsCard(),
        const SizedBox(height: 14),
        PrinterCard(
          appState: appState,
          onSelectPrinter: _goScan,
          onToggleServer: _serverRunning ? _stopServer : _startServer,
        ),
        const SizedBox(height: 14),
        StatsRow(
          appState: appState,
          onShowHistory: _showPrintHistory,
          onOpenSettings: _goPrinterSettings,
        ),
        const SizedBox(height: 14),
        PortCard(
          portController: _portCtrl,
          onSave: _savePort,
        ),
        const SizedBox(height: 14),
        TestPrintCard(
          isPrinting: appState.isPrinting,
          paperSize: appState.paperSize,
          onTestPrint: (data, label) => _doTestPrint(data, label),
        ),
        if (appState.printStatus.isNotEmpty) ...[
          const SizedBox(height: 10),
          _testStatusCard(appState)
        ],
        const SizedBox(height: 14),
        LogCard(
          logs: ref.watch(logsProvider),
          onViewAll: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => LogScreen(logs: ref.read(logsProvider)))),
        ),
        const SizedBox(height: 14),
        AutoStartCard(
          autoStart: appState.autoStart,
          onChanged: (v) async {
            _appNotifier.setAutoStart(v);
            final p = await SharedPreferences.getInstance();
            await p.setBool('auto_start', v);
          },
        ),
      ]),
    );
  }

  Widget _card(Widget child) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 3))
            ]),
        child: child,
      );

  Widget _testStatusCard(AppState appState) {
    final ok = appState.printStatus.startsWith('✅');
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: (ok ? _success : _danger).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: (ok ? _success : _danger).withValues(alpha: 0.3)),
      ),
      child: Text(appState.printStatus,
          style: TextStyle(
              color: ok ? _success : _danger,
              fontWeight: FontWeight.w600,
              fontSize: 12)),
    );
  }

  // ─── ABOUT & LICENSE DIALOGS ───────────────────────────────────────────────
  void _showCustomAboutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child:
                    const Icon(Icons.print_rounded, size: 48, color: _primary),
              ),
              const SizedBox(height: 16),
              Text(
                S.appName,
                style:
                    const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: _primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${S.versionLabel} V1.0.2',
                  style: const TextStyle(
                      fontSize: 12,
                      color: _primary,
                      fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Print Bridge for PoS',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 12),
              const Text(
                'Aplikasi pengelola koneksi printer Bluetooth thermal untuk PoS dRetail Mart.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _showLicenseDialog(context);
                    },
                    child: Text(S.license,
                        style: const TextStyle(color: _primary)),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(S.close,
                        style: TextStyle(color: Colors.grey.shade600)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showLicenseDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400, maxHeight: 500),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.description_rounded, color: _primary),
                  const SizedBox(width: 8),
                  const Text(
                    'Lisensi',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(),
              const Expanded(
                child: SingleChildScrollView(
                  child: Text(
                    _licenseText,
                    style: TextStyle(fontSize: 12, height: 1.5),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static const String _licenseText = '''
LISENSI PENGGUNA AKHIR (EULA)

Copyright (c) 2026 dRetail Mart
Hak Cipta Dilindungi Undang-Undang

Dengan mengunduh, menginstal, atau menggunakan aplikasi "dPrinter Mart", Anda setuju untuk terikat dengan syarat-syarat berikut:

1. LISENSI PENGGUNAAN
   Aplikasi ini diberikan lisensi non-eksklusif dan tidak dapat dipindahtangankan. Aplikasi ini hanya untuk penggunaan internal pada bisnis Anda.

2. LARANGAN
   Dilarang keras:
   • Mengubah, membongkar, atau membuat turunan dari aplikasi ini
   • Menjual atau mendistribusikan ulang aplikasi ini
   • Menggunakan aplikasi untuk tujuan ilegal

3. PENUNJANGAN (DISCLAIMER)
   Aplikasi ini disediakan "SEBAGAIMANA ADANYA" tanpa jaminan dalam bentuk apa pun. Kami tidak bertanggung jawab atas kerusakan atau kehilangan data akibat penggunaan aplikasi ini.

4. KONEKSI PERANGKAT
   Aplikasi memerlukan koneksi Bluetooth ke printer thermal yang didukung. Koneksi Wi-Fi digunakan untuk fitur Print Bridge.

5. PEMBARUAN SYARAT
   Kami berhak memperbarui syarat lisensi ini sewaktu-waktu. Penggunaan berkelanjutan berarti Anda setuju dengan syarat baru.

6. HUBUNGI KAMI
   Untuk pertanyaan: support@dretail.id
''';
}
