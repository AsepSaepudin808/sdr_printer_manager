import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../utils/constants.dart';

/// Logs state notifier - manages application activity logs
class LogsNotifier extends Notifier<List<String>> {
  @override
  List<String> build() => [];

  /// Add a new log message with timestamp
  void add(String message) {
    final now = DateTime.now();
    final time = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    final newLogs = ['[$time] $message', ...state];
    state = newLogs.length > AppConstants.maxLogEntries
        ? newLogs.sublist(0, AppConstants.maxLogEntries)
        : newLogs;
  }

  /// Clear all logs
  void clear() {
    state = [];
  }
}

/// Provider for application logs
final logsProvider = NotifierProvider<LogsNotifier, List<String>>(LogsNotifier.new);