import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class CrashLogService {
  static const int _maxLines = 1000;
  static const String _fileName = 'dprinter_crash.log';

  File? _file;
  final List<String> _buffer = [];
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      _file = File('${dir.path}/$_fileName');
      if (await _file!.exists()) {
        final lines = await _file!.readAsLines();
        _buffer.addAll(lines.length > _maxLines
            ? lines.sublist(lines.length - _maxLines)
            : lines);
      }
      _initialized = true;
    } catch (e) {
      debugPrint('[CrashLog] init failed: $e');
    }
  }

  Future<void> log(String level, String message, [Object? error, StackTrace? stack]) async {
    await init();
    final ts = DateTime.now().toIso8601String();
    final buf = StringBuffer('$ts [$level] $message');
    if (error != null) buf.write(' | error: $error');
    if (stack != null) buf.write('\n$stack');
    final line = buf.toString();
    _buffer.add(line);
    if (_buffer.length > _maxLines) {
      _buffer.removeRange(0, _buffer.length - _maxLines);
    }
    debugPrint(line);
    await _persist();
  }

  Future<void> _persist() async {
    if (_file == null) return;
    try {
      await _file!.writeAsString(_buffer.join('\n'), flush: true);
    } catch (e) {
      debugPrint('[CrashLog] persist failed: $e');
    }
  }

  File? get logFile => _file;
  int get lineCount => _buffer.length;
  String get preview =>
      _buffer.length <= 40 ? _buffer.join('\n') : _buffer.sublist(_buffer.length - 40).join('\n');

  Future<void> clear() async {
    _buffer.clear();
    await _persist();
  }
}

final crashLogService = CrashLogService();

void setupCrashHandlers() {
  FlutterError.onError = (details) {
    crashLogService.log(
      'FLUTTER',
      details.exceptionAsString(),
      details.exception,
      details.stack,
    );
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    crashLogService.log('PLATFORM', error.toString(), error, stack);
    return true;
  };
}