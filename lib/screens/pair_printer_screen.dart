import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/scanned_device.dart';
import '../services/bluetooth_scan_helper.dart';
import '../services/bluetooth_settings_helper.dart';
import '../utils/strings.dart';

class PairPrinterScreen extends ConsumerStatefulWidget {
  const PairPrinterScreen({super.key});

  @override
  ConsumerState<PairPrinterScreen> createState() => _PairPrinterScreenState();
}

class _PairPrinterScreenState extends ConsumerState<PairPrinterScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  List<ScannedDevice> _pairedDevices = [];
  bool _isLoadingPaired = true;
  bool _btEnabled = false;

  // Scan state
  final Map<String, ScannedDevice> _discovered = {};
  final Set<String> _pairingMacs = {};
  bool _isScanning = false;
  StreamSubscription<BluetoothDeviceEvent>? _eventSub;

  late TabController _tabController;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  static const _primary = Color(0xFF2BBCC4);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {});
      }
    });
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabController.dispose();
    _pulseController.dispose();
    _eventSub?.cancel();
    BluetoothScanHelper.stopScan();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshPaired();
      _refreshBtStatus();
    }
  }

  Future<void> _bootstrap() async {
    await _refreshBtStatus();
    await _refreshPaired();
    _subscribeEvents();
  }

  Future<void> _refreshBtStatus() async {
    final enabled = await printBluetoothThermalBluetoothEnabled();
    if (!mounted) return;
    setState(() => _btEnabled = enabled);
  }

  Future<void> _refreshPaired() async {
    final devices = await BluetoothScanHelper.getPairedDevices();
    if (!mounted) return;
    setState(() {
      _pairedDevices = devices;
      _isLoadingPaired = false;
      // Remove from discovered if now paired
      _discovered.removeWhere((mac, d) =>
          devices.any((p) => p.mac.toUpperCase() == mac.toUpperCase()));
    });
  }

  void _subscribeEvents() {
    _eventSub?.cancel();
    _eventSub = BluetoothScanHelper.events.listen((event) {
      if (!mounted) return;
      switch (event.type) {
        case 'found':
          if (event.device != null) {
            final mac = event.device!.mac.toUpperCase();
            final isAlreadyPaired = _pairedDevices
                .any((p) => p.mac.toUpperCase() == mac);
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
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(S.scanCompleteHint),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  margin: const EdgeInsets.all(16),
                ),
              );
            }
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
      await BluetoothScanHelper.stopScan();
      if (!mounted) return;
      setState(() => _isScanning = false);
    } else {
      setState(() {
        _discovered.clear();
        _isScanning = true;
      });
      await BluetoothScanHelper.startScan();
    }
  }

  Future<void> _pair(ScannedDevice device) async {
    setState(() => _pairingMacs.add(device.mac));
    final ok = await BluetoothScanHelper.pairDevice(device.mac);
    if (!ok && mounted) {
      setState(() => _pairingMacs.remove(device.mac));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(S.pairFailed),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  Future<void> _unpair(ScannedDevice device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          const Icon(Icons.warning_amber_rounded,
              color: Color(0xFFFF3B30), size: 24),
          const SizedBox(width: 10),
          Expanded(
              child: Text(S.confirmDeleteTitle,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800))),
        ]),
        content: Text(
          S.confirmDeleteMessage,
          style: const TextStyle(fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(S.cancel, style: TextStyle(color: Colors.grey.shade600)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF3B30),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              elevation: 0,
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
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(S.unpairFailed),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
    await _refreshPaired();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FC),
      appBar: AppBar(
        backgroundColor: _primary,
        foregroundColor: Colors.white,
        title: Text(
          S.pairPrinterTitle,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
        ),
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          tabs: [
            Tab(
              icon: const Icon(Icons.bluetooth_connected_rounded, size: 18),
              iconMargin: const EdgeInsets.only(bottom: 4),
              text: S.tabPaired,
            ),
            Tab(
              icon: const Icon(Icons.bluetooth_searching_rounded, size: 18),
              iconMargin: const EdgeInsets.only(bottom: 4),
              text: S.tabAvailable,
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          _buildStatusCard(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildPairedTab(),
                _buildAvailableTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _btEnabled
              ? [const Color(0xFF034B2F), const Color(0xFF06874F)]
              : [Colors.red.shade700, Colors.red.shade600],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: (_btEnabled ? Colors.green : Colors.red).withValues(alpha: 0.3),
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
                scale: _btEnabled ? _pulseAnimation.value : 1.0,
                child: child,
              );
            },
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                _btEnabled
                    ? Icons.bluetooth_rounded
                    : Icons.bluetooth_disabled_rounded,
                color: Colors.white,
                size: 22,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _btEnabled ? S.bluetoothActive : S.bluetoothInactive,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _btEnabled
                      ? S.withLang(
                          id: '${_pairedDevices.length} tersambung · ${_discovered.length} tersedia',
                          en: '${_pairedDevices.length} paired · ${_discovered.length} available',
                          ms: '${_pairedDevices.length} dipadankan · ${_discovered.length} tersedia',
                        )
                      : S.bluetoothOffHint,
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPairedTab() {
    if (!_btEnabled) {
      return _buildEmptyState(
        icon: Icons.bluetooth_disabled_rounded,
        iconBg: Colors.red.shade50,
        iconColor: Colors.red.shade400,
        title: S.bluetoothInactive,
        subtitle: S.bluetoothOffHint,
        actionLabel: S.openBluetoothSettings,
        onAction: () async {
          await BluetoothSettingsHelper.openBluetoothSettings();
        },
      );
    }
    if (_isLoadingPaired) {
      return Center(
        child: SizedBox(
          width: 40,
          height: 40,
          child: CircularProgressIndicator(strokeWidth: 3, color: _primary),
        ),
      );
    }
    if (_pairedDevices.isEmpty) {
      return _buildEmptyState(
        icon: Icons.print_rounded,
        iconBg: Colors.grey.shade100,
        iconColor: Colors.grey.shade400,
        title: S.noPairedPrinters,
        subtitle: S.tapScanToStart,
        actionLabel: S.tabAvailable,
        onAction: () => _tabController.animateTo(1),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      itemCount: _pairedDevices.length,
      itemBuilder: (_, i) => _buildPairedCard(_pairedDevices[i]),
    );
  }

  Widget _buildAvailableTab() {
    if (!_btEnabled) {
      return _buildEmptyState(
        icon: Icons.bluetooth_disabled_rounded,
        iconBg: Colors.red.shade50,
        iconColor: Colors.red.shade400,
        title: S.bluetoothInactive,
        subtitle: S.bluetoothOffHint,
        actionLabel: S.openBluetoothSettings,
        onAction: () async {
          await BluetoothSettingsHelper.openBluetoothSettings();
        },
      );
    }
    final discoveredList = _discovered.values.toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _isScanning ? S.scanningHint : S.tapScanToStart,
                  style: TextStyle(
                    fontSize: 12,
                    color: _isScanning ? _primary : Colors.grey.shade600,
                    fontWeight: _isScanning ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: _toggleScan,
                icon: _isScanning
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(
                        _isScanning
                            ? Icons.stop_rounded
                            : Icons.bluetooth_searching_rounded,
                        size: 18,
                      ),
                label: Text(_isScanning ? S.stopScan : S.scanDevices),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: discoveredList.isEmpty
              ? _buildEmptyState(
                  icon: Icons.bluetooth_searching_rounded,
                  iconBg: Colors.grey.shade100,
                  iconColor: Colors.grey.shade400,
                  title: S.noAvailablePrinters,
                  subtitle: _isScanning ? S.scanningHint : S.tapScanToStart,
                  actionLabel: S.scanDevices,
                  onAction: _toggleScan,
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  itemCount: discoveredList.length,
                  itemBuilder: (_, i) => _buildAvailableCard(discoveredList[i]),
                ),
        ),
      ],
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String title,
    required String subtitle,
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
            child: Icon(icon, size: 56, color: iconColor),
          ),
          const SizedBox(height: 18),
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
          ),
          const SizedBox(height: 22),
          ElevatedButton.icon(
            onPressed: onAction,
            icon: const Icon(Icons.bluetooth_searching_rounded, size: 18),
            label: Text(actionLabel),
            style: ElevatedButton.styleFrom(
              backgroundColor: _primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPairedCard(ScannedDevice device) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: _primary.withValues(alpha: 0.08),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(11),
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
              child: const Icon(Icons.print_rounded, color: _primary, size: 26),
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
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
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
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.green.shade200),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_circle_rounded,
                                size: 11, color: Colors.green.shade700),
                            const SizedBox(width: 3),
                            Text(
                              S.paired,
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
                  ),
                ],
              ),
            ),
            Material(
              color: Colors.transparent,
              child: IconButton(
                tooltip: S.deletePrinter,
                icon: Icon(Icons.delete_outline_rounded,
                    color: Colors.red.shade400, size: 22),
                onPressed: () => _unpair(device),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvailableCard(ScannedDevice device) {
    final isPairing = _pairingMacs.contains(device.mac);
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
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.bluetooth_rounded,
                  color: Colors.grey.shade600, size: 22),
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
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
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

// Bridge agar helper flutter_bloc/PrintBluetoothThermal dapat dicek status BT.
Future<bool> printBluetoothThermalBluetoothEnabled() async {
  try {
    return await BluetoothScanHelper.isBluetoothEnabled();
  } catch (_) {
    return false;
  }
}