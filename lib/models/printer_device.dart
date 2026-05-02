class PrinterDevice {
  final String address;
  final String name;

  const PrinterDevice({required this.address, required this.name});

  @override
  String toString() => '$name ($address)';
}