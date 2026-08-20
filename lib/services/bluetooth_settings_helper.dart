import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class BluetoothSettingsHelper {
  static const _channel =
      MethodChannel('id.dretail.sdr_printer_manager/settings');

  static Future<bool> openBluetoothSettings() async {
    try {
      return await _channel.invokeMethod<bool>('openBluetoothSettings') ?? false;
    } catch (e) {
      debugPrint('[SDR-BT] openBluetoothSettings error: $e');
      return false;
    }
  }
}
