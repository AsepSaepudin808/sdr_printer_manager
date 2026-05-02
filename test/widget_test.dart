import 'package:flutter_test/flutter_test.dart';
import 'package:sdr_printer_manager/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const SdrPrinterApp());
    expect(find.text('SDR Printer Manager'), findsOneWidget);
  });
}