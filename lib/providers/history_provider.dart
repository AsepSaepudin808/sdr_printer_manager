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

class HistoryStats {
  final int totalSuccess;
  final int totalFail;
  final int todayCount;
  final int totalBytes;
  final Map<String, int> countByType;
  final Map<String, int> countByDate;
  final double successRate;

  const HistoryStats({
    this.totalSuccess = 0,
    this.totalFail = 0,
    this.todayCount = 0,
    this.totalBytes = 0,
    this.countByType = const {},
    this.countByDate = const {},
    this.successRate = 0,
  });

  factory HistoryStats.from(List<PrintHistory> items) {
    int success = 0;
    int fail = 0;
    int totalBytes = 0;
    final byType = <String, int>{};
    final now = DateTime.now();
    final byDate = <String, int>{};
    for (int i = 6; i >= 0; i--) {
      final d = now.subtract(Duration(days: i));
      byDate['${d.day}/${d.month}'] = 0;
    }
    int today = 0;

    for (final item in items) {
      if (item.success) {
        success++;
        totalBytes += item.dataSize;
        byType[item.type] = (byType[item.type] ?? 0) + 1;
        final diff = now.difference(item.timestamp).inDays;
        if (diff < 7) {
          final key = '${item.timestamp.day}/${item.timestamp.month}';
          byDate[key] = (byDate[key] ?? 0) + 1;
        }
        if (item.timestamp.year == now.year &&
            item.timestamp.month == now.month &&
            item.timestamp.day == now.day) {
          today++;
        }
      } else {
        fail++;
      }
    }

    final rate = (success + fail) > 0 ? success / (success + fail) * 100 : 0.0;
    return HistoryStats(
      totalSuccess: success,
      totalFail: fail,
      todayCount: today,
      totalBytes: totalBytes,
      countByType: byType,
      countByDate: byDate,
      successRate: rate,
    );
  }
}

final historyStatsProvider = Provider<HistoryStats>((ref) {
  return HistoryStats.from(ref.watch(historyNotifierProvider));
});