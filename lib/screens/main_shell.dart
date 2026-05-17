import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdfx/pdfx.dart';
import 'package:image/image.dart' as img;
import 'package:curved_navigation_bar/curved_navigation_bar.dart';

import '../services/print_server_service.dart';
import '../services/bluetooth_service.dart';
import '../services/print_history_service.dart';
import '../models/printer_device.dart';
import '../models/print_history.dart';
import '../utils/escpos_helper.dart';
import '../utils/test_print_template.dart';
import '../utils/strings.dart';
import 'scan_screen.dart';
import 'log_screen.dart';
import 'settings_screen.dart';
import 'printer_settings_screen.dart';
import 'text_tab.dart';
import 'image_tab.dart';
import 'pdf_tab.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  static const MethodChannel _printJobChannel =
      MethodChannel('id.dretail.sdr_printer_manager/print_job');

  final PrintServerService _server = PrintServerService();
  final SdrBluetoothService _bt = SdrBluetoothService();
  final PrintHistoryService _historyService = PrintHistoryService();
  final GlobalKey<ScaffoldState> _scaffoldKey =
      GlobalKey<ScaffoldState>();

  int _tab = 0;
  bool _serverRunning = false;
  int _serverPort = 8080;
  PrinterDevice? _printer;
  final List<String> _logs = [];
  int _printCount = 0;
  bool _autoStart = false;
  bool _connecting = false;
  bool _btConnected = false;
  PaperSize _paperSize = PaperSize.mm80;
  bool _isPrinting = false;
  String _printStatus = '';
  final TextEditingController _portCtrl = TextEditingController();
  DateTimeRange? _historyDateRange;

  static const _primary = Color(0xFF2BBCC4);
  static const _dark = Color(0xFF2C3E50);
  static const _success = Color(0xFF06C270);
  static const _danger = Color(0xFFFF3B30);
  static const _bg = Color(0xFFF4F7FC);

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    _requestPerms();
    _setupListeners();
    _setupPrintJobChannel();
    _historyService.load().then((_) { if (mounted) setState(() {}); });
    // PRELOAD LOGO
    TestPrintTemplate.preloadLogo();
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

  int _paperMaxWidth(PaperSize size) {
    switch (size) {
      case PaperSize.mm58:
        return 384;
      case PaperSize.mm80:
        return 512;
      case PaperSize.mm100:
        return 768;
    }
  }

  img.Image _enhanceForThermal(img.Image source) {
    img.Image out = img.grayscale(source);
    // LUMINANCE THRESHOLD
    out = img.luminanceThreshold(out, threshold: 160 / 255.0);
    return out;
  }

  Future<void> _processPdfJob(String path, String name) async {
    final file = File(path);
    if (!await file.exists()) {
      _addLog('❌ File PDF tidak ditemukan: $path');
      return;
    }

    setState(() {
      _isPrinting = true;
      _printStatus = '🖨️ Memproses $name...';
    });
    _addLog('🖨️ Menerima Print Job: $name');

    // ENSURE BT CONNECTION
    final connected = await _bt.checkConnection();
    if (!connected) {
      final a = _bt.lastAddress ?? _printer?.address;
      if (a != null && a.isNotEmpty) {
        _addLog(S.reconnecting);
        setState(() => _printStatus = S.reconnecting);
        final reconOk = await _bt.connect(a);
        if (!reconOk) {
          _addLog(S.printerDisconnected);
          setState(() {
            _isPrinting = false;
            _printStatus = S.printerDisconnected;
          });
          return;
        }
        _addLog(S.printerConnected);
        setState(() => _btConnected = true);
      } else {
        _addLog(S.printerNotConnected);
        setState(() {
          _isPrinting = false;
          _printStatus = S.printerNotConnected;
        });
        return;
      }
    }

    PdfDocument? document;
    try {
      final bytes = await file.readAsBytes();
      document = await PdfDocument.openData(bytes);
      final totalPages = document.pagesCount;
      final maxWidth = _paperMaxWidth(_paperSize);

      for (int i = 1; i <= totalPages; i++) {
        if (!mounted) return;
        setState(() {
          _printStatus = '🖨️ Mencetak halaman $i/$totalPages...';
        });

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
      setState(() {
        _printStatus = S.printSuccess(name);
        _printCount++;
      });
      SharedPreferences.getInstance()
          .then((p) => p.setInt('print_count', _printCount));
      _recordHistory('pdf', name, true, 0);

      // CLEANUP TEMP FILE
      try {
        await file.delete();
      } catch (_) {}
    } catch (e) {
      _addLog('❌ Error mencetak $name: $e');
      setState(() => _printStatus = '❌ Error: $e');
    } finally {
      await document?.close();
      setState(() => _isPrinting = false);
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
    setState(() {
      _serverPort = p.getInt('server_port') ?? 8080;
      _portCtrl.text = _serverPort.toString();
      _autoStart = p.getBool('auto_start') ?? false;
      _printCount = p.getInt('print_count') ?? 0;
      final ps = p.getString('paper_size') ?? 'mm80';
      _paperSize = ps == 'mm58'
          ? PaperSize.mm58
          : ps == 'mm100'
              ? PaperSize.mm100
              : PaperSize.mm80;
      final customChars = p.getInt('chars_per_line') ?? 0;
      EscPosHelper.setCustomCharsPerLine(customChars);
      EscPosHelper.setExtraFeed(p.getInt('extra_feed') ?? 3);
      EscPosHelper.setAutoCut(p.getBool('auto_cut') ?? false);
      final addr = p.getString('printer_address');
      final name = p.getString('printer_name');
      if (addr != null && name != null) {
        _printer = PrinterDevice(address: addr, name: name);
      }
    });
    if (_autoStart && _printer != null) {
      await Future.delayed(const Duration(milliseconds: 800));
      _startServer();
    }
  }

  void _setupListeners() {
    _server.onLog = (m) {
      setState(() {
        _logs.insert(0, '[${_t()}] $m');
        if (_logs.length > 200) _logs.removeLast();
      });
    };
    _server.onPrintSuccess = () {
      setState(() => _printCount++);
      SharedPreferences.getInstance()
          .then((p) => p.setInt('print_count', _printCount));
    };
    _server.onPrintJob = (type, label, success, dataSize) {
      _recordHistory(type, label, success, dataSize);
    };
    _server.onStatusChange = (r) => setState(() => _serverRunning = r);
  }

  Future<void> _requestPerms() async {
    await [
      Permission.bluetooth,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.locationWhenInUse
    ].request();
  }

  String _t() {
    final n = DateTime.now();
    return '${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}:${n.second.toString().padLeft(2, '0')}';
  }

  void _addLog(String m) {
    setState(() {
      _logs.insert(0, '[${_t()}] $m');
      if (_logs.length > 200) _logs.removeLast();
    });
  }

  Future<void> _startServer() async {
    if (_printer == null) {
      _toast(S.selectPrinterToast, err: true);
      return;
    }
    if (_serverRunning) {
      _toast('Server sudah berjalan');
      return;
    }
    setState(() => _connecting = true);
    final ok = await _bt.connect(_printer!.address);
    setState(() => _connecting = false);
    if (!ok) {
      _addLog(S.printerConnectFail);
      _toast(S.printerConnectFail, err: true);
      return;
    }
    setState(() => _btConnected = true);
    _addLog(S.printerConnected);
    try {
      await _server.start(
          port: _serverPort, bluetoothService: _bt, paperSize: _paperSize);
      setState(() => _serverRunning = true);
      _addLog(S.serverReady);
      _toast(S.printerReady);
    } catch (e) {
      _toast('Gagal mengaktifkan layanan: $e', err: true);
      setState(() => _serverRunning = false);
    }
  }

  Future<void> _stopServer() async {
    await _server.stop();
    await _bt.disconnect();
    setState(() {
      _serverRunning = false;
      _btConnected = false;
    });
    _addLog(S.printerStopped);
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
      setState(() => _printer = r);
      final p = await SharedPreferences.getInstance();
      await p.setString('printer_address', r.address);
      await p.setString('printer_name', r.name);
      _addLog('${S.printerSelected}: ${r.name}');
    }
  }

  Future<void> _goSettings() async {
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
    await S.load(); // reload language
    final p = await SharedPreferences.getInstance();
    final ps = p.getString('paper_size') ?? 'mm80';
    final newSize = ps == 'mm58'
        ? PaperSize.mm58
        : ps == 'mm100'
            ? PaperSize.mm100
            : PaperSize.mm80;
    setState(() => _paperSize = newSize);
    _server.setPaperSize(newSize);
    // Reload history (may have been reset)
    await _historyService.load();
    final newCount = p.getInt('print_count') ?? 0;
    setState(() {
      _printCount = newCount;
      // CLEAR IN-MEMORY LOGS
      if (newCount == 0 && _historyService.items.isEmpty) {
        _logs.clear();
      }
    });
  }

  Future<void> _goPrinterSettings() async {
    await Navigator.push(context,
        MaterialPageRoute(builder: (_) => const PrinterSettingsScreen()));
    await _loadPrefs();
    if (_serverRunning) {
      _server.setPaperSize(_paperSize);
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
    setState(() => _serverPort = v);
    _toast('${S.portSaved}: $v');
  }

  Future<void> _doTestPrint(Uint8List data, String label) async {
    setState(() {
      _isPrinting = true;
      _printStatus = '';
    });
    _addLog('🖨️ Test print: $label (${data.length} bytes)');

    // ENSURE BT CONNECTION
    final connected = await _bt.checkConnection();
    if (!connected) {
      final a = _bt.lastAddress;
      if (a != null && a.isNotEmpty) {
        _addLog(S.reconnecting);
        setState(() => _printStatus = S.reconnecting);
        final reconOk = await _bt.connect(a);
        if (!reconOk) {
          _addLog(S.printerDisconnected);
          setState(() {
            _isPrinting = false;
            _printStatus = S.printerDisconnected;
          });
          return;
        }
        _addLog(S.printerConnected);
        setState(() => _btConnected = true);
      } else {
        _addLog(S.printerNotConnected);
        setState(() {
          _isPrinting = false;
          _printStatus = S.printerNotConnected;
        });
        return;
      }
    }

    final ok = await _bt.sendRaw(data);
    if (ok) {
      _addLog(S.printSuccess(label));
      setState(() {
        _isPrinting = false;
        _printStatus = S.printSuccess(label);
      });
      _recordHistory('test', label, true, data.length);
    } else {
      _addLog(S.printFail);
      setState(() {
        _isPrinting = false;
        _printStatus = S.printFail;
      });
      _recordHistory('test', label, false, data.length);
    }
  }

  // RECORD PRINT JOB
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
    _historyService.add(entry).then((_) {
      if (mounted) setState(() {});
    });
  }

  void _showPrintHistory() {
    final w = EscPosHelper.charsPerLine(_paperSize);
    final paperLabel = switch (_paperSize) {
      PaperSize.mm58 => '58mm',
      PaperSize.mm80 => '80mm',
      PaperSize.mm100 => '100mm'
    };
    // FILTER LOGS
    final printLogs = _logs
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
                Text(S.isEn ? 'Print Statistics' : 'Statistik Cetak',
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: _dark)),
              ]),
              const SizedBox(height: 16),
              // STATS GRID
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: _primary.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  Expanded(
                      child: _statItem(
                          S.isEn ? 'Total Printed' : 'Total Dicetak',
                          '$_printCount',
                          Icons.receipt_long_rounded)),
                  Container(
                      width: 1,
                      height: 40,
                      color: _primary.withValues(alpha: 0.2)),
                  Expanded(
                      child: _statItem(S.isEn ? 'Paper' : 'Kertas', paperLabel,
                          Icons.description_rounded)),
                  Container(
                      width: 1,
                      height: 40,
                      color: _primary.withValues(alpha: 0.2)),
                  Expanded(
                      child: _statItem(S.isEn ? 'Chars' : 'Karakter', '${w}kar',
                          Icons.text_fields_rounded)),
                ]),
              ),
              const SizedBox(height: 16),
              Text(S.isEn ? 'Recent Print Activity' : 'Aktivitas Cetak Terbaru',
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

  @override
  Widget build(BuildContext context) {
    final titles = [
      S.home,
      S.freeText,
      S.isEn ? 'Statistics' : 'Statistik',
      S.printImage,
      S.printPdf
    ];
    final isKeyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;

    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      systemNavigationBarColor: Colors.white,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.dark,
      statusBarColor: _primary,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ));

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: _bg,
      extendBody: true,
      resizeToAvoidBottomInset: true,
      drawerEnableOpenDragGesture: false,
      appBar: AppBar(
        backgroundColor: _primary,
        foregroundColor: Colors.white,
        title: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: Text(
            titles[_tab],
            key: ValueKey(titles[_tab]),
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
            icon: const Icon(Icons.refresh_rounded, color: Colors.white, size: 24),
            onPressed: () {
              _toast('Refreshed');
            },
          ),
        ],
      ),
      drawer: _buildDrawer(),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        transitionBuilder: (child, animation) {
          return FadeTransition(opacity: animation, child: child);
        },
        child: _buildBody(isKeyboardVisible),
      ),
      bottomNavigationBar: isKeyboardVisible ? null : _buildBottomBar(),
    );
  }

  Widget _buildDrawer() {
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
                            style: TextStyle(color: Colors.white70, fontSize: 13)),
                      ]),
                ),
              ]),
            ),
            Expanded(child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(children: [
                const SizedBox(height: 8),
                _drawerItem(Icons.home_rounded, S.home, () {
                  Navigator.pop(context);
                  setState(() => _tab = 0);
                }, isSelected: _tab == 0),
                _drawerItem(Icons.history_rounded, S.activityHistory, () {
                  Navigator.pop(context);
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => LogScreen(logs: _logs)));
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
                  const Icon(Icons.bluetooth_rounded, color: Colors.white70, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    _printer?.name ?? 'No Printer',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
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

  Widget _drawerItem(IconData icon, String label, VoidCallback onTap, {bool isSelected = false, bool isDanger = false}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: isSelected ? Colors.white.withValues(alpha: 0.15) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Icon(icon, color: isDanger ? Colors.red.shade300 : Colors.white, size: 22),
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

  Widget _buildBody(bool isKeyboardVisible) {
    switch (_tab) {
      case 0:
        return _buildHomeTab();
      case 1:
        return TextTab(
          btService: _bt,
          paperSize: _paperSize,
          isKeyboardVisible: isKeyboardVisible,
        );
      case 2:
        return _buildStatsTab();
      case 3:
        return ImageTab(btService: _bt, paperSize: _paperSize);
      case 4:
        return PdfTab(btService: _bt, paperSize: _paperSize);
      default:
        return _buildHomeTab();
    }
  }

  Widget _buildBottomBar() {
    return CurvedNavigationBar(
      backgroundColor: _bg,
      color: Colors.white,
      buttonBackgroundColor: _primary,
      height: 75,
      animationDuration: const Duration(milliseconds: 350),
      animationCurve: Curves.easeOutCubic,
      index: _tab,
      items: [
        _buildNavItem(Icons.home_rounded, _tab == 0, 'Home'),
        _buildNavItem(Icons.description_rounded, _tab == 1, 'Text'),
        _buildNavItem(Icons.insights_rounded, _tab == 2, 'Stats'),
        _buildNavItem(Icons.image_rounded, _tab == 3, 'Image'),
        _buildNavItem(Icons.picture_as_pdf_rounded, _tab == 4, 'PDF'),
      ],
      onTap: (index) {
        setState(() => _tab = index);
      },
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

  Widget _buildStatsTab() {
    final items = _historyService.items;
    final totalSuccess = _historyService.successCount;
    final totalFail = _historyService.failCount;
    final todayCount = _historyService.todayCount;
    final totalBytes = _historyService.totalBytes;
    final byType = _historyService.countByType;
    final byDate = _historyService.countByDate;
    final rate = (totalSuccess + totalFail) > 0
        ? (totalSuccess / (totalSuccess + totalFail) * 100).toStringAsFixed(0)
        : '—';

    String formatBytes(int bytes) {
      if (bytes < 1024) return '${bytes}B';
      if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    }

    // TYPE COLOR MAP
    final typeInfo = <String, (String, Color, IconData)>{
      'receipt_full': (S.receiptFull, const Color(0xFF2BBCC4), Icons.receipt_long_rounded),
      'receipt_basic': (S.receiptBasic, const Color(0xFF7B2FBE), Icons.receipt_rounded),
      'session_summary': (S.sessionSummary, const Color(0xFFF59E0B), Icons.summarize_rounded),
      'text': (S.textPrint, const Color(0xFF06C270), Icons.text_fields_rounded),
      'image': (S.imagePrint, const Color(0xFFEC4899), Icons.image_rounded),
      'pdf': (S.pdfPrint, const Color(0xFFEF4444), Icons.picture_as_pdf_rounded),
      'test': (S.testPrintLabel, Colors.grey, Icons.bug_report_rounded),
      'escpos': ('ESC/POS', const Color(0xFF6366F1), Icons.code_rounded),
    };

    // CHART MAX
    int maxDay = 1;
    for (final v in byDate.values) {
      if (v > maxDay) maxDay = v;
    }

    // DATE FILTER
    final filteredItems = _historyDateRange != null
        ? items.where((h) {
            final d = h.timestamp;
            return !d.isBefore(_historyDateRange!.start) &&
                d.isBefore(_historyDateRange!.end.add(const Duration(days: 1)));
          }).toList()
        : items;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // HEADER
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.insights_rounded, color: _primary, size: 22),
            ),
            const SizedBox(width: 10),
            Text(S.statsTitle,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800, color: _dark)),
          ]),
          const SizedBox(height: 16),

          // OVERVIEW CARDS (2x2 Grid)
          Row(children: [
            Expanded(child: _overviewCard(
              S.totalPrinted,
              '$totalSuccess',
              Icons.print_rounded,
              _primary,
            )),
            const SizedBox(width: 10),
            Expanded(child: _overviewCard(
              S.todayPrinted,
              '$todayCount',
              Icons.today_rounded,
              const Color(0xFF7B2FBE),
            )),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _overviewCard(
              S.successRate,
              '$rate%',
              Icons.check_circle_outline_rounded,
              _success,
            )),
            const SizedBox(width: 10),
            Expanded(child: _overviewCard(
              S.dataSent,
              formatBytes(totalBytes),
              Icons.data_usage_rounded,
              const Color(0xFFF59E0B),
            )),
          ]),
          const SizedBox(height: 20),

          // 7 DAY CHART
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
                                  color: e.value > 0 ? _primary : Colors.grey.shade400)),
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
                                    ? [_primary, _primary.withValues(alpha: 0.6)]
                                    : [Colors.grey.shade200, Colors.grey.shade200],
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

          // BY TYPE
          if (byType.isNotEmpty) ...[
            _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.category_rounded, color: _primary, size: 18),
                const SizedBox(width: 8),
                Text(S.printByType,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700, color: _dark)),
              ]),
              const SizedBox(height: 14),
              ...byType.entries.map((e) {
                final info = typeInfo[e.key];
                final label = info?.$1 ?? e.key;
                final color = info?.$2 ?? Colors.grey;
                final icon = info?.$3 ?? Icons.print_rounded;
                final fraction = totalSuccess > 0 ? e.value / totalSuccess : 0.0;
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

          // PRINT HISTORY

          Row(children: [
            const Icon(Icons.history_rounded, color: _primary, size: 18),
            const SizedBox(width: 8),
            Text(S.printHistory,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700, color: _dark)),
            const Spacer(),
            if (filteredItems.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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

          // DATE RANGE FILTER
          Row(children: [
            Expanded(
              child: GestureDetector(
                onTap: () async {
                  final now = DateTime.now();
                  final picked = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2024),
                    lastDate: now,
                    initialDateRange: _historyDateRange ??
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
                    setState(() => _historyDateRange = picked);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _historyDateRange != null
                          ? _primary
                          : Colors.grey.shade300,
                    ),
                  ),
                  child: Row(children: [
                    Icon(Icons.date_range_rounded,
                        size: 16,
                        color: _historyDateRange != null
                            ? _primary
                            : Colors.grey.shade400),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _historyDateRange != null
                            ? '${_historyDateRange!.start.day}/${_historyDateRange!.start.month}/${_historyDateRange!.start.year}'
                              ' — ${_historyDateRange!.end.day}/${_historyDateRange!.end.month}/${_historyDateRange!.end.year}'
                            : S.isEn ? 'Filter by date' : 'Filter tanggal',
                        style: TextStyle(
                          fontSize: 11,
                          color: _historyDateRange != null
                              ? _dark
                              : Colors.grey.shade400,
                          fontWeight: _historyDateRange != null
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                    if (_historyDateRange != null)
                      GestureDetector(
                        onTap: () =>
                            setState(() => _historyDateRange = null),
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
                      style: TextStyle(
                          color: Colors.grey.shade400, fontSize: 13)),
                ]),
              ),
            ))
          else
            ...filteredItems.take(50).map((h) {
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
                      color: (h.success ? color : _danger).withValues(alpha: 0.1),
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

  // HOME TAB
  Widget _buildHomeTab() {
    final paperLabel = switch (_paperSize) {
      PaperSize.mm58 => '58mm',
      PaperSize.mm80 => '80mm',
      PaperSize.mm100 => '100mm'
    };
    // BOTTOM PADDING
    const double bottomPad = 16.0;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, bottomPad),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _statusCard(paperLabel),
        const SizedBox(height: 14),
        _printerCard(),
        const SizedBox(height: 14),
        _statsRow(paperLabel),
        const SizedBox(height: 14),
        _portCard(),
        const SizedBox(height: 14),
        _testPrintCard(),
        if (_printStatus.isNotEmpty) ...[
          const SizedBox(height: 10),
          _testStatusCard()
        ],
        const SizedBox(height: 14),
        _logCard(),
        const SizedBox(height: 14),
        _autoStartCard(),
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

  Widget _statusCard(String paperLabel) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
            colors: _serverRunning
                ? [const Color(0xFF034B2F), const Color(0xFF06874F)]
                : [_primary, _primary.withValues(alpha: 0.85)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
              color:
                  (_serverRunning ? _success : _primary).withValues(alpha: 0.35),
              blurRadius: 20,
              offset: const Offset(0, 8))
        ],
      ),
      padding: const EdgeInsets.all(22),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.8, end: 1.0),
            duration: const Duration(milliseconds: 1200),
            curve: Curves.easeInOut,
            builder: (context, value, child) {
              return Transform.scale(
                scale: value,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: _serverRunning ? _success : Colors.grey.shade400,
                    shape: BoxShape.circle,
                    boxShadow: _serverRunning
                        ? [
                            BoxShadow(
                              color: _success.withValues(alpha: 0.6),
                              blurRadius: 8,
                              spreadRadius: 2,
                            )
                          ]
                        : null,
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 10),
          Text(_serverRunning ? S.printerActive : S.printerInactive,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(20)),
            child: Row(children: [
              const Icon(Icons.description_rounded, color: Colors.white70, size: 14),
              const SizedBox(width: 4),
              Text(paperLabel,
                  style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
            ]),
          ),
        ]),
        const SizedBox(height: 16),
        if (_serverRunning) ...[
          GestureDetector(
            onTap: () {
              Clipboard.setData(
                  ClipboardData(text: 'http://127.0.0.1:$_serverPort'));
              _toast(S.urlCopied);
            },
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('http://127.0.0.1:$_serverPort',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'monospace',
                            letterSpacing: 0.5)),
                    const SizedBox(height: 2),
                    Text(S.tapToCopy,
                        style: const TextStyle(color: Colors.white38, fontSize: 10)),
                  ]),
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.copy_rounded, color: Colors.white, size: 18),
                ),
              ]),
            ),
          ),
        ] else
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(children: [
              const Icon(Icons.wifi_rounded, color: Colors.white54, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(S.pressToActivate,
                    style: const TextStyle(color: Colors.white54, fontSize: 12)),
              ),
            ]),
          ),
      ]),
    );
  }

  Widget _printerCard() {
    final has = _printer != null;
    return _card(Row(children: [
      Container(
        width: 54,
        height: 54,
        decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: has
                  ? [_primary.withValues(alpha: 0.15), _primary.withValues(alpha: 0.05)]
                  : [Colors.grey.shade200, Colors.grey.shade100],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(Icons.print_rounded,
            color: has ? _primary : Colors.grey, size: 26),
      ),
      const SizedBox(width: 14),
      Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(has ? _printer!.name : S.noPrinter,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: has ? _dark : Colors.grey)),
          ),
          if (_btConnected)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: _success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: _success,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: _success.withValues(alpha: 0.5),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                Text(S.connected,
                    style: const TextStyle(fontSize: 10, color: _success, fontWeight: FontWeight.w600)),
              ]),
            ),
        ]),
        if (has) ...[
          const SizedBox(height: 4),
          GestureDetector(
            onTap: () {
              showModalBottomSheet(
                context: context,
                backgroundColor: Colors.white,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                builder: (_) => SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 50,
                            height: 5,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade300,
                              borderRadius: BorderRadius.circular(99),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: _primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.print_rounded, color: _primary, size: 22),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(_printer!.name,
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                              const SizedBox(height: 4),
                              Text('ID Printer',
                                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                            ]),
                          ),
                        ]),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(children: [
                            Icon(Icons.fingerprint_rounded, color: Colors.grey.shade500, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: SelectableText(_printer!.address,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Colors.black87,
                                    fontFamily: 'monospace',
                                    letterSpacing: 1,
                                  )),
                            ),
                          ]),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              await Clipboard.setData(ClipboardData(text: _printer!.address));
                              if (mounted) {
                                Navigator.pop(context);
                                _toast(S.urlCopied);
                              }
                            },
                            icon: const Icon(Icons.copy_rounded, size: 18),
                            label: Text(S.isEn ? 'Copy ID' : 'Salin ID'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('ID: ${_printer!.address}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey.shade600,
                          fontFamily: 'monospace')),
                  const SizedBox(width: 4),
                  Icon(Icons.content_copy_rounded,
                      size: 12, color: Colors.grey.shade500),
                ],
              ),
            ),
          ),
        ] else ...[
          const SizedBox(height: 4),
          Text(
            S.selectPrinterFirst,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
          ),
        ],
      ])),
      const SizedBox(width: 12),
      Column(children: [
        GestureDetector(
          onTap: _serverRunning ? null : _goScan,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: (_serverRunning ? Colors.grey : _primary).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: (_serverRunning ? Colors.grey : _primary).withValues(alpha: 0.3),
              ),
            ),
            child: Text(has ? S.change : S.select,
                style: TextStyle(
                    color: _serverRunning ? Colors.grey : _primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 12)),
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _connecting
              ? null
              : (_serverRunning ? _stopServer : _startServer),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              color: _connecting
                  ? Colors.grey.shade400
                  : _serverRunning
                      ? _danger
                      : _success,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: (_connecting
                          ? Colors.grey
                          : _serverRunning
                              ? _danger
                              : _success)
                      .withValues(alpha: 0.35),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _connecting
                      ? Icons.hourglass_top_rounded
                      : _serverRunning
                          ? Icons.power_settings_new_rounded
                          : Icons.play_arrow_rounded,
                  size: 16,
                  color: Colors.white,
                ),
                const SizedBox(width: 6),
                Text(
                  _connecting
                      ? '...'
                      : _serverRunning
                          ? 'OFF'
                          : 'ON',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ]),
    ]));
  }

  Widget _statsRow(String paperLabel) {
    final w = EscPosHelper.charsPerLine(_paperSize);
    return Row(children: [
      Expanded(
          child: GestureDetector(
        onTap: _showPrintHistory,
        child: _card(
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: _primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.receipt_long_rounded, color: _primary, size: 16),
            ),
            const Spacer(),
            Icon(Icons.chevron_right_rounded, size: 18, color: Colors.grey[400]),
          ]),
          const SizedBox(height: 10),
          TweenAnimationBuilder<int>(
            tween: IntTween(begin: 0, end: _printCount),
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) {
              return Text('$value',
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w900, color: _primary));
            },
          ),
          const SizedBox(height: 2),
          Text(S.receiptsPrinted,
              style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
        ])),
      )),
      const SizedBox(width: 12),
      Expanded(
          child: GestureDetector(
        onTap: _goPrinterSettings,
        child: _card(
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF7B2FBE).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.tune_rounded, color: Color(0xFF7B2FBE), size: 16),
            ),
            const Spacer(),
            Icon(Icons.chevron_right_rounded, size: 18, color: Colors.grey[400]),
          ]),
          const SizedBox(height: 10),
          Text('$paperLabel · ${w}kar',
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF7B2FBE))),
          Text(S.isEn ? 'Printer Settings' : 'Pengaturan Printer',
              style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
        ])),
      )),
    ]);
  }

  Widget _portCard() {
    return _card(
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.settings_ethernet_rounded,
              color: Colors.orange.shade700, size: 18),
        ),
        const SizedBox(width: 10),
        Text(S.portHttpServer,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
            child: TextField(
          controller: _portCtrl,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
              labelText: 'Port',
              labelStyle: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _primary, width: 2),
              )),
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        )),
        const SizedBox(width: 10),
        ElevatedButton(
            onPressed: _savePort,
            style: ElevatedButton.styleFrom(
                backgroundColor: _primary,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.save_rounded, size: 18, color: Colors.white),
                const SizedBox(width: 6),
                Text(S.save, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
              ],
            )),
      ]),
    ]));
  }

  Widget _testPrintCard() {
    return _card(
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: _success.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.print_rounded, color: _success, size: 18),
        ),
        const SizedBox(width: 10),
        Text(S.testPrint,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
          child: _tpBtn(
              S.shortReceipt,
              Icons.receipt_rounded,
              _primary,
              _isPrinting
                  ? null
                  : () => _doTestPrint(TestPrintTemplate.buildTestShort(_paperSize),
                      'Struk pendek')),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _tpBtn(
              S.fullReceipt,
              Icons.receipt_long_rounded,
              const Color(0xFF7B2FBE),
              _isPrinting
                  ? null
                  : () => _doTestPrint(TestPrintTemplate.buildTestLong(_paperSize),
                      'Struk lengkap')),
        ),
      ]),
      if (_isPrinting) ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _primary,
                  )),
              const SizedBox(width: 10),
              Text(S.sending,
                  style: const TextStyle(color: _primary, fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ],
    ]));
  }

  Widget _tpBtn(String label, IconData icon, Color color, VoidCallback? onTap) {
    return GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color:
                (onTap == null ? Colors.grey : color).withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: (onTap == null ? Colors.grey : color)
                    .withValues(alpha: 0.2)),
          ),
          child: Row(children: [
            Icon(icon, color: onTap == null ? Colors.grey : color, size: 18),
            const SizedBox(width: 10),
            Expanded(
                child: Text(label,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: onTap == null ? Colors.grey : _dark))),
            Icon(Icons.chevron_right_rounded,
                color: onTap == null ? Colors.grey.shade300 : color, size: 18),
          ]),
        ));
  }

  Widget _testStatusCard() {
    final ok = _printStatus.startsWith('✅');
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: (ok ? _success : _danger).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: (ok ? _success : _danger).withValues(alpha: 0.3)),
      ),
      child: Text(_printStatus,
          style: TextStyle(
              color: ok ? _success : _danger,
              fontWeight: FontWeight.w600,
              fontSize: 12)),
    );
  }

  Widget _logCard() {
    return _card(
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.terminal_rounded, size: 16, color: Colors.grey),
        const SizedBox(width: 8),
        Text(S.activity,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        const Spacer(),
        if (_logs.isNotEmpty)
          GestureDetector(
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => LogScreen(logs: _logs))),
            child: Text(S.viewAll,
                style: const TextStyle(
                    color: _primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
          ),
      ]),
      const SizedBox(height: 10),
      Container(
        height: 110,
        decoration: BoxDecoration(
            color: const Color(0xFF0D1117),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Colors.grey.shade800.withValues(alpha: 0.5),
              width: 1,
            )),
        child: _logs.isEmpty
            ? Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.terminal_rounded, color: Colors.white24, size: 28),
                  const SizedBox(height: 8),
                  Text(S.noActivity,
                      style:
                          const TextStyle(color: Colors.white38, fontSize: 11)),
                ]),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(10),
                itemCount: _logs.length > 8 ? 8 : _logs.length,
                itemBuilder: (_, i) => Row(children: [
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.only(right: 8, top: 4),
                    decoration: BoxDecoration(
                      color: _logs[i].contains('✅')
                          ? _success
                          : _logs[i].contains('❌')
                              ? _danger
                              : Colors.amber.shade600,
                      shape: BoxShape.circle,
                    ),
                  ),
                  Expanded(
                    child: Text(_logs[i],
                        style: const TextStyle(
                            color: Color(0xFF7EE787),
                            fontSize: 10,
                            fontFamily: 'monospace',
                            height: 1.4)),
                  ),
                ]),
              ),
      ),
    ]));
  }

  Widget _autoStartCard() {
    return _card(Row(children: [
      const Icon(Icons.bolt_rounded, color: _primary, size: 16),
      const SizedBox(width: 10),
      Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(S.autoStart,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        Text(S.autoStartDesc,
            style: const TextStyle(fontSize: 10, color: Colors.grey)),
      ])),
      Switch.adaptive(
        value: _autoStart,
        activeTrackColor: _primary,
        onChanged: (v) async {
          setState(() => _autoStart = v);
          final p = await SharedPreferences.getInstance();
          await p.setBool('auto_start', v);
        },
      ),
    ]));
  }

  // CUSTOM ABOUT DIALOG
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
              // APP ICON
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.print_rounded, size: 48, color: _primary),
              ),
              const SizedBox(height: 16),
              // APP NAME
              const Text(
                'dPrinter Mart',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              // VERSION
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: _primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Versi V1.0.0.1',
                  style: TextStyle(fontSize: 12, color: _primary, fontWeight: FontWeight.w600),
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
              // DESCRIPTION
              const Text(
                'Aplikasi pengelola koneksi printer Bluetooth thermal untuk PoS dRetail Mart.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 20),
              // BUTTONS
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _showLicenseDialog(context);
                    },
                    child: const Text('Lisensi', style: TextStyle(color: _primary)),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Tutup', style: TextStyle(color: Colors.grey.shade600)),
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

Copyright (c) 2025 dRetail Mart
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
