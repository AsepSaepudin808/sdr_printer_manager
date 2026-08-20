import 'dart:convert';

// PRINT HISTORY MODEL
class PrintHistory {
  final String id;
  final String type;
  final String label;
  final DateTime timestamp;
  final bool success;
  final int dataSize;
  final String source;

  PrintHistory({
    required this.id,
    required this.type,
    required this.label,
    required this.timestamp,
    required this.success,
    this.dataSize = 0,
    this.source = 'pos',
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'label': label,
    'timestamp': timestamp.toIso8601String(),
    'success': success,
    'dataSize': dataSize,
    'source': source,
  };

  factory PrintHistory.fromJson(Map<String, dynamic> json) => PrintHistory(
    id: json['id'] as String? ?? '',
    type: json['type'] as String? ?? 'unknown',
    label: json['label'] as String? ?? '',
    timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
    success: json['success'] as bool? ?? false,
    dataSize: json['dataSize'] as int? ?? 0,
    source: json['source'] as String? ?? 'pos',
  );

  static String encode(List<PrintHistory> items) =>
      jsonEncode(items.map((e) => e.toJson()).toList());

  static List<PrintHistory> decode(String jsonStr) {
    try {
      final list = jsonDecode(jsonStr) as List;
      return list.map((e) => PrintHistory.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  // TYPE LABEL
  String get typeLabel {
    switch (type) {
      case 'receipt_full':
        return 'Full Receipt';
      case 'receipt_basic':
        return 'Basic Receipt';
      case 'session_summary':
        return 'Session Summary';
      case 'qris':
        return 'QRIS Receipt';
      case 'text':
        return 'Text Print';
      case 'image':
        return 'Image Print';
      case 'pdf':
        return 'PDF';
      case 'test':
        return 'Test Print';
      case 'escpos':
        return 'ESC/POS';
      default:
        return type;
    }
  }

  // TYPE ICON
  String get typeIcon {
    switch (type) {
      case 'receipt_full':
      case 'receipt_basic':
        return 'receipt';
      case 'session_summary':
        return 'summary';
      case 'text':
        return 'text';
      case 'image':
        return 'image';
      case 'pdf':
        return 'pdf';
      case 'test':
        return 'test';
      default:
        return 'other';
    }
  }
}
