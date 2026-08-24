import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'package:network_info_plus/network_info_plus.dart';

import 'bluetooth_service.dart';
import '../utils/escpos/escpos_commands.dart';
import '../utils/escpos/escpos_config.dart';
import '../utils/escpos/escpos_receipts.dart';
import '../utils/test_print_template.dart';

class PrintServerService {
  HttpServer? _server;
  SdrBluetoothService? _btService;
  EscPosFormatter? _formatter;

  Function(String)? onLog;
  Function()? onPrintSuccess;
  Function(bool)? onStatusChange;
  Function(String type, String label, bool success, int dataSize)? onPrintJob;

  PaperSize _paperSize = PaperSize.mm58;
  CashDrawerMode _cashDrawerMode = CashDrawerMode.off;
  bool _sessionSummaryCashDrawer = false;
  bool _printQris = true;

  bool get isRunning => _server != null;

  void setPaperSize(PaperSize size) {
    _paperSize = size;
  }

  void setCashDrawerMode(CashDrawerMode mode) {
    _cashDrawerMode = mode;
  }

  void setSessionSummaryCashDrawer(bool value) {
    _sessionSummaryCashDrawer = value;
  }

  void setPrintQris(bool value) {
    _printQris = value;
  }

  Future<String> getLocalIp() async {
    try {
      final info = NetworkInfo();
      final ip = await info.getWifiIP();
      return ip ?? '127.0.0.1';
    } catch (_) {
      return '127.0.0.1';
    }
  }

