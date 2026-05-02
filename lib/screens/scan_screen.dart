import 'package:flutter/material.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import '../models/printer_device.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  List<BluetoothInfo> _pairedDevices = [];
  bool _isLoading = true;
  bool _btEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadPairedDevices();
  }

  Future<void> _loadPairedDevices() async {
    setState(() => _isLoading = true);
    try {
      _btEnabled = await PrintBluetoothThermal.bluetoothEnabled;
      if (_btEnabled) {
        final devices = await PrintBluetoothThermal.pairedBluetooths;
        setState(() {
          _pairedDevices = devices;
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pilih Printer Bluetooth'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadPairedDevices,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _btEnabled ? Colors.blue[50] : Colors.red[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _btEnabled
                    ? Colors.blue.shade200
                    : Colors.red.shade200,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      _btEnabled
                          ? Icons.bluetooth
                          : Icons.bluetooth_disabled,
                      color: _btEnabled ? Colors.blue : Colors.red,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _btEnabled
                          ? '📌 Menampilkan perangkat yang sudah dipair'
                          : '⚠️ Bluetooth tidak aktif',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color:
                        _btEnabled ? Colors.black : Colors.red,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _btEnabled
                      ? 'Jika printer belum muncul, pair dulu melalui '
                      'Pengaturan Bluetooth Android, lalu refresh.'
                      : 'Aktifkan Bluetooth di Android terlebih dahulu.',
                  style: const TextStyle(
                      fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
          Expanded(
            child: !_btEnabled
                ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.bluetooth_disabled,
                      size: 60, color: Colors.red),
                  SizedBox(height: 12),
                  Text('Aktifkan Bluetooth terlebih dahulu',
                      style: TextStyle(color: Colors.grey)),
                ],
              ),
            )
                : _pairedDevices.isEmpty
                ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.bluetooth_disabled,
                      size: 60, color: Colors.grey),
                  SizedBox(height: 12),
                  Text('Tidak ada perangkat paired',
                      style:
                      TextStyle(color: Colors.grey)),
                ],
              ),
            )
                : ListView.builder(
              itemCount: _pairedDevices.length,
              itemBuilder: (_, i) {
                final device = _pairedDevices[i];
                return ListTile(
                  leading: const Icon(Icons.print,
                      color: Colors.blue, size: 36),
                  title: Text(
                    device.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    device.macAdress,
                    style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12),
                  ),
                  trailing:
                  const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.pop(
                      context,
                      PrinterDevice(
                        address: device.macAdress,
                        name: device.name,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}