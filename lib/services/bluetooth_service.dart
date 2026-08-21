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

class SdrBluetoothService {
  BluetoothConnectionState _state = BluetoothConnectionState.disconnected;
  String? _lastAddress;
  String? _lastError;
  DateTime? _lastConnectedAt;

  static const int _maxRetryAttempts = 5;
  static const Duration _baseRetryDelay = Duration(milliseconds: 800);
  static const Duration _connectionTimeout = Duration(seconds: 15);
  static const Duration _writeTimeout = Duration(seconds: 30);

  BluetoothConnectionState get state => _state;
  bool get isConnected => _state == BluetoothConnectionState.connected;
  String? get lastAddress => _lastAddress;
  String? get lastError => _lastError;
  DateTime? get lastConnectedAt => _lastConnectedAt;

  Future<bool> isBluetoothEnabled() async {
    try {
      return await PrintBluetoothThermal.bluetoothEnabled;
    } catch (e) {
      debugPrint('[SDR-BT] isBluetoothEnabled error: $e');
      return false;
    }
  }

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

  /// Connect to printer with robust retry mechanism
  Future<bool> connect(String address) async {
    _state = BluetoothConnectionState.connecting;
    _lastError = null;

    for (int attempt = 1; attempt <= _maxRetryAttempts; attempt++) {
      try {
        debugPrint(
            '[SDR-BT] Connect attempt $attempt/$_maxRetryAttempts to $address');

        // Disconnect first if already connected
        if (_state == BluetoothConnectionState.connected) {
          await disconnect();
          await Future.delayed(const Duration(milliseconds: 300));
        }

        // Try to connect with timeout
        final result = await PrintBluetoothThermal.connect(
          macPrinterAddress: address,
        ).timeout(
          _connectionTimeout,
          onTimeout: () {
            debugPrint('[SDR-BT] Connect attempt $attempt timeout');
            return false;
          },
        );

        if (result) {
          _state = BluetoothConnectionState.connected;
          _lastAddress = address;
          _lastConnectedAt = DateTime.now();
          debugPrint(
              '[SDR-BT] Connected successfully to $address on attempt $attempt');
          return true;
        }

        // Calculate delay with exponential backoff
        if (attempt < _maxRetryAttempts) {
          final delay = _baseRetryDelay * attempt;
          debugPrint(
              '[SDR-BT] Attempt $attempt failed, retrying in ${delay.inMilliseconds}ms...');
          await Future.delayed(delay);
        }
      } catch (e) {
        _lastError = e.toString();
        debugPrint('[SDR-BT] Connect attempt $attempt exception: $e');
        if (attempt < _maxRetryAttempts) {
          final delay = _baseRetryDelay * attempt;
          await Future.delayed(delay);
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
      _state = status
          ? BluetoothConnectionState.connected
          : BluetoothConnectionState.disconnected;
      return status;
    } catch (e) {
      debugPrint('[SDR-BT] checkConnection error: $e');
      _state = BluetoothConnectionState.error;
      return false;
    }
  }

  /// Send raw bytes to printer with auto-reconnect and retry
  Future<bool> sendRaw(Uint8List data) async {
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

    // Retry sending data if it fails
    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        debugPrint(
            '[SDR-BT] Sending ${data.length} bytes (attempt $attempt/3)...');

        // Small delay before sending
        await Future.delayed(
            const Duration(milliseconds: AppConstants.reconnectDelayMs));

        bool ok = await PrintBluetoothThermal.writeBytes(data).timeout(
          _writeTimeout,
          onTimeout: () {
            debugPrint('[SDR-BT] writeBytes timeout on attempt $attempt');
            return false;
          },
        );

        if (ok) {
          debugPrint('[SDR-BT] All ${data.length} bytes sent successfully');
          return true;
        }

        debugPrint('[SDR-BT] FAILED to send data on attempt $attempt');
        if (attempt < 3) {
          await Future.delayed(Duration(milliseconds: 200 * attempt));
        }
      } catch (e) {
        debugPrint('[SDR-BT] sendRaw exception on attempt $attempt: $e');
        if (attempt < 3) {
          await Future.delayed(Duration(milliseconds: 200 * attempt));
        }
      }
    }

    _state = BluetoothConnectionState.error;
    debugPrint('[SDR-BT] Failed to send data after 3 attempts');
    return false;
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
