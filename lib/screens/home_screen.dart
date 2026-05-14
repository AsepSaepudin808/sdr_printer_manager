import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/print_server_service.dart';
import '../services/bluetooth_service.dart';
import '../models/printer_device.dart';
import 'scan_screen.dart';
import 'log_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final PrintServerService _serverService = PrintServerService();
  final SdrBluetoothService _btService = SdrBluetoothService();

  bool _serverRunning = false;
  String _localIp = '';
  int _serverPort = 8080;
  PrinterDevice? _selectedPrinter;
  final List<String> _logs = [];
  int _printCount = 0;
  bool _autoStart = false;
  bool _isConnectingBt = false;
  bool _btConnected = false;

  // Animasi
  late AnimationController _pulseController;
  late AnimationController _fadeController;
  late Animation<double> _pulseAnim;
  late Animation<double> _fadeAnim;

  // Warna tema dRetail
  static const Color _primary = Color(0xFF1346A0);
  static const Color _primaryLight = Color(0xFF1A5DC8);
  static const Color _accent = Color(0xFF00B4D8);
  static const Color _success = Color(0xFF06C270);
  static const Color _danger = Color(0xFFFF3B30);
  static const Color _bg = Color(0xFFF4F7FC);
  static const Color _kCardColor = Colors.white;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();

    _pulseAnim = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _fadeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOut),
    );

    _loadPrefs();
    _requestPermissions();
    _setupListeners();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _fadeController.dispose();
    _serverService.stop();
    _btService.disconnect();
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _serverPort = prefs.getInt('server_port') ?? 8080;
      _autoStart = prefs.getBool('auto_start') ?? false;
      _printCount = prefs.getInt('print_count') ?? 0;
      final addr = prefs.getString('printer_address');
      final name = prefs.getString('printer_name');
      if (addr != null && name != null) {
        _selectedPrinter = PrinterDevice(address: addr, name: name);
      }
    });
    if (_autoStart && _selectedPrinter != null) {
      await Future.delayed(const Duration(milliseconds: 800));
      _startServer();
    }
  }

  void _setupListeners() {
    _serverService.onLog = (msg) {
      setState(() {
        _logs.insert(0, '[${_timeNow()}] $msg');
        if (_logs.length > 200) _logs.removeLast();
      });
    };
    _serverService.onPrintSuccess = () {
      setState(() => _printCount++);
      SharedPreferences.getInstance()
          .then((p) => p.setInt('print_count', _printCount));
    };
    _serverService.onStatusChange = (running) {
      setState(() => _serverRunning = running);
    };
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.bluetooth,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.locationWhenInUse,
    ].request();
  }

  Future<void> _startServer() async {
    if (_selectedPrinter == null) {
      _showToast('Pilih printer terlebih dahulu', isError: true);
      return;
    }
    setState(() => _isConnectingBt = true);
    _addLog('Menghubungkan ke ${_selectedPrinter!.name}...');

    final connected = await _btService.connect(_selectedPrinter!.address);
    setState(() => _isConnectingBt = false);

    if (!connected) {
      _addLog('Gagal menghubungkan printer');
      _showToast('Gagal menghubungkan printer', isError: true);
      return;
    }

    setState(() => _btConnected = true);
    _addLog('Printer terhubung');

    final ip = await _serverService.getLocalIp();
    setState(() => _localIp = ip);

    await _serverService.start(
      port: _serverPort,
      bluetoothService: _btService,
    );

    setState(() => _serverRunning = true);
    _addLog('Siap menerima print dari PoS');
    _showToast('Printer siap digunakan!');
  }

  Future<void> _stopServer() async {
    await _serverService.stop();
    await _btService.disconnect();
    setState(() {
      _serverRunning = false;
      _btConnected = false;
      _localIp = '';
    });
    _addLog('Printer dinonaktifkan');
  }

  void _addLog(String msg) {
    setState(() {
      _logs.insert(0, '[${_timeNow()}] $msg');
      if (_logs.length > 200) _logs.removeLast();
    });
  }

  String _timeNow() {
    final n = DateTime.now();
    return '${n.hour.toString().padLeft(2, '0')}:'
        '${n.minute.toString().padLeft(2, '0')}:'
        '${n.second.toString().padLeft(2, '0')}';
  }

  void _showToast(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(isError ? Icons.error_outline : Icons.check_circle_outline,
                color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(msg)),
          ],
        ),
        backgroundColor: isError ? _danger : _success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _goToScan() async {
    final result = await Navigator.push<PrinterDevice>(
      context,
      MaterialPageRoute(builder: (_) => const ScanScreen()),
    );
    if (result != null) {
      setState(() => _selectedPrinter = result);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('printer_address', result.address);
      await prefs.setString('printer_name', result.name);
      _addLog('Printer dipilih: ${result.name}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: CustomScrollView(
          slivers: [
            _buildAppBar(),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  _buildStatusHero(),
                  const SizedBox(height: 16),
                  _buildPrinterCard(),
                  const SizedBox(height: 16),
                  _buildStatsRow(),
                  const SizedBox(height: 16),
                  _buildLogCard(),
                  const SizedBox(height: 16),
                  _buildAutoStartRow(),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return SliverAppBar(
      expandedHeight: 120,
      pinned: true,
      backgroundColor: _primary,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [_primary, _primaryLight],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.print_rounded,
                            color: Colors.white, size: 22),
                      ),
                      const SizedBox(width: 10),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('dRetail Mart',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5)),
                          Text('Printer Manager',
                              style: TextStyle(
                                  color: Colors.white60,
                                  fontSize: 11,
                                  letterSpacing: 1.2)),
                        ],
                      ),
                      const Spacer(),
                      _appBarBtn(
                        icon: Icons.history_rounded,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => LogScreen(logs: _logs)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _appBarBtn({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }

  // ── HERO STATUS ──────────────────────────────────────────────────
  Widget _buildStatusHero() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _serverRunning
              ? [const Color(0xFF034B2F), const Color(0xFF06874F)]
              : [const Color(0xFF1A1A2E), const Color(0xFF16213E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color:
                (_serverRunning ? _success : _primary).withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Indikator animasi
              AnimatedBuilder(
                animation: _pulseAnim,
                builder: (_, __) => Transform.scale(
                  scale: _serverRunning ? _pulseAnim.value : 1.0,
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: _serverRunning ? _success : Colors.grey,
                      shape: BoxShape.circle,
                      boxShadow: _serverRunning
                          ? [
                              BoxShadow(
                                  color: _success.withValues(alpha: 0.6),
                                  blurRadius: 8,
                                  spreadRadius: 2)
                            ]
                          : [],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                _serverRunning ? 'Printer Aktif' : 'Printer Tidak Aktif',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              if (_serverRunning)
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(
                        text: 'http://$_localIp:$_serverPort/print'));
                    _showToast('URL disalin');
                  },
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.2)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.copy_rounded,
                            color: Colors.white60, size: 12),
                        SizedBox(width: 4),
                        Text('Salin URL',
                            style:
                                TextStyle(color: Colors.white60, fontSize: 11)),
                      ],
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 16),

          if (_serverRunning) ...[
            Text(
              'http://$_localIp:$_serverPort',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Point of Sale terhubung ke printer ini',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ] else ...[
            const Text(
              'Aktifkan printer agar kasir\ndapat mencetak struk.',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ],

          const SizedBox(height: 20),

          // Tombol utama
          Row(
            children: [
              Expanded(
                child: _serverRunning
                    ? _heroBtn(
                        label: 'Nonaktifkan',
                        icon: Icons.stop_rounded,
                        color: _danger,
                        onTap: _stopServer,
                      )
                    : _heroBtn(
                        label: _isConnectingBt
                            ? 'Menghubungkan...'
                            : 'Aktifkan Printer',
                        icon: _isConnectingBt
                            ? Icons.hourglass_top_rounded
                            : Icons.play_arrow_rounded,
                        color: _success,
                        onTap: _isConnectingBt ? null : _startServer,
                        isLoading: _isConnectingBt,
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroBtn({
    required String label,
    required IconData icon,
    required Color color,
    VoidCallback? onTap,
    bool isLoading = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: onTap == null ? color.withValues(alpha: 0.4) : color,
          borderRadius: BorderRadius.circular(14),
          boxShadow: onTap != null
              ? [
                  BoxShadow(
                      color: color.withValues(alpha: 0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 4))
                ]
              : [],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isLoading)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            else
              Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15)),
          ],
        ),
      ),
    );
  }

  // ── PRINTER CARD ─────────────────────────────────────────────────
  Widget _buildPrinterCard() {
    final hasPrinter = _selectedPrinter != null;
    return _buildCard(
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: hasPrinter
                  ? _primary.withValues(alpha: 0.1)
                  : Colors.grey.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.print_rounded,
              color: hasPrinter ? _primary : Colors.grey,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasPrinter ? _selectedPrinter!.name : 'Belum ada printer',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: hasPrinter ? Colors.black87 : Colors.grey,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: _btConnected ? _success : Colors.grey,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      _btConnected
                          ? 'Terhubung via Bluetooth'
                          : hasPrinter
                              ? 'Belum terhubung'
                              : 'Pilih printer terlebih dahulu',
                      style: TextStyle(
                          fontSize: 12,
                          color: _btConnected ? _success : Colors.grey),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _serverRunning ? null : _goToScan,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: _serverRunning
                    ? Colors.grey.withValues(alpha: 0.1)
                    : _primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                hasPrinter ? 'Ganti' : 'Pilih',
                style: TextStyle(
                  color: _serverRunning ? Colors.grey : _primary,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── STATS ROW ────────────────────────────────────────────────────
  Widget _buildStatsRow() {
    return Row(
      children: [
        Expanded(
          child: _statCard(
            icon: Icons.receipt_long_rounded,
            label: 'Struk Dicetak',
            value: '$_printCount',
            color: _accent,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _statCard(
            icon: Icons.wifi_rounded,
            label: 'Port Server',
            value: ':$_serverPort',
            color: _primaryLight,
            onTap: _serverRunning ? null : _showPortDialog,
          ),
        ),
      ],
    );
  }

  Widget _statCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: _buildCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 16),
                ),
                if (onTap != null) ...[
                  const Spacer(),
                  const Icon(Icons.edit_rounded,
                      size: 14,
                      color: Colors.grey),
                ],
              ],
            ),
            const SizedBox(height: 10),
            Text(value,
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w800, color: color)),
            const SizedBox(height: 2),
            Text(label,
                style: const TextStyle(
                    fontSize: 11,
                    color: Colors.grey,
                    fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  // ── LOG CARD ─────────────────────────────────────────────────────
  Widget _buildLogCard() {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.terminal_rounded,
                    size: 16, color: Colors.grey),
              ),
              const SizedBox(width: 10),
              const Text('Aktivitas',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              const Spacer(),
              if (_logs.isNotEmpty)
                GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => LogScreen(logs: _logs)),
                  ),
                  child: const Text('Lihat semua',
                      style: TextStyle(
                          color: _primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            height: 120,
            decoration: BoxDecoration(
              color: const Color(0xFF0D1117),
              borderRadius: BorderRadius.circular(12),
            ),
            child: _logs.isEmpty
                ? const Center(
                    child: Text('Belum ada aktivitas',
                        style: TextStyle(color: Colors.white38, fontSize: 12)))
                : ListView.builder(
                    padding: const EdgeInsets.all(10),
                    itemCount: _logs.length > 10 ? 10 : _logs.length,
                    itemBuilder: (_, i) => Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        _logs[i],
                        style: const TextStyle(
                            color: Color(0xFF7EE787),
                            fontSize: 11,
                            fontFamily: 'monospace'),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // ── AUTO START ROW ───────────────────────────────────────────────
  Widget _buildAutoStartRow() {
    return _buildCard(
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.bolt_rounded,
                color: _accent, size: 16),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Aktifkan Otomatis',
                    style:
                        TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                Text('Printer langsung aktif saat app dibuka',
                    style: TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          ),
          Switch.adaptive(
            value: _autoStart,
            activeTrackColor: _primary,
            onChanged: (v) async {
              setState(() => _autoStart = v);
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('auto_start', v);
            },
          ),
        ],
      ),
    );
  }

  // ── HELPERS ──────────────────────────────────────────────────────
  Widget _buildCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kCardColor,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  Future<void> _showPortDialog() async {
    final controller = TextEditingController(text: _serverPort.toString());
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(18))),
        title: const Text('Ganti Port',
            style: TextStyle(fontWeight: FontWeight.w700)),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Port (default: 8080)',
            border: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(12))),
            prefixIcon: Icon(Icons.settings_ethernet_rounded),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _primary,
              foregroundColor: Colors.white,
              shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(10))),
            ),
            onPressed: () {
              final v = int.tryParse(controller.text);
              if (v != null && v > 1024 && v < 65535) {
                Navigator.pop(ctx, v);
              }
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    if (result != null) {
      setState(() => _serverPort = result);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('server_port', result);
    }
  }
}
