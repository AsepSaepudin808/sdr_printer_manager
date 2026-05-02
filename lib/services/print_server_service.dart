import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'package:network_info_plus/network_info_plus.dart';

import 'bluetooth_service.dart';
import '../utils/escpos_helper.dart';

class PrintServerService {
  HttpServer? _server;
  SdrBluetoothService? _btService;

  Function(String)? onLog;
  Function()? onPrintSuccess;
  Function(bool)? onStatusChange;

  bool get isRunning => _server != null;

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

    final router = Router();

    // ── GET /status ──────────────────────────────────────────────
    router.get('/status', (Request req) {
      final body = jsonEncode({
        'status': 'ok',
        'server': 'SDR Printer Manager',
        'version': '1.0.0',
        'printer_connected': _btService?.isConnected ?? false,
      });
      return Response.ok(body,
          headers: const {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
          });
    });

    // ── GET /test-print ──────────────────────────────────────────
    router.get('/test-print', (Request req) async {
      final testData = EscPosHelper.buildTestShort(paperSize);
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
        onLog?.call('Test print GAGAL');
        return Response.internalServerError(
            body: jsonEncode(
                {'status': 'error', 'message': 'Printer tidak terhubung'}),
            headers: const {
              'Content-Type': 'application/json',
              'Access-Control-Allow-Origin': '*',
            });
      }
    });

    // ── OPTIONS preflight ────────────────────────────────────────
    router.options('/print', (Request req) {
      return Response.ok('',
          headers: const {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'POST, OPTIONS',
            'Access-Control-Allow-Headers': 'Content-Type, X-Print-Format',
          });
    });

    // ── POST /print ───────────────────────────────────────────────
    router.post('/print', (Request req) async {
      try {
        final contentType = req.headers['content-type'] ?? '';
        Uint8List printData;

        if (contentType.contains('application/json')) {
          final body = await req.readAsString();
          final json = jsonDecode(body) as Map<String, dynamic>;
          final format    = json['format'] as String? ?? 'escpos';
          final dataField = json['data']   as String? ?? '';

          if (format == 'text') {
            printData = EscPosHelper.textToEscPos(dataField, paperSize);
          } else {
            printData = base64Decode(dataField);
          }
          onLog?.call(
              'Terima job (JSON, format=$format, ${printData.length}B)');
        } else if (contentType.contains('text/plain')) {
          final body = await req.readAsString();
          printData = EscPosHelper.textToEscPos(body, paperSize);
          onLog?.call('Terima job (TEXT, ${printData.length}B)');
        } else {
          final bytes = await req.read().expand((x) => x).toList();
          printData = Uint8List.fromList(bytes);
          onLog?.call('Terima job (BINARY, ${printData.length}B)');
        }

        final ok = await _btService?.sendRaw(printData) ?? false;
        if (ok) {
          onLog?.call('✅ Print berhasil');
          onPrintSuccess?.call();
          return Response.ok(
            jsonEncode({'status': 'ok', 'message': 'Print berhasil'}),
            headers: const {
              'Content-Type': 'application/json',
              'Access-Control-Allow-Origin': '*',
            },
          );
        } else {
          onLog?.call('❌ Gagal kirim ke printer');
          return Response.internalServerError(
            body: jsonEncode(
                {'status': 'error', 'message': 'Gagal kirim ke printer'}),
            headers: const {
              'Content-Type': 'application/json',
              'Access-Control-Allow-Origin': '*',
            },
          );
        }
      } catch (e) {
        onLog?.call('❌ Error: $e');
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

    _server = await io.serve(handler, InternetAddress.anyIPv4, port);
    onStatusChange?.call(true);
    onLog?.call('HTTP Server aktif di port $port');
  }

  Middleware _corsMiddleware() {
    return (Handler handler) {
      return (Request request) async {
        final response = await handler(request);
        return response.change(headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
          'Access-Control-Allow-Headers': 'Content-Type, X-Print-Format',
          ...response.headers,
        });
      };
    };
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    onStatusChange?.call(false);
  }
}