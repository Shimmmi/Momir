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

Uint8List encodeTestPattern({required int width}) {
  const height = 48;
  final bytesPerRow = width ~/ 8;
  final raster = Uint8List(bytesPerRow * height);
  for (var x = 0; x < width; x++) {
    raster[x >> 3] |= 0x80 >> (x & 7);
    final bottom = (height - 1) * bytesPerRow;
    raster[bottom + (x >> 3)] |= 0x80 >> (x & 7);
  }
  for (var y = 0; y < height; y++) {
    raster[y * bytesPerRow] |= 0x80;
    raster[y * bytesPerRow + bytesPerRow - 1] |= 0x01;
  }
  return encodeEscPosRaster(
    raster: raster,
    width: width,
    height: height,
    feedLines: 8,
  );
}
