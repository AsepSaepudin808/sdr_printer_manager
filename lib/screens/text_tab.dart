import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/bluetooth_service.dart';
import '../utils/escpos_helper.dart';
import '../utils/strings.dart';
import 'printer_settings_screen.dart';

class TextTab extends StatefulWidget {
  final SdrBluetoothService btService;
  final PaperSize paperSize;

  const TextTab({
    super.key,
    required this.btService,
    required this.paperSize,
  });

  @override
  State<TextTab> createState() => _TextTabState();
}

class _TextTabState extends State<TextTab> with SingleTickerProviderStateMixin {
  static const _primary = Color(0xFF2BBCC4);
  PaperSize? _localPaperSize;
  final TextEditingController _textCtrl = TextEditingController();

  bool _isPrinting = false;
  int _alignMode = 0;
  bool _isBold = false;
  bool _isItalic = false;

  late AnimationController _animController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _localPaperSize = widget.paperSize;
    _loadLocalSettings();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.03).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );
  }

  Future<void> _loadLocalSettings() async {
    final p = await SharedPreferences.getInstance();
    final ps = p.getString('paper_size') ?? 'mm80';
    final newSize = ps == 'mm58'
        ? PaperSize.mm58
        : ps == 'mm100'
            ? PaperSize.mm100
            : PaperSize.mm80;

    EscPosHelper.setCustomCharsPerLine(p.getInt('chars_per_line') ?? 0);
    EscPosHelper.setExtraFeed(p.getInt('extra_feed') ?? 3);
    EscPosHelper.setAutoCut(p.getBool('auto_cut') ?? false);

    if (!mounted) return;
    setState(() => _localPaperSize = newSize);
  }

  PaperSize get _paperSize => _localPaperSize ?? widget.paperSize;

  @override
  void dispose() {
    _textCtrl.dispose();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _print() async {
    if (_textCtrl.text.isEmpty) {
      _showSnackBar('Ketik teks terlebih dahulu', isError: true);
      return;
    }

    setState(() => _isPrinting = true);

    final cpl = EscPosHelper.charsPerLine(_paperSize);
    final printAlignMode = _alignMode == 3 ? 0 : _alignMode;

    final wrappedText = _wrapText(
      _textCtrl.text,
      cpl,
      justify: _alignMode == 3,
    );

    final data = EscPosHelper.textToEscPos(
      wrappedText,
      _paperSize,
      isBold: _isBold,
      alignMode: printAlignMode,
    );

    final success = await widget.btService.sendRaw(data);

    if (!mounted) return;
    setState(() => _isPrinting = false);
    _showSnackBar(
      success ? S.printSuccess('Text') : S.printFail,
      isError: !success,
    );
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(
          isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
          color: Colors.white,
          size: 20,
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(message)),
      ]),
      backgroundColor: isError ? const Color(0xFFFF3B30) : const Color(0xFF06C270),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));
  }

  String _wrapText(String text, int width, {bool justify = false}) {
    final lines = text.split('\n');
    final result = <String>[];

    for (var i = 0; i < lines.length; i++) {
      var line = lines[i];
      if (line.isEmpty) {
        result.add('');
        continue;
      }

      String currentLine = line;
      while (currentLine.length > width) {
        int cutIndex = currentLine.lastIndexOf(' ', width);
        if (cutIndex == -1) cutIndex = width;

        final segment = currentLine.substring(0, cutIndex).trim();
        if (justify) {
          result.add(_justifyLine(segment, width));
        } else {
          result.add(segment);
        }

        currentLine = currentLine.substring(cutIndex).trimLeft();
      }

      result.add(currentLine.trimRight());
    }

    return result.join('\n');
  }

  String _justifyLine(String line, int width) {
    final words = line.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

    if (words.length <= 1) return line.padRight(width);

    final totalWordsLength = words.fold(0, (sum, word) => sum + word.length);
    final totalSpacesNeeded = width - totalWordsLength;
    final gaps = words.length - 1;

    final spacePerGap = totalSpacesNeeded ~/ gaps;
    final extraSpaces = totalSpacesNeeded % gaps;

    final sb = StringBuffer();
    for (int i = 0; i < words.length; i++) {
      sb.write(words[i]);
      if (i < gaps) {
        final spacesToApply = spacePerGap + (i < extraSpaces ? 1 : 0);
        sb.write(' ' * spacesToApply);
      }
    }
    return sb.toString();
  }

  void _insertTestPattern() {
    const pattern = "================================\n"
        "         dPrinter Mart\n"
        "           TEST PRINT\n"
        "================================\n"
        "ABCDEFGHIJKLMNOPQRSTUVWXYZ\n"
        "abcdefghijklmnopqrstuvwxyz\n"
        "0123456789 !@#\$%^&*()\n"
        "--------------------------------\n"
        "Receipt OK - All features work!\n"
        "================================\n";

    _textCtrl.text = pattern;
    setState(() {});
  }

  double _getCharWidth(int charsPerLine) {
    final textPainter = TextPainter(
      text: const TextSpan(
        text: 'W',
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 14,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    return textPainter.width;
  }

  @override
  Widget build(BuildContext context) {
    final charsPerLine = EscPosHelper.charsPerLine(_paperSize);
    final charWidth = _getCharWidth(charsPerLine);
    final paperContentWidth = (charWidth * charsPerLine) + 2.0;

    final textAlign = _alignMode == 0
        ? TextAlign.left
        : _alignMode == 1
            ? TextAlign.center
            : _alignMode == 2
                ? TextAlign.right
                : TextAlign.justify;

    final viewPadding = MediaQuery.viewPaddingOf(context);
    final safeTop = viewPadding.top;
    final safeBottom = viewPadding.bottom;
    final safeLeft = viewPadding.left;

    const bottomBarH = 75.0;
    final totalBottomPad = bottomBarH + safeBottom;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFF8FAFB),
            Color(0xFFF0F2F5),
          ],
        ),
      ),
      child: Padding(
        padding: EdgeInsets.only(
          left: 20 + safeLeft,
          right: 20,
          top: 16 + safeTop,
          bottom: totalBottomPad,
        ),
        child: Column(
          children: [
            _buildToolbar(),
            const SizedBox(height: 14),
            Expanded(
              child: _buildReceiptPreview(
                charsPerLine,
                paperContentWidth,
                textAlign,
              ),
            ),
            const SizedBox(height: 14),
            _buildPrintButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbar() {
    const themeColor = Color(0xFF2BBCC4);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: themeColor.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.grey.shade200, width: 1),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Column(children: [
        Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  children: [
                    _formatBtn(Icons.format_align_left_rounded, _alignMode == 0,
                        () => setState(() => _alignMode = 0), 'Rata Kiri', themeColor),
                    _formatBtn(Icons.format_align_center_rounded, _alignMode == 1,
                        () => setState(() => _alignMode = 1), 'Rata Tengah', themeColor),
                    _formatBtn(Icons.format_align_right_rounded, _alignMode == 2,
                        () => setState(() => _alignMode = 2), 'Rata Kanan', themeColor),
                    _formatBtn(Icons.format_align_justify_rounded, _alignMode == 3,
                        () => setState(() => _alignMode = 3), 'Rata Kiri Kanan', themeColor),
                    const SizedBox(width: 6),
                    Container(width: 1.5, height: 22, color: Colors.grey.shade200),
                    const SizedBox(width: 6),
                    _formatBtn(Icons.format_bold_rounded, _isBold,
                        () => setState(() => _isBold = !_isBold), 'Tebal', themeColor),
                    _formatBtn(Icons.format_italic_rounded, _isItalic,
                        () => setState(() => _isItalic = !_isItalic), 'Miring', themeColor),
                  ],
                ),
              ),
            ),
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
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.auto_awesome_rounded,
                    size: 20, color: Color(0xFF7B2FBE)),
              ),
            ),
            GestureDetector(
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PrinterSettingsScreen()),
                );
                await _loadLocalSettings();
              },
              behavior: HitTestBehavior.opaque,
              child: Container(
                margin: const EdgeInsets.only(left: 6),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: themeColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.settings_suggest_rounded, size: 20, color: themeColor),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: themeColor.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.description_rounded, size: 14, color: _primary),
              const SizedBox(width: 6),
              Text(
                '${_paperSize.name.replaceAll('mm', '')}mm • ${EscPosHelper.charsPerLine(_paperSize)} chars',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ],
          ),
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
            color: isActive ? themeColor.withValues(alpha: 0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isActive ? themeColor.withValues(alpha: 0.3) : Colors.transparent,
            ),
          ),
          child: Icon(
            icon,
            size: 20,
            color: isActive ? themeColor : Colors.grey.shade400,
          ),
        ),
      ),
    );
  }

  Widget _buildReceiptPreview(int charsPerLine, double paperContentWidth,
      TextAlign textAlign) {
    return Stack(
      children: [
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF0F2F5),
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        ),
        Column(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 32),
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF2BBCC4), Color(0xFF24AAB1)],
                ),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF2BBCC4).withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  )
                ],
              ),
              child: Center(
                child: Text(
                  '${_paperSize.name.replaceAll('mm', '')}mm THERMAL RECEIPT',
                  style: const TextStyle(
                    fontSize: 10,
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Center(
                  child: Container(
                    width: paperContentWidth + 16,
                    constraints: const BoxConstraints(minHeight: 200),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Stack(
                      children: [
                        // PERFORATED EDGE EFFECT
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
                                  color: Colors.black.withValues(alpha: 0.05),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                )
                              ],
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
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
                                      width: 0.5,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(10, 20, 10, 16),
                          child: TextField(
                            controller: _textCtrl,
                            maxLines: null,
                            textAlign: textAlign,
                            onChanged: (_) => setState(() {}),
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 13,
                              fontWeight: _isBold ? FontWeight.w700 : FontWeight.w400,
                              fontStyle: _isItalic ? FontStyle.italic : FontStyle.normal,
                              color: const Color(0xFF1A1A1A),
                              height: 1.3,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Ketik struk Anda di sini...',
                              hintStyle: TextStyle(
                                color: Colors.grey.shade300,
                                fontFamily: 'sans-serif',
                                fontSize: 12,
                                fontStyle: FontStyle.italic,
                              ),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPrintButton() {
    return GestureDetector(
      onTap: _isPrinting ? null : _print,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _isPrinting ? 1.0 : _scaleAnimation.value,
            child: child,
          );
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
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: (_isPrinting
                        ? Colors.grey
                        : const Color(0xFF2BBCC4))
                    .withValues(alpha: 0.4),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: _isPrinting
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      S.sending.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                        color: Colors.white,
                      ),
                    ),
                  ],
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.print_rounded, size: 24, color: Colors.white),
                    const SizedBox(width: 10),
                    Text(
                      S.printText.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}