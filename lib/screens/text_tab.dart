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
  int _alignMode = 0; // 0: Left, 1: Center, 2: Right
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
    final newSize = ps == 'mm58' ? PaperSize.mm58 : ps == 'mm100' ? PaperSize.mm100 : PaperSize.mm80;
    
    // Also ensure EscPosHelper is updated with latest settings
    EscPosHelper.setCustomCharsPerLine(p.getInt('chars_per_line') ?? 0);
    EscPosHelper.setExtraFeed(p.getInt('extra_feed') ?? 3);
    EscPosHelper.setAutoCut(p.getBool('auto_cut') ?? false);

    if (mounted) {
      setState(() {
        _localPaperSize = newSize;
      });
    }
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
    
    // Auto-wrap text to match the paper size for "What You See Is What You Get"
    final cpl = EscPosHelper.charsPerLine(_paperSize);
    final wrappedText = _wrapText(_textCtrl.text, cpl);

    final data = EscPosHelper.textToEscPos(
      wrappedText,
      _paperSize,
      isBold: _isBold,
      alignMode: _alignMode,
    );
    await widget.btService.sendRaw(data);
    setState(() => _isPrinting = false);
  }

  String _wrapText(String text, int width) {
    final lines = text.split('\n');
    final result = <String>[];
    for (var line in lines) {
      if (line.isEmpty) {
        result.add('');
        continue;
      }
      
      String currentLine = line;
      while (currentLine.length > width) {
        // Try to find last space within width
        int cutIndex = currentLine.lastIndexOf(' ', width);
        if (cutIndex == -1) cutIndex = width;
        
        result.add(currentLine.substring(0, cutIndex).trimRight());
        currentLine = currentLine.substring(cutIndex).trimLeft();
      }
      result.add(currentLine);
    }
    return result.join('\n');
  }

  double _getCharWidth(int charsPerLine) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: 'W', // Use a wide character to be safe, though monospace should be equal
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 14,
          fontWeight: _isBold ? FontWeight.w700 : FontWeight.w400,
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
    final paperContentWidth = charWidth * charsPerLine;
    
    final textAlign = _alignMode == 0 ? TextAlign.left 
                    : _alignMode == 1 ? TextAlign.center 
                    : TextAlign.right;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        children: [
          // ── TOOLBAR ATAS ──
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                )
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                _formatBtn(
                  icon: Icons.format_align_left_rounded, 
                  isActive: _alignMode == 0, 
                  onTap: () => setState(() => _alignMode = 0),
                ),
                _formatBtn(
                  icon: Icons.format_align_center_rounded, 
                  isActive: _alignMode == 1, 
                  onTap: () => setState(() => _alignMode = 1),
                ),
                _formatBtn(
                  icon: Icons.format_align_right_rounded, 
                  isActive: _alignMode == 2, 
                  onTap: () => setState(() => _alignMode = 2),
                ),
                Container(
                  width: 1, height: 24, 
                  color: Colors.grey.shade300, 
                  margin: const EdgeInsets.symmetric(horizontal: 8)
                ),
                _formatBtn(
                  icon: Icons.format_bold_rounded, 
                  isActive: _isBold, 
                  onTap: () => setState(() => _isBold = !_isBold),
                ),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const PrinterSettingsScreen()),
                    );
                    await _loadLocalSettings();
                  },
                  icon: const Icon(Icons.settings_rounded, size: 16),
                  label: const Text('Setting', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF2BBCC4),
                    side: const BorderSide(color: Color(0xFF2BBCC4)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                    minimumSize: const Size(0, 36),
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 16),

          // ── REALISTIC PREVIEW AREA ──
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFFFDFBF7),
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  )
                ],
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                children: [
                  Container(
                    height: 24,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                    ),
                    child: Center(
                      child: Text(
                        'Preview — Lebar: ${_paperSize.name} ($charsPerLine kar)',
                        style: TextStyle(fontSize: 10, color: Colors.grey.shade600, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Container(
                          width: paperContentWidth, // Exact width for the character count
                          constraints: const BoxConstraints(minHeight: 400),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.1),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              )
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 20), // Only vertical padding
                            child: TextField(
                              controller: _textCtrl,
                              maxLines: null,
                              textAlign: textAlign,
                              onChanged: (_) => setState(() {}),
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 14,
                                fontWeight: _isBold ? FontWeight.w700 : FontWeight.w400,
                                color: Colors.black,
                                height: 1.1,
                                letterSpacing: 0,
                              ),
                              decoration: InputDecoration(
                                hintText: 'Ketik struk Anda di sini...',
                                hintStyle: TextStyle(
                                  color: Colors.grey.shade300, 
                                  fontFamily: 'sans-serif',
                                  fontSize: 12,
                                ),
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // ── PRINT BUTTON ──
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isPrinting ? null : _print,
              icon: _isPrinting
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.print_rounded),
              label: Text(_isPrinting ? S.printing : S.printText),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2BBCC4),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _formatBtn({required IconData icon, required bool isActive, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF2BBCC4).withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(
          icon, 
          size: 20, 
          color: isActive ? const Color(0xFF2BBCC4) : Colors.grey.shade600,
        ),
      ),
    );
  }
}
