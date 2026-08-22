import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/scanned_device.dart';
import '../services/bluetooth_scan_helper.dart';
import '../services/bluetooth_settings_helper.dart';
import '../utils/strings.dart';

class PrinterScreen extends ConsumerStatefulWidget {
  const PrinterScreen({super.key});

  @override
  ConsumerState<PrinterScreen> createState() => _PrinterScreenState();
}

class _PrinterScreenState extends ConsumerState<PrinterScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  List<ScannedDevice> _pairedDevices = [];
  bool _isLoadingPaired = true;
  bool _btPermissionsGranted = false;
  bool _locationEnabled = false;
  bool _btHardwareEnabled = false;
  String? _activePrinterMac;

  // Scan state
  final Map<String, ScannedDevice> _discovered = {};
  final Set<String> _pairingMacs = {};
  bool _isScanning = false;
  StreamSubscription<BluetoothDeviceEvent>? _eventSub;
  Timer? _scanTimeoutTimer;
  Timer? _pairPollingTimer;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  static const _primary = Color(0xFF2BBCC4);
  static const _danger = Color(0xFFFF3B30);
  static const _bg = Color(0xFFF4F7FC);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pulseController.dispose();
    _eventSub?.cancel();
    _scanTimeoutTimer?.cancel();
    _pairPollingTimer?.cancel();
    BluetoothScanHelper.stopScan();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshAll();
    } else if (state == AppLifecycleState.paused) {
      BluetoothScanHelper.stopScan();
      _scanTimeoutTimer?.cancel();
      if (_isScanning && mounted) {
        setState(() => _isScanning = false);
      }
    }
  }

  Future<void> _bootstrap() async {
    await _checkPermissions();
    await _refreshAll();
    _subscribeEvents();
  }

  Future<void> _checkPermissions() async {
    final btConnect = await Permission.bluetoothConnect.status;
    final location = await Permission.locationWhenInUse.status;
    if (!mounted) return;
    setState(() {
      _btPermissionsGranted = btConnect.isGranted && location.isGranted;
      _locationEnabled = location.isGranted;
    });
  }

  Future<void> _refreshAll() async {
    await Future.wait([
      _refreshBtStatus(),
      _refreshPaired(),
    ]);
  }

  Future<void> _refreshBtStatus() async {
    final btConnect = await Permission.bluetoothConnect.status;
    final location = await Permission.locationWhenInUse.status;
    final hwEnabled = await BluetoothScanHelper.isBluetoothEnabled();
    final prefs = await SharedPreferences.getInstance();
    final activeMac = prefs.getString('printer_address');
    if (!mounted) return;
    setState(() {
      _btPermissionsGranted = btConnect.isGranted && location.isGranted;
      _locationEnabled = location.isGranted;
      _btHardwareEnabled = hwEnabled;
      _activePrinterMac = activeMac?.toUpperCase();
    });
  }

  Future<void> _refreshPaired() async {
    final devices = await BluetoothScanHelper.getPairedDevices();
    if (!mounted) return;
    setState(() {
      _pairedDevices = devices;
      _isLoadingPaired = false;
      _discovered.removeWhere((mac, d) =>
          devices.any((p) => p.mac.toUpperCase() == mac.toUpperCase()));
    });
  }

  void _subscribeEvents() {
    _eventSub?.cancel();
    _eventSub = BluetoothScanHelper.events.listen((event) {
      if (!mounted) return;
      switch (event.type) {
        case 'location_disabled':
          setState(() => _isScanning = false);
          _showLocationRequiredSnackBar();
          break;
        case 'found':
          if (event.device != null) {
            final mac = event.device!.mac.toUpperCase();
            final isAlreadyPaired =
                _pairedDevices.any((p) => p.mac.toUpperCase() == mac);
            if (!isAlreadyPaired) {
              setState(() {
                _discovered[event.device!.mac] = event.device!;
              });
            }
          }
          break;
        case 'discovery_finished':
          if (_isScanning) {
            setState(() => _isScanning = false);
          }
          break;
        case 'bond_state':
          if (event.paired == true) {
            _pairingMacs.remove(event.device?.mac);
            _refreshPaired();
          } else if (event.bondState == BluetoothBondState.none) {
            _pairingMacs.remove(event.device?.mac);
            _refreshPaired();
          }
          break;
      }
    });
  }

  Future<void> _toggleScan() async {
    if (_isScanning) {
      _scanTimeoutTimer?.cancel();
      await BluetoothScanHelper.stopScan();
      if (!mounted) return;
      setState(() => _isScanning = false);
    } else {
      if (!_btPermissionsGranted) {
        _showBtRequiredSnackBar();
        return;
      }
      setState(() {
        _discovered.clear();
        _isScanning = true;
      });
      final started = await BluetoothScanHelper.startScan();
      if (!started && mounted) {
        setState(() => _isScanning = false);
        return;
      }
      // Auto-stop scan after 15 seconds
      _scanTimeoutTimer?.cancel();
      _scanTimeoutTimer = Timer(const Duration(seconds: 15), () {
        if (mounted && _isScanning) {
          BluetoothScanHelper.stopScan();
          if (mounted) setState(() => _isScanning = false);
        }
      });
    }
  }

  void _showBtRequiredSnackBar() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(S.bluetoothRequired),
        behavior: SnackBarBehavior.floating,
        backgroundColor: _danger,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        action: SnackBarAction(
          label: S.openSettings,
          textColor: Colors.white,
          onPressed: () => BluetoothSettingsHelper.openBluetoothSettings(),
        ),
      ),
    );
  }

  void _showLocationRequiredSnackBar() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(S.locationRequiredForScan),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.orange,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        action: SnackBarAction(
          label: S.openSettings,
          textColor: Colors.white,
          onPressed: () {
            BluetoothSettingsHelper.openBluetoothSettings();
          },
        ),
      ),
    );
  }

  Future<void> _pair(ScannedDevice device) async {
    setState(() => _pairingMacs.add(device.mac));
    final ok = await BluetoothScanHelper.pairDevice(device.mac);
    if (!ok && mounted) {
      setState(() => _pairingMacs.remove(device.mac));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(S.pairFailed),
          backgroundColor: _danger,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
      return;
    }

    // Poll paired devices until the new device appears (max 10 seconds).
    // ACTION_BOND_STATE_CHANGED may not reach Flutter on some devices (e.g. Samsung),
    // so we poll getPairedDevices() directly instead.
    int attempts = 0;
    _pairPollingTimer?.cancel();
    _pairPollingTimer =
        Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      attempts++;
      final paired = await BluetoothScanHelper.getPairedDevices();
      final found = paired.any(
        (p) => p.mac.toUpperCase() == device.mac.toUpperCase(),
      );
      if (found || attempts >= 10) {
        timer.cancel();
        setState(() => _pairingMacs.remove(device.mac));
        await _refreshPaired();
        // Reload active printer MAC so badge updates if this printer was selected
        final prefs = await SharedPreferences.getInstance();
        final activeMac = prefs.getString('printer_address');
        if (!mounted) return;
        setState(() => _activePrinterMac = activeMac?.toUpperCase());
        if (!mounted) return;
        final messenger = ScaffoldMessenger.of(context);
        if (found) {
          messenger.showSnackBar(
            SnackBar(
              content: Text('${S.printerSuccessfullyPaired} ${device.name}'),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              margin: const EdgeInsets.all(16),
            ),
          );
        } else {
          messenger.showSnackBar(
            SnackBar(
              content: Text(S.pairFailed),
              backgroundColor: _danger,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              margin: const EdgeInsets.all(16),
            ),
          );
        }
      }
    });
  }

  Future<void> _unpair(ScannedDevice device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: _danger.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.warning_amber_rounded, color: _danger, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              S.confirmDeleteTitle,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              S.confirmDeleteMessage,
              style: const TextStyle(fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: _primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.print_rounded,
                      color: _primary, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        device.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 13),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        device.mac,
                        style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey.shade500,
                            fontFamily: 'monospace'),
                      ),
                    ],
                  ),
                ),
              ]),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child:
                Text(S.cancel, style: TextStyle(color: Colors.grey.shade600)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _danger,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            child: Text(S.deletePrinter,
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final ok = await BluetoothScanHelper.unpairDevice(device.mac);
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${S.printerDeleted} ${device.name}'),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(S.unpairFailed),
          backgroundColor: _danger,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
    await _refreshPaired();
    // Reload active printer MAC in case the unpaired device was active
    final prefs = await SharedPreferences.getInstance();
    final activeMac = prefs.getString('printer_address');
    if (!mounted) return;
    setState(() => _activePrinterMac = activeMac?.toUpperCase());
  }

  Future<void> _refreshPairedDevices() async {
    setState(() => _isLoadingPaired = true);
    await _refreshPaired();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(langProvider);
    return Scaffold(
      backgroundColor: _bg,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          _buildSliverAppBar(),
          SliverToBoxAdapter(child: _buildBluetoothStatusBanner()),
          SliverToBoxAdapter(child: _buildSavedPrintersSection()),
          SliverToBoxAdapter(child: _buildDiscoveredSection()),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  Widget _buildSliverAppBar() {
    return SliverAppBar(
      expandedHeight: 140,
      pinned: true,
      backgroundColor: _primary,
      foregroundColor: Colors.white,
      elevation: 0,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                _primary,
                _primary.withValues(alpha: 0.85),
              ],
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
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.print_rounded,
                            color: Colors.white, size: 28),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              S.printer,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            Text(
                              S.printerManageSubtitle,
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _buildScanButton(),
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

  Widget _buildScanButton() {
    return GestureDetector(
      onTap: _toggleScan,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color:
              _isScanning ? Colors.white.withValues(alpha: 0.2) : Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isScanning)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: _primary,
                ),
              )
            else
              const Icon(Icons.bluetooth_searching_rounded,
                  color: _primary, size: 18),
            const SizedBox(width: 6),
            Text(
              _isScanning ? S.stopScan : S.scan,
              style: TextStyle(
                color: _isScanning ? Colors.white : _primary,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBluetoothStatusBanner() {
    final allReady =
        _btHardwareEnabled && _btPermissionsGranted && _locationEnabled;
    final btOff = !_btHardwareEnabled;

    Color bgStart, bgEnd;
    IconData icon;
    String title;
    String subtitle;

    if (btOff) {
      bgStart = Colors.red.shade700;
      bgEnd = Colors.red.shade600;
      icon = Icons.bluetooth_disabled_rounded;
      title = S.bluetoothInactive;
      subtitle = S.bluetoothScanHint;
    } else if (!allReady) {
      bgStart = Colors.orange.shade700;
      bgEnd = Colors.orange.shade600;
      icon = Icons.bluetooth_rounded;
      title = S.bluetoothNeedsPermission;
      subtitle = S.bluetoothNeedsPermissionDesc;
    } else {
      bgStart = const Color(0xFF034B2F);
      bgEnd = const Color(0xFF06874F);
      icon = Icons.bluetooth_rounded;
      title = S.bluetoothActive;
      subtitle = _activePrinterMac != null
          ? S.printerActiveConnected
          : S.selectPrinterToUse;
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [bgStart, bgEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color:
                (btOff ? Colors.red : (allReady ? Colors.green : Colors.orange))
                    .withValues(alpha: 0.3),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: allReady ? _pulseAnimation.value : 1.0,
                child: child,
              );
            },
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: Colors.white, size: 24),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
          ),
          if (btOff || !allReady)
            TextButton(
              onPressed: () => BluetoothSettingsHelper.openBluetoothSettings(),
              style: TextButton.styleFrom(
                backgroundColor: Colors.white.withValues(alpha: 0.2),
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: Text(S.openSettings,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 12)),
            ),
        ],
      ),
    );
  }

  Widget _buildSavedPrintersSection() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: _primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.bookmark_rounded,
                    color: _primary, size: 18),
              ),
              const SizedBox(width: 10),
              Text(
                S.savedPrinters,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF2C3E50),
                ),
              ),
              const Spacer(),
              if (!_isLoadingPaired && _pairedDevices.isNotEmpty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_pairedDevices.length}',
                    style: const TextStyle(
                      color: _primary,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _refreshPairedDevices,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.refresh_rounded,
                      color: Colors.grey.shade600, size: 18),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_isLoadingPaired)
            _buildLoadingCard()
          else if (_pairedDevices.isEmpty)
            _buildEmptySavedCard()
          else
            ...List.generate(_pairedDevices.length, (i) {
              return _buildSavedPrinterCard(_pairedDevices[i],
                  isLast: i == _pairedDevices.length - 1);
            }),
        ],
      ),
    );
  }

  Widget _buildLoadingCard() {
    return Container(
      padding: const EdgeInsets.all(24),
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
      child: const Center(
        child: SizedBox(
          width: 32,
          height: 32,
          child: CircularProgressIndicator(strokeWidth: 3, color: _primary),
        ),
      ),
    );
  }

  Widget _buildEmptySavedCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.print_rounded,
                size: 40, color: Colors.grey.shade300),
          ),
          const SizedBox(height: 14),
          Text(
            S.noSavedPrinters,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            S.noSavedPrintersDesc,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _toggleScan,
            icon: const Icon(Icons.bluetooth_searching_rounded, size: 18),
            label: Text(S.scan),
            style: ElevatedButton.styleFrom(
              backgroundColor: _primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSavedPrinterCard(ScannedDevice device, {bool isLast = false}) {
    final isActive =
        _activePrinterMac?.toUpperCase() == device.mac.toUpperCase();
    return Container(
      margin: EdgeInsets.only(bottom: isLast ? 0 : 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: _primary.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _showPrinterOptions(device),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        _primary.withValues(alpha: 0.12),
                        _primary.withValues(alpha: 0.05),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Icon(Icons.print_rounded,
                      color: _primary, size: 26),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        device.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: Color(0xFF2C3E50),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              device.mac,
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 10,
                                color: Colors.grey.shade600,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                          if (isActive) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(10),
                                border:
                                    Border.all(color: Colors.green.shade200),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.link_rounded,
                                      size: 11, color: Colors.green.shade700),
                                  const SizedBox(width: 3),
                                  Text(
                                    S.printerConnected,
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.green.shade700,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: S.deletePrinter,
                  icon: Icon(Icons.delete_outline_rounded,
                      color: _danger.withValues(alpha: 0.7), size: 22),
                  onPressed: () => _unpair(device),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showPrinterOptions(ScannedDevice device) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
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
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    _primary.withValues(alpha: 0.1),
                    _primary.withValues(alpha: 0.04),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.print_rounded,
                        color: _primary, size: 30),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          device.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 17,
                            color: Color(0xFF2C3E50),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          device.mac,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _buildOptionTile(
              icon: Icons.link_off_rounded,
              iconBg: _danger.withValues(alpha: 0.1),
              iconColor: _danger,
              label: S.deletePrinter,
              labelColor: _danger,
              onTap: () {
                Navigator.pop(context);
                _unpair(device);
              },
            ),
            const SizedBox(height: 8),
            _buildOptionTile(
              icon: Icons.check_circle_outline_rounded,
              iconBg: Colors.green.shade50,
              iconColor: Colors.green.shade700,
              label: S.close,
              onTap: () => Navigator.pop(context),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionTile({
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String label,
    Color? labelColor,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: iconBg.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 14),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: labelColor ?? const Color(0xFF2C3E50),
                ),
              ),
              const Spacer(),
              Icon(Icons.chevron_right_rounded,
                  color: Colors.grey.shade400, size: 22),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDiscoveredSection() {
    final discoveredList = _discovered.values.toList();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: _primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.wifi_find_rounded,
                    color: _primary.withValues(alpha: 0.8), size: 18),
              ),
              const SizedBox(width: 10),
              Text(
                S.discoveredDevices,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF2C3E50),
                ),
              ),
              const Spacer(),
              if (_isScanning) ...[
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _primary,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  S.scanningHint,
                  style: TextStyle(
                    fontSize: 11,
                    color: _primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ] else if (discoveredList.isNotEmpty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Text(
                    '${discoveredList.length} ${S.found}',
                    style: TextStyle(
                      color: Colors.orange.shade700,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (!_btPermissionsGranted)
            _buildBluetoothWarningCard()
          else if (!_isScanning && discoveredList.isEmpty)
            _buildScanPromptCard()
          else
            ...discoveredList.map((device) {
              final isPairing = _pairingMacs.contains(device.mac);
              return _buildDiscoveredCard(device, isPairing: isPairing);
            }),
        ],
      ),
    );
  }

  Widget _buildBluetoothWarningCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.orange.shade100,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.bluetooth_disabled_rounded,
                color: Colors.orange.shade700, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  S.bluetoothInactive,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: Colors.orange.shade900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  S.bluetoothOffHint,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.orange.shade700,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => BluetoothSettingsHelper.openBluetoothSettings(),
            style: TextButton.styleFrom(
              backgroundColor: Colors.orange.shade100,
              foregroundColor: Colors.orange.shade800,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: Text(S.openSettings,
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildScanPromptCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF6FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFB3DCFF)),
        boxShadow: [
          BoxShadow(
            color: _primary.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: _primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.bluetooth_searching_rounded,
                  size: 44, color: _primary),
            ),
            const SizedBox(height: 16),
            Text(
              S.readyToScan,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1A3A5C),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              S.readyToScanDesc,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Color(0xFF4A6A8A)),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _toggleScan,
              icon: const Icon(Icons.bluetooth_searching_rounded, size: 18),
              label: Text(S.startScan),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiscoveredCard(ScannedDevice device, {bool isPairing = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _primary.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    _primary.withValues(alpha: 0.08),
                    _primary.withValues(alpha: 0.03),
                  ],
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.bluetooth_rounded,
                  color: _primary.withValues(alpha: 0.8), size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    device.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: Color(0xFF2C3E50),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    device.mac,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 36,
              child: ElevatedButton.icon(
                onPressed: isPairing ? null : () => _pair(device),
                icon: isPairing
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.link_rounded, size: 16),
                label: Text(isPairing ? S.pairing : S.pair),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: _primary.withValues(alpha: 0.5),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  textStyle: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
