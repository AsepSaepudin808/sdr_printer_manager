import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/bluetooth_service.dart';

final bluetoothServiceProvider = Provider<SdrBluetoothService>((ref) {
  return SdrBluetoothService();
});