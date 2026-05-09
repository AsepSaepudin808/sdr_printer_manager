import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'package:network_info_plus/network_info_plus.dart';

import 'bluetooth_service.dart';
import '../utils/escpos_helper.dart';
import '../utils/test_print_template.dart';

class PrintServerService {
  HttpServer? _server;
  SdrBluetoothService? _btService;

  Function(String)? onLog;
  Function()? onPrintSuccess;
  Function(bool)? onStatusChange;

  PaperSize _paperSize = PaperSize.mm80;

  bool get isRunning => _server != null;

  void setPaperSize(PaperSize size) {
    _paperSize = size;
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
    required SdrBluetoothService bluetoothService,
    PaperSize paperSize = PaperSize.mm80,
  }) async {
    _btService = bluetoothService;
    _paperSize = paperSize;

    final router = Router();

    // ── GET /status ──────────────────────────────────────────────────────────
    router.get('/status', (Request req) {
      final body = jsonEncode({
        'status': 'ok',
        'server': 'dPrinter Mart',
        'version': '1.0.0',
        'printer_connected': _btService?.isConnected ?? false,
      });
      return Response.ok(body, headers: const {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
      });
    });

    // ── GET /test-print ──────────────────────────────────────────────────────
    router.get('/test-print', (Request req) async {
      final action = req.url.queryParameters['type'] ?? 'test_short';
      final size = _paperSize;

      Uint8List? testData;
      if (action == 'test_short') {
        testData = TestPrintTemplate.buildTestShort(size);
      } else if (action == 'test_long') {
        testData = TestPrintTemplate.buildTestLong(size);
      } else {
        testData = TestPrintTemplate.buildTestShort(size);
      }

      final ok = await _btService?.sendRaw(testData) ?? false;
      if (ok) {
        onLog?.call('Test print berhasil');
        onPrintSuccess?.call();
        return Response.ok(
            jsonEncode({'status': 'ok', 'message': 'Test print berhasil'}),
            headers: const {
              'Content-Type': 'application/json',
              'Access-Control-Allow-Origin': '*',
            });
      } else {
        onLog?.call('❌ Test print GAGAL — printer tidak terhubung');
        return Response.internalServerError(
            body: jsonEncode(
                {'status': 'error', 'message': 'Printer tidak terhubung'}),
            headers: const {
              'Content-Type': 'application/json',
              'Access-Control-Allow-Origin': '*',
            });
      }
    });

    // ── OPTIONS preflight ────────────────────────────────────────────────────
    // PENTING: 'Access-Control-Allow-Private-Network: true' wajib ada agar
    // Chrome 98+ mengizinkan request dari HTTPS page (mis. odoo-dev.dretail.id)
    // ke server lokal (http://127.0.0.1:8080) — Private Network Access policy.
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

    // ── POST /print ──────────────────────────────────────────────────────────
    router.post('/print', (Request req) async {
      onLog?.call('📥 Request masuk dari Odoo!');

      try {
        final contentType = req.headers['content-type'] ?? '';
        Uint8List printData;

        if (contentType.contains('application/json')) {
          final bodyStr = await req.readAsString();
          final Map<String, dynamic> json =
              jsonDecode(bodyStr) as Map<String, dynamic>;

          final format = json['format'] as String? ?? 'escpos';
          final dataField = json['data'];

          if (format == 'odoo_json') {
            Map<String, dynamic> orderData;
            if (dataField is Map<String, dynamic>) {
              orderData = dataField;
            } else if (dataField is String) {
              orderData = jsonDecode(dataField) as Map<String, dynamic>;
            } else {
              orderData = {};
            }

            final receiptType = orderData['receipt_type'] as String? ?? 'full';

            if (receiptType == 'basic') {
              printData = EscPosHelper.buildFromOdooData(orderData, _paperSize,
                  basic: true);
              onLog?.call(
                  '🖨️ Terima job Basic Receipt (odoo_json, ${printData.length}B)');
            } else {
              printData = EscPosHelper.buildFromOdooData(orderData, _paperSize,
                  basic: false);
              onLog?.call(
                  '🖨️ Terima job Full Receipt (odoo_json, ${printData.length}B)');
            }
          } else if (format == 'text') {
            final textContent =
                dataField is String ? dataField : dataField.toString();
            printData = EscPosHelper.textToEscPos(textContent, _paperSize);
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
            onLog?.call('Terima job (ESC/POS base64, ${printData.length}B)');
          }
        } else if (contentType.contains('text/plain')) {
          final body = await req.readAsString();
          printData = EscPosHelper.textToEscPos(body, _paperSize);
          onLog?.call('Terima job (TEXT, ${printData.length}B)');
        } else {
          final bytes = await req.read().expand((x) => x).toList();
          printData = Uint8List.fromList(bytes);
          onLog?.call('Terima job (BINARY, ${printData.length}B)');
        }

        final ok = await _btService?.sendRaw(printData) ?? false;
        if (ok) {
          onLog?.call('✅ Print berhasil (${printData.length}B dikirim)');
          onPrintSuccess?.call();
          return Response.ok(
            jsonEncode({'status': 'ok', 'message': 'Print berhasil'}),
            headers: const {
              'Content-Type': 'application/json',
              'Access-Control-Allow-Origin': '*',
            },
          );
        } else {
          onLog?.call('❌ Gagal kirim ke printer — cek koneksi Bluetooth');
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
        // ignore: avoid_print
        print('[SDR] /print error:\n$e\n$st');
        return Response.internalServerError(
          body: jsonEncode({'status': 'error', 'message': e.toString()}),
          headers: const {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
          },
        );
      }
    });

    final handler = const Pipeline()
        .addMiddleware(_corsMiddleware())
        .addHandler(router.call);

    try {
      if (_server != null) {
        await _server?.close(force: true);
        _server = null;
      }
      _server = await io.serve(handler, InternetAddress.anyIPv4, port, shared: true);
      onStatusChange?.call(true);
      onLog?.call('🚀 HTTP Server aktif di port $port');
    } catch (e) {
      onLog?.call('❌ Gagal memulai server: $e');
      onStatusChange?.call(false);
      rethrow;
    }
  }

  Middleware _corsMiddleware() {
    return (Handler handler) {
      return (Request request) async {
        if (request.method == 'OPTIONS') {
          return Response.ok('', headers: {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
            'Access-Control-Allow-Headers':
                'Content-Type, X-Print-Format, X-Print-Source, Authorization',
            // Wajib untuk Chrome 98+ Private Network Access:
            // Mengizinkan HTTPS page mengakses server lokal (127.0.0.1)
            'Access-Control-Allow-Private-Network': 'true',
          });
        }
        final response = await handler(request);
        return response.change(headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
          'Access-Control-Allow-Headers':
              'Content-Type, X-Print-Format, X-Print-Source, Authorization',
          'Access-Control-Allow-Private-Network': 'true',
          ...response.headers,
        });
      };
    };
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    onStatusChange?.call(false);
    onLog?.call('⏹️ HTTP Server dihentikan');
  }
}
