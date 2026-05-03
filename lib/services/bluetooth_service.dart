import 'dart:typed_data';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

class SdrBluetoothService {
  bool _isConnected  = false;
  String? _lastAddress;

  bool get isConnected => _isConnected;
  String? get lastAddress => _lastAddress;

  Future<List<BluetoothInfo>> getPairedDevices() async {
    try {
      final bool enabled = await PrintBluetoothThermal.bluetoothEnabled;
      if (!enabled) return [];
      return await PrintBluetoothThermal.pairedBluetooths;
    } catch (_) {
      return [];
    }
  }

  Future<bool> connect(String address) async {
    try {
      if (_isConnected) await disconnect();
      final result = await PrintBluetoothThermal.connect(
        macPrinterAddress: address,
      );
      _isConnected = result;
      if (result) _lastAddress = address;
      return result;
    } catch (_) {
      _isConnected = false;
      return false;
    }
  }

  Future<void> disconnect() async {
    try {
      await PrintBluetoothThermal.disconnect;
    } catch (_) {}
    _isConnected = false;
  }

  Future<bool> sendRaw(Uint8List data) async {
    // Cek koneksi aktual
    try {
      _isConnected = await PrintBluetoothThermal.connectionStatus;
    } catch (_) {
      _isConnected = false;
    }

    // Auto reconnect
    if (!_isConnected && _lastAddress != null) {
      try {
        _isConnected = await PrintBluetoothThermal.connect(
          macPrinterAddress: _lastAddress!,
        );
      } catch (_) {
        _isConnected = false;
      }
    }

    if (!_isConnected) return false;

    try {
      // Konversi Uint8List → List<int> sesuai signature plugin
      final List<int> bytes = data.toList();

      const chunkSize = 512;

      if (bytes.length <= chunkSize) {
        // Langsung kirim sebagai List<int>
        return await PrintBluetoothThermal.writeBytes(bytes);
      }

      // Kirim per chunk sebagai List<int>
      for (int i = 0; i < bytes.length; i += chunkSize) {
        final end =
        (i + chunkSize < bytes.length) ? i + chunkSize : bytes.length;
        final chunk = bytes.sublist(i, end); // List<int> langsung
        final ok = await PrintBluetoothThermal.writeBytes(chunk);
        if (!ok) {
          _isConnected = false;
          return false;
        }
        await Future.delayed(const Duration(milliseconds: 30));
      }
      return true;
    } catch (e) {
      _isConnected = false;
      return false;
    }
  }

  Future<bool> sendText(String text) async {
    if (!_isConnected) return false;
    try {
      final result = await PrintBluetoothThermal.writeString(
        printText: PrintTextSize(size: 1, text: '$text\n'),
      );
      return result;
    } catch (_) {
      _isConnected = false;
      return false;
    }
  }

  Future<bool> checkConnection() async {
    try {
      _isConnected = await PrintBluetoothThermal.connectionStatus;
      return _isConnected;
    } catch (_) {
      _isConnected = false;
      return false;
    }
  }
}