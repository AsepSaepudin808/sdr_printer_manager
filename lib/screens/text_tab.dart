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

class _TextTabState extends State<TextTab> {
  PaperSize? _localPaperSize;
  final TextEditingController _textCtrl = TextEditingController();

  bool _isPrinting = false;
  int _alignMode = 0;
  bool _isBold = false;

  @override
  void initState() {
    super.initState();
    _localPaperSize = widget.paperSize;
    _loadLocalSettings();
  }

  Future<void> _loadLocalSettings() async {
    final p = await SharedPreferences.getInstance();
    final ps = p.getString('paper_size') ?? 'mm80';
    final newSize = ps == 'mm58'
        ? PaperSize.mm58
        : ps == 'mm100'
            ? PaperSize.mm100
            : PaperSize.mm80;

    // Update EscPosHelper with latest settings.
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
    super.dispose();
  }

  Future<void> _print() async {
    if (_textCtrl.text.isEmpty) return;

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

    await widget.btService.sendRaw(data);

    if (!mounted) return;
    setState(() => _isPrinting = false);
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
    final words =
        line.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

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
    const pattern = "TEST PRINT PATTERN\n"
        "================================\n"
        "ABCDEFG HIJKLMNOP QRSTUV WXYZ\n"
        "abcdefg hijklmnop qrstuv wxyz\n"
        "0123456789 !@#\$%^&*()_+-=\n"
        "--------------------------------\n"
        "dPrinter Mart - OK\n";

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

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFFF8FAFB),
            Colors.white.withValues(alpha: 0.8),
          ],
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final shortestSide = constraints.maxWidth < constraints.maxHeight
              ? constraints.maxWidth
              : constraints.maxHeight;

          final isMobile = shortestSide < 450;
          final safeInset = MediaQuery.of(context).viewPadding.bottom;

          // Curved bar in main_shell height ≈ 65; plus gesture nav inset on HP.
          // Tablet should be tighter; mobile needs more space.
          final basePad = isMobile ? 115.0 : 80.0;
          final computedBottomPad = basePad + safeInset;

          // Extra padding inside preview scroll so the bottom controls never overlap.
          final previewBottomPad = computedBottomPad - (isMobile ? 15 : 20);

          return Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, computedBottomPad),
            child: Column(
              children: [
                // ── MODERN GLASS TOOLBAR ──
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF2BBCC4).withValues(alpha: 0.08),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          child: Row(
                            children: [
                              _formatBtn(
                                icon: Icons.format_align_left_rounded,
                                isActive: _alignMode == 0,
                                onTap: () => setState(() => _alignMode = 0),
                                tooltip: 'Rata Kiri',
                              ),
                              _formatBtn(
                                icon: Icons.format_align_center_rounded,
                                isActive: _alignMode == 1,
                                onTap: () => setState(() => _alignMode = 1),
                                tooltip: 'Rata Tengah',
                              ),
                              _formatBtn(
                                icon: Icons.format_align_right_rounded,
                                isActive: _alignMode == 2,
                                onTap: () => setState(() => _alignMode = 2),
                                tooltip: 'Rata Kanan',
                              ),
                              _formatBtn(
                                icon: Icons.format_align_justify_rounded,
                                isActive: _alignMode == 3,
                                onTap: () => setState(() => _alignMode = 3),
                                tooltip: 'Rata Kanan Kiri',
                              ),
                              const SizedBox(width: 8),
                              Container(
                                width: 1.5,
                                height: 24,
                                color: Colors.grey.shade200,
                              ),
                              const SizedBox(width: 8),
                              _formatBtn(
                                icon: Icons.format_bold_rounded,
                                isActive: _isBold,
                                onTap: () => setState(() => _isBold = !_isBold),
                                tooltip: 'Tebal',
                              ),
                              _formatBtn(
                                icon: Icons.text_fields_rounded,
                                isActive: false,
                                onTap: _insertTestPattern,
                                tooltip: 'Teks Tes',
                                color: const Color(0xFF6C757D),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 1.5,
                        height: 24,
                        color: Colors.grey.shade200,
                      ),
                      const SizedBox(width: 8),
                      // Settings button.
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const PrinterSettingsScreen(),
                              ),
                            );
                            await _loadLocalSettings();
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2BBCC4)
                                  .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.settings_suggest_rounded,
                              size: 22,
                              color: Color(0xFF2BBCC4),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // ── PREMIUM RECEIPT PREVIEW ──
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Column(
                          children: [
                            const SizedBox(height: 10),
                            Expanded(
                              child: Container(
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF0F2F5),
                                  borderRadius: BorderRadius.circular(24),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        children: [
                          Container(
                            margin: const EdgeInsets.symmetric(horizontal: 40),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2BBCC4),
                              borderRadius: const BorderRadius.vertical(
                                bottom: Radius.circular(12),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF2BBCC4)
                                      .withValues(alpha: 0.3),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                )
                              ],
                            ),
                            child: Center(
                              child: Text(
                                '${_paperSize.name.replaceAll('mm', '')}mm • $charsPerLine CHARS',
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Expanded(
                            child: SingleChildScrollView(
                              physics: const BouncingScrollPhysics(),
                              padding: EdgeInsets.fromLTRB(
                                16,
                                0,
                                16,
                                previewBottomPad,
                              ),
                              child: Center(
                                child: Container(
                                  width: paperContentWidth + 24,
                                  constraints:
                                      const BoxConstraints(minHeight: 450),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(4),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black
                                            .withValues(alpha: 0.12),
                                        blurRadius: 20,
                                        offset: const Offset(0, 10),
                                      ),
                                      BoxShadow(
                                        color: Colors.black
                                            .withValues(alpha: 0.05),
                                        blurRadius: 5,
                                        offset: const Offset(5, 0),
                                      ),
                                    ],
                                  ),
                                  child: Stack(
                                    children: [
                                      Positioned(
                                        top: 0,
                                        left: 0,
                                        right: 0,
                                        height: 10,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              begin: Alignment.topCenter,
                                              end: Alignment.bottomCenter,
                                              colors: [
                                                Colors.grey.shade200,
                                                Colors.transparent,
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 24,
                                        ),
                                        child: TextField(
                                          controller: _textCtrl,
                                          maxLines: null,
                                          textAlign: textAlign,
                                          onChanged: (_) => setState(() {}),
                                          style: TextStyle(
                                            fontFamily: 'monospace',
                                            fontSize: 14,
                                            fontWeight: _isBold
                                                ? FontWeight.w700
                                                : FontWeight.w400,
                                            color: const Color(0xFF1A1A1A),
                                            height: 1.1,
                                            letterSpacing: 0,
                                          ),
                                          decoration: InputDecoration(
                                            hintText:
                                                'Ketik struk Anda di sini...',
                                            hintStyle: TextStyle(
                                              color: Colors.grey.shade300,
                                              fontFamily: 'sans-serif',
                                              fontSize: 13,
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
                  ),
                ),

                const SizedBox(height: 12),

                // ── MODERN PRINT BUTTON ──
                Container(
                  width: double.infinity,
                  height: 60,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF2BBCC4), Color(0xFF24AAB1)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF2BBCC4).withValues(alpha: 0.35),
                        blurRadius: 15,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: ElevatedButton.icon(
                    onPressed: _isPrinting ? null : _print,
                    icon: _isPrinting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.print_rounded, size: 24),
                    label: Text(
                      _isPrinting
                          ? S.printing.toUpperCase()
                          : S.printText.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      foregroundColor: Colors.white,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _formatBtn({
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
    required String tooltip,
    Color? color,
  }) {
    final themeColor = color ?? const Color(0xFF2BBCC4);

    return Tooltip(
      message: tooltip,
      child: Padding(
        padding: const EdgeInsets.only(right: 8.0),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          child: Material(
            color: isActive
                ? themeColor.withValues(alpha: 0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isActive
                        ? themeColor.withValues(alpha: 0.3)
                        : Colors.transparent,
                    width: 1,
                  ),
                ),
                child: Icon(
                  icon,
                  size: 22,
                  color: isActive ? themeColor : Colors.grey.shade500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
