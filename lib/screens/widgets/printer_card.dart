import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/app_state_provider.dart';
import '../../utils/strings.dart';
import '../../utils/colors.dart';

class PrinterCard extends ConsumerWidget {
  final VoidCallback? onSelectPrinter;
  final VoidCallback? onToggleServer;

  const PrinterCard({
    super.key,
    this.onSelectPrinter,
    this.onToggleServer,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(langProvider);
    final printer = ref.watch(printerConfigProvider.select((s) => s.printer));
    final btConnected = ref.watch(printerConfigProvider.select((s) => s.btConnected));
    final serverRunning = ref.watch(serverStateProvider.select((s) => s.running));
    final connecting = ref.watch(serverStateProvider.select((s) => s.connecting));

    final hasPrinter = printer != null;

    return _card(
      Row(children: [
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: hasPrinter
                  ? [AppColors.primary.withValues(alpha: 0.15), AppColors.primary.withValues(alpha: 0.05)]
                  : [Colors.grey.shade200, Colors.grey.shade100],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(Icons.print_rounded, color: hasPrinter ? AppColors.primary : Colors.grey, size: 26),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(
                  printer?.name ?? S.noPrinter,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: hasPrinter ? AppColors.dark : Colors.grey,
                  ),
                ),
              ),
              if (btConnected)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: AppColors.success,
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: AppColors.success.withValues(alpha: 0.5), blurRadius: 4)],
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(S.connected, style: const TextStyle(fontSize: 10, color: AppColors.success, fontWeight: FontWeight.w600)),
                  ]),
                ),
            ]),
            if (hasPrinter)
              GestureDetector(
                onTap: () => _showPrinterDetails(context, printer.address, printer.name),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('ID: ${printer.address}', maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10, color: Colors.grey.shade600, fontFamily: 'monospace')),
                      const SizedBox(width: 4),
                      Icon(Icons.content_copy_rounded, size: 12, color: Colors.grey.shade500),
                    ],
                  ),
                ),
              )
            else
              const SizedBox(height: 4),
              Text(S.selectPrinterFirst, style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
          ]),
        ),
        const SizedBox(width: 12),
        Column(children: [
          GestureDetector(
            onTap: serverRunning ? null : onSelectPrinter,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: (serverRunning ? Colors.grey : AppColors.primary).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: (serverRunning ? Colors.grey : AppColors.primary).withValues(alpha: 0.3)),
              ),
              child: Text(hasPrinter ? S.change : S.select,
                style: TextStyle(color: serverRunning ? Colors.grey : AppColors.primary, fontWeight: FontWeight.w700, fontSize: 12)),
            ),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: connecting ? null : onToggleServer,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                color: connecting
                    ? Colors.grey.shade400
                    : serverRunning
                        ? AppColors.danger
                        : AppColors.success,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: (connecting
                        ? Colors.grey
                        : serverRunning
                            ? AppColors.danger
                            : AppColors.success).withValues(alpha: 0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    connecting
                        ? Icons.hourglass_top_rounded
                        : serverRunning
                            ? Icons.power_settings_new_rounded
                            : Icons.play_arrow_rounded,
                    size: 16,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    connecting
                        ? '...'
                        : serverRunning
                            ? 'OFF'
                            : 'ON',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _card(Widget child) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 3))]
    ),
    child: child,
  );

  void _showPrinterDetails(BuildContext context, String address, String name) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 50,
                  height: 5,
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(99)),
                ),
              ),
              const SizedBox(height: 16),
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.print_rounded, color: AppColors.primary, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(S.printerId, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                ])),
              ]),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(10)),
                child: Row(children: [
                  Icon(Icons.fingerprint_rounded, color: Colors.grey.shade500, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: SelectableText(address,
                    style: const TextStyle(fontSize: 14, color: Colors.black87, fontFamily: 'monospace', letterSpacing: 1))),
                ]),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: address));
                    if (context.mounted) Navigator.pop(context);
                  },
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: Text(S.copyId),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}