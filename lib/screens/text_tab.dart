import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_state_provider.dart';
import '../providers/escpos_formatter_provider.dart';
import '../providers/bluetooth_provider.dart';
import '../providers/history_provider.dart';
import '../models/print_history.dart';
import '../utils/escpos_helper.dart';
import '../utils/strings.dart';
import '../utils/colors.dart';
import 'printer_settings_screen.dart';

class TextTab extends ConsumerStatefulWidget {
  final bool isKeyboardVisible;
  const TextTab({super.key, this.isKeyboardVisible = false});

  @override
  ConsumerState<TextTab> createState() => _TextTabState();
}

class _TextTabState extends ConsumerState<TextTab>
    with SingleTickerProviderStateMixin {
  static const _primary = AppColors.primary;

  final TextEditingController _textCtrl = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  bool _isPrinting = false;
  int _alignMode = 3;
  bool _isBold = false;
  bool _isItalic = false;
  bool _isTestPattern = false;

  late AnimationController _animController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _loadLocalSettings();
    _animController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat(reverse: true);
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.03).animate(
        CurvedAnimation(parent: _animController, curve: Curves.easeInOut));
  }

  Future<void> _loadLocalSettings() async {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _focusNode.dispose();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _print() async {
    if (_textCtrl.text.isEmpty) {
      _showSnackBar(S.typeTextFirst, isError: true);
      return;
    }

    setState(() => _isPrinting = true);

    final paperSize = ref.read(printerConfigProvider).paperSize;
    final formatter = ref.read(escposFormatterProvider);
    final cpl = formatter.charsPerLine(paperSize);
    final printAlignMode = _alignMode == 3 ? 0 : _alignMode;

    final wrappedText =
        _wrapText(_textCtrl.text, cpl, justify: _alignMode == 3);
    final data = formatter.textToEscPos(wrappedText, paperSize,
        isBold: _isBold, alignMode: printAlignMode);

    final btService = ref.read(bluetoothServiceProvider);
    final success = await btService.sendRaw(data);

    if (mounted) {
      setState(() => _isPrinting = false);
      if (success) {
        ref.read(historyNotifierProvider.notifier).add(PrintHistory(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              type: 'text',
              label: 'Text Print',
              timestamp: DateTime.now(),
              success: true,
              dataSize: data.length,
              source: 'manual',
            ));
        _showSnackBar(S.printSuccess('Text'));
      } else {
        _showSnackBar(S.printFail, isError: true);
      }
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(
            isError
                ? Icons.error_outline_rounded
                : Icons.check_circle_outline_rounded,
            color: Colors.white,
            size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(message)),
      ]),
      backgroundColor:
          isError ? const Color(0xFFFF3B30) : const Color(0xFF06C270),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));
  }

  String _wrapText(String text, int width, {bool justify = false}) {
    final lines = text.split('\n');
    final result = <String>[];
    for (var line in lines) {
      if (line.isEmpty) {
        result.add('');
        continue;
      }
      String current = line;
      while (current.length > width) {
        int cut = current.lastIndexOf(' ', width);
        if (cut == -1) cut = width;
        final seg = current.substring(0, cut).trim();
        result.add(justify ? _justifyLine(seg, width) : seg);
        current = current.substring(cut).trimLeft();
      }
      result.add(current.trimRight());
    }
    return result.join('\n');
  }

  String _justifyLine(String line, int width) {
    final words =
        line.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.length <= 1) return line.padRight(width);
    final totalLen = words.fold(0, (sum, w) => sum + w.length);
    final totalSpaces = width - totalLen;
    final gaps = words.length - 1;
    final spacePerGap = totalSpaces ~/ gaps;
    final extras = totalSpaces % gaps;
    final sb = StringBuffer();
    for (int i = 0; i < words.length; i++) {
      sb.write(words[i]);
      if (i < gaps) sb.write(' ' * (spacePerGap + (i < extras ? 1 : 0)));
    }
    return sb.toString();
  }

  void _insertTestPattern() {
    _isTestPattern = true;
    final paperSize = ref.read(printerConfigProvider).paperSize;
    final cpl = ref.read(escposFormatterProvider).charsPerLine(paperSize);
    final now = DateTime.now();
    final date =
        '${now.day.toString().padLeft(2, '0')}-${now.month.toString().padLeft(2, '0')}-${now.year}';
    final time =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    final buf = StringBuffer();
    String sep(String c) => c * cpl;

    if (_alignMode == 0) {
      buf.writeln(sep('='));
      buf.writeln('dPrinter Mart');
      buf.writeln('Test Print - Rata Kiri');
      buf.writeln(sep('='));
      buf.writeln('Tanggal : $date');
      buf.writeln('Waktu   : $time');
      buf.writeln('No. Trx : TRX-TEST-001');
      buf.writeln('Kasir   : Admin');
      buf.writeln(sep('-'));
      buf.writeln('Kopi Susu       x1   15.000');
      buf.writeln('Teh Manis       x2   20.000');
      buf.writeln('Nasi Goreng     x1   25.000');
      buf.writeln(sep('-'));
      buf.writeln('Total                60.000');
      buf.writeln(sep('='));
      buf.writeln('Terima Kasih');
    } else if (_alignMode == 1) {
      buf.writeln(sep('='));
      buf.writeln('dPrinter Mart');
      buf.writeln('Test Print - Rata Tengah');
      buf.writeln(sep('='));
      buf.writeln('Tgl: $date  Jam: $time');
      buf.writeln('No: TRX-TEST-001');
      buf.writeln('Kasir: Admin');
      buf.writeln(sep('-'));
      buf.writeln('Kopi Susu  x1  15.000');
      buf.writeln('Teh Manis  x2  20.000');
      buf.writeln('Nasi Goreng  x1  25.000');
      buf.writeln(sep('-'));
      buf.writeln('Total : 60.000');
      buf.writeln(sep('='));
      buf.writeln('Terima Kasih!');
    } else if (_alignMode == 2) {
      buf.writeln(sep('='));
      buf.writeln('dPrinter Mart');
      buf.writeln('Test Print - Rata Kanan');
      buf.writeln(sep('='));
      buf.writeln('Tgl: $date');
      buf.writeln('Jam: $time');
      buf.writeln('No: TRX-TEST-001');
      buf.writeln('Kasir: Admin');
      buf.writeln(sep('-'));
      buf.writeln('15.000   x1       Kopi Susu');
      buf.writeln('20.000   x2       Teh Manis');
      buf.writeln('25.000   x1     Nasi Goreng');
      buf.writeln(sep('-'));
      buf.writeln('60.000 : Total');
      buf.writeln(sep('='));
      buf.writeln('Terima Kasih!');
    } else {
      String lr(String l, String r) {
        final g = cpl - l.length - r.length;
        return g <= 0 ? '$l $r' : l + ' ' * g + r;
      }

      String cntr(String t) {
        if (t.length >= cpl) return t;
        return ' ' * ((cpl - t.length) ~/ 2) + t;
      }

      buf.writeln(sep('='));
      buf.writeln(cntr('dPrinter Mart'));
      buf.writeln(cntr('Test Print - Rata Kiri Kanan'));
      buf.writeln(sep('='));
      buf.writeln(lr('Tgl: $date', 'Jam: $time'));
      buf.writeln(lr('No: TRX-TEST-001', 'Kasir: Admin'));
      buf.writeln(sep('-'));
      buf.writeln(lr('Kopi Susu x1', '15.000'));
      buf.writeln(lr('Teh Manis x2', '20.000'));
      buf.writeln(lr('Nasi Goreng x1', '25.000'));
      buf.writeln(sep('-'));
      buf.writeln(lr('Subtotal', '60.000'));
      buf.writeln(lr('Pajak 11%', '6.600'));
      buf.writeln(sep('='));
      buf.writeln(lr('TOTAL', '66.600'));
      buf.writeln(sep('='));
      buf.writeln(cntr('Terima Kasih!'));
    }

    _textCtrl.text = buf.toString().trimRight();
    setState(() {});
  }

  double _getFullLineWidth(int charsPerLine) {
    final tp = TextPainter(
      text: TextSpan(
          text: '0' * charsPerLine,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 14)),
      textDirection: TextDirection.ltr,
    )..layout();
    return tp.width;
  }

  void _clearAll() => setState(() {
        _textCtrl.clear();
        _isTestPattern = false;
      });

  @override
  Widget build(BuildContext context) {
    final paperSize =
        ref.watch(printerConfigProvider.select((s) => s.paperSize));
    final charsPerLine =
        ref.watch(escposFormatterProvider).charsPerLine(paperSize);
    final lineWidth = _getFullLineWidth(charsPerLine);
    final paperContentWidth = lineWidth + 8.0;

    final textAlign = _alignMode == 0
        ? TextAlign.left
        : _alignMode == 1
            ? TextAlign.center
            : _alignMode == 2
                ? TextAlign.right
                : TextAlign.justify;
    final vp = MediaQuery.viewPaddingOf(context);

    return Container(
      decoration: const BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFF8FAFB), Color(0xFFF0F2F5)])),
      child: Padding(
        padding: EdgeInsets.only(
            left: 20 + vp.left, right: 20, top: 16 + vp.top, bottom: 8.0),
        child: Column(children: [
          _buildToolbar(paperSize, charsPerLine),
          const SizedBox(height: 14),
          Expanded(
              child: _buildReceiptPreview(
                  charsPerLine, paperContentWidth, textAlign, paperSize)),
          const SizedBox(height: 14),
          _buildPrintButton(),
        ]),
      ),
    );
  }

  Widget _buildToolbar(PaperSize paperSize, int charsPerLine) {
    const themeColor = Color(0xFF2BBCC4);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: themeColor.withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, 4))
        ],
        border: Border.all(color: Colors.grey.shade200),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Column(children: [
        Row(children: [
          Expanded(
              child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(children: [
              _formatBtn(Icons.format_align_left_rounded, _alignMode == 0, () {
                setState(() {
                  _alignMode = 0;
                  if (_isTestPattern) _insertTestPattern();
                });
              }, S.alignLeft, themeColor),
              _formatBtn(Icons.format_align_center_rounded, _alignMode == 1,
                  () {
                setState(() {
                  _alignMode = 1;
                  if (_isTestPattern) _insertTestPattern();
                });
              }, S.center, themeColor),
              _formatBtn(Icons.format_align_right_rounded, _alignMode == 2, () {
                setState(() {
                  _alignMode = 2;
                  if (_isTestPattern) _insertTestPattern();
                });
              }, S.right, themeColor),
              _formatBtn(Icons.format_align_justify_rounded, _alignMode == 3,
                  () {
                setState(() {
                  _alignMode = 3;
                  if (_isTestPattern) _insertTestPattern();
                });
              }, S.justify, themeColor),
              const SizedBox(width: 6),
              Container(width: 1.5, height: 22, color: Colors.grey.shade200),
              const SizedBox(width: 6),
              _formatBtn(Icons.format_bold_rounded, _isBold,
                  () => setState(() => _isBold = !_isBold), S.bold, themeColor),
              _formatBtn(
                  Icons.format_italic_rounded,
                  _isItalic,
                  () => setState(() => _isItalic = !_isItalic),
                  S.italic,
                  themeColor),
            ]),
          )),
          const SizedBox(width: 6),
          Container(width: 1.5, height: 24, color: Colors.grey.shade200),
          const SizedBox(width: 6),
          GestureDetector(
              onTap: _insertTestPattern,
              behavior: HitTestBehavior.opaque,
              child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: const Color(0xFF7B2FBE).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.auto_awesome_rounded,
                      size: 20, color: Color(0xFF7B2FBE)))),
          GestureDetector(
              onTap: () async {
                await Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const PrinterSettingsScreen()));
                await _loadLocalSettings();
                if (_isTestPattern) _insertTestPattern();
              },
              behavior: HitTestBehavior.opaque,
              child: Container(
                  margin: const EdgeInsets.only(left: 6),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: themeColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.settings_suggest_rounded,
                      size: 20, color: themeColor))),
          if (_textCtrl.text.isNotEmpty)
            GestureDetector(
                onTap: () {
                  showDialog(
                      context: context,
                      builder: (_) => AlertDialog(
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                            title: const Text('Hapus Semua?',
                                style: TextStyle(fontWeight: FontWeight.w800)),
                            content: const Text(
                                'Semua teks yang sudah diketik akan dihapus.'),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: Text('Batal',
                                      style: TextStyle(
                                          color: Colors.grey.shade500))),
                              TextButton(
                                  onPressed: () {
                                    Navigator.pop(context);
                                    _clearAll();
                                  },
                                  child: const Text('Hapus',
                                      style: TextStyle(
                                          color: Colors.red,
                                          fontWeight: FontWeight.w700))),
                            ],
                          ));
                },
                behavior: HitTestBehavior.opaque,
                child: Container(
                    margin: const EdgeInsets.only(left: 6),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.delete_sweep_rounded,
                        size: 20, color: Colors.red))),
        ]),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
              color: themeColor.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(8)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.description_rounded, size: 14, color: _primary),
            const SizedBox(width: 6),
            Text(
                '${paperSize.name.replaceAll('mm', '')}mm • $charsPerLine chars',
                style:
                    const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
          ]),
        ),
      ]),
    );
  }

  Widget _formatBtn(IconData icon, bool isActive, VoidCallback onTap,
      String tooltip, Color themeColor) {
    return Tooltip(
        message: tooltip,
        child: GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: isActive
                        ? themeColor.withValues(alpha: 0.15)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: isActive
                            ? themeColor.withValues(alpha: 0.3)
                            : Colors.transparent)),
                child: Icon(icon,
                    size: 20,
                    color: isActive ? themeColor : Colors.grey.shade400))));
  }

  Widget _buildReceiptPreview(int charsPerLine, double paperContentWidth,
      TextAlign textAlign, PaperSize paperSize) {
    return LayoutBuilder(builder: (context, constraints) {
      const headerApproxHeight = 54.0;
      final minBoxHeight = (constraints.maxHeight - headerApproxHeight)
          .clamp(200.0, double.infinity);
      return Stack(children: [
        Positioned.fill(
            child: GestureDetector(
                onTap: () => _focusNode.requestFocus(),
                child: Container(
                    decoration: BoxDecoration(
                        color: const Color(0xFFF0F2F5),
                        borderRadius: BorderRadius.circular(20))))),
        Column(children: [
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 32),
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFF2BBCC4), Color(0xFF24AAB1)]),
              borderRadius:
                  const BorderRadius.vertical(bottom: Radius.circular(12)),
              boxShadow: [
                BoxShadow(
                    color: const Color(0xFF2BBCC4).withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4))
              ],
            ),
            child: Center(
                child: Text(
                    '${paperSize.name.replaceAll('mm', '')}mm THERMAL RECEIPT',
                    style: const TextStyle(
                        fontSize: 10,
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5))),
          ),
          const SizedBox(height: 12),
          Expanded(
              child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Center(
                child: GestureDetector(
                    onTap: () => _focusNode.requestFocus(),
                    child: Container(
                      width: paperContentWidth + 16,
                      constraints: BoxConstraints(minHeight: minBoxHeight),
                      decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black.withValues(alpha: 0.08),
                                blurRadius: 20,
                                offset: const Offset(0, 8))
                          ]),
                      child: Stack(children: [
                        Positioned(
                            left: 0,
                            right: 0,
                            top: 0,
                            child: Container(
                                height: 8,
                                decoration: BoxDecoration(
                                    color: const Color(0xFFF0F2F5),
                                    borderRadius: const BorderRadius.vertical(
                                        top: Radius.circular(6)),
                                    boxShadow: [
                                      BoxShadow(
                                          color: Colors.black
                                              .withValues(alpha: 0.05),
                                          blurRadius: 4,
                                          offset: const Offset(0, 2))
                                    ]),
                                child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceEvenly,
                                    children: List.generate(
                                        30,
                                        (_) => Container(
                                            width: 4,
                                            height: 4,
                                            decoration: BoxDecoration(
                                                color: const Color(0xFFF0F2F5),
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                    color: Colors.grey.shade300,
                                                    width: 0.5))))))),
                        if (_textCtrl.text.isEmpty)
                          Positioned.fill(
                              child: IgnorePointer(
                                  child: Center(
                                      child: Text(S.touchToEnterText,
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                              color: Colors.grey.shade300,
                                              fontSize: 13,
                                              fontStyle: FontStyle.italic))))),
                        Padding(
                            padding: const EdgeInsets.fromLTRB(10, 20, 10, 16),
                            child: TextField(
                                controller: _textCtrl,
                                focusNode: _focusNode,
                                maxLines: null,
                                textAlign: textAlign,
                                onChanged: (_) =>
                                    setState(() => _isTestPattern = false),
                                style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 13,
                                    fontWeight: _isBold
                                        ? FontWeight.w700
                                        : FontWeight.w400,
                                    fontStyle: _isItalic
                                        ? FontStyle.italic
                                        : FontStyle.normal,
                                    color: const Color(0xFF1A1A1A),
                                    height: 1.3),
                                decoration: const InputDecoration(
                                    border: InputBorder.none,
                                    isDense: true,
                                    contentPadding: EdgeInsets.zero))),
                      ]),
                    ))),
          )),
        ]),
      ]);
    });
  }

  Widget _buildPrintButton() {
    return GestureDetector(
      onTap: _isPrinting ? null : _print,
      child: AnimatedBuilder(
          animation: _scaleAnimation,
          builder: (context, child) {
            return Transform.scale(
                scale: _isPrinting ? 1.0 : _scaleAnimation.value, child: child);
          },
          child: Container(
            width: double.infinity,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                  colors: _isPrinting
                      ? [Colors.grey.shade400, Colors.grey.shade500]
                      : [const Color(0xFF2BBCC4), const Color(0xFF24AAB1)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight),
              boxShadow: [
                BoxShadow(
                    color: (_isPrinting ? Colors.grey : const Color(0xFF2BBCC4))
                        .withValues(alpha: 0.4),
                    blurRadius: 16,
                    offset: const Offset(0, 6))
              ],
            ),
            child: _isPrinting
                ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white.withValues(alpha: 0.9))),
                    const SizedBox(width: 12),
                    Text(S.sending.toUpperCase(),
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1,
                            color: Colors.white)),
                  ])
                : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.print_rounded,
                        size: 24, color: Colors.white),
                    const SizedBox(width: 10),
                    Text(S.printText.toUpperCase(),
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                            color: Colors.white)),
                  ]),
          )),
    );
  }
}
