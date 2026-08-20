class ScannedDevice {
  final String mac;
  final String name;

  const ScannedDevice({required this.mac, required this.name});

  factory ScannedDevice.fromMap(Map<dynamic, dynamic> map) {
    return ScannedDevice(
      mac: map['mac'] as String? ?? '',
      name: map['name'] as String? ?? 'Unknown',
    );
  }
}

enum BluetoothBondState { none, bonding, bonded, unknown }

BluetoothBondState parseBondState(String value) {
  switch (value) {
    case 'none':
      return BluetoothBondState.none;
    case 'bonding':
      return BluetoothBondState.bonding;
    case 'bonded':
      return BluetoothBondState.bonded;
    default:
      return BluetoothBondState.unknown;
  }
}

class BluetoothDeviceEvent {
  final String type;
  final ScannedDevice? device;
  final BluetoothBondState? bondState;
  final bool? paired;

  const BluetoothDeviceEvent({
    required this.type,
    this.device,
    this.bondState,
    this.paired,
  });

  factory BluetoothDeviceEvent.fromMap(Map<dynamic, dynamic> map) {
    final type = map['type'] as String? ?? '';
    final mac = map['mac'] as String?;
    final name = map['name'] as String?;
    ScannedDevice? device;
    if (mac != null && mac.isNotEmpty) {
      device = ScannedDevice(
        mac: mac,
        name: name ?? 'Unknown',
      );
    }
    BluetoothBondState? bondState;
    final stateStr = map['state'] as String?;
    if (stateStr != null) {
      bondState = parseBondState(stateStr);
    }
    final paired = map['paired'] as bool?;
    return BluetoothDeviceEvent(
      type: type,
      device: device,
      bondState: bondState,
      paired: paired,
    );
  }
}
extension BluetoothDeviceEventExt on BluetoothDeviceEvent {
  bool get isLocationDisabled => type == 'location_disabled';
}
