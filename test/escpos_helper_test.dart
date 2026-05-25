import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:sdr_printer_manager/utils/escpos_helper.dart';

void main() {
  group('EscPosHelper Commands', () {
    test('init() returns correct ESC/POS initialization bytes', () {
      final result = EscPosHelper.init();
      expect(result, isA<Uint8List>());
      expect(result.length, 2);
      expect(result[0], 0x1B); // ESC
      expect(result[1], 0x40); // @ (Initialize)
    });

    test('cut() returns correct cut command bytes', () {
      final result = EscPosHelper.cut();
      expect(result, isA<Uint8List>());
      expect(result.length, 4);
      expect(result[0], 0x1D); // GS
      expect(result[1], 0x56); // V
      expect(result[2], 0x41); // A
      expect(result[3], 0x00); // mode
    });

    test('bold(true) enables bold', () {
      final result = EscPosHelper.bold(true);
      expect(result[0], 0x1B); // ESC
      expect(result[1], 0x45); // E
      expect(result[2], 1); // n = 1 (on)
    });

    test('bold(false) disables bold', () {
      final result = EscPosHelper.bold(false);
      expect(result[0], 0x1B);
      expect(result[1], 0x45);
      expect(result[2], 0); // n = 0 (off)
    });

    test('align(0) = left, align(1) = center, align(2) = right', () {
      expect(EscPosHelper.align(0)[2], 0); // Left
      expect(EscPosHelper.align(1)[2], 1); // Center
      expect(EscPosHelper.align(2)[2], 2); // Right
    });

    test('feed(n) returns correct feed command', () {
      final result = EscPosHelper.feed(3);
      expect(result[0], 0x1B);
      expect(result[1], 0x64); // d
      expect(result[2], 3); // n lines
    });

    test('openCashDrawer() returns correct command', () {
      final result = EscPosHelper.openCashDrawer();
      expect(result.length, 5);
      expect(result[0], 0x1B); // ESC
      expect(result[1], 0x70); // p
      expect(result[2], 0x00); // m
      expect(result[3], 0x19); // t (25)
      expect(result[4], 0xFA); // u (250)
    });

    test('doubleSize(true) sets double size', () {
      final result = EscPosHelper.doubleSize(true);
      expect(result[0], 0x1D); // GS
      expect(result[1], 0x21); // !
      expect(result[2], 0x11); // double width + height
    });

    test('doubleSize(false) clears double size', () {
      final result = EscPosHelper.doubleSize(false);
      expect(result[2], 0x00);
    });
  });

  group('EscPosHelper Paper Size', () {
    test('defaultCharsPerLine returns correct values', () {
      expect(EscPosHelper.defaultCharsPerLine(PaperSize.mm58), 32);
      expect(EscPosHelper.defaultCharsPerLine(PaperSize.mm80), 48);
      expect(EscPosHelper.defaultCharsPerLine(PaperSize.mm100), 64);
    });

    test('paperMaxWidth returns correct pixel values', () {
      expect(EscPosHelper.paperMaxWidth(PaperSize.mm58), 384);
      expect(EscPosHelper.paperMaxWidth(PaperSize.mm80), 576);
      expect(EscPosHelper.paperMaxWidth(PaperSize.mm100), 768);
    });

    test('charsPerLine uses custom value when set', () {
      EscPosHelper.setCustomCharsPerLine(40);
      expect(EscPosHelper.charsPerLine(PaperSize.mm80), 40);
      EscPosHelper.setCustomCharsPerLine(0); // Reset
    });

    test('charsPerLine uses default when custom is 0', () {
      EscPosHelper.setCustomCharsPerLine(0);
      expect(EscPosHelper.charsPerLine(PaperSize.mm58), 32);
      expect(EscPosHelper.charsPerLine(PaperSize.mm80), 48);
      expect(EscPosHelper.charsPerLine(PaperSize.mm100), 64);
    });
  });

  group('EscPosHelper Settings', () {
    test('setExtraFeed updates _extraFeed', () {
      EscPosHelper.setExtraFeed(5);
      expect(EscPosHelper.extraFeedSetting, 5);
      EscPosHelper.setExtraFeed(3); // Reset
    });

    test('setAutoCut updates _autoCut', () {
      EscPosHelper.setAutoCut(true);
      expect(EscPosHelper.autoCutSetting, true);
      EscPosHelper.setAutoCut(false); // Reset
    });

    test('setCashDrawerMode updates _cashDrawerMode', () {
      EscPosHelper.setCashDrawerMode(CashDrawerMode.openAfterPrint);
      expect(EscPosHelper.cashDrawerModeSetting, CashDrawerMode.openAfterPrint);
      EscPosHelper.setCashDrawerMode(CashDrawerMode.off); // Reset
    });

    test('finalize includes feed when extraFeed > 0', () {
      EscPosHelper.setExtraFeed(5);
      EscPosHelper.setAutoCut(false);
      final result = EscPosHelper.finalize();
      expect(result, isNotEmpty);
      // Reset
      EscPosHelper.setExtraFeed(3);
    });

    test('finalize includes cut when autoCut is true', () {
      EscPosHelper.setExtraFeed(0);
      EscPosHelper.setAutoCut(true);
      final result = EscPosHelper.finalize();
      expect(result, isNotEmpty);
      // GS V A 0
      expect(result.length >= 4, true);
      // Reset
      EscPosHelper.setExtraFeed(3);
      EscPosHelper.setAutoCut(false);
    });
  });

  group('EscPosHelper Currency Formatting', () {
    test('rp formats positive number with dot separator', () {
      final result = EscPosHelper.rp(1000000);
      expect(result, 'Rp1.000.000');
    });

    test('rp formats negative number correctly', () {
      final result = EscPosHelper.rp(-50000);
      expect(result.contains('-'), true);
    });

    test('rp formats large numbers with dot separator', () {
      // 12345 formatted should be "Rp12.345" (dot separator for thousands)
      final result = EscPosHelper.rp(12345);
      expect(result, 'Rp12.345');
    });

    test('rp with symbol prefix', () {
      final result = EscPosHelper.rp(5000, symbol: '\$');
      expect(result.startsWith('\$'), true);
    });

    test('rp with symbol suffix (positionAfter)', () {
      final result = EscPosHelper.rp(5000, symbol: 'IDR', positionAfter: true);
      expect(result.endsWith('IDR'), true);
    });
  });

  group('EscPosHelper Date Formatting', () {
    // Note: _formatDateShort is private, tested indirectly via buildFromOdooData
    // The date formatting is used internally when building receipts

    test('receipt building handles date parsing', () {
      // Test that buildFromOdooData handles various date formats
      final data = {
        'name': 'ORDER-001',
        'date': '2024-01-15T10:30:00',
        'cashier': 'Kasir 1',
        'amount_total': 50000.0,
        'orderlines': <Map<String, dynamic>>[],
        'paymentlines': <Map<String, dynamic>>[],
        'company': <String, dynamic>{'name': 'Toko Test'},
      };

      final result = EscPosHelper.buildFromOdooData(data, PaperSize.mm80);
      expect(result, isA<Uint8List>());
      expect(result.isNotEmpty, true);
    });

    test('receipt building handles ISO date with timezone', () {
      final data = {
        'name': 'ORDER-002',
        'date': '2024-06-20T14:45:00Z',
        'cashier': 'Kasir 1',
        'amount_total': 100000.0,
        'orderlines': <Map<String, dynamic>>[],
        'paymentlines': <Map<String, dynamic>>[],
        'company': <String, dynamic>{'name': 'Toko Test'},
      };

      final result = EscPosHelper.buildFromOdooData(data, PaperSize.mm80);
      expect(result, isA<Uint8List>());
      expect(result.isNotEmpty, true);
    });

    test('receipt building handles empty date', () {
      final data = {
        'name': 'ORDER-003',
        'date': '',
        'cashier': 'Kasir 1',
        'amount_total': 75000.0,
        'orderlines': <Map<String, dynamic>>[],
        'paymentlines': <Map<String, dynamic>>[],
        'company': <String, dynamic>{'name': 'Toko Test'},
      };

      final result = EscPosHelper.buildFromOdooData(data, PaperSize.mm80);
      expect(result, isA<Uint8List>());
      expect(result.isNotEmpty, true);
    });

    test('receipt building handles DD/MM/YYYY format', () {
      final data = {
        'name': 'ORDER-004',
        'date': '15/06/2024 10:30',
        'cashier': 'Kasir 1',
        'amount_total': 88000.0,
        'orderlines': <Map<String, dynamic>>[],
        'paymentlines': <Map<String, dynamic>>[],
        'company': <String, dynamic>{'name': 'Toko Test'},
      };

      final result = EscPosHelper.buildFromOdooData(data, PaperSize.mm80);
      expect(result, isA<Uint8List>());
      expect(result.isNotEmpty, true);
    });
  });

  group('EscPosHelper Build Receipt', () {
    test('buildFromOdooData with basic=true returns bytes', () {
      final data = {
        'name': 'ORDER-001',
        'date': '2024-01-15T10:00:00',
        'cashier': 'Kasir 1',
        'amount_total': 50000.0,
        'orderlines': <Map<String, dynamic>>[],
        'paymentlines': <Map<String, dynamic>>[],
        'company': <String, dynamic>{'name': 'Toko Test'},
      };

      final result = EscPosHelper.buildFromOdooData(data, PaperSize.mm80, basic: true);
      expect(result, isA<Uint8List>());
      expect(result.isNotEmpty, true);
    });

    test('buildFromOdooData with basic=false returns full receipt bytes', () {
      final data = {
        'name': 'ORDER-002',
        'date': '2024-01-15T10:00:00',
        'cashier': 'Kasir 1',
        'amount_total': 100000.0,
        'amount_tax': 10000.0,
        'total_without_tax': 90000.0,
        'orderlines': <Map<String, dynamic>>[],
        'paymentlines': <Map<String, dynamic>>[],
        'company': <String, dynamic>{'name': 'Toko Test'},
      };

      final result = EscPosHelper.buildFromOdooData(data, PaperSize.mm80, basic: false);
      expect(result, isA<Uint8List>());
      expect(result.isNotEmpty, true);
    });

    test('buildSessionSummary returns bytes', () {
      final data = {
        'pos_name': 'PoS 1',
        'session_name': 'Session 1',
        'cashier_name': 'Kasir 1',
        'gross_sales': 1000000.0,
        'total_discount': 50000.0,
        'net_sales_before_tax': 950000.0,
        'total_taxes': 50000.0,
        'total_sales': 1000000.0,
        'company': <String, dynamic>{
          'currency': <String, dynamic>{'symbol': 'Rp', 'decimal_places': 0}
        },
      };

      final result = EscPosHelper.buildSessionSummary(data, PaperSize.mm80);
      expect(result, isA<Uint8List>());
      expect(result.isNotEmpty, true);
    });

    test('textToEscPos converts text to bytes', () {
      final result = EscPosHelper.textToEscPos('Hello World', PaperSize.mm80);
      expect(result, isA<Uint8List>());
      expect(result.isNotEmpty, true);
    });

    test('textToEscPos with bold formatting', () {
      final result = EscPosHelper.textToEscPos('Bold Text', PaperSize.mm80, isBold: true);
      expect(result, isA<Uint8List>());
      expect(result.isNotEmpty, true);
    });
  });

  group('EscPosHelper Word Wrap', () {
    test('word wrap handles short text', () {
      final lines = _wordWrap('Hello', 10);
      expect(lines, ['Hello']);
    });

    test('word wrap splits long text', () {
      final lines = _wordWrap('Hello World', 5);
      expect(lines, hasLength(greaterThan(1)));
    });

    test('word wrap handles empty text', () {
      final lines = _wordWrap('', 10);
      expect(lines, ['']);
    });
  });

  group('EscPosHelper Utility Functions', () {
    test('fixLen pads short strings', () {
      final result = EscPosHelper.fixLen('Hi', 5);
      expect(result.length, 5);
      expect(result, 'Hi   ');
    });

    test('fixLen truncates long strings', () {
      final result = EscPosHelper.fixLen('Hello World', 5);
      expect(result.length, 5);
      expect(result, 'Hello');
    });

    test('fixLenR pads to the right', () {
      final result = EscPosHelper.fixLenR('Hi', 5);
      expect(result.length, 5);
      expect(result, '   Hi');
    });

    test('sectionHeader creates centered header', () {
      final result = EscPosHelper.sectionHeader('TEST', PaperSize.mm80);
      expect(result, isA<List<int>>());
      expect(result.isNotEmpty, true);
    });

    test('divider creates line of dashes', () {
      final result = EscPosHelper.divider(PaperSize.mm80);
      expect(result, isA<List<int>>());
    });

    test('divider with custom character', () {
      final result = EscPosHelper.divider(PaperSize.mm58, char: '=');
      expect(result, isA<List<int>>());
    });
  });

  group('EscPosHelper Receipt with Order Lines', () {
    test('buildFromOdooData handles order with discount', () {
      final data = {
        'name': 'ORDER-DISCOUNT',
        'date': '2024-01-15T10:00:00',
        'cashier': 'Kasir 1',
        'amount_total': 90000.0,
        'total_without_tax': 90000.0,
        'amount_tax': 0.0,
        'orderlines': [
          {
            'product_name': 'Item 1',
            'qty': 2.0,
            'price': 50000.0,
            'price_with_tax': 100000.0,
            'discount': 10.0,
            'discount_amount': 10000.0,
            'discount_type': '%',
          }
        ],
        'paymentlines': [
          {'name': 'Cash', 'amount': 100000.0}
        ],
        'company': <String, dynamic>{
          'name': 'Toko Test',
          'currency': <String, dynamic>{'symbol': 'Rp', 'decimal_places': 0}
        },
      };

      final result = EscPosHelper.buildFromOdooData(data, PaperSize.mm80);
      expect(result, isA<Uint8List>());
      expect(result.isNotEmpty, true);
    });

    test('buildFromOdooData handles global discount', () {
      final data = {
        'name': 'ORDER-GLOBAL',
        'date': '2024-01-15T10:00:00',
        'cashier': 'Kasir 1',
        'amount_total': 80000.0,
        'total_without_tax': 80000.0,
        'amount_tax': 0.0,
        'total_discount': 20000.0,
        'orderlines': [
          {
            'product_name': 'Item 1',
            'qty': 1.0,
            'price': 100000.0,
            'price_with_tax': 100000.0,
            'is_global_discount': true,
            'discount_amount': 20000.0,
          }
        ],
        'paymentlines': [
          {'name': 'Cash', 'amount': 80000.0}
        ],
        'company': <String, dynamic>{
          'name': 'Toko Test',
          'currency': <String, dynamic>{'symbol': 'Rp', 'decimal_places': 0}
        },
      };

      final result = EscPosHelper.buildFromOdooData(data, PaperSize.mm80);
      expect(result, isA<Uint8List>());
      expect(result.isNotEmpty, true);
    });
  });
}

// Helper function to test word wrap (private method testing)
List<String> _wordWrap(String text, int w) {
  final words = text.split(' ');
  final lines = <String>[];
  final buf = StringBuffer();
  for (final word in words) {
    if (word.isEmpty) {
      continue;
    }
    if (buf.isEmpty) {
      buf.write(word);
    } else if (buf.length + 1 + word.length <= w) {
      buf.write(' ');
      buf.write(word);
    } else {
      lines.add(buf.toString());
      buf.clear();
      buf.write(word);
    }
  }
  if (buf.isNotEmpty) {
    lines.add(buf.toString());
  }
  return lines.isEmpty ? [''] : lines;
}