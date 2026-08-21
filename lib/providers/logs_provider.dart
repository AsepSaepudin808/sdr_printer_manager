import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../utils/constants.dart';

class LogsNotifier extends Notifier<List<String>> {
  @override
  List<String> build() => [];

  void add(String message) {
    final now = DateTime.now();
    final time =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    final newLogs = ['[$time] $message', ...state];
    state = newLogs.length > AppConstants.maxLogEntries
        ? newLogs.sublist(0, AppConstants.maxLogEntries)
        : newLogs;
  }

  void clear() {
    state = [];
  }
}

final logsProvider =
    NotifierProvider<LogsNotifier, List<String>>(LogsNotifier.new);
