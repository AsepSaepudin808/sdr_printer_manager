import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'escpos_commands.dart';
import 'escpos_config.dart';

class EscPosImage {
  static Uint8List esc(img.Image src, PaperSize paperSize) {
    int maxW = EscPosCommands.paperMaxWidth(paperSize);
    img.Image resized = src;

    if (src.numChannels == 4) {
      final rgbImage =
          img.Image(width: src.width, height: src.height, numChannels: 3);
      for (int y = 0; y < src.height; y++) {
        for (int x = 0; x < src.width; x++) {
          final p = src.getPixel(x, y);
          final r = p.r.toInt();
          final g = p.g.toInt();
          final bVal = p.b.toInt();
          final a = p.a.toInt();
          final double alpha = a / 255.0;
          final int blendedR =
              (r * alpha + 255 * (1 - alpha)).round().clamp(0, 255);
          final int blendedG =
              (g * alpha + 255 * (1 - alpha)).round().clamp(0, 255);
          final int blendedB =
              (bVal * alpha + 255 * (1 - alpha)).round().clamp(0, 255);
          rgbImage.setPixelRgb(x, y, blendedR, blendedG, blendedB);
        }
      }
      resized = rgbImage;
    }

    if (resized.width > maxW) {
      resized = img.copyResize(resized, width: maxW);
    }

    final int imgWidth = resized.width;
    final int imgHeight = resized.height;
    final int widthBytes = (imgWidth + 7) ~/ 8;

    final List<double> gray = List<double>.filled(imgWidth * imgHeight, 0.0);
    for (int y = 0; y < imgHeight; y++) {
      for (int x = 0; x < imgWidth; x++) {
        final pixel = resized.getPixel(x, y);
        gray[y * imgWidth + x] =
            (0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b) / 255.0;
      }
    }

    final List<bool> bw = List<bool>.filled(imgWidth * imgHeight, false);
    for (int y = 0; y < imgHeight; y++) {
      for (int x = 0; x < imgWidth; x++) {
        final idx = y * imgWidth + x;
        final oldVal = gray[idx].clamp(0.0, 1.0);
        final newValue = oldVal < 0.5 ? 0.0 : 1.0;
        bw[idx] = newValue == 0.0;
        final err = oldVal - newValue;
        if (x + 1 < imgWidth) {
          gray[idx + 1] += err * (7.0 / 16.0);
        }
        if (y + 1 < imgHeight) {
          if (x - 1 >= 0) {
            gray[(y + 1) * imgWidth + (x - 1)] += err * (3.0 / 16.0);
          }
          gray[(y + 1) * imgWidth + x] += err * (5.0 / 16.0);
          if (x + 1 < imgWidth) {
            gray[(y + 1) * imgWidth + (x + 1)] += err * (1.0 / 16.0);
          }
        }
      }
    }

    final List<int> output = [];
    output.addAll([0x1D, 0x76, 0x30, 0x00]);
    output.addAll([widthBytes % 256, widthBytes ~/ 256]);
    output.addAll([imgHeight % 256, imgHeight ~/ 256]);

    for (int y = 0; y < imgHeight; y++) {
      for (int byteX = 0; byteX < widthBytes; byteX++) {
        int byte = 0;
        for (int bit = 0; bit < 8; bit++) {
          final pixelX = byteX * 8 + bit;
          if (pixelX >= imgWidth) continue;
          if (bw[y * imgWidth + pixelX]) {
            byte |= 1 << (7 - bit);
          }
        }
        output.add(byte);
      }
    }

    return Uint8List.fromList(output);
  }

  static img.Image cropWhiteBorder(img.Image src) {
    const threshold = 240;
    int top = 0, bottom = src.height - 1, left = 0, right = src.width - 1;

    outer_top:
    for (int y = 0; y < src.height; y++) {
      for (int x = 0; x < src.width; x++) {
        final p = src.getPixel(x, y);
        if ((p.r + p.g + p.b) ~/ 3 < threshold) {
          top = y;
          break outer_top;
        }
      }
    }
    outer_bottom:
    for (int y = src.height - 1; y >= top; y--) {
      for (int x = 0; x < src.width; x++) {
        final p = src.getPixel(x, y);
        if ((p.r + p.g + p.b) ~/ 3 < threshold) {
          bottom = y;
          break outer_bottom;
        }
      }
    }
    outer_left:
    for (int x = 0; x < src.width; x++) {
      for (int y = top; y <= bottom; y++) {
        final p = src.getPixel(x, y);
        if ((p.r + p.g + p.b) ~/ 3 < threshold) {
          left = x;
          break outer_left;
        }
      }
    }
    outer_right:
    for (int x = src.width - 1; x >= left; x--) {
      for (int y = top; y <= bottom; y++) {
        final p = src.getPixel(x, y);
        if ((p.r + p.g + p.b) ~/ 3 < threshold) {
          right = x;
          break outer_right;
        }
      }
    }

    final w = right - left + 1;
    final h = bottom - top + 1;
    if (w <= 0 || h <= 0) return src;
    return img.copyCrop(src, x: left, y: top, width: w, height: h);
  }
}
