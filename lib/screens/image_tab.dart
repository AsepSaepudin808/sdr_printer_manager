import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;
import '../providers/app_state_provider.dart';
import '../providers/bluetooth_provider.dart';
import '../providers/history_provider.dart';
import '../models/print_history.dart';
import '../utils/escpos_helper.dart';
import '../utils/strings.dart';
import '../utils/colors.dart';

class ImageTab extends ConsumerStatefulWidget {
  const ImageTab({super.key});

  @override
  ConsumerState<ImageTab> createState() => _ImageTabState();
}

class _ImageTabState extends ConsumerState<ImageTab>
    with SingleTickerProviderStateMixin {
  static const _primary = AppColors.primary;

  File? _imageFile;
  bool _isPrinting = false;
  String _status = '';
  late AnimationController _pulseController;

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

  Future<void> _pickImage() async {
    final result = await FilePicker.pickFiles(type: FileType.image);
    if (result.isNotEmpty && result.first.path != null) {
      setState(() {
        _imageFile = File(result.first.path!);
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
      // Baca paperSize dari provider langsung
      final paperSize = ref.read(appStateProvider).paperSize;
      final bytes = await _imageFile!.readAsBytes();
      final original = img.decodeImage(bytes);
      if (original == null) {
        setState(() {
          _isPrinting = false;
          _status = S.imageReadFail;
        });
        return;
      }

      final maxW = EscPosHelper.paperMaxWidth(paperSize);
      final resized = img.copyResize(original, width: maxW);
      final mono = img.grayscale(resized);

      final escData = _imageToEscPos(mono, maxW);

      final btService = ref.read(bluetoothServiceProvider);
      final ok = await btService.sendRaw(escData);

      if (ok) {
        ref.read(historyNotifierProvider.notifier).add(PrintHistory(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              type: 'image',
              label: 'Image Print',
              timestamp: DateTime.now(),
              success: true,
              dataSize: escData.length,
              source: 'manual',
            ));
      }

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
              if (img.getLuminance(pixel) < 128) byte |= (0x80 >> bit);
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

  Widget _buildImageButton(
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

  @override
  Widget build(BuildContext context) {
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
          Expanded(
              child: GestureDetector(
            onTap: _pickImage,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: _imageFile != null
                        ? _primary.withValues(alpha: 0.3)
                        : Colors.grey.shade200,
                    width: 2),
                boxShadow: [
                  BoxShadow(
                      color: (_imageFile != null ? _primary : Colors.grey)
                          .withValues(alpha: 0.1),
                      blurRadius: 20,
                      offset: const Offset(0, 8))
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: _imageFile != null
                    ? Stack(children: [
                        Positioned.fill(
                            child:
                                Image.file(_imageFile!, fit: BoxFit.contain)),
                        Positioned(
                            top: 12,
                            right: 12,
                            child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.5),
                                    borderRadius: BorderRadius.circular(10)),
                                child: const Icon(Icons.image_rounded,
                                    color: Colors.white, size: 20))),
                      ])
                    : Center(
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                        AnimatedBuilder(
                            animation: _pulseController,
                            builder: (context, child) {
                              return Transform.scale(
                                  scale: 1.0 + (_pulseController.value * 0.1),
                                  child: Opacity(
                                      opacity:
                                          0.5 + (_pulseController.value * 0.5),
                                      child: child));
                            },
                            child: Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                    color: _primary.withValues(alpha: 0.1),
                                    shape: BoxShape.circle),
                                child: const Icon(
                                    Icons.add_photo_alternate_rounded,
                                    size: 48,
                                    color: _primary))),
                        const SizedBox(height: 16),
                        Text(S.tapToSelectImage,
                            style: TextStyle(
                                color: Colors.grey.shade500,
                                fontSize: 15,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        Text('PNG, JPG, JPEG',
                            style: TextStyle(
                                color: Colors.grey.shade400, fontSize: 12)),
                      ])),
              ),
            ),
          )),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
                child: _buildImageButton(
                    icon: Icons.folder_open_rounded,
                    label: S.selectImage,
                    color: _primary,
                    outlined: true,
                    onTap: _pickImage)),
            const SizedBox(width: 12),
            Expanded(
                child: _buildImageButton(
                    icon: _isPrinting ? null : Icons.print_rounded,
                    label: _isPrinting ? S.printing : S.print_,
                    color: _primary,
                    outlined: false,
                    loading: _isPrinting,
                    onTap: (_isPrinting || _imageFile == null)
                        ? null
                        : _printImage)),
          ]),
          if (_status.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: _status.startsWith('✅')
                    ? const Color(0xFF06C270).withValues(alpha: 0.1)
                    : const Color(0xFFFF3B30).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(_status,
                  style: TextStyle(
                      color: _status.startsWith('✅')
                          ? const Color(0xFF06C270)
                          : const Color(0xFFFF3B30),
                      fontWeight: FontWeight.w600,
                      fontSize: 13)),
            ),
          ],
        ]),
      ),
    );
  }
}
