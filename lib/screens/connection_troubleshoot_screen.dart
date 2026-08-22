import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../providers/app_state_provider.dart';
import '../providers/bluetooth_provider.dart';
import '../services/bluetooth_scan_helper.dart';
import '../services/bluetooth_settings_helper.dart';
import '../utils/strings.dart';

enum _StepStatus { pending, checking, ok, fail }

class _DiagStep {
  final String title;
  final String description;
  final IconData icon;
  _StepStatus status = _StepStatus.pending;
  String? actionLabel;
  VoidCallback? onAction;

  _DiagStep({
    required this.title,
    required this.description,
    required this.icon,
    this.actionLabel,
    this.onAction,
  });
}

class ConnectionTroubleshootScreen extends ConsumerStatefulWidget {
  const ConnectionTroubleshootScreen({super.key});

  @override
  ConsumerState<ConnectionTroubleshootScreen> createState() =>
      _ConnectionTroubleshootScreenState();
}

class _ConnectionTroubleshootScreenState
    extends ConsumerState<ConnectionTroubleshootScreen> {
  late List<_DiagStep> _steps;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _steps = _buildSteps();
  }

  List<_DiagStep> _buildSteps() {
    final isEn = S.isEn;
    return [
      _DiagStep(
        title: isEn ? 'Bluetooth is ON' : 'Bluetooth Aktif',
        description: isEn
            ? 'Hardware Bluetooth must be enabled.'
            : 'Bluetooth hardware harus dinyalakan.',
        icon: Icons.bluetooth_rounded,
        actionLabel: isEn ? 'Open Settings' : 'Buka Settings',
        onAction: () => BluetoothSettingsHelper.openBluetoothSettings(),
      ),
      _DiagStep(
        title: isEn ? 'Permissions granted' : 'Permission diberikan',
        description: isEn
            ? 'Bluetooth Connect + Location must be allowed.'
            : 'Bluetooth Connect + Lokasi harus diizinkan.',
        icon: Icons.lock_outline_rounded,
        actionLabel: isEn ? 'Grant' : 'Izinkan',
        onAction: () async {
          await Permission.bluetoothConnect.request();
          await Permission.locationWhenInUse.request();
          await _runCheck(1);
        },
      ),
      _DiagStep(
        title: isEn ? 'Printer paired' : 'Printer sudah paired',
        description: isEn
            ? 'Your printer must be paired in Android Bluetooth settings.'
            : 'Printer harus sudah di-pair di Bluetooth Settings Android.',
        icon: Icons.print_rounded,
        actionLabel: isEn ? 'Scan' : 'Pindai',
        onAction: () => _runCheck(2),
      ),
      _DiagStep(
        title: isEn ? 'Connection test' : 'Tes koneksi',
        description: isEn
            ? 'Try to reach the selected printer.'
            : 'Coba hubungi printer yang dipilih.',
        icon: Icons.wifi_rounded,
        actionLabel: isEn ? 'Retry' : 'Coba lagi',
        onAction: () => _runCheck(3),
      ),
    ];
  }

  Future<void> _runCheck(int index) async {
    setState(() => _steps[index].status = _StepStatus.checking);
    final result = await _check(index);
    if (!mounted) return;
    setState(() => _steps[index].status = result);
  }

  Future<_StepStatus> _check(int index) async {
    switch (index) {
      case 0:
        return await BluetoothScanHelper.isBluetoothEnabled()
            ? _StepStatus.ok
            : _StepStatus.fail;
      case 1:
        final bt = await Permission.bluetoothConnect.status;
        final loc = await Permission.locationWhenInUse.status;
        return (bt.isGranted && loc.isGranted) ? _StepStatus.ok : _StepStatus.fail;
      case 2:
        final config = ref.read(printerConfigProvider);
        final printer = config.printer;
        if (printer == null) return _StepStatus.fail;
        final devices = await BluetoothScanHelper.getPairedDevices();
        return devices.any((d) =>
                d.mac.toUpperCase() == printer.address.toUpperCase())
            ? _StepStatus.ok
            : _StepStatus.fail;
      case 3:
        final config = ref.read(printerConfigProvider);
        final printer = config.printer;
        if (printer == null) return _StepStatus.fail;
        final bt = ref.read(bluetoothServiceProvider);
        return await bt.checkConnection() ? _StepStatus.ok : _StepStatus.fail;
    }
    return _StepStatus.fail;
  }

  Future<void> _runAll() async {
    if (_running) return;
    setState(() => _running = true);
    for (var i = 0; i < _steps.length; i++) {
      if (!mounted) break;
      await _runCheck(i);
    }
    if (!mounted) return;
    setState(() => _running = false);
    final allOk = _steps.every((s) => s.status == _StepStatus.ok);
    if (allOk) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(S.isEn
            ? 'All checks passed. Connection looks healthy.'
            : 'Semua cek berhasil. Koneksi terlihat sehat.'),
        backgroundColor: const Color(0xFF06C270),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(S.isEn ? 'Connection Troubleshoot' : 'Troubleshoot Koneksi',
            style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Row(children: [
              Icon(Icons.info_outline_rounded,
                  color: Colors.blue.shade700, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  S.isEn
                      ? 'Diagnose printer connection step-by-step. Run all checks at once or tap each card to retry.'
                      : 'Diagnosa koneksi printer langkah demi langkah. Jalankan semua cek sekaligus atau tap kartu untuk coba lagi.',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          ...List.generate(_steps.length, (i) => _buildStepCard(i)),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _running ? null : _runAll,
              icon: _running
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.play_arrow_rounded, size: 20),
              label: Text(
                S.isEn ? 'Run All Checks' : 'Jalankan Semua Cek',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2BBCC4),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepCard(int index) {
    final step = _steps[index];
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          _statusIcon(step.status),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(step.title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 14)),
                const SizedBox(height: 2),
                Text(step.description,
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade600)),
              ],
            ),
          ),
          if (step.actionLabel != null)
            TextButton(
              onPressed: () {
                if (step.status == _StepStatus.checking) return;
                step.onAction?.call();
              },
              child: Text(step.actionLabel!,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
        ]),
      ),
    );
  }

  Widget _statusIcon(_StepStatus status) {
    final map = {
      _StepStatus.pending: (Icons.circle_outlined, Colors.grey.shade400),
      _StepStatus.checking:
          (Icons.hourglass_top_rounded, Colors.orange.shade600),
      _StepStatus.ok: (Icons.check_circle_rounded, const Color(0xFF06C270)),
      _StepStatus.fail: (Icons.error_rounded, const Color(0xFFFF3B30)),
    };
    final (icon, color) = map[status]!;
    if (status == _StepStatus.checking) {
      return SizedBox(
        width: 28,
        height: 28,
        child: CircularProgressIndicator(
            strokeWidth: 2.5, color: color),
      );
    }
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: color, size: 20),
    );
  }
}