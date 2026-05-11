import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:pdfx/pdfx.dart';
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
  Uint8List? _pdfBytes;
  Uint8List? _previewBytes;
  int _pageCount = 0;

  bool _isPrinting = false;
  String _status = '';

  PaperSize? _overridePaperSize;
  double _contrast = 1.35;
  int _threshold = 160;
  bool _useDither = false;

  PaperSize get _activePaperSize => _overridePaperSize ?? widget.paperSize;

  Future<void> _pickPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true,
    );

    if (result != null &&
        result.files.single.path != null &&
        result.files.single.bytes != null) {
      final bytes = result.files.single.bytes!;
      Uint8List? preview;
      int pages = 0;

      try {
        final doc = await PdfDocument.openData(bytes);
        pages = doc.pagesCount;
        if (pages > 0) {
          final page = await doc.getPage(1);
          final imgData = await page.render(
            width: 600,
            height: (page.height * 600 / page.width),
            format: PdfPageImageFormat.png,
            backgroundColor: '#FFFFFF',
          );
          await page.close();
          preview = imgData?.bytes;
        }
        await doc.close();
      } catch (_) {}

      setState(() {
        _pdfFile = File(result.files.single.path!);
        _fileName = result.files.single.name;
        _pdfBytes = bytes;
        _previewBytes = preview;
        _pageCount = pages;
        _status = '';
      });
    }
  }

  void _clearPdf() {
    if (_isPrinting) return;
    setState(() {
      _pdfFile = null;
      _fileName = null;
      _pdfBytes = null;
      _previewBytes = null;
      _pageCount = 0;
      _status = '';
    });
  }

  int _paperMaxWidth(PaperSize size) {
    switch (size) {
      case PaperSize.mm58:
        return 384;
      case PaperSize.mm80:
        return 576;
      case PaperSize.mm100:
        return 768;
    }
  }

  img.Image _enhanceForThermal(img.Image source) {
    img.Image out = img.grayscale(source);

    if (_useDither) {
      out = img.adjustColor(out, contrast: _contrast);
      out = img.ditherImage(out);
    } else {
      out = img.luminanceThreshold(out, threshold: _threshold / 255.0);
    }

    return out;
  }

  Future<void> _printPdfContent() async {
    if (_pdfBytes == null || _fileName == null) return;

    setState(() {
      _isPrinting = true;
      _status = '';
    });

    PdfDocument? document;
    try {
      document = await PdfDocument.openData(_pdfBytes!);
      final totalPages = document.pagesCount;
      final maxWidth = _paperMaxWidth(_activePaperSize);

      for (int i = 1; i <= totalPages; i++) {
        if (!mounted) return;
        setState(() {
          _status = '🖨️ Mencetak halaman $i/$totalPages...';
        });

        final page = await document.getPage(i);
        final pageImage = await page.render(
          width: maxWidth.toDouble(),
          height: (page.height * maxWidth / page.width),
          format: PdfPageImageFormat.png,
          backgroundColor: '#FFFFFF',
        );
        await page.close();

        if (pageImage == null) {
          throw Exception('Gagal render halaman $i');
        }

        final decoded = img.decodeImage(pageImage.bytes);
        if (decoded == null) {
          throw Exception('Gagal decode image halaman $i');
        }

        final processed = _enhanceForThermal(decoded);

        final List<int> buf = [];
        buf.addAll(EscPosHelper.init());
        buf.addAll(EscPosHelper.align(1));
        buf.addAll(EscPosHelper.imageEsc(processed, _activePaperSize));
        buf.addAll(EscPosHelper.feed(2));

        final ok = await widget.btService.sendRaw(Uint8List.fromList(buf));
        if (!ok) {
          throw Exception('Printer gagal menerima data di halaman $i');
        }
      }

      setState(() {
        _isPrinting = false;
        _status = S.printSuccess('PDF ($_fileName)');
      });
    } catch (e) {
      setState(() {
        _isPrinting = false;
        _status = '❌ Error: $e';
      });
    } finally {
      await document?.close();
    }
  }

  Widget _iconBtn({
    IconData? icon,
    required String label,
    required Color color,
    required bool outlined,
    bool loading = false,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          color: outlined
              ? Colors.white
              : (onTap == null ? color.withValues(alpha: 0.4) : color),
          borderRadius: BorderRadius.circular(12),
          border: outlined
              ? Border.all(
                  color: onTap == null ? Colors.grey.shade300 : color)
              : null,
          boxShadow: !outlined && onTap != null
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  )
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (loading)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            else if (icon != null)
              Icon(icon,
                  size: 18,
                  color: outlined
                      ? (onTap == null ? Colors.grey : color)
                      : Colors.white),
            if (icon != null || loading) const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: outlined
                    ? (onTap == null ? Colors.grey : color)
                    : Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaperSelector() {
    final current = _activePaperSize;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          const Icon(Icons.straighten_rounded, size: 18, color: _primary),
          const SizedBox(width: 8),
          const Text('Paper:', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(width: 10),
          DropdownButton<PaperSize>(
            value: current,
            underline: const SizedBox.shrink(),
            onChanged: _isPrinting
                ? null
                : (v) {
                    if (v == null) return;
                    setState(() => _overridePaperSize = v);
                  },
            items: const [
              DropdownMenuItem(value: PaperSize.mm58, child: Text('58mm')),
              DropdownMenuItem(value: PaperSize.mm80, child: Text('80mm')),
              DropdownMenuItem(value: PaperSize.mm100, child: Text('100mm')),
            ],
          ),
          const Spacer(),
          Text(
            'Kualitas',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    if (_pdfFile == null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.upload_file_rounded,
              size: 48, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(
            S.tapToSelectPdf,
            style: TextStyle(color: Colors.grey.shade400, fontSize: 14),
          ),
        ]),
      );
    }

    return Column(
      children: [
        Expanded(
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(10),
            ),
            clipBehavior: Clip.antiAlias,
            child: _previewBytes != null
                ? Image.memory(_previewBytes!, fit: BoxFit.contain)
                : const Center(
                    child: Icon(Icons.picture_as_pdf_rounded,
                        size: 72, color: Colors.red)),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          _fileName ?? '',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          _pageCount > 0
              ? '$_pageCount halaman • ketuk untuk ganti file'
              : S.tapToChange,
          style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildQualityControls() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.tune_rounded, size: 18, color: _primary),
              const SizedBox(width: 8),
              const Text('Kualitas Cetak',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              const Spacer(),
              Switch(
                value: _useDither,
                onChanged:
                    _isPrinting ? null : (v) => setState(() => _useDither = v),
              ),
              Text(_useDither ? 'Dither ON' : 'Dither OFF',
                  style: const TextStyle(fontSize: 12)),
            ],
          ),
          Row(
            children: [
              const SizedBox(width: 4),
              const Text('Contrast', style: TextStyle(fontSize: 12)),
              Expanded(
                child: Slider(
                  value: _contrast,
                  min: 1.0,
                  max: 2.0,
                  divisions: 10,
                  label: _contrast.toStringAsFixed(2),
                  onChanged:
                      _isPrinting ? null : (v) => setState(() => _contrast = v),
                ),
              ),
            ],
          ),
          if (!_useDither)
            Row(
              children: [
                const SizedBox(width: 4),
                const Text('Threshold', style: TextStyle(fontSize: 12)),
                Expanded(
                  child: Slider(
                    value: _threshold.toDouble(),
                    min: 80,
                    max: 220,
                    divisions: 28,
                    label: _threshold.toString(),
                    onChanged: _isPrinting
                        ? null
                        : (v) => setState(() => _threshold = v.toInt()),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Responsive: handle safe area insets and landscape orientation
    final viewPadding = MediaQuery.viewPaddingOf(context);
    final safeBottom = viewPadding.bottom;
    const bottomBarH = 65.0;
    final totalBottomPad = bottomBarH + safeBottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16 + viewPadding.left,
        16 + viewPadding.top,
        16 + viewPadding.right,
        16 + totalBottomPad,
      ),
      child: Column(
        children: [
          _buildPaperSelector(),
          const SizedBox(height: 8),
          _buildQualityControls(),
          const SizedBox(height: 10),
          // Preview area — Expanded to fill remaining space
          Expanded(
            child: GestureDetector(
              onTap: _pickPdf,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: _buildPreview(),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: _iconBtn(
                icon: Icons.folder_open_rounded,
                label: S.selectPdf,
                color: _primary,
                outlined: true,
                onTap: _pickPdf,
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: (_pdfFile == null || _isPrinting) ? null : _clearPdf,
              tooltip: 'Hapus PDF',
              icon: const Icon(Icons.close_rounded),
              style: IconButton.styleFrom(
                foregroundColor: Colors.redAccent,
                side: BorderSide(color: Colors.grey.shade300),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _iconBtn(
                icon: _isPrinting ? null : Icons.print_rounded,
                label: _isPrinting ? S.printing : S.print_,
                color: _primary,
                outlined: false,
                loading: _isPrinting,
                onTap: (_pdfFile == null || _pdfBytes == null || _isPrinting)
                    ? null
                    : _printPdfContent,
              ),
            ),
          ]),
          if (_status.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              _status,
              style: TextStyle(
                color: _status.startsWith('✅')
                    ? const Color(0xFF06C270)
                    : const Color(0xFFFF3B30),
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ],
      ),
    );
  }
}