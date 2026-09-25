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
/// A fixed threshold of 128 turns night arts into a solid black rectangle:
/// every pixel sits below the cut, so error diffusion never reaches white.
/// Stretch the 2nd–98th percentile onto 0…255 before dithering.
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
  _stretchContrast(lum);

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

/// Maps the 2nd and 98th percentiles onto 0 and 255 so a dark crop still
/// has both ink and paper after the 128 threshold.
void _stretchContrast(List<double> lum) {
  if (lum.length < 8) return;
  final sorted = List<double>.from(lum)..sort();
  final lo = sorted[(sorted.length * 0.02).floor()];
  final hiIndex = (sorted.length * 0.98).floor().clamp(0, sorted.length - 1);
  final hi = sorted[hiIndex];
  final span = hi - lo;
  if (span < 8) return;
  for (var i = 0; i < lum.length; i++) {
    lum[i] = ((lum[i] - lo) / span * 255).clamp(0.0, 255.0);
  }
}
