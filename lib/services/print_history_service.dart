import 'package:shared_preferences/shared_preferences.dart';
import '../models/print_history.dart';
import '../utils/constants.dart';

/// PRINT HISTORY SERVICE
class PrintHistoryService {
  static const String _key = 'print_history_v1';
  static const int _maxEntries = AppConstants.maxHistoryItems;

  List<PrintHistory> _items = [];
  List<PrintHistory> get items => List.unmodifiable(_items);

  int get totalCount => _items.length;
  int get successCount => _items.where((e) => e.success).length;
  int get failCount => _items.where((e) => !e.success).length;

  // LOAD HISTORY
  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key);
    if (raw != null && raw.isNotEmpty) {
      _items = PrintHistory.decode(raw);
    } else {
      _items = [];
    }
  }

  // ADD ENTRY
  Future<void> add(PrintHistory entry) async {
    _items.insert(0, entry);
    // TRIM TO MAX
    if (_items.length > _maxEntries) {
      _items = _items.sublist(0, _maxEntries);
    }
    await _save();
  }

  // CLEAR HISTORY
  Future<void> clear() async {
    _items.clear();
    final p = await SharedPreferences.getInstance();
    await p.remove(_key);
  }

  // PERSIST TO DISK
  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, PrintHistory.encode(_items));
  }

  // COUNT BY TYPE
  Map<String, int> get countByType {
    final map = <String, int>{};
    for (final item in _items.where((e) => e.success)) {
      map[item.type] = (map[item.type] ?? 0) + 1;
    }
    return map;
  }

  // COUNT BY DATE
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

  // TOTAL BYTES
  int get totalBytes {
    int sum = 0;
    for (final item in _items.where((e) => e.success)) {
      sum += item.dataSize;
    }
    return sum;
  }

  // TODAY COUNT
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
