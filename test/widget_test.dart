import 'package:flutter_test/flutter_test.dart';
import 'package:sdr_printer_manager/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const SdrPrinterApp());
    expect(find.byType(SdrPrinterApp), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
  });
}