  Future<void> start({
    required int port,
    required EscPosFormatter formatter,
    required SdrBluetoothService bluetoothService,
    PaperSize paperSize = PaperSize.mm58,
  }) async {
    _btService = bluetoothService;
    _formatter = formatter;
    _paperSize = paperSize;

    final router = Router();

    // STATUS ENDPOINT
    router.get('/status', (Request req) {
      final body = jsonEncode({
        'status': 'ok',
        'server': 'dPrinter Mart',
        'version': '1.0.3',
        'printer_connected': _btService?.isConnected ?? false,
      });
      return Response.ok(body, headers: const {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
      });
    });

    // TEST PRINT ENDPOINT
    router.get('/test-print', (Request req) async {
      final action = req.url.queryParameters['type'] ?? 'test_short';
      final size = _paperSize;

      Uint8List? testData;
      if (action == 'test_short') {
        testData = TestPrintTemplate.buildTestShort(size, _formatter!);
      } else if (action == 'test_long') {
        testData = TestPrintTemplate.buildTestLong(size, _formatter!);
      } else {
        testData = TestPrintTemplate.buildTestShort(size, _formatter!);
      }

      final ok = await _btService?.sendRaw(testData) ?? false;
      if (ok) {
        onLog?.call('Test print berhasil');
        onPrintSuccess?.call();
        onPrintJob?.call('test', 'Test Print ($action)', true, testData.length);
        return Response.ok(
            jsonEncode({'status': 'ok', 'message': 'Test print berhasil'}),
            headers: const {
              'Content-Type': 'application/json',
              'Access-Control-Allow-Origin': '*',
            });
      } else {
        onLog?.call('❌ Test print GAGAL — printer tidak terhubung');
        onPrintJob?.call(
            'test', 'Test Print ($action)', false, testData.length);
        return Response.internalServerError(
            body: jsonEncode(
                {'status': 'error', 'message': 'Printer tidak terhubung'}),
            headers: const {
              'Content-Type': 'application/json',
              'Access-Control-Allow-Origin': '*',
            });
      }
    });

    // QRIS PRINT ENDPOINT
    router.post('/print-qris', (Request req) async {
      if (!_printQris) {
        onLog?.call('QRIS print disabled in settings');
        return Response.ok(
          jsonEncode({'status': 'ok', 'message': 'QRIS print disabled'}),
          headers: const {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
          },
        );
      }

      onLog?.call('📥 Request print QRIS dari Odoo!');

      try {
        final bodyStr = await req.readAsString();
        final Map<String, dynamic> json =
            jsonDecode(bodyStr) as Map<String, dynamic>;

        final qrisData = json['data'] is Map<String, dynamic>
            ? json['data'] as Map<String, dynamic>
            : json;

        final printData = _formatter!.buildQRISReceipt(qrisData, _paperSize);

        final ok = await _btService?.sendRaw(printData) ?? false;
        if (ok) {
          onLog?.call('✅ QRIS receipt printed (${printData.length}B)');
          onPrintSuccess?.call();
          onPrintJob?.call('qris', 'QRIS Receipt', true, printData.length);
          return Response.ok(
            jsonEncode({'status': 'ok', 'message': 'QRIS printed'}),
            headers: const {
              'Content-Type': 'application/json',
              'Access-Control-Allow-Origin': '*',
            },
          );
        } else {
          onLog?.call('❌ Gagal kirim QRIS ke printer');
          onPrintJob?.call('qris', 'QRIS Receipt', false, printData.length);
          return Response.internalServerError(
            body: jsonEncode(
                {'status': 'error', 'message': 'Printer not connected'}),
            headers: const {
              'Content-Type': 'application/json',
              'Access-Control-Allow-Origin': '*',
            },
          );
        }
      } catch (e, st) {
        onLog?.call('❌ Error handler /print-qris: $e');
        debugPrint('[SDR] /print-qris error:\n$e\n$st');
        return Response.internalServerError(
          body: jsonEncode({'status': 'error', 'message': e.toString()}),
          headers: const {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
          },
        );
      }
    });

    // OPTIONS PREFLIGHT
    router.options('/print', (Request req) {
      return Response.ok('', headers: const {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'POST, OPTIONS',
        'Access-Control-Allow-Headers':
            'Content-Type, X-Print-Format, X-Print-Source',
        'Access-Control-Allow-Private-Network': 'true',
      });
    });

    router.options('/status', (Request req) {
      return Response.ok('', headers: const {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type',
        'Access-Control-Allow-Private-Network': 'true',
      });
    });

    router.options('/print-qris', (Request req) {
      return Response.ok('', headers: const {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'POST, OPTIONS',
        'Access-Control-Allow-Headers':
            'Content-Type, X-Print-Format, X-Print-Source',
        'Access-Control-Allow-Private-Network': 'true',
      });
    });

    // PRINT ENDPOINT
    router.post('/print', (Request req) async {
      onLog?.call('📥 Request masuk dari Odoo!');

      try {
        final contentType = req.headers['content-type'] ?? '';
        Uint8List printData;
        String jobType = 'escpos';
        String jobLabel = 'Print Job';

        if (contentType.contains('application/json')) {
          final bodyStr = await req.readAsString();
          final Map<String, dynamic> json =
              jsonDecode(bodyStr) as Map<String, dynamic>;

          final format = json['format'] as String? ?? 'escpos';
          final dataField = json['data'];

          // SESSION SUMMARY
          if (format == 'session_summary') {
            Map<String, dynamic> summaryData;
            if (dataField is Map<String, dynamic>) {
              summaryData = dataField;
            } else if (dataField is String) {
              summaryData = jsonDecode(dataField) as Map<String, dynamic>;
            } else {
              summaryData = {};
            }
            printData =
                _formatter!.buildSessionSummary(summaryData, _paperSize);
            jobType = 'session_summary';
            final sessionName = summaryData['session_name'] as String? ??
                summaryData['name'] as String? ??
                summaryData['session_id']?.toString() ??
                '';
            jobLabel = sessionName.isNotEmpty
                ? 'Session Summary $sessionName'
                : 'Session Summary Report';
            onLog?.call(
                '🖨️ Terima job Session Summary Report (${printData.length}B)');
          } else if (format == 'odoo_json') {
            Map<String, dynamic> orderData;
            if (dataField is Map<String, dynamic>) {
              orderData = dataField;
            } else if (dataField is String) {
              orderData = jsonDecode(dataField) as Map<String, dynamic>;
            } else {
              orderData = {};
            }

            final receiptType = orderData['receipt_type'] as String? ?? 'full';
            final orderName = (orderData['name'] as String?)?.isNotEmpty == true
                ? orderData['name'] as String
                : (orderData['order_ref'] as String?)?.isNotEmpty == true
                    ? orderData['order_ref'] as String
                    : (orderData['pos_reference'] as String?)?.isNotEmpty ==
                            true
                        ? orderData['pos_reference'] as String
                        : '';

            if (receiptType == 'basic') {
              printData = _formatter!
                  .buildFromOdooData(orderData, _paperSize, basic: true);
              jobType = 'receipt_basic';
              jobLabel = orderName.isNotEmpty
                  ? 'Basic Receipt\n$orderName'
                  : 'Basic Receipt';
              onLog?.call(
                  '🖨️ Terima job Basic Receipt (odoo_json, ${printData.length}B)');
            } else {
              printData = _formatter!
                  .buildFromOdooData(orderData, _paperSize, basic: false);
              jobType = 'receipt_full';
              jobLabel = orderName.isNotEmpty
                  ? 'Full Receipt\n$orderName'
                  : 'Full Receipt';
              onLog?.call(
                  '🖨️ Terima job Full Receipt (odoo_json, ${printData.length}B)');
            }
          } else if (format == 'text') {
            final textContent =
                dataField is String ? dataField : dataField.toString();
            printData = _formatter!.textToEscPos(textContent, _paperSize);
            jobType = 'text';
            jobLabel = 'Cetak Teks';
            onLog?.call('Terima job (TEXT, ${printData.length}B)');
          } else {
            final b64 = dataField is String ? dataField : '';
            if (b64.isEmpty) {
              onLog?.call('❌ Format escpos tapi data kosong');
              return Response.badRequest(
                body: jsonEncode(
                    {'status': 'error', 'message': 'Data base64 kosong'}),
                headers: const {
                  'Content-Type': 'application/json',
                  'Access-Control-Allow-Origin': '*',
                },
              );
            }
            printData = base64Decode(b64);
            jobType = 'escpos';
            jobLabel = 'ESC/POS Data';
            onLog?.call('Terima job (ESC/POS base64, ${printData.length}B)');
          }
        } else if (contentType.contains('text/plain')) {
          final body = await req.readAsString();
          printData = _formatter!.textToEscPos(body, _paperSize);
          jobType = 'text';
          jobLabel = 'Cetak Teks';
          onLog?.call('Terima job (TEXT, ${printData.length}B)');
        } else {
          final bytes = await req.read().expand((x) => x).toList();
          printData = Uint8List.fromList(bytes);
          jobType = 'escpos';
          jobLabel = 'Binary Data';
          onLog?.call('Terima job (BINARY, ${printData.length}B)');
        }

        final isReceiptJob =
            jobType == 'receipt_full' || jobType == 'receipt_basic';

        if (isReceiptJob && _cashDrawerMode == CashDrawerMode.openBeforePrint) {
          onLog?.call('🔓 Membuka cash drawer sebelum cetak...');
          await _btService?.sendRaw(EscPosCommands.openCashDrawer());
          await Future.delayed(const Duration(milliseconds: 1500));
        }

        final ok = await _btService?.sendRaw(printData) ?? false;
        if (ok) {
          if (isReceiptJob &&
              _cashDrawerMode == CashDrawerMode.openAfterPrint) {
            onLog?.call('🔓 Membuka cash drawer setelah cetak...');
            await Future.delayed(const Duration(milliseconds: 1000));
            await _btService?.sendRaw(EscPosCommands.openCashDrawer());
          }
          if (jobType == 'session_summary' && _sessionSummaryCashDrawer) {
            onLog?.call('🔓 Membuka cash drawer untuk Session Summary...');
            await Future.delayed(const Duration(milliseconds: 1000));
            await _btService?.sendRaw(EscPosCommands.openCashDrawer());
          }
          onLog?.call('✅ Print berhasil (${printData.length}B dikirim)');
          onPrintSuccess?.call();
          onPrintJob?.call(jobType, jobLabel, true, printData.length);
          return Response.ok(
            jsonEncode({'status': 'ok', 'message': 'Print berhasil'}),
            headers: const {
              'Content-Type': 'application/json',
              'Access-Control-Allow-Origin': '*',
            },
          );
        } else {
          onLog?.call('❌ Gagal kirim ke printer — cek koneksi Bluetooth');
          onPrintJob?.call(jobType, jobLabel, false, printData.length);
          return Response.internalServerError(
            body: jsonEncode(
                {'status': 'error', 'message': 'Gagal kirim ke printer'}),
            headers: const {
              'Content-Type': 'application/json',
              'Access-Control-Allow-Origin': '*',
            },
          );
        }
      } catch (e, st) {
        onLog?.call('❌ Error handler /print: $e');
        debugPrint('[SDR] /print error:\n$e\n$st');
        return Response.internalServerError(
          body: jsonEncode({'status': 'error', 'message': e.toString()}),
          headers: const {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
          },
        );
      }
    });

    final handler = const Pipeline().addHandler(router.call);

    try {
      if (_server != null) {
        await _server?.close(force: true);
        _server = null;
      }
      _server = await io.serve(handler, InternetAddress.loopbackIPv4, port,
          shared: true);
      onStatusChange?.call(true);
      onLog?.call('🚀 HTTP Server aktif di port $port (localhost only)');
    } catch (e) {
      onLog?.call('❌ Gagal memulai server: $e');
      onStatusChange?.call(false);
      rethrow;
    }
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    onStatusChange?.call(false);
    onLog?.call('⏹️ HTTP Server dihentikan');
  }
}
