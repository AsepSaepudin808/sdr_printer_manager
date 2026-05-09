import 'package:flutter/material.dart';
import '../services/bluetooth_service.dart';
import '../utils/escpos_helper.dart';
import '../utils/strings.dart';

class TextTab extends StatefulWidget {
  final SdrBluetoothService btService;
  final PaperSize paperSize;
  const TextTab({super.key, required this.btService, required this.paperSize});

  @override
  State<TextTab> createState() => _TextTabState();
}

class _TextTabState extends State<TextTab> {
  final TextEditingController _textCtrl = TextEditingController();
  double _fontSize = 20;
  bool _isPrinting = false;

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _print() async {
    if (_textCtrl.text.trim().isEmpty) return;
    setState(() => _isPrinting = true);
    final data = EscPosHelper.textToEscPos(_textCtrl.text, widget.paperSize);
    await widget.btService.sendRaw(data);
    setState(() => _isPrinting = false);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 48),
      child: Column(children: [
        Row(children: [
          Text(S.size, style: const TextStyle(fontSize: 13)),
          const SizedBox(width: 8),
          SizedBox(
              width: 40,
              child: Text(_fontSize.round().toString(),
                  style: const TextStyle(fontWeight: FontWeight.w700))),
          Expanded(
            child: Slider(
                value: _fontSize,
                min: 10,
                max: 40,
                onChanged: (v) => setState(() => _fontSize = v),
                activeColor: const Color(0xFF2BBCC4)),
          ),
        ]),
        const SizedBox(height: 8),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300)),
            child: TextField(
              controller: _textCtrl,
              maxLines: null,
              expands: true,
              style: TextStyle(fontSize: _fontSize),
              decoration: InputDecoration(
                  hintText: S.typeTextHere,
                  contentPadding: const EdgeInsets.all(16),
                  border: InputBorder.none),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _isPrinting ? null : _print,
            icon: _isPrinting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.print_rounded),
            label: Text(_isPrinting ? S.printing : S.printText),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2BBCC4),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ]),
    );
  }
}
