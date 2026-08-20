import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/scanned_device.dart';

class BluetoothScanHelper {
  static const _channel =
      MethodChannel('id.dretail.sdr_printer_manager/bluetooth');
  static const _eventChannel =
      EventChannel('id.dretail.sdr_printer_manager/bluetooth_events');

  static Stream<BluetoothDeviceEvent>? _eventStream;

  static Future<List<ScannedDevice>> getPairedDevices() async {
    try {
      final result = await _channel.invokeMethod<List<dynamic>>('getPairedDevices');
      if (result == null) return const [];
      return result
          .whereType<Map<dynamic, dynamic>>()
          .map(ScannedDevice.fromMap)
          .toList();
    } catch (e) {
      debugPrint('[SDR-BT] getPairedDevices error: $e');
      return const [];
    }
  }

  static Future<bool> startScan() async {
    try {
      return await _channel.invokeMethod<bool>('startScan') ?? false;
    } catch (e) {
      debugPrint('[SDR-BT] startScan error: $e');
      return false;
    }
  }

  static Future<bool> stopScan() async {
    try {
      return await _channel.invokeMethod<bool>('stopScan') ?? false;
    } catch (e) {
      debugPrint('[SDR-BT] stopScan error: $e');
      return false;
    }
  }

  static Future<bool> pairDevice(String mac) async {
    try {
      return await _channel.invokeMethod<bool>(
        'pairDevice',
        <String, dynamic>{'mac': mac},
      ) ?? false;
    } catch (e) {
      debugPrint('[SDR-BT] pairDevice error: $e');
      return false;
    }
  }

  static Future<bool> unpairDevice(String mac) async {
    try {
      return await _channel.invokeMethod<bool>(
        'unpairDevice',
        <String, dynamic>{'mac': mac},
      ) ?? false;
    } catch (e) {
      debugPrint('[SDR-BT] unpairDevice error: $e');
      return false;
    }
  }

  static Stream<BluetoothDeviceEvent> get events {
    _eventStream ??= _eventChannel
        .receiveBroadcastStream()
        .map((event) {
          if (event is Map) {
            return BluetoothDeviceEvent.fromMap(event);
          }
          return const BluetoothDeviceEvent(type: 'unknown');
        })
        .handleError((Object error) {
          debugPrint('[SDR-BT] event stream error: $error');
        });
    return _eventStream!;
  }
}
