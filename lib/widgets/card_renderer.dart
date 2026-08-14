import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

import '../core/art/art_prep.dart';
import '../core/ble/escpos_encoder.dart';
import '../core/ble/printer_profile.dart';
import '../core/constants.dart';
import '../core/mana/mana_cost_parser.dart';
import '../models/creature.dart';

class PrintableCard {
  const PrintableCard({
    required this.width,
    required this.height,
    required this.raster,
    required this.pngBytes,
  });

  final int width;
  final int height;
  final Uint8List raster;
  final Uint8List pngBytes;
}

class CardRenderService {
  CardRenderService();

  Map<String, ui.Image>? _mana;
  final _paintWidth = PrinterProfile.pt210.printWidth;

  Future<void> ensureLoaded() async {
    if (_mana != null) return;
    final icons = <String, ui.Image>{};
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    for (final key in manifest.listAssets()) {
      if (!key.startsWith('assets/mana/') || !key.endsWith('.png')) continue;
      final file = key.split('/').last.replaceAll('.png', '');
      final image = await _decodeAsset(key);
      icons[file] = image;
      icons[file.replaceAll('_', '/')] = image;
    }
    _mana = icons;
  }

  Future<ui.Image> _decodeAsset(String key) async {
    final data = await rootBundle.load(key);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  Future<PrintableCard> renderCreature(
    Creature creature, {
    Uint8List? artJpeg,
  }) async {
    await ensureLoaded();
    ui.Image? art;
    if (artJpeg != null && artJpeg.isNotEmpty) {
      art = await _ditherToUiImage(artJpeg);
    }
    try {
      return await _paintCard(creature, art);
    } finally {
      art?.dispose();
    }
  }

  Future<PrintableCard> renderPlainText(String text) async {
    await ensureLoaded();
    const pad = 12.0;
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Colors.black,
          fontSize: 28,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: _paintWidth - pad * 2);
    final height = (pad * 2 + tp.height + 24).ceil().clamp(48, 2000);
    return _rasterize(_paintWidth, height, (canvas) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, _paintWidth.toDouble(), height.toDouble()),
        Paint()..color = Colors.white,
      );
      tp.paint(canvas, const Offset(pad, pad));
    });
  }

  Future<ui.Image> _ditherToUiImage(Uint8List jpeg) async {
    final decoded = img.decodeImage(jpeg);
    if (decoded == null) {
      throw StateError('Не удалось декодировать арт');
    }
    final bw = ditherToBlackWhite(flattenOnWhite(decoded));
    final rgba = bw.convert(numChannels: 4);
    final bytes = rgba.getBytes(order: img.ChannelOrder.rgba);
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      bytes,
      rgba.width,
      rgba.height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }

  Future<PrintableCard> _paintCard(Creature creature, ui.Image? art) async {
    const pad = 10.0;
    const manaSize = 22.0;
    final width = _paintWidth.toDouble();
    final contentW = width - pad * 2;

    final manaSpans = parseManaText(creature.manaCost);
    final manaWidth = _manaRowWidth(manaSpans, manaSize);
    final nameMax = (contentW - (manaWidth > 0 ? manaWidth + 8 : 0)).clamp(
      80.0,
      contentW,
    );
    var nameSize = 22.0;
    TextPainter namePainter;
    while (true) {
      namePainter = TextPainter(
        text: TextSpan(
          text: creature.name,
          style: TextStyle(
            color: Colors.black,
            fontSize: nameSize,
            fontWeight: FontWeight.w800,
            height: 1.05,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 2,
        ellipsis: '…',
      )..layout(maxWidth: nameMax);
      if (namePainter.height <= 52 || nameSize <= 12) break;
      nameSize -= 1;
    }

    final headerH = [
      namePainter.height,
      manaWidth > 0 ? manaSize : 0.0,
    ].reduce((a, b) => a > b ? a : b);

    final typePainter = TextPainter(
      text: TextSpan(
        text: creature.typeLine ?? 'Creature',
        style: const TextStyle(
          color: Colors.black,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 2,
      ellipsis: '…',
    )..layout(maxWidth: contentW);

    final oracleHeight = _measureOracle(
      creature.oracleText,
      contentW,
      kMaxOracleHeight,
    );

    final pt = [
      creature.power,
      creature.toughness,
    ].whereType<String>().join('/');
    final ptPainter = TextPainter(
      text: TextSpan(
        text: pt.isEmpty ? '' : pt,
        style: const TextStyle(
          color: Colors.black,
          fontSize: 26,
          fontWeight: FontWeight.w800,
        ),
      ),
      textAlign: TextAlign.right,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: contentW);

    var y = pad;
    y += headerH + 6;
    y += 2 + 6; // line
    final artH = art != null ? kArtHeight.toDouble() : 72.0;
    y += artH + 6;
    y += typePainter.height + 6;
    y += 2 + 6;
    y += oracleHeight + 8;
    y += 2 + 6;
    y += (ptPainter.height) + pad;
    final height = y.ceil().clamp(120, 4000);

    return _rasterize(_paintWidth, height, (canvas) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, width, height.toDouble()),
        Paint()..color = Colors.white,
      );
      final black = Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;

      var cy = pad;
      namePainter.paint(canvas, Offset(pad, cy));
      if (manaWidth > 0) {
        _paintManaRow(
          canvas,
          manaSpans,
          Offset(width - pad - manaWidth, cy + (headerH - manaSize) / 2),
          manaSize,
        );
      }
      cy += headerH + 6;
      canvas.drawLine(Offset(pad, cy), Offset(width - pad, cy), black);
      cy += 8;
      final artRect = Rect.fromLTWH(pad, cy, contentW, artH);
      canvas.drawRect(artRect, black);
      if (art != null) {
        paintImage(
          canvas: canvas,
          rect: artRect.deflate(2),
          image: art,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.none,
        );
      } else {
        final ph = TextPainter(
          text: const TextSpan(
            text: 'нет арта',
            style: TextStyle(color: Colors.black, fontSize: 14),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        ph.paint(
          canvas,
          Offset(
            artRect.center.dx - ph.width / 2,
            artRect.center.dy - ph.height / 2,
          ),
        );
      }
      cy += artH + 6;
      typePainter.paint(canvas, Offset(pad, cy));
      cy += typePainter.height + 6;
      canvas.drawLine(Offset(pad, cy), Offset(width - pad, cy), black);
      cy += 8;
      _paintOracle(
        canvas,
        creature.oracleText,
        Rect.fromLTWH(pad, cy, contentW, oracleHeight),
      );
      cy += oracleHeight + 8;
      canvas.drawLine(Offset(pad, cy), Offset(width - pad, cy), black);
      cy += 8;
      if (pt.isNotEmpty) {
        ptPainter.paint(canvas, Offset(width - pad - ptPainter.width, cy));
      }
    });
  }

  double _manaRowWidth(List<ManaSpan> spans, double size) {
    var w = 0.0;
    for (final s in spans) {
      if (s.isSymbol) {
        w += size + 2;
      }
    }
    return w;
  }

  void _paintManaRow(
    Canvas canvas,
    List<ManaSpan> spans,
    Offset origin,
    double size,
  ) {
    var x = origin.dx;
    for (final s in spans) {
      if (!s.isSymbol) continue;
      _paintSymbol(canvas, s.symbol!, Offset(x, origin.dy), size);
      x += size + 2;
    }
  }

  void _paintSymbol(Canvas canvas, String code, Offset origin, double size) {
    final icon = _mana?[code] ?? _mana?[code.replaceAll('/', '_')];
    if (icon != null) {
      paintImage(
        canvas: canvas,
        rect: Rect.fromLTWH(origin.dx, origin.dy, size, size),
        image: icon,
        filterQuality: FilterQuality.none,
      );
      return;
    }
    final tp = TextPainter(
      text: TextSpan(
        text: '{$code}',
        style: TextStyle(color: Colors.black, fontSize: size * 0.55),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, origin);
  }

  double _measureOracle(String? text, double maxWidth, double maxHeight) {
    if (text == null || text.trim().isEmpty) return 0;
    return _layoutOracle(text, maxWidth, maxHeight, null, Offset.zero);
  }

  void _paintOracle(Canvas canvas, String? text, Rect bounds) {
    if (text == null || text.trim().isEmpty) return;
    _layoutOracle(text, bounds.width, bounds.height, canvas, bounds.topLeft);
  }

  double _layoutOracle(
    String text,
    double maxWidth,
    double maxHeight,
    Canvas? canvas,
    Offset origin,
  ) {
    const fontSize = 13.0;
    const lineH = 18.0;
    const icon = 14.0;
    const paragraphGap = 6.0;
    var x = 0.0;
    var y = 0.0;
    var atLineStart = true;

    void newline({bool paragraph = false}) {
      x = 0;
      y += lineH + (paragraph ? paragraphGap : 0);
      atLineStart = true;
    }

    final spaceWidth = _spaceWidth(fontSize);
    final pieces = oraclePieces(text);
    for (final piece in pieces) {
      if (y + lineH > maxHeight) break;
      switch (piece.kind) {
        case OraclePieceKind.lineBreak:
          newline(paragraph: true);
          if (y + lineH > maxHeight) return y;
        case OraclePieceKind.space:
          if (atLineStart) break;
          if (x + spaceWidth > maxWidth) {
            newline();
          } else {
            x += spaceWidth;
          }
        case OraclePieceKind.symbol:
          if (x + icon > maxWidth && !atLineStart) newline();
          if (y + lineH > maxHeight) return y;
          if (canvas != null) {
            _paintSymbol(
              canvas,
              piece.symbol!,
              Offset(origin.dx + x, origin.dy + y),
              icon,
            );
          }
          x += icon + 1;
          atLineStart = false;
        case OraclePieceKind.word:
          final tp = _word(piece.text ?? '', fontSize);
          if (x + tp.width > maxWidth && !atLineStart) newline();
          if (y + lineH > maxHeight) {
            if (canvas != null) {
              _word('…', fontSize).paint(
                canvas,
                Offset(origin.dx + x, origin.dy + y),
              );
            }
            return maxHeight;
          }
          if (canvas != null) {
            tp.paint(canvas, Offset(origin.dx + x, origin.dy + y));
          }
          x += tp.width;
          atLineStart = false;
      }
    }
    return y + lineH;
  }

  double _spaceWidth(double fontSize) {
    final gap = _word('x x', fontSize).width - _word('xx', fontSize).width;
    return gap >= 1 ? gap : fontSize * 0.3;
  }

  TextPainter _word(String text, double fontSize) {
    return TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: Colors.black, fontSize: fontSize, height: 1.2),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
  }

  Future<PrintableCard> _rasterize(
    int width,
    int height,
    void Function(Canvas canvas) paint,
  ) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    paint(canvas);
    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    if (rgba == null || png == null) {
      throw StateError('Не удалось растеризовать карточку');
    }
    final raster = packRgbaToRaster(rgba.buffer.asUint8List(), width, height);
    return PrintableCard(
      width: width,
      height: height,
      raster: raster,
      pngBytes: png.buffer.asUint8List(),
    );
  }
}
