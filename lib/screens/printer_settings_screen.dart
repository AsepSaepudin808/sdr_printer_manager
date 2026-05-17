import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import '../utils/escpos_helper.dart';
import '../utils/strings.dart';
import '../utils/test_print_template.dart';

class PrinterSettingsScreen extends StatefulWidget {
  const PrinterSettingsScreen({super.key});
  @override
  State<PrinterSettingsScreen> createState() => _PrinterSettingsScreenState();
}

class _PrinterSettingsScreenState extends State<PrinterSettingsScreen> {
  static const Color _primary = Color(0xFF2BBCC4);

  // STATE VARIABLES
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

  // LOAD PREFS
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

  // TEST PRINT
  Future<void> _testPrint(bool isFull) async {
    final isConnected = await PrintBluetoothThermal.connectionStatus;
    if (!isConnected) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(children: [
          const Icon(Icons.error_outline_rounded, color: Colors.white),
          const SizedBox(width: 10),
          Text(S.isEn ? 'Printer is not connected!' : 'Printer belum terhubung!'),
        ]),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ));
      return;
    }

    final originalChars = EscPosHelper.customCharsPerLineSetting;
    final originalFeed = EscPosHelper.extraFeedSetting;
    final originalCut = EscPosHelper.autoCutSetting;

    final chars = int.tryParse(_charsCtrl.text.trim()) ??
        EscPosHelper.defaultCharsPerLine(_paperSize);
    final defaultChars = EscPosHelper.defaultCharsPerLine(_paperSize);
    EscPosHelper.setCustomCharsPerLine(chars != defaultChars ? chars : 0);
    EscPosHelper.setExtraFeed(_extraFeed);
    EscPosHelper.setAutoCut(_autoCut);

    try {
      final bytes = isFull
          ? TestPrintTemplate.buildTestLong(_paperSize)
          : TestPrintTemplate.buildTestShort(_paperSize);

      await PrintBluetoothThermal.writeBytes(bytes);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(children: [
          const Icon(Icons.check_circle_rounded, color: Colors.white),
          const SizedBox(width: 10),
          Text(S.isEn ? 'Test print sent' : 'Test print berhasil dikirim'),
        ]),
        backgroundColor: const Color(0xFF06C270),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(children: [
          const Icon(Icons.error_outline_rounded, color: Colors.white),
          const SizedBox(width: 10),
          Text('Error: $e'),
        ]),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ));
    } finally {
      EscPosHelper.setCustomCharsPerLine(originalChars);
      EscPosHelper.setExtraFeed(originalFeed);
      EscPosHelper.setAutoCut(originalCut);
    }
  }

  // SAVE LOGIC
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
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(children: [
          const Icon(Icons.check_circle_rounded, color: Colors.white),
          const SizedBox(width: 10),
          Text(S.settingsSaved),
        ]),
        backgroundColor: const Color(0xFF06C270),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ));
      Navigator.pop(context);
    }
  }

  // UI COMPONENTS
  Widget _buildSection(String label, {required Widget child, IconData? icon, Color? iconColor}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            if (icon != null) ...[
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: (iconColor ?? _primary).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: iconColor ?? _primary),
              ),
              const SizedBox(width: 10),
            ],
            Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Color(0xFF2C3E50),
              ),
            ),
          ]),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  // BUILD SCREEN
  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final defaultChars = EscPosHelper.defaultCharsPerLine(_paperSize);
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FC),
      appBar: AppBar(
        backgroundColor: _primary,
        foregroundColor: Colors.white,
        title: Text(
          S.isEn ? 'Printer Settings' : 'Pengaturan Printer',
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
        ),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSection(
            S.printerSize,
            icon: Icons.straighten_rounded,
            iconColor: _primary,
            child: SegmentedButton<PaperSize>(
              segments: const [
                ButtonSegment(
                  value: PaperSize.mm58,
                  label: Text('58mm', style: TextStyle(fontSize: 12)),
                ),
                ButtonSegment(
                  value: PaperSize.mm80,
                  label: Text('80mm', style: TextStyle(fontSize: 12)),
                ),
                ButtonSegment(
                  value: PaperSize.mm100,
                  label: Text('100mm', style: TextStyle(fontSize: 12)),
                ),
              ],
              selected: {_paperSize},
              onSelectionChanged: _onPaperSizeChanged,
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.resolveWith((s) =>
                    s.contains(WidgetState.selected) ? _primary : null),
                foregroundColor: WidgetStateProperty.resolveWith((s) =>
                    s.contains(WidgetState.selected) ? Colors.white : null),
              ),
            ),
          ),

          _buildSection(
            S.charsPerLine,
            icon: Icons.text_fields_rounded,
            iconColor: const Color(0xFF7B2FBE),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  SizedBox(
                    width: 80,
                    child: TextField(
                      controller: _charsCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    S.isEn ? 'chars' : 'kar',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ]),
                const SizedBox(height: 8),
                Text(
                  S.isEn
                      ? 'Default for ${_paperSize.name}: $defaultChars chars'
                      : 'Default untuk ${_paperSize.name}: $defaultChars kar',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),

          _buildSection(
            S.autoCut,
            icon: Icons.content_cut_rounded,
            iconColor: Colors.orange.shade700,
            child: Row(children: [
              Expanded(
                child: Text(
                  S.autoCutDesc,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              Switch.adaptive(
                value: _autoCut,
                activeTrackColor: _primary,
                thumbColor: WidgetStateProperty.resolveWith((s) =>
                    s.contains(WidgetState.selected) ? Colors.white : Colors.grey),
                onChanged: (v) => setState(() => _autoCut = v),
              ),
            ]),
          ),

          _buildSection(
            S.extraFeed,
            icon: Icons.linear_scale_rounded,
            iconColor: Colors.amber.shade700,
            child: Column(
              children: [
                Row(children: [
                  Expanded(
                    child: SliderTheme(
                      data: SliderThemeData(
                        activeTrackColor: _primary,
                        thumbColor: _primary,
                        inactiveTrackColor: _primary.withValues(alpha: 0.2),
                      ),
                      child: Slider(
                        value: _extraFeed.toDouble(),
                        min: 0,
                        max: 20,
                        divisions: 20,
                        label: '$_extraFeed',
                        onChanged: (v) =>
                            setState(() => _extraFeed = v.round()),
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$_extraFeed ${S.lines}',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                ]),
                Text(
                  S.extraFeedDesc,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),

          _buildSection(
            S.isEn ? 'Test Print' : 'Cetak Percobaan',
            icon: Icons.print_rounded,
            iconColor: const Color(0xFF06C270),
            child: Row(children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _testPrint(false),
                  icon: const Icon(Icons.receipt_long_rounded, size: 18),
                  label: Text(S.isEn ? 'Short' : 'Pendek'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber.shade700,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _testPrint(true),
                  icon: const Icon(Icons.receipt_rounded, size: 18),
                  label: Text(S.isEn ? 'Full' : 'Lengkap'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF06C270),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ]),
          ),

          const SizedBox(height: 16),

          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.grey.shade600,
                  side: BorderSide(color: Colors.grey.shade400),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(
                  S.cancel,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  S.save,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ]),

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}