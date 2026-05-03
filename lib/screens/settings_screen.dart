import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/escpos_helper.dart';
import '../services/bluetooth_service.dart';

class SettingsScreen extends StatefulWidget {
  final SdrBluetoothService btService;
  const SettingsScreen({super.key, required this.btService});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  PaperSize _paperSize = PaperSize.mm80;
  bool _isPrinting    = false;
  String _printStatus = '';

  static const Color _primary   = Color(0xFF1346A0);
  static const Color _success   = Color(0xFF06C270);
  static const Color _danger    = Color(0xFFFF3B30);
  static const Color _bgColor   = Color(0xFFF4F7FC);
  static const Color _cardColor = Colors.white;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('paper_size') ?? 'mm80';
    setState(() {
      _paperSize = saved == 'mm58' ? PaperSize.mm58 : PaperSize.mm80;
    });
  }

  Future<void> _savePaperSize(PaperSize size) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'paper_size', size == PaperSize.mm58 ? 'mm58' : 'mm80');
    setState(() => _paperSize = size);
  }

  Future<void> _doPrint(Uint8List data, String label) async {
    setState(() {
      _isPrinting  = true;
      _printStatus = '';
    });

    // Cek koneksi aktual
    final connected = await widget.btService.checkConnection();

    if (!connected) {
      // Coba reconnect otomatis pakai lastAddress
      final addr = widget.btService.lastAddress;
      if (addr != null && addr.isNotEmpty) {
        setState(() => _printStatus = '🔄 Menghubungkan ulang...');
        final reconnected = await widget.btService.connect(addr);
        if (!reconnected) {
          setState(() {
            _isPrinting  = false;
            _printStatus =
            '❌ Printer terputus!\nKembali ke halaman utama dan aktifkan printer kembali.';
          });
          return;
        }
      } else {
        setState(() {
          _isPrinting  = false;
          _printStatus =
          '❌ Printer belum terhubung!\nAktifkan printer di halaman utama dulu.';
        });
        return;
      }
    }

    final ok = await widget.btService.sendRaw(data);
    setState(() {
      _isPrinting  = false;
      _printStatus = ok
          ? '✅ $label berhasil dicetak!'
          : '❌ Gagal mencetak.\nPastikan printer menyala dan kertas tersedia.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: _primary,
        foregroundColor: Colors.white,
        title: const Text('Pengaturan Printer',
            style: TextStyle(fontWeight: FontWeight.w700)),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildConnectionStatus(),
            const SizedBox(height: 16),
            _buildPaperSizeCard(),
            const SizedBox(height: 16),
            _buildTestPrintCard(),
            if (_printStatus.isNotEmpty) ...[
              const SizedBox(height: 16),
              _buildStatusCard(),
            ],
          ],
        ),
      ),
    );
  }

  // ── STATUS KONEKSI ───────────────────────────────────────────────
  Widget _buildConnectionStatus() {
    final connected = widget.btService.isConnected;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: connected
            ? _success.withValues(alpha: 0.08)
            : _danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: connected
              ? _success.withValues(alpha: 0.3)
              : _danger.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: connected ? _success : _danger,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  connected
                      ? 'Printer terhubung — siap test print'
                      : 'Printer tidak aktif',
                  style: TextStyle(
                      color: connected ? _success : _danger,
                      fontWeight: FontWeight.w700,
                      fontSize: 13),
                ),
                if (!connected)
                  const Text(
                    'Kembali ke halaman utama dan aktifkan printer dulu',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── PAPER SIZE CARD ──────────────────────────────────────────────
  Widget _buildPaperSizeCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.receipt_long_rounded,
                    color: _primary, size: 20),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Ukuran Kertas Thermal',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15)),
                  Text('Sesuaikan dengan printer Anda',
                      style:
                      TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _paperOption(
                  size: PaperSize.mm58,
                  label: '58 mm',
                  sub: '32 karakter/baris',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _paperOption(
                  size: PaperSize.mm80,
                  label: '80 mm',
                  sub: '48 karakter/baris',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.blue.shade100),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded,
                    size: 16, color: Colors.blue),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _paperSize == PaperSize.mm58
                        ? 'Kertas 58mm: lebar cetak ±48mm, umum di printer portable kecil.'
                        : 'Kertas 80mm: lebar cetak ±72mm, umum di printer kasir standard.',
                    style: const TextStyle(
                        fontSize: 11, color: Colors.blue),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _paperOption({
    required PaperSize size,
    required String label,
    required String sub,
  }) {
    final selected = _paperSize == size;
    return GestureDetector(
      onTap: () => _savePaperSize(size),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding:
        const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: selected
              ? _primary.withValues(alpha: 0.08)
              : Colors.grey.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? _primary : Colors.grey.shade300,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(Icons.straighten_rounded,
                color: selected ? _primary : Colors.grey, size: 28),
            const SizedBox(height: 8),
            Text(label,
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    color: selected ? _primary : Colors.grey[600])),
            const SizedBox(height: 2),
            Text(sub,
                style: TextStyle(
                    fontSize: 10,
                    color: selected ? _primary : Colors.grey),
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: selected ? _primary : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: selected
                        ? _primary
                        : Colors.grey.shade300),
              ),
              child: Text(
                selected ? '✓ Dipilih' : 'Pilih',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : Colors.grey),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── TEST PRINT CARD ──────────────────────────────────────────────
  Widget _buildTestPrintCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.print_rounded,
                    color: _success, size: 20),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Test Print',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15)),
                  Text('Cetak struk percobaan ke printer',
                      style:
                      TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          _testBtn(
            label: 'Cetak Struk Pendek',
            sub: 'Header + total saja (~10 baris)',
            icon: Icons.receipt_rounded,
            color: _primary,
            onTap: _isPrinting
                ? null
                : () => _doPrint(
              EscPosHelper.buildTestShort(_paperSize),
              'Struk pendek',
            ),
          ),
          const SizedBox(height: 10),
          _testBtn(
            label: 'Cetak Struk Lengkap',
            sub: 'Header + item + subtotal + footer (~30 baris)',
            icon: Icons.receipt_long_rounded,
            color: const Color(0xFF7B2FBE),
            onTap: _isPrinting
                ? null
                : () => _doPrint(
              EscPosHelper.buildTestLong(_paperSize),
              'Struk lengkap',
            ),
          ),
          if (_isPrinting) ...[
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 10),
                Text(
                  _printStatus.contains('Menghubungkan')
                      ? _printStatus
                      : 'Mengirim ke printer...',
                  style: const TextStyle(color: Colors.grey),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _testBtn({
    required String label,
    required String sub,
    required IconData icon,
    required Color color,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: onTap == null
              ? Colors.grey.withValues(alpha: 0.05)
              : color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: onTap == null
                ? Colors.grey.shade200
                : color.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: onTap == null
                    ? Colors.grey.withValues(alpha: 0.1)
                    : color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon,
                  color: onTap == null ? Colors.grey : color,
                  size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: onTap == null
                              ? Colors.grey
                              : Colors.black87)),
                  Text(sub,
                      style: const TextStyle(
                          fontSize: 11, color: Colors.grey)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: onTap == null
                    ? Colors.grey.shade300
                    : color),
          ],
        ),
      ),
    );
  }

  // ── STATUS CARD ──────────────────────────────────────────────────
  Widget _buildStatusCard() {
    final isOk = _printStatus.startsWith('✅');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isOk
            ? _success.withValues(alpha: 0.08)
            : _danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isOk
              ? _success.withValues(alpha: 0.3)
              : _danger.withValues(alpha: 0.3),
        ),
      ),
      child: Text(
        _printStatus,
        style: TextStyle(
            color: isOk ? _success : _danger,
            fontWeight: FontWeight.w600,
            fontSize: 13),
      ),
    );
  }

  // ── CARD WRAPPER ─────────────────────────────────────────────────
  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardColor,
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
}