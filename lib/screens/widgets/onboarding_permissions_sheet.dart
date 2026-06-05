import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../services/foreground_service_helper.dart';
import '../../utils/strings.dart';

/// Bottom sheet onboarding permission.
/// Muncul hanya jika ada permission yang belum diberikan.
/// Menggunakan permission_handler sesuai best practice:
/// - cek status sebelum request
/// - handle isPermanentlyDenied dengan openAppSettings()
/// - tidak double-request permission yang sudah granted
class OnboardingPermissionsSheet extends StatefulWidget {
  final VoidCallback? onComplete;
  const OnboardingPermissionsSheet({super.key, this.onComplete});

  @override
  State<OnboardingPermissionsSheet> createState() =>
      _OnboardingPermissionsSheetState();
}

class _OnboardingPermissionsSheetState
    extends State<OnboardingPermissionsSheet> {
  static const _primary = Color(0xFF2BBCC4);

  bool _bluetoothGranted = false;
  bool _locationGranted = false;
  bool _notificationGranted = false;
  bool _batteryGranted = false;
  bool _autoStartAcknowledged = false;

  // Track permanently denied untuk tampilkan hint buka settings
  bool _bluetoothPermanent = false;
  bool _locationPermanent = false;
  bool _notificationPermanent = false;

  @override
  void initState() {
    super.initState();
    _checkAll();
  }

  Future<void> _checkAll() async {
    // Cek status semua permission sekaligus tanpa meminta dulu
    final btStatus = await Permission.bluetoothConnect.status;
    final locStatus = await Permission.locationWhenInUse.status;
    final notifStatus = await Permission.notification.status;
    final batteryGranted =
        await ForegroundServiceHelper.isIgnoringBatteryOptimizations();
    final autoStartAck =
        await ForegroundServiceHelper.isAutoStartAcknowledged();

    if (!mounted) return;
    setState(() {
      _bluetoothGranted = btStatus.isGranted;
      _locationGranted = locStatus.isGranted;
      _notificationGranted = notifStatus.isGranted;
      _batteryGranted = batteryGranted;
      _autoStartAcknowledged = autoStartAck;

      _bluetoothPermanent = btStatus.isPermanentlyDenied;
      _locationPermanent = locStatus.isPermanentlyDenied;
      _notificationPermanent = notifStatus.isPermanentlyDenied;
    });
  }

  /// Request semua permission sekaligus.
  /// permission_handler menampilkan dialog OS per permission secara otomatis.
  Future<void> _grantAll() async {
    // Kumpulkan hanya permission yang belum granted
    final toRequest = <Permission>[];
    if (!_bluetoothGranted) {
      toRequest.addAll([Permission.bluetoothConnect, Permission.bluetoothScan]);
    }
    if (!_locationGranted) toRequest.add(Permission.locationWhenInUse);
    if (!_notificationGranted) toRequest.add(Permission.notification);

    if (toRequest.isNotEmpty) {
      final results = await toRequest.request();
      if (!mounted) return;
      setState(() {
        if (results.containsKey(Permission.bluetoothConnect)) {
          _bluetoothGranted =
              results[Permission.bluetoothConnect]?.isGranted ?? false;
          _bluetoothPermanent =
              results[Permission.bluetoothConnect]?.isPermanentlyDenied ??
                  false;
        }
        if (results.containsKey(Permission.locationWhenInUse)) {
          _locationGranted =
              results[Permission.locationWhenInUse]?.isGranted ?? false;
          _locationPermanent =
              results[Permission.locationWhenInUse]?.isPermanentlyDenied ??
                  false;
        }
        if (results.containsKey(Permission.notification)) {
          _notificationGranted =
              results[Permission.notification]?.isGranted ?? false;
          _notificationPermanent =
              results[Permission.notification]?.isPermanentlyDenied ?? false;
        }
      });
    }

    // Jika ada yang permanently denied, arahkan ke app settings
    if (_bluetoothPermanent || _locationPermanent || _notificationPermanent) {
      await openAppSettings();
      await Future.delayed(const Duration(milliseconds: 500));
      await _checkAll();
    }
  }

  Future<void> _requestSingle(Permission permission) async {
    final status = await permission.status;

    if (status.isPermanentlyDenied) {
      // Permanently denied — satu-satunya cara adalah buka app settings
      await openAppSettings();
      await Future.delayed(const Duration(milliseconds: 500));
      await _checkAll();
      return;
    }

    final result = await permission.request();
    if (!mounted) return;
    setState(() {
      switch (permission) {
        case Permission.bluetoothConnect:
        case Permission.bluetoothScan:
          _bluetoothGranted = result.isGranted;
          _bluetoothPermanent = result.isPermanentlyDenied;
        case Permission.locationWhenInUse:
          _locationGranted = result.isGranted;
          _locationPermanent = result.isPermanentlyDenied;
        case Permission.notification:
          _notificationGranted = result.isGranted;
          _notificationPermanent = result.isPermanentlyDenied;
        default:
          break;
      }
    });

    // Jika hasil akhirnya permanently denied, langsung arahkan ke settings
    if (result.isPermanentlyDenied) {
      await openAppSettings();
      await Future.delayed(const Duration(milliseconds: 500));
      await _checkAll();
    }
  }

  Future<void> _requestBattery() async {
    final granted =
        await ForegroundServiceHelper.requestIgnoreBatteryOptimizations();
    if (!mounted) return;
    setState(() => _batteryGranted = granted);
    if (!granted) {
      // Cek lagi setelah sedikit delay (beberapa device butuh waktu update status)
      await Future.delayed(const Duration(milliseconds: 800));
      final check =
          await ForegroundServiceHelper.isIgnoringBatteryOptimizations();
      if (mounted) setState(() => _batteryGranted = check);
    }
  }

  Future<void> _openAutoStart() async {
    await ForegroundServiceHelper.openAutoStartSettings();
    await ForegroundServiceHelper.setAutoStartAcknowledged();
    if (!mounted) return;
    setState(() => _autoStartAcknowledged = true);
  }

  bool get _allDone =>
      _bluetoothGranted &&
      _locationGranted &&
      _notificationGranted &&
      _batteryGranted &&
      _autoStartAcknowledged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child:
                  const Icon(Icons.security_rounded, color: _primary, size: 36),
            ),
            const SizedBox(height: 16),
            Text(
              S.permissionOnboardingTitle,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1A1A2E),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _allDone
                  ? S.permissionGranted
                  : 'Berikan izin berikut agar aplikasi berfungsi optimal.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            _permTile(
              icon: Icons.bluetooth_rounded,
              color: const Color(0xFF2196F3),
              title: S.permissionBluetooth,
              subtitle: _bluetoothPermanent
                  ? 'Izin ditolak permanen — ketuk untuk buka Pengaturan Aplikasi'
                  : S.permissionBluetoothDesc,
              granted: _bluetoothGranted,
              isPermanent: _bluetoothPermanent,
              onTap: () => _requestSingle(Permission.bluetoothConnect),
            ),
            const SizedBox(height: 12),
            _permTile(
              icon: Icons.location_on_rounded,
              color: const Color(0xFF4CAF50),
              title: S.permissionLocation,
              subtitle: _locationPermanent
                  ? 'Izin ditolak permanen — ketuk untuk buka Pengaturan Aplikasi'
                  : S.permissionLocationDesc,
              granted: _locationGranted,
              isPermanent: _locationPermanent,
              onTap: () => _requestSingle(Permission.locationWhenInUse),
            ),
            const SizedBox(height: 12),
            _permTile(
              icon: Icons.notifications_rounded,
              color: const Color(0xFFFF9800),
              title: S.permissionNotification,
              subtitle: _notificationPermanent
                  ? 'Izin ditolak permanen — ketuk untuk buka Pengaturan Aplikasi'
                  : S.permissionNotificationDesc,
              granted: _notificationGranted,
              isPermanent: _notificationPermanent,
              onTap: () => _requestSingle(Permission.notification),
            ),
            const SizedBox(height: 12),

            // Battery optimization — menggunakan permission_handler standard
            _permTile(
              icon: Icons.battery_charging_full_rounded,
              color: const Color(0xFF00BCD4),
              title: 'Optimasi Baterai',
              subtitle: 'Agar server cetak tetap aktif saat layar mati',
              granted: _batteryGranted,
              isPermanent: false,
              onTap: _requestBattery,
            ),
            const SizedBox(height: 12),

            // Autostart — manufacturer-specific, tidak bisa dicek via API
            _permTile(
              icon: Icons.power_settings_new_rounded,
              color: const Color(0xFF9C27B0),
              title: S.backgroundPermissionTitle,
              subtitle: _autoStartAcknowledged
                  ? 'Sudah diarahkan ke pengaturan — pastikan diaktifkan'
                  : S.backgroundPermissionDesc,
              granted: _autoStartAcknowledged,
              isPermanent: false,
              onTap: _openAutoStart,
            ),
            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _allDone ? null : _grantAll,
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      _allDone ? const Color(0xFF4CAF50) : _primary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFF4CAF50),
                  disabledForegroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_allDone) ...[
                      const Icon(Icons.check_circle_rounded, size: 20),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      _allDone ? S.permissionGranted : S.permissionGrantAll,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () {
                widget.onComplete?.call();
                Navigator.pop(context);
              },
              child: Text(
                S.permissionSkip,
                style: TextStyle(
                    color: Colors.grey.shade500, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _permTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required bool granted,
    required bool isPermanent,
    required VoidCallback onTap,
  }) {
    final effectiveColor = isPermanent ? Colors.red.shade400 : color;

    return InkWell(
      onTap: granted ? null : onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: granted
              ? color.withValues(alpha: 0.08)
              : isPermanent
                  ? Colors.red.withValues(alpha: 0.05)
                  : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: granted
                ? color.withValues(alpha: 0.3)
                : isPermanent
                    ? Colors.red.withValues(alpha: 0.3)
                    : Colors.grey.shade200,
          ),
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: effectiveColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: effectiveColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                      fontSize: 11,
                      color: isPermanent
                          ? Colors.red.shade600
                          : Colors.grey.shade600),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: granted
                  ? color
                  : isPermanent
                      ? Colors.red.shade400
                      : Colors.grey.shade200,
              shape: BoxShape.circle,
            ),
            child: Icon(
              granted
                  ? Icons.check_rounded
                  : isPermanent
                      ? Icons.settings_rounded
                      : Icons.add_rounded,
              color: (granted || isPermanent)
                  ? Colors.white
                  : Colors.grey.shade500,
              size: 18,
            ),
          ),
        ]),
      ),
    );
  }
}
