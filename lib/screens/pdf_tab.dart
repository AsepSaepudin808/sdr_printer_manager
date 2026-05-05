import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/bluetooth_service.dart';
import '../utils/escpos_helper.dart';
import '../utils/strings.dart';

class PdfTab extends StatefulWidget {
  final SdrBluetoothService btService;
  final PaperSize paperSize;
  const PdfTab({super.key, required this.btService, required this.paperSize});

  @override
  State<PdfTab> createState() => _PdfTabState();
}

class _PdfTabState extends State<PdfTab> {
  static const _primary = Color(0xFF2BBCC4);
  File? _pdfFile;
  String? _fileName;
  bool _isPrinting = false;
  String _status = '';

  Future<void> _pickPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (result != null && result.files.single.path != null) {
      setState(() {
        _pdfFile = File(result.files.single.path!);
        _fileName = result.files.single.name;
        _status = '';
      });
    }
  }

  Future<void> _printPdfInfo() async {
    if (_pdfFile == null || _fileName == null) return;
    setState(() {
      _isPrinting = true;
      _status = '';
    });

    try {
      final size = widget.paperSize;
      final fileSize = await _pdfFile!.length();
      final fileSizeStr = fileSize > 1024 * 1024
          ? '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB'
          : '${(fileSize / 1024).toStringAsFixed(1)} KB';

      // Build ESC/POS receipt with PDF info
      final List<int> buf = [];
      buf.addAll(EscPosHelper.init());
      buf.addAll(EscPosHelper.align(1));
      buf.addAll(EscPosHelper.bold(true));
      buf.addAll(EscPosHelper.txt('CETAK PDF'));
      buf.addAll(EscPosHelper.bold(false));
      buf.addAll(EscPosHelper.align(0));
      buf.addAll(EscPosHelper.divider(size));
      buf.addAll(EscPosHelper.txt('File: $_fileName'));
      buf.addAll(EscPosHelper.txt('Ukuran: $fileSizeStr'));
      buf.addAll(EscPosHelper.txt(
          'Tanggal: ${DateTime.now().toString().substring(0, 16)}'));
      buf.addAll(EscPosHelper.divider(size));
      buf.addAll(EscPosHelper.align(1));
      buf.addAll(EscPosHelper.txt('PDF berhasil dimuat'));
      buf.addAll(EscPosHelper.txt('Konten dicetak sebagai info'));
      buf.addAll(EscPosHelper.align(0));
      buf.addAll(EscPosHelper.divider(size));
      buf.addAll(EscPosHelper.feed(3));

      final ok = await widget.btService.sendRaw(Uint8List.fromList(buf));
      setState(() {
        _isPrinting = false;
        _status = ok ? S.printSuccess('PDF') : S.printFail;
      });
    } catch (e) {
      setState(() {
        _isPrinting = false;
        _status = '❌ Error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        Expanded(
          child: GestureDetector(
            onTap: _pickPdf,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: _pdfFile != null
                  ? Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.picture_as_pdf_rounded,
                            size: 64, color: Colors.red),
                        const SizedBox(height: 16),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Text(_fileName ?? '',
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w600),
                              textAlign: TextAlign.center,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis),
                        ),
                        const SizedBox(height: 8),
                        Text(S.tapToChange,
                            style: TextStyle(
                                color: Colors.grey.shade400, fontSize: 12)),
                      ]),
                    )
                  : Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.upload_file_rounded,
                            size: 48, color: Colors.grey.shade300),
                        const SizedBox(height: 12),
                        Text(S.tapToSelectPdf,
                            style: TextStyle(
                                color: Colors.grey.shade400, fontSize: 14)),
                      ]),
                    ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _pickPdf,
              icon: const Icon(Icons.folder_open_rounded),
              label: Text(S.selectPdf),
              style: OutlinedButton.styleFrom(
                foregroundColor: _primary,
                side: const BorderSide(color: _primary),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton.icon(
              onPressed:
                  (_isPrinting || _pdfFile == null) ? null : _printPdfInfo,
              icon: _isPrinting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.print_rounded),
              label: Text(_isPrinting ? S.printing : S.print_),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ]),
        if (_status.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(_status,
              style: TextStyle(
                color: _status.startsWith('✅')
                    ? const Color(0xFF06C270)
                    : const Color(0xFFFF3B30),
                fontWeight: FontWeight.w600,
                fontSize: 13,
              )),
        ],
      ]),
    );
  }
}
