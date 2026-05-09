import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdfx/pdfx.dart';
import 'package:image/image.dart' as img;

import '../services/print_server_service.dart';
import '../services/bluetooth_service.dart';
import '../models/printer_device.dart';
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

  int _tab = 0;
  bool _serverRunning = false;
  String _localIp = '';
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
    // Check if there is a pending job when app starts
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
    // Use strict luminance threshold for pure black and white without dither artifacts
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

    // Ensure connected
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
          
      // Clean up temp file
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
    final ip = await _server.getLocalIp();
    setState(() => _localIp = ip);
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
      _localIp = '';
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

    // Pastikan koneksi BT aktif
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
    } else {
      _addLog(S.printFail);
      setState(() {
        _isPrinting = false;
        _printStatus = S.printFail;
      });
    }
  }

  void _showPrintHistory() {
    final w = EscPosHelper.charsPerLine(_paperSize);
    final paperLabel = switch (_paperSize) {
      PaperSize.mm58 => '58mm',
      PaperSize.mm80 => '80mm',
      PaperSize.mm100 => '100mm'
    };
    // Filter logs yang berisi print
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
              // Stats grid
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
    final titles = [S.home, S.freeText, S.printImage, S.printPdf];
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _primary,
        foregroundColor: Colors.white,
        title: Text(titles[_tab],
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        elevation: 0,
      ),
      drawer: _buildDrawer(),
      body: _buildBody(),
      bottomNavigationBar: _buildBottomBar(),
      floatingActionButton: _buildFAB(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      child: Column(children: [
        DrawerHeader(
          decoration: const BoxDecoration(color: _primary),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.print_rounded,
                  color: Colors.white, size: 28),
            ),
            const SizedBox(width: 12),
            const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('dPrinter Mart',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800)),
                  Text('Print Bridge for PoS',
                      style: TextStyle(color: Colors.white60, fontSize: 12)),
                ]),
          ]),
        ),
        _drawerItem(Icons.home_rounded, S.home, () {
          Navigator.pop(context);
          setState(() => _tab = 0);
        }),
        _drawerItem(Icons.history_rounded, S.activityHistory, () {
          Navigator.pop(context);
          Navigator.push(context,
              MaterialPageRoute(builder: (_) => LogScreen(logs: _logs)));
        }),
        const Divider(),
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
          showAboutDialog(
              context: context,
              applicationName: S.appName,
              applicationVersion: '1.0.0',
              applicationIcon:
                  const Icon(Icons.print_rounded, color: _primary, size: 40));
        }),
        const Spacer(),
        const Divider(),
        _drawerItem(
            Icons.exit_to_app_rounded, S.exit, () => SystemNavigator.pop()),
        const SizedBox(height: 16),
      ]),
    );
  }

  Widget _drawerItem(IconData icon, String label, VoidCallback onTap) {
    return ListTile(
        leading: Icon(icon, color: _dark), title: Text(label), onTap: onTap);
  }

  Widget _buildBody() {
    switch (_tab) {
      case 0:
        return _buildHomeTab();
      case 1:
        return TextTab(btService: _bt, paperSize: _paperSize);
      case 2:
        return ImageTab(btService: _bt, paperSize: _paperSize);
      case 3:
        return PdfTab(btService: _bt, paperSize: _paperSize);
      default:
        return _buildHomeTab();
    }
  }

  Widget _buildBottomBar() {
    return BottomAppBar(
      shape: const CircularNotchedRectangle(),
      notchMargin: 8,
      color: Colors.white,
      elevation: 10,
      child: SizedBox(
        height: 62,
        child: Row(children: [
          _navBtn(Icons.home_rounded, S.home, 0),
          _navBtn(Icons.description_rounded, S.freeText, 1),
          const SizedBox(width: 52),
          _navBtn(Icons.image_rounded, S.printImage, 2),
          _navBtn(Icons.picture_as_pdf_rounded, S.printPdf, 3),
        ]),
      ),
    );
  }

  Widget _navBtn(IconData icon, String label, int idx) {
    final sel = _tab == idx;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => setState(() => _tab = idx),
        child: SizedBox(
          height: 54,
          child: Stack(
            alignment: Alignment.center,
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 380),
                curve: Curves.easeOutBack,
                top: sel ? 6 : 11,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 380),
                  curve: Curves.easeOutCubic,
                  width: sel ? 44 : 0,
                  height: sel ? 30 : 0,
                  decoration: BoxDecoration(
                    color: sel
                        ? _primary.withValues(alpha: 0.14)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              AnimatedSlide(
                duration: const Duration(milliseconds: 360),
                curve: Curves.easeOutCubic,
                offset: Offset(0, sel ? -0.12 : 0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TweenAnimationBuilder<double>(
                      duration: const Duration(milliseconds: 360),
                      curve: Curves.easeOutBack,
                      tween: Tween(begin: 0, end: sel ? 1 : 0),
                      builder: (context, t, child) {
                        final scale = 1 + (0.13 * t);
                        return Transform.scale(scale: scale, child: child);
                      },
                      child: Icon(
                        icon,
                        color: sel ? _primary : Colors.grey.shade500,
                        size: 22,
                      ),
                    ),
                    const SizedBox(height: 2),
                    AnimatedOpacity(
                      duration: const Duration(milliseconds: 260),
                      opacity: sel ? 1 : 0.78,
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: sel ? 10.5 : 10,
                          color: sel ? _primary : Colors.grey.shade500,
                          fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                          letterSpacing: sel ? 0.1 : 0,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFAB() {
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: _primary.withValues(alpha: 0.22),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: FloatingActionButton(
        backgroundColor: _primary,
        onPressed: _showPrintHistory,
        elevation: 0,
        child:
            const Icon(Icons.insights_rounded, color: Colors.white, size: 26),
      ),
    );
  }

  // ── HOME TAB ──
  Widget _buildHomeTab() {
    final paperLabel = switch (_paperSize) {
      PaperSize.mm58 => '58mm',
      PaperSize.mm80 => '80mm',
      PaperSize.mm100 => '100mm'
    };
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 48),
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
                : [const Color(0xFF1A8A91), _primary]),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color:
                  (_serverRunning ? _success : _primary).withValues(alpha: 0.3),
              blurRadius: 16,
              offset: const Offset(0, 6))
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                  color: _serverRunning ? _success : Colors.grey,
                  shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text(_serverRunning ? S.printerActive : S.printerInactive,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20)),
            child: Text('📄 $paperLabel',
                style: const TextStyle(color: Colors.white70, fontSize: 11)),
          ),
        ]),
        const SizedBox(height: 8),
        if (_serverRunning) ...[
          GestureDetector(
            onTap: () {
              Clipboard.setData(
                  ClipboardData(text: 'http://$_localIp:$_serverPort'));
              _toast(S.urlCopied);
            },
            child: Row(children: [
              Text('http://$_localIp:$_serverPort',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'monospace')),
              const SizedBox(width: 6),
              const Icon(Icons.copy_rounded, color: Colors.white38, size: 14),
            ]),
          ),
          Text(S.tapToCopy,
              style: const TextStyle(color: Colors.white38, fontSize: 10)),
        ] else
          Text(S.pressToActivate,
              style: const TextStyle(color: Colors.white54, fontSize: 12)),
      ]),
    );
  }

  Widget _printerCard() {
    final has = _printer != null;
    return _card(Row(children: [
      Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
            color: (has ? _primary : Colors.grey).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12)),
        child: Icon(Icons.print_rounded,
            color: has ? _primary : Colors.grey, size: 24),
      ),
      const SizedBox(width: 12),
      Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(has ? _printer!.name : S.noPrinter,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: has ? _dark : Colors.grey)),
        if (has) ...[
          const SizedBox(height: 2),
          GestureDetector(
            onTap: () {
              showModalBottomSheet(
                context: context,
                backgroundColor: Colors.white,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
                ),
                builder: (_) => SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          S.isEn ? 'Printer ID' : 'ID Printer',
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 8),
                        SelectableText(
                          _printer!.address,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.black87,
                            fontFamily: 'monospace',
                          ),
                        ),
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: () async {
                              await Clipboard.setData(
                                  ClipboardData(text: _printer!.address));
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(S.urlCopied)),
                                );
                              }
                            },
                            icon: const Icon(Icons.copy_rounded, size: 18),
                            label: Text(S.isEn ? 'Copy ID' : 'Salin ID'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
            child: Row(
              children: [
                Expanded(
                  child: Text('ID: ${_printer!.address}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 10.5,
                          color: Colors.grey.shade500,
                          fontFamily: 'monospace')),
                ),
                const SizedBox(width: 4),
                Icon(Icons.content_copy_rounded,
                    size: 12, color: Colors.grey.shade500),
              ],
            ),
          ),
        ],
        const SizedBox(height: 3),
        Row(children: [
          Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                  color: _btConnected ? _success : Colors.grey,
                  shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
                _btConnected
                    ? S.connected
                    : has
                        ? S.notConnected
                        : S.selectPrinterFirst,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11,
                    color: _btConnected ? _success : Colors.grey)),
          ),
        ]),
      ])),
      LayoutBuilder(builder: (context, constraints) {
        final compact = constraints.maxWidth < 120;
        final changeFont = compact ? 11.0 : 12.0;
        final powerFont = compact ? 10.0 : 11.5;
        final powerHPad = compact ? 10.0 : 16.0;
        final powerVPad = compact ? 8.0 : 10.0;
        final iconSize = compact ? 12.0 : 14.0;
        final gap = compact ? 4.0 : 6.0;

        return Wrap(
          spacing: 6,
          runSpacing: 6,
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            GestureDetector(
              onTap: _serverRunning ? null : _goScan,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                    color: (_serverRunning ? Colors.grey : _primary)
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8)),
                child: Text(has ? S.change : S.select,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: _serverRunning ? Colors.grey : _primary,
                        fontWeight: FontWeight.w700,
                        fontSize: changeFont)),
              ),
            ),
            GestureDetector(
              onTap: _connecting
                  ? null
                  : (_serverRunning ? _stopServer : _startServer),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                padding: EdgeInsets.symmetric(
                    horizontal: powerHPad, vertical: powerVPad),
                constraints: BoxConstraints(minWidth: compact ? 66 : 78),
                decoration: BoxDecoration(
                  color: _connecting
                      ? Colors.grey.shade400
                      : _serverRunning
                          ? _danger
                          : _success,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: (_connecting
                              ? Colors.grey
                              : _serverRunning
                                  ? _danger
                                  : _success)
                          .withValues(alpha: 0.28),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
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
                      size: iconSize,
                      color: Colors.white,
                    ),
                    SizedBox(width: gap),
                    Text(
                      _connecting
                          ? (S.isEn ? 'WAIT' : 'TUNGGU')
                          : _serverRunning
                              ? (S.isEn ? 'STOP' : 'MATIKAN')
                              : (S.isEn ? 'ON' : 'NYALAKAN'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: powerFont,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      }),
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
            const Icon(Icons.receipt_long_rounded, color: _primary, size: 18),
            const Spacer(),
            Icon(Icons.info_outline_rounded, size: 12, color: Colors.grey[400]),
          ]),
          const SizedBox(height: 8),
          Text('$_printCount',
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w800, color: _primary)),
          Text(S.receiptsPrinted,
              style: const TextStyle(fontSize: 10, color: Colors.grey)),
        ])),
      )),
      const SizedBox(width: 12),
      Expanded(
          child: GestureDetector(
        onTap: _goPrinterSettings,
        child: _card(
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.tune_rounded, color: Color(0xFF7B2FBE), size: 18),
            const Spacer(),
            Icon(Icons.chevron_right_rounded,
                size: 16, color: Colors.grey[400]),
          ]),
          const SizedBox(height: 8),
          Text('$paperLabel · ${w}kar',
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF7B2FBE))),
          Text(S.isEn ? 'Printer Settings' : 'Pengaturan Printer',
              style: const TextStyle(fontSize: 10, color: Colors.grey)),
        ])),
      )),
    ]);
  }

  Widget _portCard() {
    return _card(
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.settings_ethernet_rounded,
            color: Colors.orange, size: 16),
        const SizedBox(width: 8),
        Text(S.portHttpServer,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(
            child: TextField(
          controller: _portCtrl,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
              labelText: 'Port',
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
          style: const TextStyle(fontSize: 13),
        )),
        const SizedBox(width: 8),
        ElevatedButton(
            onPressed: _savePort,
            style: ElevatedButton.styleFrom(
                backgroundColor: _primary,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8))),
            child: Text(S.save, style: const TextStyle(fontSize: 12))),
      ]),
    ]));
  }

  Widget _testPrintCard() {
    return _card(
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.print_rounded, color: _success, size: 16),
        const SizedBox(width: 8),
        Text(S.testPrint,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
      ]),
      const SizedBox(height: 10),
      _tpBtn(
          S.shortReceipt,
          Icons.receipt_rounded,
          _primary,
          _isPrinting
              ? null
              : () => _doTestPrint(TestPrintTemplate.buildTestShort(_paperSize),
                  'Struk pendek')),
      const SizedBox(height: 8),
      _tpBtn(
          S.fullReceipt,
          Icons.receipt_long_rounded,
          const Color(0xFF7B2FBE),
          _isPrinting
              ? null
              : () => _doTestPrint(TestPrintTemplate.buildTestLong(_paperSize),
                  'Struk lengkap')),
      if (_isPrinting) ...[
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 8),
          Text(S.sending,
              style: const TextStyle(color: Colors.grey, fontSize: 12)),
        ]),
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
        height: 100,
        decoration: BoxDecoration(
            color: const Color(0xFF0D1117),
            borderRadius: BorderRadius.circular(10)),
        child: _logs.isEmpty
            ? Center(
                child: Text(S.noActivity,
                    style:
                        const TextStyle(color: Colors.white38, fontSize: 11)))
            : ListView.builder(
                padding: const EdgeInsets.all(8),
                itemCount: _logs.length > 8 ? 8 : _logs.length,
                itemBuilder: (_, i) => Text(_logs[i],
                    style: const TextStyle(
                        color: Color(0xFF7EE787),
                        fontSize: 10,
                        fontFamily: 'monospace')),
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
}
