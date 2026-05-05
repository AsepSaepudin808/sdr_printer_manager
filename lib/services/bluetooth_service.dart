import 'package:flutter/foundation.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

class SdrBluetoothService {
  bool _isConnected = false;
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
    try {
      _isConnected = await PrintBluetoothThermal.connectionStatus;
      debugPrint('[SDR-BT] connectionStatus: $_isConnected');
    } catch (e) {
      debugPrint('[SDR-BT] connectionStatus error: $e');
      _isConnected = false;
    }

    if (!_isConnected && _lastAddress != null) {
      debugPrint('[SDR-BT] Auto-reconnecting to $_lastAddress...');
      try {
        _isConnected = await PrintBluetoothThermal.connect(
          macPrinterAddress: _lastAddress!,
        );
        debugPrint('[SDR-BT] reconnect result: $_isConnected');
      } catch (e) {
        debugPrint('[SDR-BT] reconnect error: $e');
        _isConnected = false;
      }
    }

    if (!_isConnected) {
      debugPrint('[SDR-BT] NOT connected, aborting send');
      return false;
    }

    try {
      final List<int> bytes = data.toList();
      debugPrint('[SDR-BT] Sending ${bytes.length} bytes...');

      await Future.delayed(const Duration(milliseconds: 200));

      if (bytes.length <= 512) {
        final ok = await PrintBluetoothThermal.writeBytes(bytes);
        debugPrint('[SDR-BT] Direct write result: $ok');
        if (!ok) _isConnected = false;
        return ok;
      }

      const chunkSize = 512;
      int sent = 0;
      for (int i = 0; i < bytes.length; i += chunkSize) {
        final end =
            (i + chunkSize < bytes.length) ? i + chunkSize : bytes.length;
        final chunk = bytes.sublist(i, end);

        bool ok = false;
        for (int retry = 0; retry < 3 && !ok; retry++) {
          if (retry > 0) {
            debugPrint('[SDR-BT] Retry $retry for chunk at offset $i');
            await Future.delayed(const Duration(milliseconds: 300));
          }
          ok = await PrintBluetoothThermal.writeBytes(chunk);
        }
        if (!ok) {
          debugPrint('[SDR-BT] FAILED at offset $i after 3 retries');
          _isConnected = false;
          return false;
        }
        sent += chunk.length;
        await Future.delayed(const Duration(milliseconds: 120));
      }
      debugPrint('[SDR-BT] All $sent bytes sent successfully');
      return true;
    } catch (e) {
      debugPrint('[SDR-BT] sendRaw exception: $e');
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
