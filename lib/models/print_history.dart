import 'dart:convert';

/// Represents one print job entry for the history log.
class PrintHistory {
  final String id;
  final String type;       // 'receipt_full', 'receipt_basic', 'session_summary', 'text', 'image', 'pdf', 'test', 'escpos'
  final String label;      // Human-readable label, e.g. "Order #12345"
  final DateTime timestamp;
  final bool success;
  final int dataSize;      // bytes sent
  final String source;     // 'pos', 'manual', 'android_print_service'

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

  /// Human-readable type label
  String get typeLabel {
    switch (type) {
      case 'receipt_full':
        return 'Struk Lengkap';
      case 'receipt_basic':
        return 'Struk Pendek';
      case 'session_summary':
        return 'Laporan Sesi';
      case 'text':
        return 'Teks';
      case 'image':
        return 'Gambar';
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

  /// Icon-friendly type category
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
