import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/app_state_provider.dart';
import '../../utils/strings.dart';

class AutoStartCard extends ConsumerWidget {
  final ValueChanged<bool>? onChanged;

  const AutoStartCard({super.key, this.onChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final autoStart = ref.watch(printerConfigProvider.select((s) => s.autoStart));

    return _card(
      Row(children: [
        const Icon(Icons.bolt_rounded, color: Color(0xFF2BBCC4), size: 16),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(S.autoStart, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            Text(S.autoStartDesc, style: const TextStyle(fontSize: 10, color: Colors.grey)),
          ]),
        ),
        Switch.adaptive(
          value: autoStart,
          activeTrackColor: const Color(0xFF2BBCC4),
          onChanged: onChanged,
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
}