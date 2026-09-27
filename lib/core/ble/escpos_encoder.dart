import 'dart:typed_data';

import '../../core/constants.dart';

/// Packs RGBA pixels into ESC/POS 1-bit raster (MSB-first, 1 = black).
Uint8List packRgbaToRaster(Uint8List rgba, int width, int height) {
  if (width % 8 != 0) {
    throw ArgumentError('width must be divisible by 8, got $width');
  }
  final bytesPerRow = width ~/ 8;
  final out = Uint8List(bytesPerRow * height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final i = (y * width + x) * 4;
      final r = rgba[i];
      final g = rgba[i + 1];
      final b = rgba[i + 2];
      final luma = (r * 3 + g * 4 + b) >> 3;
      if (luma < 128) {
        out[y * bytesPerRow + (x >> 3)] |= 0x80 >> (x & 7);
      }
    }
  }
  return out;
}

/// ESC/POS: ESC @ initialize, GS v 0 raster bands, then line feeds.
Uint8List encodeEscPosRaster({
  required Uint8List raster,
  required int width,
  required int height,
  int bandHeight = kRasterBandHeight,
  int feedLines = kFeedLines,
}) {
  if (width % 8 != 0) {
    throw ArgumentError('width must be divisible by 8');
  }
  final bytesPerRow = width ~/ 8;
  final expected = bytesPerRow * height;
  if (raster.length != expected) {
    throw ArgumentError('raster length ${raster.length} != $expected');
  }

  final out = BytesBuilder(copy: false);
  out.add(const [0x1b, 0x40]); // ESC @

  var y = 0;
  while (y < height) {
    final sliceH = (height - y).clamp(1, bandHeight);
    final xL = bytesPerRow & 0xff;
    final xH = (bytesPerRow >> 8) & 0xff;
    final yL = sliceH & 0xff;
    final yH = (sliceH >> 8) & 0xff;
    out.add([0x1d, 0x76, 0x30, 0x00, xL, xH, yL, yH]);
    final start = y * bytesPerRow;
    out.add(raster.sublist(start, start + bytesPerRow * sliceH));
    y += sliceH;
  }

  for (var i = 0; i < feedLines; i++) {
    out.add(const [0x0a]);
  }
  return out.toBytes();
}

/// Full-width ruler raster. Long ticks every 64 dots, short ticks every 32.
Uint8List widthRulerRaster({required int width}) {
  const height = 72;
  final bytesPerRow = width ~/ 8;
  final raster = Uint8List(bytesPerRow * height);

  void set(int x, int y) {
    raster[y * bytesPerRow + (x >> 3)] |= 0x80 >> (x & 7);
  }

  for (var x = 0; x < width; x++) {
    set(x, 0);
    set(x, 1);
    set(x, height - 2);
    set(x, height - 1);
  }
  for (var x = 0; x < width; x += 32) {
    final tall = x % 64 == 0;
    final mark = tall ? 56 : 28;
    for (var y = 4; y < mark; y++) {
      set(x, y);
      if (x + 1 < width) set(x + 1, y);
    }
  }
  return raster;
}

Uint8List encodeWidthRuler({required int width}) {
  const height = 72;
  return encodeEscPosRaster(
    raster: widthRulerRaster(width: width),
    width: width,
    height: height,
    feedLines: 8,
  );
}
