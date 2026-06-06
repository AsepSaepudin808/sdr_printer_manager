import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../services/foreground_service_helper.dart';
import '../../utils/strings.dart';

class BackgroundPermissionsCard extends StatefulWidget {
  const BackgroundPermissionsCard({super.key});

  @override
  State<BackgroundPermissionsCard> createState() =>
      _BackgroundPermissionsCardState();
}

class _BackgroundPermissionsCardState extends State<BackgroundPermissionsCard>
    with WidgetsBindingObserver {
  bool _loading = true;

  bool _bluetoothGranted = false;
  bool _locationGranted = false;
  bool _notificationGranted = false;
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _check();
    }
  }

  Future<void> _check() async {
    final bt = await Permission.bluetoothConnect.status;
    final loc = await Permission.locationWhenInUse.status;
    final notif = await Permission.notification.status;
    final battery = await Permission.ignoreBatteryOptimizations.isGranted;
    final autoStart = await ForegroundServiceHelper.isAutoStartAcknowledged();

    if (!mounted) {
      return;
    }
    setState(() {
      _bluetoothGranted = bt.isGranted;
      _locationGranted = loc.isGranted;
      _notificationGranted = notif.isGranted;
      _batteryGranted = battery;
      _autoStartAcknowledged = autoStart;
      _loading = false;
    });
  }

  bool get _allGranted =>
      _bluetoothGranted &&
      _locationGranted &&
      _notificationGranted &&
      _batteryGranted &&
      _autoStartAcknowledged;

  Future<void> _openSheet() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PermissionSheetCompact(onDone: _check),
    );
    await _check();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _allGranted) {
      return const SizedBox.shrink();
    }

    final missingCount = [
      !_bluetoothGranted,
      !_locationGranted,
      !_notificationGranted,
      !_batteryGranted,
      !_autoStartAcknowledged,
    ].where((v) => v).length;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: const Color(0xFFFF9800).withValues(alpha: 0.5)),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFFF9800).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.warning_amber_rounded,
              color: Color(0xFFFF9800), size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$missingCount izin belum diberikan',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1A2E),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _buildMissingList(),
                style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        TextButton(
          onPressed: _openSheet,
          style: TextButton.styleFrom(
            backgroundColor: const Color(0xFFFF9800),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: const Text(
            'Izinkan',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ),
      ]),
    );
  }

  String _buildMissingList() {
    final missing = <String>[];
    if (!_bluetoothGranted) {
      missing.add('Bluetooth');
    }
    if (!_locationGranted) {
      missing.add('Lokasi');
    }
    if (!_notificationGranted) {
      missing.add('Notifikasi');
    }
    if (!_batteryGranted) {
      missing.add('Optimasi Baterai');
    }
    if (!_autoStartAcknowledged) {
      missing.add(S.backgroundPermissionTitle);
    }
    return missing.join(', ');
  }
}

class _PermissionSheetCompact extends StatefulWidget {
  final VoidCallback? onDone;
  const _PermissionSheetCompact({this.onDone});

  @override
  State<_PermissionSheetCompact> createState() =>
      _PermissionSheetCompactState();
}

