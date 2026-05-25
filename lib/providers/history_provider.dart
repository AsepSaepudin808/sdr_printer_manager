import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/print_history_service.dart';
import '../models/print_history.dart';

final printHistoryServiceProvider = Provider<PrintHistoryService>((ref) {
  return PrintHistoryService();
});

class HistoryNotifier extends Notifier<List<PrintHistory>> {
  @override
  List<PrintHistory> build() => [];

  int get totalCount => state.length;
  int get successCount => state.where((e) => e.success).length;
  int get failCount => state.where((e) => !e.success).length;

  Map<String, int> get countByType {
    final map = <String, int>{};
    for (final item in state.where((e) => e.success)) {
      map[item.type] = (map[item.type] ?? 0) + 1;
    }
    return map;
  }

  Map<String, int> get countByDate {
    final map = <String, int>{};
    final now = DateTime.now();
    for (int i = 6; i >= 0; i--) {
      final d = now.subtract(Duration(days: i));
      final key = '${d.day}/${d.month}';
      map[key] = 0;
    }
    for (final item in state.where((e) => e.success)) {
      final diff = now.difference(item.timestamp).inDays;
      if (diff < 7) {
        final key = '${item.timestamp.day}/${item.timestamp.month}';
        map[key] = (map[key] ?? 0) + 1;
      }
    }
    return map;
  }

  int get totalBytes {
    int sum = 0;
    for (final item in state.where((e) => e.success)) {
      sum += item.dataSize;
    }
    return sum;
  }

  int get todayCount {
    final now = DateTime.now();
    return state
        .where((e) =>
            e.success &&
            e.timestamp.year == now.year &&
            e.timestamp.month == now.month &&
            e.timestamp.day == now.day)
        .length;
  }

  Future<void> load() async {
    final service = ref.read(printHistoryServiceProvider);
    await service.load();
    state = service.items;
  }

  Future<void> add(PrintHistory entry) async {
    final service = ref.read(printHistoryServiceProvider);
    await service.add(entry);
    state = service.items;
  }

  Future<void> clear() async {
    final service = ref.read(printHistoryServiceProvider);
    await service.clear();
    state = [];
  }
}

final historyNotifierProvider =
    NotifierProvider<HistoryNotifier, List<PrintHistory>>(HistoryNotifier.new);