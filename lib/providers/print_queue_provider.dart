import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/print_queue_service.dart';

/// Print queue service provider
final printQueueServiceProvider = Provider<PrintQueueService>((ref) {
  return PrintQueueService();
});

/// Print queue state notifier
class PrintQueueNotifier extends Notifier<List<PrintJob>> {
  @override
  List<PrintJob> build() => [];

  PrintQueueService get _service => ref.read(printQueueServiceProvider);

  /// Load queue from storage
  Future<void> load() async {
    await _service.load();
    state = _service.queue;
  }

  /// Add a job to queue
  Future<void> addJob(String type, Uint8List data) async {
    await _service.addFromData(type, data);
    state = _service.queue;
  }

  /// Process all pending jobs
  Future<void> processQueue(Future<bool> Function(List<int>) sendCallback) async {
    await _service.processQueue((bytes) => sendCallback(bytes));
    state = _service.queue;
  }

  /// Clear all jobs
  Future<void> clearAll() async {
    await _service.clearAll();
    state = [];
  }

  /// Clear old completed/failed jobs
  Future<void> clearOld() async {
    await _service.clearOldJobs();
    state = _service.queue;
  }
}

final printQueueNotifierProvider = NotifierProvider<PrintQueueNotifier, List<PrintJob>>(
  PrintQueueNotifier.new,
);