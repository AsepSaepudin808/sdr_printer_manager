import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

/// Service untuk mengelola foreground service di Android.
/// Memastikan app tetap aktif di background, terutama untuk device
/// dengan battery optimization agresif (Xiaomi, MIUI, Samsung, dll)
class ForegroundServiceHelper {
  static const _channel = MethodChannel('id.dretail.sdr_printer_manager/foreground_service');

  /// Start foreground service - menjaga app tetap aktif
  static Future<bool> start() async {
    try {
      final result = await _channel.invokeMethod<bool>('startService');
      debugPrint('[SDR-FG] Foreground service started: $result');
      return result ?? false;
    } catch (e) {
      debugPrint('[SDR-FG] Failed to start foreground service: $e');
      return false;
    }
  }

  /// Stop foreground service
  static Future<bool> stop() async {
    try {
      final result = await _channel.invokeMethod<bool>('stopService');
      debugPrint('[SDR-FG] Foreground service stopped: $result');
      return result ?? false;
    } catch (e) {
      debugPrint('[SDR-FG] Failed to stop foreground service: $e');
      return false;
    }
  }

  /// Open battery optimization settings untuk user
  /// User bisa nonaktifkan battery optimization untuk app ini
  static Future<bool> openBatteryOptimization() async {
    try {
      final result = await _channel.invokeMethod<bool>('openBatteryOptimization');
      return result ?? false;
    } catch (e) {
      debugPrint('[SDR-FG] Failed to open battery optimization: $e');
      return false;
    }
  }
}