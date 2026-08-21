import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/app_state_provider.dart';
import '../../utils/strings.dart';
import '../../utils/colors.dart';
import '../../utils/escpos_helper.dart';

class StatusCard extends ConsumerWidget {
  final VoidCallback? onCopyUrl;

  const StatusCard({super.key, this.onCopyUrl});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paperSize = ref.watch(printerConfigProvider.select((s) => s.paperSize));
    final serverRunning = ref.watch(serverStateProvider.select((s) => s.running));
    final serverPort = ref.watch(serverStateProvider.select((s) => s.port));

    final paperLabel = switch (paperSize) {
      PaperSize.mm58 => '58mm',
      PaperSize.mm80 => '80mm',
      PaperSize.mm100 => '100mm'
    };

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: serverRunning
              ? [const Color(0xFF034B2F), const Color(0xFF06874F)]
              : [AppColors.primary, AppColors.primary.withValues(alpha: 0.85)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: (serverRunning ? AppColors.success : AppColors.primary)
                .withValues(alpha: 0.35),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(22),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.8, end: 1.0),
            duration: const Duration(milliseconds: 1200),
            curve: Curves.easeInOut,
            builder: (context, value, child) {
              return Transform.scale(
                scale: value,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: serverRunning
                        ? AppColors.success
                        : Colors.grey.shade400,
                    shape: BoxShape.circle,
                    boxShadow: serverRunning
                        ? [
                            BoxShadow(
                              color: AppColors.success.withValues(alpha: 0.6),
                              blurRadius: 8,
                              spreadRadius: 2,
                            )
                          ]
                        : null,
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 10),
          Text(
            serverRunning ? S.printerActive : S.printerInactive,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(children: [
              const Icon(Icons.description_rounded, color: Colors.white70, size: 14),
              const SizedBox(width: 4),
              Text(paperLabel, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
            ]),
          ),
        ]),
        const SizedBox(height: 16),
        if (serverRunning)
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: 'http://127.0.0.1:$serverPort'));
              onCopyUrl?.call();
            },
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'http://127.0.0.1:$serverPort',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'monospace',
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(S.tapToCopy, style: const TextStyle(color: Colors.white38, fontSize: 10)),
                    ]),
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.copy_rounded, color: Colors.white, size: 18),
                ),
              ]),
            ),
          )
        else
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(children: [
              const Icon(Icons.wifi_rounded, color: Colors.white54, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(S.pressToActivate, style: const TextStyle(color: Colors.white54, fontSize: 12))),
            ]),
          ),
      ]),
    );
  }
}