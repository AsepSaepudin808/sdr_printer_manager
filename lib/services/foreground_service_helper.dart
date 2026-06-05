import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

/// Helper untuk mengelola foreground service dan permission background
/// yang bersifat manufacturer-specific (tidak tersedia di Android AOSP standar).
class ForegroundServiceHelper {
  static const _channel =
      MethodChannel('id.dretail.sdr_printer_manager/foreground_service');

  /// Start foreground service.
  static Future<bool> start() async {
    try {
      return await _channel.invokeMethod<bool>('startService') ?? false;
    } catch (e) {
      debugPrint('[SDR-FG] start error: $e');
      return false;
    }
  }

  /// Stop foreground service.
  static Future<bool> stop() async {
    try {
      return await _channel.invokeMethod<bool>('stopService') ?? false;
    } catch (e) {
      debugPrint('[SDR-FG] stop error: $e');
      return false;
    }
  }

  /// Cek status permission ignoreBatteryOptimizations menggunakan
  /// permission_handler (lebih reliable daripada MethodChannel langsung).
  static Future<bool> isIgnoringBatteryOptimizations() async {
    try {
      return await Permission.ignoreBatteryOptimizations.isGranted;
    } catch (e) {
      debugPrint('[SDR-FG] isIgnoringBatteryOptimizations error: $e');
      return false;
    }
  }

  /// Request permission ignoreBatteryOptimizations melalui permission_handler.
  /// Menampilkan dialog sistem Android untuk exclude app dari battery optimization.
  /// Returns true jika granted.
  static Future<bool> requestIgnoreBatteryOptimizations() async {
    try {
      final status = await Permission.ignoreBatteryOptimizations.request();
      return status.isGranted;
    } catch (e) {
      debugPrint('[SDR-FG] requestIgnoreBatteryOptimizations error: $e');
      return false;
    }
  }

  /// Cek apakah user sudah pernah diarahkan ke pengaturan autostart manufacturer.
  /// Autostart (Xiaomi MIUI, Samsung, Oppo, dll) adalah fitur manufacturer-specific
  /// yang TIDAK bisa dibaca via Android API manapun — tidak ada API standarnya.
  /// Solusinya: simpan flag di SharedPreferences native setelah user buka settings.
  static Future<bool> isAutoStartAcknowledged() async {
    try {
      return await _channel.invokeMethod<bool>('isAutoStartAcknowledged') ??
          false;
    } catch (e) {
      debugPrint('[SDR-FG] isAutoStartAcknowledged error: $e');
      return false;
    }
  }

  /// Simpan flag bahwa user sudah diarahkan ke pengaturan autostart.
  static Future<bool> setAutoStartAcknowledged() async {
    try {
      return await _channel.invokeMethod<bool>('setAutoStartAcknowledged') ??
          false;
    } catch (e) {
      debugPrint('[SDR-FG] setAutoStartAcknowledged error: $e');
      return false;
    }
  }

  /// Buka halaman autostart khusus per manufacturer (Xiaomi, Samsung, Oppo, dll).
  /// Fallback ke App Info jika device tidak dikenali.
  static Future<bool> openAutoStartSettings() async {
    try {
      return await _channel.invokeMethod<bool>('openAutoStartSettings') ??
          false;
    } catch (e) {
      debugPrint('[SDR-FG] openAutoStartSettings error: $e');
      return false;
    }
  }
}
