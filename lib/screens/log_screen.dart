import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// LOG SCREEN
class LogScreen extends StatelessWidget {
  final List<String> logs;
  const LogScreen({super.key, required this.logs});

  // BUILD UI
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Log Lengkap'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy, color: Colors.white),
            tooltip: 'Salin semua log',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: logs.join('\n')));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Log disalin!')),
              );
            },
          ),
        ],
      ),
      body: Container(
        color: Colors.grey[900],
        child: ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: logs.length,
          itemBuilder: (_, i) => Text(
            logs[i],
            style: const TextStyle(
                color: Colors.greenAccent,
                fontSize: 12,
                fontFamily: 'monospace'),
          ),
        ),
      ),
    );
  }
}
