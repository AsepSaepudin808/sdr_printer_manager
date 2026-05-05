import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/escpos_helper.dart';
import '../utils/strings.dart';

class PrinterSettingsScreen extends StatefulWidget {
  const PrinterSettingsScreen({super.key});
  @override
  State<PrinterSettingsScreen> createState() => _PrinterSettingsScreenState();
}

class _PrinterSettingsScreenState extends State<PrinterSettingsScreen> {
  static const Color _primary = Color(0xFF2BBCC4);

  PaperSize _paperSize = PaperSize.mm80;
  final TextEditingController _charsCtrl = TextEditingController();
  bool _autoCut = false;
  int _extraFeed = 3;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  @override
  void dispose() {
    _charsCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    final ps = p.getString('paper_size') ?? 'mm80';
    final paperSize = ps == 'mm58'
        ? PaperSize.mm58
        : ps == 'mm100'
            ? PaperSize.mm100
            : PaperSize.mm80;
    final savedChars = p.getInt('chars_per_line') ?? 0;
    setState(() {
      _paperSize = paperSize;
      _charsCtrl.text = (savedChars > 0
              ? savedChars
              : EscPosHelper.defaultCharsPerLine(paperSize))
          .toString();
      _autoCut = p.getBool('auto_cut') ?? false;
      _extraFeed = p.getInt('extra_feed') ?? 3;
      _loaded = true;
    });
  }

  void _onPaperSizeChanged(Set<PaperSize> v) {
    final s = v.first;
    setState(() {
      _paperSize = s;
      _charsCtrl.text = EscPosHelper.defaultCharsPerLine(s).toString();
    });
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    final key = switch (_paperSize) {
      PaperSize.mm58 => 'mm58',
      PaperSize.mm80 => 'mm80',
      PaperSize.mm100 => 'mm100'
    };
    await p.setString('paper_size', key);

    final chars = int.tryParse(_charsCtrl.text.trim()) ??
        EscPosHelper.defaultCharsPerLine(_paperSize);
    final defaultChars = EscPosHelper.defaultCharsPerLine(_paperSize);
    if (chars != defaultChars && chars > 0) {
      await p.setInt('chars_per_line', chars);
    } else {
      await p.remove('chars_per_line');
    }
    EscPosHelper.setCustomCharsPerLine(chars != defaultChars ? chars : 0);

    await p.setBool('auto_cut', _autoCut);
    EscPosHelper.setAutoCut(_autoCut);

    await p.setInt('extra_feed', _extraFeed);
    EscPosHelper.setExtraFeed(_extraFeed);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(S.settingsSaved),
        backgroundColor: const Color(0xFF06C270),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final defaultChars = EscPosHelper.defaultCharsPerLine(_paperSize);
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FC),
      appBar: AppBar(
        backgroundColor: _primary,
        foregroundColor: Colors.white,
        title: Text(S.isEn ? 'Printer Settings' : 'Pengaturan Printer',
            style: const TextStyle(fontWeight: FontWeight.w700)),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Ukuran Kertas
          _section(S.printerSize,
              child: SegmentedButton<PaperSize>(
                segments: const [
                  ButtonSegment(
                      value: PaperSize.mm58,
                      label: Text('58mm', style: TextStyle(fontSize: 12))),
                  ButtonSegment(
                      value: PaperSize.mm80,
                      label: Text('80mm', style: TextStyle(fontSize: 12))),
                  ButtonSegment(
                      value: PaperSize.mm100,
                      label: Text('100mm', style: TextStyle(fontSize: 12))),
                ],
                selected: {_paperSize},
                onSelectionChanged: _onPaperSizeChanged,
                style: ButtonStyle(
                  backgroundColor: WidgetStateProperty.resolveWith((s) =>
                      s.contains(WidgetState.selected) ? _primary : null),
                  foregroundColor: WidgetStateProperty.resolveWith((s) =>
                      s.contains(WidgetState.selected) ? Colors.white : null),
                ),
              )),
          // Karakter per Baris
          _section(S.charsPerLine,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    SizedBox(
                      width: 80,
                      child: TextField(
                        controller: _charsCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(S.isEn ? 'chars' : 'kar',
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                  ]),
                  const SizedBox(height: 6),
                  Text(
                    S.isEn
                        ? 'Default for ${_paperSize.name}: $defaultChars chars. Adjust if text doesn\'t fit.'
                        : 'Default untuk ${_paperSize.name}: $defaultChars kar. Sesuaikan jika teks tidak pas.',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  ),
                ],
              )),
          // Auto Cut
          _section(S.autoCut,
              child: Row(children: [
                Expanded(
                    child: Text(S.autoCutDesc,
                        style: const TextStyle(fontSize: 13))),
                Switch.adaptive(
                  value: _autoCut,
                  activeTrackColor: _primary,
                  onChanged: (v) => setState(() => _autoCut = v),
                ),
              ])),
          // Extra Feed
          _section(S.extraFeed,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: Slider(
                        value: _extraFeed.toDouble(),
                        min: 0,
                        max: 20,
                        divisions: 20,
                        activeColor: _primary,
                        label: '$_extraFeed',
                        onChanged: (v) =>
                            setState(() => _extraFeed = v.round()),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text('$_extraFeed ${S.lines}',
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                  ]),
                  const SizedBox(height: 4),
                  Text(S.extraFeedDesc,
                      style:
                          TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                ],
              )),
          const SizedBox(height: 24),
          Row(children: [
            Expanded(
                child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.grey[600],
                side: BorderSide(color: Colors.grey.shade400),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(S.cancel,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            )),
            const SizedBox(width: 12),
            Expanded(
                child: ElevatedButton(
              onPressed: _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: _primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(S.save,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            )),
          ]),
        ],
      ),
    );
  }

  Widget _section(String label, {required Widget child}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(fontSize: 14, color: Colors.grey.shade600),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          contentPadding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
        ),
        child: child,
      ),
    );
  }
}
