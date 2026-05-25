import 'package:flutter/material.dart';
import '../../utils/strings.dart';

/// Auto start card widget - toggle for auto-starting server
class AutoStartCard extends StatelessWidget {
  final bool autoStart;
  final ValueChanged<bool>? onChanged;

  const AutoStartCard({
    super.key,
    required this.autoStart,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
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