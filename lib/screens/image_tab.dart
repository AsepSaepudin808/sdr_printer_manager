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

      // Resize to printer width
      final maxW = widget.paperSize == PaperSize.mm58
          ? 384
          : widget.paperSize == PaperSize.mm80
              ? 576
              : 832;
      final resized = img.copyResize(original, width: maxW);
      final mono = img.grayscale(resized);

      // Convert to ESC/POS raster bitmap
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

    // Initialize printer
    buf.addAll([0x1B, 0x40]);
    // Center align
    buf.addAll([0x1B, 0x61, 0x01]);

    // Print in bands of 24 pixels height (GS v 0)
    for (int y = 0; y < h; y += 24) {
      final bandH = (y + 24 > h) ? h - y : 24;
      // GS v 0 command
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

    // Feed and left align
    buf.addAll([0x0A, 0x0A, 0x0A]);
    buf.addAll([0x1B, 0x61, 0x00]);

    return Uint8List.fromList(buf);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
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
            child: OutlinedButton.icon(
              onPressed: _pickImage,
              icon: const Icon(Icons.folder_open_rounded),
              label: Text(S.selectImage),
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
                  (_isPrinting || _imageFile == null) ? null : _printImage,
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
