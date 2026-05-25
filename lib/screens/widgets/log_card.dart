import 'package:flutter/material.dart';
import '../../utils/strings.dart';

/// Log card widget - shows activity log
class LogCard extends StatelessWidget {
  final List<String> logs;
  final VoidCallback? onViewAll;

  const LogCard({
    super.key,
    required this.logs,
    this.onViewAll,
  });

  @override
  Widget build(BuildContext context) {
    return _card(
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.terminal_rounded, size: 16, color: Colors.grey),
          const SizedBox(width: 8),
          Text(S.activity, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          const Spacer(),
          if (logs.isNotEmpty)
            GestureDetector(
              onTap: onViewAll,
              child: Text(S.viewAll, style: const TextStyle(color: Color(0xFF2BBCC4), fontSize: 11, fontWeight: FontWeight.w600)),
            ),
        ]),
        const SizedBox(height: 10),
        Container(
          height: 110,
          decoration: BoxDecoration(
            color: const Color(0xFF0D1117),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade800.withValues(alpha: 0.5), width: 1),
          ),
          child: logs.isEmpty
            ? Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.terminal_rounded, color: Colors.white24, size: 28),
                  const SizedBox(height: 8),
                  Text(S.noActivity, style: const TextStyle(color: Colors.white38, fontSize: 11)),
                ]),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(10),
                itemCount: logs.length > 8 ? 8 : logs.length,
                itemBuilder: (_, i) => Row(children: [
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.only(right: 8, top: 4),
                    decoration: BoxDecoration(
                      color: logs[i].contains('✅')
                          ? const Color(0xFF06C270)
                          : logs[i].contains('❌')
                              ? const Color(0xFFFF3B30)
                              : Colors.amber.shade600,
                      shape: BoxShape.circle,
                    ),
                  ),
                  Expanded(
                    child: Text(logs[i], style: const TextStyle(color: Color(0xFF7EE787), fontSize: 10, fontFamily: 'monospace', height: 1.4)),
                  ),
                ]),
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
}