import 'dart:math' as math;

import 'package:image/image.dart' as img;

/// JPEG has no alpha. Transparent PNG pixels otherwise become black.
img.Image flattenOnWhite(img.Image src) {
  final out = img.Image(width: src.width, height: src.height, numChannels: 3);
  img.fill(out, color: img.ColorRgb8(255, 255, 255));
  img.compositeImage(out, src);
  return out;
}

/// Floyd–Steinberg to real black/white.
///
/// `image.quantize(..., numberOfColors: 2)` uses an octree and can pick two
/// dark palette colors, so night-time arts render as a black rectangle.
img.Image ditherToBlackWhite(img.Image src, {double gamma = 0.85}) {
  final w = src.width;
  final h = src.height;
  final lum = List<double>.filled(w * h, 0);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = src.getPixel(x, y);
      final g = (0.299 * p.r.toDouble() +
              0.587 * p.g.toDouble() +
              0.114 * p.b.toDouble())
          .clamp(0.0, 255.0);
      lum[y * w + x] = 255 * math.pow(g / 255.0, gamma).toDouble();
    }
  }

  final out = img.Image(width: w, height: h, numChannels: 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = y * w + x;
      final old = lum[i].clamp(0.0, 255.0);
      final neu = old < 128 ? 0.0 : 255.0;
      final err = old - neu;
      final v = neu.toInt();
      out.setPixelRgba(x, y, v, v, v, 255);
      if (x + 1 < w) {
        lum[i + 1] += err * 7 / 16;
      }
      if (y + 1 < h) {
        if (x > 0) {
          lum[i + w - 1] += err * 3 / 16;
        }
        lum[i + w] += err * 5 / 16;
        if (x + 1 < w) {
          lum[i + w + 1] += err * 1 / 16;
        }
      }
    }
  }
  return out;
}
