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
  CashDrawerMode _cashDrawerMode = CashDrawerMode.off;
  bool _sessionSummaryCashDrawer = false;
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
    final savedCashDrawer = p.getString('cash_drawer_mode') ?? 'off';
    final cashDrawerMode = savedCashDrawer == 'after'
        ? CashDrawerMode.openAfterPrint
        : savedCashDrawer == 'before'
            ? CashDrawerMode.openBeforePrint
            : CashDrawerMode.off;
    final sessionSummaryCashDrawer = p.getBool('session_summary_cash_drawer') ?? false;
    setState(() {
      _paperSize = paperSize;
      _charsCtrl.text = (savedChars > 0
              ? savedChars
              : EscPosHelper.defaultCharsPerLine(paperSize))
          .toString();
      _autoCut = p.getBool('auto_cut') ?? false;
      _extraFeed = p.getInt('extra_feed') ?? 3;
      _cashDrawerMode = cashDrawerMode;
      _sessionSummaryCashDrawer = sessionSummaryCashDrawer;
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
    final originalCashDrawer = EscPosHelper.cashDrawerModeSetting;

    final chars = int.tryParse(_charsCtrl.text.trim()) ??
        EscPosHelper.defaultCharsPerLine(_paperSize);
    final defaultChars = EscPosHelper.defaultCharsPerLine(_paperSize);
    EscPosHelper.setCustomCharsPerLine(chars != defaultChars ? chars : 0);
    EscPosHelper.setExtraFeed(_extraFeed);
    EscPosHelper.setAutoCut(_autoCut);
    EscPosHelper.setCashDrawerMode(_cashDrawerMode);

    try {
      final bytes = isFull
          ? TestPrintTemplate.buildTestLong(_paperSize)
          : TestPrintTemplate.buildTestShort(_paperSize);

      // CASH DRAWER: Open before print
      if (_cashDrawerMode == CashDrawerMode.openBeforePrint) {
        await PrintBluetoothThermal.writeBytes(EscPosHelper.openCashDrawer());
        await Future.delayed(const Duration(milliseconds: 1500));
      }

      await PrintBluetoothThermal.writeBytes(bytes);

      // CASH DRAWER: Open after print
      if (_cashDrawerMode == CashDrawerMode.openAfterPrint) {
        await Future.delayed(const Duration(milliseconds: 1000));
        await PrintBluetoothThermal.writeBytes(EscPosHelper.openCashDrawer());
      }

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
      EscPosHelper.setCashDrawerMode(originalCashDrawer);
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

    final cashDrawerKey = switch (_cashDrawerMode) {
      CashDrawerMode.openAfterPrint => 'after',
      CashDrawerMode.openBeforePrint => 'before',
      CashDrawerMode.off => 'off',
    };
    await p.setString('cash_drawer_mode', cashDrawerKey);
    EscPosHelper.setCashDrawerMode(_cashDrawerMode);

    await p.setBool('session_summary_cash_drawer', _sessionSummaryCashDrawer);
    EscPosHelper.setSessionSummaryCashDrawer(_sessionSummaryCashDrawer);

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

  Widget _buildCashDrawerChip({
    required CashDrawerMode mode,
    required String label,
    required IconData icon,
  }) {
    final isSelected = _cashDrawerMode == mode;
    return InkWell(
      onTap: () => setState(() => _cashDrawerMode = mode),
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? _primary : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? _primary : Colors.grey.shade400,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? Colors.white : Colors.grey.shade600,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white : Colors.grey.shade700,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
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
            S.cashDrawer,
            icon: Icons.lock_clock_rounded,
            iconColor: Colors.teal.shade700,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(
                      S.cashDrawerDesc,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  Switch.adaptive(
                    value: _cashDrawerMode != CashDrawerMode.off,
                    activeTrackColor: _primary,
                    thumbColor: WidgetStateProperty.resolveWith((s) =>
                        s.contains(WidgetState.selected) ? Colors.white : Colors.grey),
                    onChanged: (v) => setState(() {
                      _cashDrawerMode = v ? CashDrawerMode.openBeforePrint : CashDrawerMode.off;
                    }),
                  ),
                ]),
                if (_cashDrawerMode != CashDrawerMode.off) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: InkWell(
                      onTap: () => setState(() => _sessionSummaryCashDrawer = !_sessionSummaryCashDrawer),
                      borderRadius: BorderRadius.circular(8),
                      child: Row(children: [
                        Icon(
                          _sessionSummaryCashDrawer
                              ? Icons.check_box_rounded
                              : Icons.check_box_outline_blank_rounded,
                          size: 20,
                          color: _sessionSummaryCashDrawer ? Colors.purple.shade600 : Colors.grey.shade500,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            S.cashDrawerOnSessionSummary,
                            style: TextStyle(
                              fontSize: 12,
                              color: _sessionSummaryCashDrawer ? Colors.purple.shade700 : Colors.grey.shade600,
                              fontWeight: _sessionSummaryCashDrawer ? FontWeight.w600 : FontWeight.w500,
                            ),
                          ),
                        ),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: _primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: _buildCashDrawerChip(
                            mode: CashDrawerMode.openBeforePrint,
                            label: S.cashDrawerOpenBeforePrint,
                            icon: Icons.front_hand_rounded,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildCashDrawerChip(
                            mode: CashDrawerMode.openAfterPrint,
                            label: S.cashDrawerOpenAfterPrint,
                            icon: Icons.print_rounded,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
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