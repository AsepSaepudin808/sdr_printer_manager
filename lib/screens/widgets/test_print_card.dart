import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/app_state_provider.dart';
import '../../providers/escpos_formatter_provider.dart';
import '../../utils/strings.dart';
import '../../utils/colors.dart';
import '../../utils/test_print_template.dart';

class TestPrintCard extends ConsumerWidget {
  final void Function(Uint8List, String) onTestPrint;

  const TestPrintCard({super.key, required this.onTestPrint});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPrinting = ref.watch(printStateProvider.select((s) => s.isPrinting));
    final paperSize = ref.watch(printerConfigProvider.select((s) => s.paperSize));
    final formatter = ref.watch(escposFormatterProvider);

    return _card(
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.print_rounded, color: AppColors.success, size: 18),
          ),
          const SizedBox(width: 10),
          Text(S.testPrint, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: _tpBtn(
              S.shortReceiptPrint,
              Icons.receipt_rounded,
              AppColors.primary,
              isPrinting ? null : () => onTestPrint(
                TestPrintTemplate.buildTestShort(paperSize, formatter),
                S.shortReceiptPrint,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _tpBtn(
              S.fullReceiptPrint,
              Icons.receipt_long_rounded,
              const Color(0xFF7B2FBE),
              isPrinting ? null : () => onTestPrint(
                TestPrintTemplate.buildTestLong(paperSize, formatter),
                S.fullReceiptPrint,
              ),
            ),
          ),
        ]),
        if (isPrinting)
          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)),
                const SizedBox(width: 10),
                Text(S.sending, style: const TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
      ]),
    );
  }

  Widget _card(Widget child) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 3)),
      ],
    ),
    child: child,
  );

  Widget _tpBtn(String label, IconData icon, Color color, VoidCallback? onTap) {
    final isDisabled = onTap == null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: (isDisabled ? Colors.grey : color).withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: (isDisabled ? Colors.grey : color).withValues(alpha: 0.2)),
        ),
        child: Row(children: [
          Icon(icon, color: isDisabled ? Colors.grey : color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isDisabled ? Colors.grey : AppColors.dark)),
          ),
          Icon(Icons.chevron_right_rounded, color: isDisabled ? Colors.grey.shade300 : color, size: 18),
        ]),
      ),
    );
  }
}