import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import '../utils/constants.dart';

/// Bluetooth connection state
enum BluetoothConnectionState {
  disconnected,
  connecting,
  connected,
  error,
}

/// Bluetooth service dengan error handling dan retry mechanism
class SdrBluetoothService {
  BluetoothConnectionState _state = BluetoothConnectionState.disconnected;
  String? _lastAddress;
  String? _lastError;
  DateTime? _lastConnectedAt;

  static const int _maxRetryAttempts = 3;
  static const Duration _retryDelay = Duration(milliseconds: 500);

  BluetoothConnectionState get state => _state;
  bool get isConnected => _state == BluetoothConnectionState.connected;
  String? get lastAddress => _lastAddress;
  String? get lastError => _lastError;
  DateTime? get lastConnectedAt => _lastConnectedAt;

  /// Check if Bluetooth is enabled
  Future<bool> isBluetoothEnabled() async {
    try {
      return await PrintBluetoothThermal.bluetoothEnabled;
    } catch (e) {
      debugPrint('[SDR-BT] isBluetoothEnabled error: $e');
      return false;
    }
  }

  /// Get paired Bluetooth devices
  Future<List<BluetoothInfo>> getPairedDevices() async {
    try {
      final bool enabled = await PrintBluetoothThermal.bluetoothEnabled;
      if (!enabled) return [];
      return await PrintBluetoothThermal.pairedBluetooths;
    } catch (e) {
      debugPrint('[SDR-BT] getPairedDevices error: $e');
      return [];
    }
  }

  /// Connect to printer with retry mechanism
  Future<bool> connect(String address) async {
    _state = BluetoothConnectionState.connecting;
    _lastError = null;

    for (int attempt = 1; attempt <= _maxRetryAttempts; attempt++) {
      try {
        debugPrint('[SDR-BT] Connect attempt $attempt/$_maxRetryAttempts to $address');

        // Disconnect first if already connected
        if (_state == BluetoothConnectionState.connected) {
          await disconnect();
          await Future.delayed(const Duration(milliseconds: 200));
        }

        final result = await PrintBluetoothThermal.connect(
          macPrinterAddress: address,
        ).timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            debugPrint('[SDR-BT] Connect timeout');
            return false;
          },
        );

        if (result) {
          _state = BluetoothConnectionState.connected;
          _lastAddress = address;
          _lastConnectedAt = DateTime.now();
          debugPrint('[SDR-BT] Connected successfully to $address');
          return true;
        }

        if (attempt < _maxRetryAttempts) {
          debugPrint('[SDR-BT] Attempt $attempt failed, retrying...');
          await Future.delayed(_retryDelay * attempt);
        }
      } catch (e) {
        _lastError = e.toString();
        debugPrint('[SDR-BT] Connect attempt $attempt exception: $e');
        if (attempt < _maxRetryAttempts) {
          await Future.delayed(_retryDelay * attempt);
        }
      }
    }

    _state = BluetoothConnectionState.error;
    debugPrint('[SDR-BT] Failed to connect after $_maxRetryAttempts attempts');
    return false;
  }

  /// Disconnect from printer
  Future<void> disconnect() async {
    try {
      await PrintBluetoothThermal.disconnect;
      debugPrint('[SDR-BT] Disconnected');
    } catch (e) {
      debugPrint('[SDR-BT] Disconnect error: $e');
    }
    _state = BluetoothConnectionState.disconnected;
  }

  /// Check current connection status
  Future<bool> checkConnection() async {
    try {
      final status = await PrintBluetoothThermal.connectionStatus;
      _state = status ? BluetoothConnectionState.connected : BluetoothConnectionState.disconnected;
      return status;
    } catch (e) {
      debugPrint('[SDR-BT-j] checkConnection error: $e');
      _state = BluetoothConnectionState.error;
      return false;
    }
  }

  /// Send raw bytes to printer with auto-reconnect
  Future<bool> sendRaw(Uint8List data) async {
    // First check connection status
    await checkConnection();

    // Auto-reconnect if disconnected but we have a last address
    if (_state != BluetoothConnectionState.connected && _lastAddress != null) {
      debugPrint('[SDR-BT] Auto-reconnecting to $_lastAddress...');
      final reconnectOk = await connect(_lastAddress!);
      if (!reconnectOk) {
        debugPrint('[SDR-BT] Auto-reconnect failed');
        return false;
      }
    }

    if (_state != BluetoothConnectionState.connected) {
      debugPrint('[SDR-BT] NOT connected, aborting send');
      return false;
    }

    try {
      final List<int> bytes = data.toList();
      debugPrint('[SDR-BT] Sending ${bytes.length} bytes...');

      // Small delay before sending
      await Future.delayed(const Duration(milliseconds: AppConstants.reconnectDelayMs));

      bool ok = await PrintBluetoothThermal.writeBytes(bytes).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          debugPrint('[SDR-BT] writeBytes timeout');
          return false;
        },
      );

      if (!ok) {
        debugPrint('[SDR-BT] FAILED to send data');
        _state = BluetoothConnectionState.error;
        return false;
      }

      debugPrint('[SDR-BT] All ${bytes.length} bytes sent successfully');
      return true;
    } catch (e) {
      debugPrint('[SDR-BT] sendRaw exception: $e');
      _lastError = e.toString();
      _state = BluetoothConnectionState.error;
      return false;
    }
  }

  /// Send text to printer
  Future<bool> sendText(String text) async {
    if (!isConnected) return false;
    try {
      final result = await PrintBluetoothThermal.writeString(
        printText: PrintTextSize(size: 1, text: '$text\n'),
      );
      return result;
    } catch (e) {
      debugPrint('[SDR-BT] sendText error: $e');
      _lastError = e.toString();
      _state = BluetoothConnectionState.error;
      return false;
    }
  }

  /// Reset state
  void reset() {
    _state = BluetoothConnectionState.disconnected;
    _lastError = null;
  }
}
