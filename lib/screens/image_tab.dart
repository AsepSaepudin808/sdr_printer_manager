import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;
import '../services/bluetooth_service.dart';
import '../utils/escpos_helper.dart';
import '../utils/strings.dart';

class ImageTab extends StatefulWidget {
  final SdrBluetoothService btService;
  final PaperSize paperSize;
  const ImageTab({super.key, required this.btService, required this.paperSize});

  @override
  State<ImageTab> createState() => _ImageTabState();
}

class _ImageTabState extends State<ImageTab> {
  static const _primary = Color(0xFF2BBCC4);
  File? _imageFile;
  bool _isPrinting = false;
  String _status = '';

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result != null && result.files.single.path != null) {
      setState(() {
        _imageFile = File(result.files.single.path!);
        _status = '';
      });
    }
  }

  Future<void> _printImage() async {
    if (_imageFile == null) return;
    setState(() {
      _isPrinting = true;
      _status = '';
    });

    try {
      final bytes = await _imageFile!.readAsBytes();
      final original = img.decodeImage(bytes);
      if (original == null) {
        setState(() {
          _isPrinting = false;
          _status = S.imageReadFail;
        });
        return;
      }

      final maxW = widget.paperSize == PaperSize.mm58
          ? 384
          : widget.paperSize == PaperSize.mm80
              ? 576
              : 832;
      final resized = img.copyResize(original, width: maxW);
      final mono = img.grayscale(resized);

      final escData = _imageToEscPos(mono, maxW);
      final ok = await widget.btService.sendRaw(escData);
      setState(() {
        _isPrinting = false;
        _status = ok ? S.printSuccess('Image') : S.printFail;
      });
    } catch (e) {
      setState(() {
        _isPrinting = false;
        _status = '❌ Error: $e';
      });
    }
  }

  Uint8List _imageToEscPos(img.Image image, int maxW) {
    final w = image.width;
    final h = image.height;
    final widthBytes = (w + 7) ~/ 8;
    final List<int> buf = [];

    buf.addAll([0x1B, 0x40]);
    buf.addAll([0x1B, 0x61, 0x01]);

    for (int y = 0; y < h; y += 24) {
      final bandH = (y + 24 > h) ? h - y : 24;
      buf.addAll([0x1D, 0x76, 0x30, 0x00]);
      buf.addAll([widthBytes & 0xFF, (widthBytes >> 8) & 0xFF]);
      buf.addAll([bandH & 0xFF, (bandH >> 8) & 0xFF]);

      for (int row = 0; row < bandH; row++) {
        for (int col = 0; col < widthBytes; col++) {
          int byte = 0;
          for (int bit = 0; bit < 8; bit++) {
            final px = col * 8 + bit;
            if (px < w && (y + row) < h) {
              final pixel = image.getPixel(px, y + row);
              final lum = img.getLuminance(pixel);
              if (lum < 128) byte |= (0x80 >> bit);
            }
          }
          buf.add(byte);
        }
      }
    }

    buf.addAll([0x0A, 0x0A, 0x0A]);
    buf.addAll([0x1B, 0x61, 0x00]);

    return Uint8List.fromList(buf);
  }

  Widget _imgBtn({
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
              ? Border.all(color: onTap == null ? Colors.grey.shade300 : color)
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
                  color:
                      outlined ? (onTap == null ? Colors.grey : color) : Colors.white),
            if (icon != null || loading) const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color:
                    outlined ? (onTap == null ? Colors.grey : color) : Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Responsive: handle safe area insets
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
      child: Column(children: [
        Expanded(
          child: GestureDetector(
            onTap: _pickImage,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: _imageFile != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(_imageFile!, fit: BoxFit.contain),
                    )
                  : Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.add_photo_alternate_rounded,
                            size: 48, color: Colors.grey.shade300),
                        const SizedBox(height: 12),
                        Text(S.tapToSelectImage,
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
            child: _imgBtn(
              icon: Icons.folder_open_rounded,
              label: S.selectImage,
              color: _primary,
              outlined: true,
              onTap: _pickImage,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _imgBtn(
              icon: _isPrinting ? null : Icons.print_rounded,
              label: _isPrinting ? S.printing : S.print_,
              color: _primary,
              outlined: false,
              loading: _isPrinting,
              onTap: (_isPrinting || _imageFile == null) ? null : _printImage,
            ),
          ),
        ]),
        if (_status.isNotEmpty) ...[
          const SizedBox(height: 8),
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
