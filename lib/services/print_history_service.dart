import 'package:shared_preferences/shared_preferences.dart';
import '../models/print_history.dart';

/// Manages persistent print history storage using SharedPreferences.
class PrintHistoryService {
  static const String _key = 'print_history_v1';
  static const int _maxEntries = 500;

  List<PrintHistory> _items = [];
  List<PrintHistory> get items => List.unmodifiable(_items);

  int get totalCount => _items.length;
  int get successCount => _items.where((e) => e.success).length;
  int get failCount => _items.where((e) => !e.success).length;

  /// Load history from disk
  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key);
    if (raw != null && raw.isNotEmpty) {
      _items = PrintHistory.decode(raw);
    } else {
      _items = [];
    }
  }

  /// Add a new print history entry and persist
  Future<void> add(PrintHistory entry) async {
    _items.insert(0, entry);
    // Trim to max
    if (_items.length > _maxEntries) {
      _items = _items.sublist(0, _maxEntries);
    }
    await _save();
  }

  /// Clear all history
  Future<void> clear() async {
    _items.clear();
    final p = await SharedPreferences.getInstance();
    await p.remove(_key);
  }

  /// Persist to disk
  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, PrintHistory.encode(_items));
  }

  /// Get count by type
  Map<String, int> get countByType {
    final map = <String, int>{};
    for (final item in _items.where((e) => e.success)) {
      map[item.type] = (map[item.type] ?? 0) + 1;
    }
    return map;
  }

  /// Get count by date (last 7 days)
  Map<String, int> get countByDate {
    final map = <String, int>{};
    final now = DateTime.now();
    for (int i = 6; i >= 0; i--) {
      final d = now.subtract(Duration(days: i));
      final key = '${d.day}/${d.month}';
      map[key] = 0;
    }
    for (final item in _items.where((e) => e.success)) {
      final diff = now.difference(item.timestamp).inDays;
      if (diff < 7) {
        final key = '${item.timestamp.day}/${item.timestamp.month}';
        map[key] = (map[key] ?? 0) + 1;
      }
    }
    return map;
  }

  /// Total bytes printed
  int get totalBytes {
    int sum = 0;
    for (final item in _items.where((e) => e.success)) {
      sum += item.dataSize;
    }
    return sum;
  }

  /// Today's count
  int get todayCount {
    final now = DateTime.now();
    return _items
        .where((e) =>
            e.success &&
            e.timestamp.year == now.year &&
            e.timestamp.month == now.month &&
            e.timestamp.day == now.day)
        .length;
  }
}
