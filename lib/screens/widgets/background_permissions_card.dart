import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../services/foreground_service_helper.dart';
import '../../utils/strings.dart';

/// Card peringatan yang muncul di halaman utama jika ada izin background
/// yang belum diberikan. Menggabungkan pengecekan:
/// 1. ignoreBatteryOptimizations (AOSP standar, bisa dicek via permission_handler)
/// 2. AutoStart manufacturer-specific (hanya bisa track via acknowledged flag)
///
/// Card ini TIDAK muncul jika semua sudah oke.
class BackgroundPermissionsCard extends StatefulWidget {
  const BackgroundPermissionsCard({super.key});

  @override
  State<BackgroundPermissionsCard> createState() =>
      _BackgroundPermissionsCardState();
}

class _BackgroundPermissionsCardState extends State<BackgroundPermissionsCard>
    with WidgetsBindingObserver {
  bool _loading = true;
  bool _batteryGranted = false;
  bool _autoStartAcknowledged = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Re-check saat user kembali dari settings
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _check();
    }
  }

  Future<void> _check() async {
    final battery = await Permission.ignoreBatteryOptimizations.isGranted;
    final ack = await ForegroundServiceHelper.isAutoStartAcknowledged();
    if (!mounted) {
      return;
    }
    setState(() {
      _batteryGranted = battery;
      _autoStartAcknowledged = ack;
      _loading = false;
    });
  }

  Future<void> _requestBattery() async {
    final granted =
        await ForegroundServiceHelper.requestIgnoreBatteryOptimizations();
    if (!mounted) {
      return;
    }
    setState(() => _batteryGranted = granted);
    if (!granted) {
      await Future.delayed(const Duration(milliseconds: 800));
      final check = await Permission.ignoreBatteryOptimizations.isGranted;
      if (mounted) {
        setState(() => _batteryGranted = check);
      }
    }
  }

  Future<void> _openAutoStart() async {
    await ForegroundServiceHelper.openAutoStartSettings();
    await ForegroundServiceHelper.setAutoStartAcknowledged();
    if (!mounted) {
      return;
    }
    setState(() => _autoStartAcknowledged = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox.shrink();
    }

    // Tidak tampilkan jika semua sudah oke
    if (_batteryGranted && _autoStartAcknowledged) {
      return const SizedBox.shrink();
    }

    return Column(
      children: [
        if (!_batteryGranted)
          _buildCard(
            icon: Icons.battery_alert_rounded,
            color: const Color(0xFFFF9800),
            bgColor: const Color(0xFFFFF3E0),
            title: 'Optimasi Baterai',
            desc:
                'Aktifkan agar server cetak tidak dimatikan sistem saat background.',
            btnLabel: 'Izinkan',
            onTap: _requestBattery,
          ),
        if (!_batteryGranted && !_autoStartAcknowledged)
          const SizedBox(height: 8),
        if (!_autoStartAcknowledged)
          _buildCard(
            icon: Icons.power_settings_new_rounded,
            color: const Color(0xFF9C27B0),
            bgColor: const Color(0xFFF3E5F5),
            title: S.backgroundPermissionTitle,
            desc: S.backgroundPermissionDesc,
            btnLabel: S.backgroundPermissionBtn,
            onTap: _openAutoStart,
          ),
      ],
    );
  }

  Widget _buildCard({
    required IconData icon,
    required Color color,
    required Color bgColor,
    required String title,
    required String desc,
    required String btnLabel,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1A2E),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                desc,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: Text(
            btnLabel,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ),
      ]),
    );
  }
}
