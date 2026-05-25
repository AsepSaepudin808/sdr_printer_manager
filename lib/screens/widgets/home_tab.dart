import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/app_state_provider.dart';
import '../../utils/strings.dart';
import '../../utils/colors.dart';
import 'status_card.dart';
import 'printer_card.dart';
import 'stats_row.dart';
import 'port_card.dart';
import 'test_print_card.dart';
import 'log_card.dart';
import 'auto_start_card.dart';

/// Home tab widget - main dashboard with all cards
class HomeTab extends ConsumerWidget {
  final VoidCallback? onSelectPrinter;
  final VoidCallback? onToggleServer;
  final VoidCallback? onShowHistory;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onSavePort;
  final void Function(Uint8List, String)? onTestPrint;

  const HomeTab({
    super.key,
    this.onSelectPrinter,
    this.onToggleServer,
    this.onShowHistory,
    this.onOpenSettings,
    this.onSavePort,
    this.onTestPrint,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appState = ref.watch(appStateProvider);
    final logs = ref.watch(logsProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        StatusCard(
          appState: appState,
          onCopyUrl: () => _showToast(context, S.urlCopied),
        ),
        const SizedBox(height: 14),
        PrinterCard(
          appState: appState,
          onSelectPrinter: onSelectPrinter,
          onToggleServer: onToggleServer,
        ),
        const SizedBox(height: 14),
        StatsRow(
          appState: appState,
          onShowHistory: onShowHistory,
          onOpenSettings: onOpenSettings,
        ),
        const SizedBox(height: 14),
        PortCard(
          portController: TextEditingController(text: appState.serverPort.toString()),
          onSave: onSavePort,
        ),
        const SizedBox(height: 14),
        TestPrintCard(
          isPrinting: appState.isPrinting,
          paperSize: appState.paperSize,
          onTestPrint: (data, label) => onTestPrint?.call(data, label),
        ),
        if (appState.printStatus.isNotEmpty) ...[
          const SizedBox(height: 10),
          _buildTestStatusCard(appState),
        ],
        const SizedBox(height: 14),
        LogCard(
          logs: logs,
          onViewAll: () => _navigateToLogScreen(context, logs),
        ),
        const SizedBox(height: 14),
        AutoStartCard(
          autoStart: appState.autoStart,
          onChanged: (v) => _toggleAutoStart(ref, v),
        ),
      ]),
    );
  }

  Widget _buildTestStatusCard(AppState appState) {
    final ok = appState.printStatus.startsWith('✅');
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: (ok ? AppColors.success : AppColors.danger).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: (ok ? AppColors.success : AppColors.danger).withValues(alpha: 0.3),
        ),
      ),
      child: Text(
        appState.printStatus,
        style: TextStyle(
          color: ok ? AppColors.success : AppColors.danger,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }

  void _showToast(BuildContext context, String message) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: AppColors.success,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));
  }

  void _navigateToLogScreen(BuildContext context, List<String> logs) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _LogScreenFromWidget(logs: logs)),
    );
  }

  Future<void> _toggleAutoStart(WidgetRef ref, bool value) async {
    ref.read(appStateProvider.notifier).setAutoStart(value);
    final p = await SharedPreferences.getInstance();
    await p.setBool('auto_start', value);
  }
}

/// Inline log screen for widget usage
class _LogScreenFromWidget extends StatelessWidget {
  final List<String> logs;

  const _LogScreenFromWidget({required this.logs});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FC),
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: Text(S.activityHistory, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
        elevation: 0,
      ),
      body: logs.isEmpty
          ? Center(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.history_rounded, size: 64, color: Colors.grey.shade300),
                const SizedBox(height: 16),
                Text(S.noActivity, style: TextStyle(color: Colors.grey.shade400, fontSize: 14)),
              ]),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: logs.length,
              itemBuilder: (_, i) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: logs[i].contains('✅')
                          ? AppColors.success
                          : logs[i].contains('❌')
                              ? AppColors.danger
                              : Colors.amber.shade600,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(logs[i], style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
                  ),
                ]),
              ),
            ),
    );
  }
}