class _PermissionSheetCompactState extends State<_PermissionSheetCompact>
    with WidgetsBindingObserver {
  static const _primary = Color(0xFF2BBCC4);

  bool _bluetoothGranted = false;
  bool _locationGranted = false;
  bool _notificationGranted = false;
  bool _batteryGranted = false;
  bool _autoStartAcknowledged = false;
  bool _isRequesting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkAll();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAll();
    }
  }

  Future<void> _checkAll() async {
    final bt = await Permission.bluetoothConnect.status;
    final loc = await Permission.locationWhenInUse.status;
    final notif = await Permission.notification.status;
    final battery = await Permission.ignoreBatteryOptimizations.isGranted;
    final autoStart = await ForegroundServiceHelper.isAutoStartAcknowledged();

    if (!mounted) {
      return;
    }
    setState(() {
      _bluetoothGranted = bt.isGranted;
      _locationGranted = loc.isGranted;
      _notificationGranted = notif.isGranted;
      _batteryGranted = battery;
      _autoStartAcknowledged = autoStart;
    });
  }

  Future<void> _grantAll() async {
    if (_isRequesting) {
      return;
    }
    setState(() => _isRequesting = true);

    try {
      final toRequest = <Permission>[];
      if (!_bluetoothGranted) {
        toRequest
            .addAll([Permission.bluetoothConnect, Permission.bluetoothScan]);
      }
      if (!_locationGranted) {
        toRequest.add(Permission.locationWhenInUse);
      }
      if (!_notificationGranted) {
        toRequest.add(Permission.notification);
      }

      if (toRequest.isNotEmpty) {
        final results = await toRequest.request();
        if (!mounted) {
          return;
        }
        setState(() {
          _bluetoothGranted = results[Permission.bluetoothConnect]?.isGranted ??
              _bluetoothGranted;
          _locationGranted = results[Permission.locationWhenInUse]?.isGranted ??
              _locationGranted;
          _notificationGranted = results[Permission.notification]?.isGranted ??
              _notificationGranted;
        });
      }

      if (!_batteryGranted) {
        final status = await Permission.ignoreBatteryOptimizations.request();
        if (mounted) {
          setState(() => _batteryGranted = status.isGranted);
        }
        if (!status.isGranted) {
          await Future.delayed(const Duration(milliseconds: 600));
          final check = await Permission.ignoreBatteryOptimizations.isGranted;
          if (mounted) {
            setState(() => _batteryGranted = check);
          }
        }
      }

      if (!_autoStartAcknowledged) {
        await ForegroundServiceHelper.openAutoStartSettings();
        await ForegroundServiceHelper.setAutoStartAcknowledged();
        if (mounted) {
          setState(() => _autoStartAcknowledged = true);
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isRequesting = false);
      }
      widget.onDone?.call();
    }
  }

  bool get _allDone =>
      _bluetoothGranted &&
      _locationGranted &&
      _notificationGranted &&
      _batteryGranted &&
      _autoStartAcknowledged;

  Widget _tile(String title, bool granted, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: (granted ? color : Colors.grey.shade300)
                .withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon,
              color: granted ? color : Colors.grey.shade400, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: granted ? const Color(0xFF1A1A2E) : Colors.grey.shade600,
            ),
          ),
        ),
        Icon(
          granted ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
          color: granted ? color : Colors.grey.shade400,
          size: 20,
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
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
          const SizedBox(height: 16),
          Text(
            S.permissionOnboardingTitle,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1A1A2E),
            ),
          ),
          const SizedBox(height: 16),
          _tile(S.permissionBluetooth, _bluetoothGranted,
              Icons.bluetooth_rounded, const Color(0xFF2196F3)),
          _tile(S.permissionLocation, _locationGranted,
              Icons.location_on_rounded, const Color(0xFF4CAF50)),
          _tile(S.permissionNotification, _notificationGranted,
              Icons.notifications_rounded, const Color(0xFFFF9800)),
          _tile('Optimasi Baterai', _batteryGranted,
              Icons.battery_charging_full_rounded, const Color(0xFF00BCD4)),
          _tile(S.backgroundPermissionTitle, _autoStartAcknowledged,
              Icons.power_settings_new_rounded, const Color(0xFF9C27B0)),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: (_allDone || _isRequesting) ? null : _grantAll,
              style: ElevatedButton.styleFrom(
                backgroundColor: _allDone ? const Color(0xFF4CAF50) : _primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: _allDone
                    ? const Color(0xFF4CAF50)
                    : _primary.withValues(alpha: 0.6),
                disabledForegroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: _isRequesting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_allDone) ...[
                          const Icon(Icons.check_circle_rounded, size: 18),
                          const SizedBox(width: 6),
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
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              S.permissionSkip,
              style: TextStyle(
                  color: Colors.grey.shade500, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
