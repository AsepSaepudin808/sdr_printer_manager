import 'package:flutter/material.dart';
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
  final TextEditingController _textCtrl = TextEditingController();
  bool _isPrinting = false;
  
  // Format state
  int _alignMode = 0; // 0: Left, 1: Center, 2: Right
  bool _isBold = false;
  
  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _print() async {
    if (_textCtrl.text.isEmpty) return;
    setState(() => _isPrinting = true);
    final data = EscPosHelper.textToEscPos(
      _textCtrl.text,
      widget.paperSize,
      isBold: _isBold,
      alignMode: _alignMode,
    );
    await widget.btService.sendRaw(data);
    setState(() => _isPrinting = false);
  }

  @override
  Widget build(BuildContext context) {
    final charsPerLine = EscPosHelper.charsPerLine(widget.paperSize);
    
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
                    setState(() {});
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
                        'Preview — Lebar: ${widget.paperSize.name} ($charsPerLine kar)',
                        style: TextStyle(fontSize: 10, color: Colors.grey.shade600, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: TextField(
                        controller: _textCtrl,
                        maxLines: null,
                        expands: true,
                        textAlign: textAlign,
                        onChanged: (_) => setState(() {}),
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 14,
                          fontWeight: _isBold ? FontWeight.w700 : FontWeight.w400,
                          color: Colors.black87,
                          height: 1.5,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Ketik struk Anda di sini...\n\nTampilan ini mengikuti font monospace dan ukuran kertas printer.',
                          hintStyle: TextStyle(
                            color: Colors.grey.shade400, 
                            fontFamily: 'sans-serif',
                            fontWeight: FontWeight.normal,
                          ),
                          border: InputBorder.none,
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
