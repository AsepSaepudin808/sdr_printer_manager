import 'package:flutter/material.dart';
import '../../providers/app_state_provider.dart';
import '../../utils/escpos_helper.dart';
import '../../utils/strings.dart';
import '../../utils/colors.dart';

/// Stats row widget - shows print count and printer settings
class StatsRow extends StatelessWidget {
  final AppState appState;
  final VoidCallback? onShowHistory;
  final VoidCallback? onOpenSettings;

  const StatsRow({
    super.key,
    required this.appState,
    this.onShowHistory,
    this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    final paperLabel = switch (appState.paperSize) {
      PaperSize.mm58 => '58mm',
      PaperSize.mm80 => '80mm',
      PaperSize.mm100 => '100mm'
    };
    final chars = EscPosHelper.charsPerLine(appState.paperSize);

    return Row(children: [
      Expanded(
        child: GestureDetector(
          onTap: onShowHistory,
          child: _card(
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.receipt_long_rounded, color: AppColors.primary, size: 16),
                ),
                const Spacer(),
                Icon(Icons.chevron_right_rounded, size: 18, color: Colors.grey[400]),
              ]),
              const SizedBox(height: 10),
              TweenAnimationBuilder<int>(
                tween: IntTween(begin: 0, end: appState.printCount),
                duration: const Duration(milliseconds: 800),
                curve: Curves.easeOutCubic,
                builder: (context, value, child) {
                  return Text('$value', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.primary));
                },
              ),
              const SizedBox(height: 2),
              Text(S.receiptsPrinted, style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
            ]),
          ),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: GestureDetector(
          onTap: onOpenSettings,
          child: _card(
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7B2FBE).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.tune_rounded, color: Color(0xFF7B2FBE), size: 16),
                ),
                const Spacer(),
                Icon(Icons.chevron_right_rounded, size: 18, color: Colors.grey[400]),
              ]),
              const SizedBox(height: 10),
              Text('$paperLabel · ${chars}kar', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF7B2FBE))),
              Text(S.isEn ? 'Printer Settings' : 'Pengaturan Printer', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
            ]),
          ),
        ),
      ),
    ]);
  }

  Widget _card(Widget child) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 3)),
      ],
    ),
    child: child,
  );
}