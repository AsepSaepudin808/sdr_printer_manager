import 'dart:typed_data';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

class SdrBluetoothService {
  bool _isConnected = false;

  bool get isConnected => _isConnected;

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
    if (!_isConnected) return false;
    try {
      final result = await PrintBluetoothThermal.writeBytes(data);
      return result;
    } catch (_) {
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