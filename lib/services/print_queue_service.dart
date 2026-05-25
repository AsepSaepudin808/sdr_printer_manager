import 'dart:convert';
import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';

/// Print job status
enum PrintJobStatus {
  pending,
  processing,
  completed,
  failed,
}

/// A single print job entry
class PrintJob {
  final String id;
  final String type;
  final Uint8List data;
  final DateTime createdAt;
  PrintJobStatus status;
  String? errorMessage;
  int retryCount;

  PrintJob({
    required this.id,
    required this.type,
    required this.data,
    required this.createdAt,
    this.status = PrintJobStatus.pending,
    this.errorMessage,
    this.retryCount = 0,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'data': base64Encode(data),
    'createdAt': createdAt.toIso8601String(),
    'status': status.index,
    'errorMessage': errorMessage,
    'retryCount': retryCount,
  };

  factory PrintJob.fromJson(Map<String, dynamic> json) {
    return PrintJob(
      id: json['id'] as String,
      type: json['type'] as String,
      data: base64Decode(json['data'] as String),
      createdAt: DateTime.parse(json['createdAt'] as String),
      status: PrintJobStatus.values[json['status'] as int? ?? 0],
      errorMessage: json['errorMessage'] as String?,
      retryCount: json['retryCount'] as int? ?? 0,
    );
  }
}

/// Print queue service untuk menangani print job yang gagal/pending
class PrintQueueService {
  static const String _key = 'print_queue_v1';
  static const int _maxQueueSize = 50;
  static const int _maxRetries = 3;

  final List<PrintJob> _queue = [];
  bool _isProcessing = false;

  List<PrintJob> get queue => List.unmodifiable(_queue);
  int get pendingCount => _queue.where((j) => j.status == PrintJobStatus.pending).length;
  bool get isProcessing => _isProcessing;
  bool get hasPendingJobs => pendingCount > 0;

  /// Add a print job to the queue
  Future<void> add(PrintJob job) async {
    _queue.insert(0, job);
    if (_queue.length > _maxQueueSize) {
      _queue.removeLast();
    }
    await _save();
  }

  /// Add a job from raw data
  Future<PrintJob> addFromData(String type, Uint8List data, {String? label}) async {
    final job = PrintJob(
      id: '${DateTime.now().millisecondsSinceEpoch}',
      type: type,
      data: data,
      createdAt: DateTime.now(),
    );
    await add(job);
    return job;
  }

  /// Get next pending job
  PrintJob? getNextPending() {
    for (final job in _queue) {
      if (job.status == PrintJobStatus.pending && job.retryCount < _maxRetries) {
        return job;
      }
    }
    return null;
  }

  /// Mark job as processing
  void markProcessing(PrintJob job) {
    final index = _queue.indexWhere((j) => j.id == job.id);
    if (index != -1) {
      _queue[index].status = PrintJobStatus.processing;
    }
  }

  /// Mark job as completed
  Future<void> markCompleted(PrintJob job) async {
    final index = _queue.indexWhere((j) => j.id == job.id);
    if (index != -1) {
      _queue[index].status = PrintJobStatus.completed;
      // Remove completed jobs from queue
      _queue.removeAt(index);
    }
    await _save();
  }

  /// Mark job as failed with retry
  Future<bool> markFailed(PrintJob job, String error) async {
    final index = _queue.indexWhere((j) => j.id == job.id);
    if (index != -1) {
      _queue[index].retryCount++;
      _queue[index].errorMessage = error;

      if (_queue[index].retryCount >= _maxRetries) {
        _queue[index].status = PrintJobStatus.failed;
        return false; // No more retries
      }
      _queue[index].status = PrintJobStatus.pending;
    }
    await _save();
    return true; // Can retry
  }

  /// Clear completed and failed jobs
  Future<void> clearOldJobs() async {
    _queue.removeWhere((j) =>
        j.status == PrintJobStatus.completed ||
        j.status == PrintJobStatus.failed);
    await _save();
  }

  /// Clear all jobs
  Future<void> clearAll() async {
    _queue.clear();
    final p = await SharedPreferences.getInstance();
    await p.remove(_key);
  }

  /// Process all pending jobs using a printer callback
  Future<void> processQueue(
    Future<bool> Function(Uint8List) sendCallback,
  ) async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      while (true) {
        final job = getNextPending();
        if (job == null) break;

        markProcessing(job);

        final success = await sendCallback(job.data);

        if (success) {
          await markCompleted(job);
        } else {
          final canRetry = await markFailed(job, 'Send failed');
          if (!canRetry) {
            // Job failed permanently, notify about it
            break;
          }
        }
      }
    } finally {
      _isProcessing = false;
    }
  }

  /// Load queue from storage
  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key);
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List;
        _queue.clear();
        _queue.addAll(
          list.map((e) => PrintJob.fromJson(e as Map<String, dynamic>)),
        );
      } catch (_) {
        _queue.clear();
      }
    }
  }

  /// Save queue to storage
  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    final list = _queue.map((j) => j.toJson()).toList();
    await p.setString(_key, jsonEncode(list));
  }
}