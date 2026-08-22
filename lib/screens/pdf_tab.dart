import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pdfx/pdfx.dart';
import 'package:image/image.dart' as img;
import '../providers/app_state_provider.dart';
import '../providers/bluetooth_provider.dart';
import '../providers/history_provider.dart';
import '../models/print_history.dart';
import '../utils/escpos_helper.dart';
import '../utils/strings.dart';
import '../utils/colors.dart';

class PdfTab extends ConsumerStatefulWidget {
  const PdfTab({super.key});

  @override
  ConsumerState<PdfTab> createState() => _PdfTabState();
}

class _PdfTabState extends ConsumerState<PdfTab>
    with SingleTickerProviderStateMixin {
  static const _primary = AppColors.primary;

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

  late AnimationController _pulseController;

  PaperSize get _activePaperSize =>
      _overridePaperSize ?? ref.read(printerConfigProvider).paperSize;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _pickPdf() async {
    final result = await FilePicker.pickFiles(
        type: FileType.custom, allowedExtensions: ['pdf']);
    if (result.isNotEmpty && result.first.path != null) {
      final bytes = await result.first.readAsBytes();
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
              backgroundColor: '#FFFFFF');
          await page.close();
          preview = imgData?.bytes;
        }
        await doc.close();
      } catch (_) {}

      setState(() {
        _pdfFile = File(result.first.path!);
        _fileName = result.first.name;
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
      // Baca btService dari provider langsung
      final btService = ref.read(bluetoothServiceProvider);
      final activePaperSize = _activePaperSize;

      document = await PdfDocument.openData(_pdfBytes!);
      final totalPages = document.pagesCount;
      final maxWidth = EscPosHelper.paperMaxWidth(activePaperSize);

      for (int i = 1; i <= totalPages; i++) {
        if (!mounted) return;
        setState(() => _status = S.printingPage(i, totalPages));

        final page = await document.getPage(i);
        final pageImage = await page.render(
            width: maxWidth.toDouble(),
            height: (page.height * maxWidth / page.width),
            format: PdfPageImageFormat.png,
            backgroundColor: '#FFFFFF');
        await page.close();

        if (pageImage == null) throw Exception(S.renderFail(i));
        final decoded = img.decodeImage(pageImage.bytes);
        if (decoded == null) throw Exception(S.decodeFail(i));

        final processed = _enhanceForThermal(decoded);
        final List<int> buf = [];
        buf.addAll(EscPosHelper.init());
        buf.addAll(EscPosHelper.align(1));
        buf.addAll(EscPosHelper.imageEsc(processed, activePaperSize));
        buf.addAll(EscPosHelper.feed(2));

        final ok = await btService.sendRaw(Uint8List.fromList(buf));
        if (!ok) throw Exception(S.printerDataFail(i));
      }

      ref.read(historyNotifierProvider.notifier).add(PrintHistory(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            type: 'pdf',
            label: _fileName ?? 'PDF Print',
            timestamp: DateTime.now(),
            success: true,
            dataSize: _pdfBytes!.length,
            source: 'manual',
          ));

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

  Widget _buildButton(
      {IconData? icon,
      required String label,
      required Color color,
      required bool outlined,
      bool loading = false,
      VoidCallback? onTap}) {
    return GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          decoration: BoxDecoration(
            color: outlined
                ? Colors.white
                : (onTap == null ? color.withValues(alpha: 0.4) : color),
            borderRadius: BorderRadius.circular(14),
            border: outlined
                ? Border.all(
                    color: onTap == null ? Colors.grey.shade300 : color,
                    width: 2)
                : null,
            boxShadow: !outlined && onTap != null
                ? [
                    BoxShadow(
                        color: color.withValues(alpha: 0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4))
                  ]
                : null,
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (loading)
              SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5, color: outlined ? color : Colors.white))
            else if (icon != null)
              Icon(icon,
                  size: 20,
                  color: outlined
                      ? (onTap == null ? Colors.grey : color)
                      : Colors.white),
            if (icon != null || loading) const SizedBox(width: 8),
            Text(label,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: outlined
                        ? (onTap == null ? Colors.grey : color)
                        : Colors.white)),
          ]),
        ));
  }

  Widget _buildPaperSelector() {
    final globalPaperSize =
        ref.watch(printerConfigProvider.select((s) => s.paperSize));
    final current = _overridePaperSize ?? globalPaperSize;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
                color: Colors.grey.withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, 4))
          ]),
      child: Row(children: [
        Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: _primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.straighten_rounded,
                size: 18, color: _primary)),
        const SizedBox(width: 12),
        Text(S.paperLabel, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(width: 10),
        Expanded(
            child: DropdownButton<PaperSize>(
          value: current,
          underline: const SizedBox.shrink(),
          isExpanded: true,
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
        )),
      ]),
    );
  }

  Widget _buildPreview() {
    if (_pdfFile == null) {
      return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              return Transform.scale(
                  scale: 1.0 + (_pulseController.value * 0.1),
                  child: Opacity(
                      opacity: 0.5 + (_pulseController.value * 0.5),
                      child: child));
            },
            child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                    color: _primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle),
                child: const Icon(Icons.upload_file_rounded,
                    size: 48, color: _primary))),
        const SizedBox(height: 16),
        Text(S.tapToSelectPdf,
            style: TextStyle(
                color: Colors.grey.shade500,
                fontSize: 15,
                fontWeight: FontWeight.w600)),
      ]));
    }
    return Column(children: [
      Expanded(
          child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200)),
              clipBehavior: Clip.antiAlias,
              child: _previewBytes != null
                  ? Image.memory(_previewBytes!, fit: BoxFit.contain)
                  : Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.picture_as_pdf_rounded,
                          size: 56, color: Colors.red.shade300),
                      const SizedBox(height: 8),
                      Text(S.previewUnavailable,
                          style: TextStyle(color: Colors.grey.shade500)),
                    ])))),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
            color: _primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10)),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.description_rounded, size: 16, color: _primary),
          const SizedBox(width: 8),
          Expanded(
              child: Text(_fileName ?? '',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis)),
          if (_pageCount > 0) ...[
            Container(
                margin: const EdgeInsets.only(left: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                    color: _primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8)),
                child: Text(S.pages(_pageCount),
                    style: const TextStyle(
                        fontSize: 11,
                        color: _primary,
                        fontWeight: FontWeight.w600))),
          ],
        ]),
      ),
    ]);
  }

  Widget _buildQualityControls() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: const [
            BoxShadow(
                color: Colors.black12, blurRadius: 12, offset: Offset(0, 4))
          ]),
      child: Column(children: [
        Row(children: [
          Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                  color: const Color(0xFF7B2FBE).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.tune_rounded,
                  size: 16, color: Color(0xFF7B2FBE))),
          const SizedBox(width: 10),
          Text(S.printQuality,
              style: TextStyle(fontWeight: FontWeight.w700)),
          const Spacer(),
          Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color: _useDither
                      ? const Color(0xFF7B2FBE).withValues(alpha: 0.15)
                      : _primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8)),
              child: Text(_useDither ? 'Dither ON' : 'Dither OFF',
                  style: TextStyle(
                      fontSize: 11,
                      color: _useDither ? const Color(0xFF7B2FBE) : _primary,
                      fontWeight: FontWeight.w600))),
          const SizedBox(width: 8),
          Switch(
              value: _useDither,
              onChanged:
                  _isPrinting ? null : (v) => setState(() => _useDither = v)),
        ]),
        const SizedBox(height: 10),
        _buildSliderRow('Kontras', _contrast, 1.0, 2.0,
            (v) => setState(() => _contrast = v)),
        if (!_useDither)
          _buildSliderRow('Threshold', _threshold.toDouble(), 80, 220,
              (v) => setState(() => _threshold = v.toInt()),
              divisions: 28),
      ]),
    );
  }

  Widget _buildSliderRow(String label, double value, double min, double max,
      ValueChanged<double> onChanged,
      {int? divisions}) {
    return Row(children: [
      SizedBox(
          width: 70,
          child: Text(label,
              style:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w500))),
      Expanded(
          child: SliderTheme(
              data: SliderThemeData(
                  activeTrackColor: _primary,
                  thumbColor: _primary,
                  inactiveTrackColor: _primary.withValues(alpha: 0.2)),
              child: Slider(
                  value: value,
                  min: min,
                  max: max,
                  divisions: divisions,
                  onChanged: _isPrinting ? null : onChanged))),
      Container(
          width: 45,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
              color: _primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6)),
          child: Text(
              divisions != null
                  ? value.toInt().toString()
                  : value.toStringAsFixed(2),
              style: const TextStyle(
                  fontSize: 11, color: _primary, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(langProvider);
    // extendBody:false + SafeArea di navBar = Scaffold handle insets otomatis
    final vp = MediaQuery.viewPaddingOf(context);

    return Container(
      decoration: const BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFF8FAFB), Color(0xFFF0F2F5)])),
      child: Padding(
        padding: EdgeInsets.fromLTRB(16 + vp.left, 16 + vp.top, 16, 8.0),
        child: Column(children: [
          _buildPaperSelector(),
          const SizedBox(height: 10),
          _buildQualityControls(),
          const SizedBox(height: 10),
          Expanded(
              child: GestureDetector(
                  onTap: _pickPdf,
                  child: Container(
                      decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: _pdfFile != null
                                  ? _primary.withValues(alpha: 0.3)
                                  : Colors.grey.shade200,
                              width: 2)),
                      child: _buildPreview()))),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
                child: _buildButton(
                    icon: Icons.folder_open_rounded,
                    label: S.selectPdf,
                    color: _primary,
                    outlined: true,
                    onTap: _pickPdf)),
            const SizedBox(width: 10),
            if (_pdfFile != null)
              GestureDetector(
                  onTap: _isPrinting ? null : _clearPdf,
                  child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.red.shade200)),
                      child: Icon(Icons.close_rounded,
                          color: Colors.red.shade400, size: 22))),
            if (_pdfFile != null) const SizedBox(width: 10),
            Expanded(
                child: _buildButton(
                    icon: _isPrinting ? null : Icons.print_rounded,
                    label: _isPrinting ? S.printing : S.print_,
                    color: _primary,
                    outlined: false,
                    loading: _isPrinting,
                    onTap:
                        (_pdfFile == null || _pdfBytes == null || _isPrinting)
                            ? null
                            : _printPdfContent)),
          ]),
          if (_status.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: _status.startsWith('✅')
                    ? const Color(0xFF06C270).withValues(alpha: 0.1)
                    : const Color(0xFFFF3B30).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(_status,
                  style: TextStyle(
                      color: _status.startsWith('✅')
                          ? const Color(0xFF06C270)
                          : const Color(0xFFFF3B30),
                      fontWeight: FontWeight.w600,
                      fontSize: 12)),
            ),
          ],
        ]),
      ),
    );
  }
}
