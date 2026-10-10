import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:image/image.dart' as img;
import 'package:momir/core/art/art_prep.dart';
import 'package:momir/core/ble/escpos_encoder.dart';
import 'package:momir/core/ble/tspl_encoder.dart';
import 'package:momir/core/mana/mana_cost_parser.dart';
import 'package:dio/dio.dart';
import 'package:momir/core/scryfall/bulk_uri.dart';
import 'package:momir/core/scryfall/card_extractor.dart';
import 'package:momir/core/scryfall/json_array_reader.dart';
import 'package:momir/core/scryfall/sync_error.dart';

void main() {
  test('parseManaText splits symbols and text', () {
    final spans = parseManaText('{2}{U}{U}: Draw a card. {T}: Tap target.');
    expect(spans.where((s) => s.isSymbol).map((s) => s.symbol).toList(), [
      '2',
      'U',
      'U',
      'T',
    ]);
    expect(spans.any((s) => s.text?.contains('Draw a card') == true), isTrue);
    expect(manaAssetPath('W/U'), 'assets/mana/W_U.png');
    expect(isGenericMana('2'), isTrue);
    expect(isGenericMana('X'), isTrue);
    expect(isGenericMana('W'), isFalse);
    expect(isGenericMana('W/U'), isFalse);
  });

  test('flattenOnWhite composites transparent pixels onto white', () {
    final src = img.Image(width: 2, height: 1, numChannels: 4);
    src.setPixelRgba(0, 0, 0, 0, 0, 0);
    src.setPixelRgba(1, 0, 0, 0, 255, 255);
    final out = flattenOnWhite(src);
    expect(out.getPixel(0, 0).r, 255);
    expect(out.getPixel(0, 0).g, 255);
    expect(out.getPixel(0, 0).b, 255);
    expect(out.getPixel(1, 0).b, 255);
    expect(out.getPixel(1, 0).r, 0);
  });

  test('ditherToBlackWhite keeps black and white on a gradient', () {
    final src = img.Image(width: 32, height: 8, numChannels: 3);
    for (final p in src) {
      final v = (p.x * 8).clamp(0, 255);
      p
        ..r = v
        ..g = v
        ..b = v;
    }
    final bw = ditherToBlackWhite(src);
    var black = 0;
    var white = 0;
    for (final p in bw) {
      if (p.r < 128) {
        black++;
      } else {
        white++;
      }
    }
    expect(black, greaterThan(10));
    expect(white, greaterThan(10));
  });

  test('ditherToBlackWhite keeps detail in a dark crop', () {
    final src = img.Image(width: 64, height: 16, numChannels: 3);
    for (final p in src) {
      final v = 10 + (p.x * 30 / 63).round();
      p
        ..r = v
        ..g = v
        ..b = v;
    }
    final bw = ditherToBlackWhite(src);
    var black = 0;
    var white = 0;
    for (final p in bw) {
      if (p.r < 128) {
        black++;
      } else {
        white++;
      }
    }
    expect(black, greaterThan(20));
    expect(white, greaterThan(20));
  });

  test('oraclePieces keeps spaces and paragraph breaks', () {
    final pieces = oraclePieces('{T}: Draw a card.\nFlying');
    expect(pieces.map((p) => p.kind).toList(), [
      OraclePieceKind.symbol,
      OraclePieceKind.word,
      OraclePieceKind.space,
      OraclePieceKind.word,
      OraclePieceKind.space,
      OraclePieceKind.word,
      OraclePieceKind.space,
      OraclePieceKind.word,
      OraclePieceKind.lineBreak,
      OraclePieceKind.word,
    ]);
    expect(
      pieces
          .where((p) => p.kind == OraclePieceKind.word)
          .map((p) => p.text)
          .toList(),
      [':', 'Draw', 'a', 'card.', 'Flying'],
    );
  });

  test('packRgbaToRaster sets MSB-first black bits', () {
    // 8x1 white then one black pixel at x=0
    final rgba = List<int>.filled(8 * 4, 255);
    rgba[0] = 0;
    rgba[1] = 0;
    rgba[2] = 0;
    final packed = packRgbaToRaster(Uint8List.fromList(rgba), 8, 1);
    expect(packed.length, 1);
    expect(packed[0] & 0x80, 0x80);
    expect(packed[0] & 0x40, 0);
  });

  test('encodeEscPosRaster starts with ESC @ and GS v 0', () {
    final raster = Uint8List(48); // 384/8 * 1
    final bytes = encodeEscPosRaster(
      raster: raster,
      width: 384,
      height: 1,
      feedLines: 2,
    );
    expect(bytes[0], 0x1b);
    expect(bytes[1], 0x40);
    expect(bytes[2], 0x1d);
    expect(bytes[3], 0x76);
    expect(bytes[4], 0x30);
    expect(bytes.last, 0x0a);
  });

  test('encodeTsplBitmap uses 48-byte rows for 57 mm paper', () {
    const width = 384;
    const height = 8;
    final bytes = encodeTsplBitmap(
      raster: Uint8List(width ~/ 8 * height),
      width: width,
      height: height,
    );
    final text = String.fromCharCodes(bytes.take(80));
    expect(text, contains('SIZE 48 mm'));
    expect(text, contains('BITMAP 0,0,48,8,0,'));
    final marker = ascii.encode('BITMAP 0,0,48,8,0,');
    final start = _indexOf(bytes, marker) + marker.length;
    expect(bytes[start], 0xff);
  });

  test('extractCreature keeps creatures and skips tokens', () {
    final creature = extractCreature({
      'id': 'abc',
      'name': 'Grizzly Bears',
      'mana_cost': '{1}{G}',
      'cmc': 2,
      'type_line': 'Creature — Bear',
      'oracle_text': '',
      'power': '2',
      'toughness': '2',
      'colors': ['G'],
      'set': '10e',
      'set_name': 'Tenth Edition',
      'layout': 'normal',
      'image_uris': {
        'art_crop': 'https://example.com/art.jpg',
        'normal': 'https://example.com/n.jpg',
      },
    });
    expect(creature?.name, 'Grizzly Bears');
    expect(creature?.cmc, 2);
    expect(creature?.imageUriArtCrop, contains('art.jpg'));
    expect(creature?.setCode, '10e');
    expect(creature?.setName, 'Tenth Edition');

    expect(
      extractCreature({
        'id': 'tok',
        'name': 'Bear',
        'type_line': 'Token Creature — Bear',
        'cmc': 0,
        'layout': 'token',
        'colors': <String>[],
      }),
      isNull,
    );
  });

  test('extractCreature uses creature face of DFC', () {
    final c = extractCreature({
      'id': 'dfc',
      'name': 'Delver of Secrets // Insectile Aberration',
      'cmc': 1,
      'type_line': 'Creature — Human Wizard // Creature — Human Insect',
      'layout': 'transform',
      'colors': ['U'],
      'card_faces': [
        {
          'name': 'Delver of Secrets',
          'mana_cost': '{U}',
          'type_line': 'Creature — Human Wizard',
          'oracle_text': '{T}: ...',
          'power': '1',
          'toughness': '1',
          'image_uris': {'art_crop': 'https://example.com/delver.jpg'},
        },
        {
          'name': 'Insectile Aberration',
          'type_line': 'Creature — Human Insect',
          'power': '3',
          'toughness': '2',
        },
      ],
    });
    expect(c?.name, 'Delver of Secrets');
    expect(c?.manaCost, '{U}');
    expect(c?.isCreature, isTrue);
    expect(c?.isArtifact, isFalse);
  });

  test('extractCreature keeps artifacts, enchantments, and planeswalkers', () {
    final golem = extractCreature({
      'id': 'golem',
      'name': 'Iron Golem',
      'mana_cost': '{4}',
      'cmc': 4,
      'type_line': 'Artifact Creature — Golem',
      'power': '4',
      'toughness': '4',
      'colors': <String>[],
      'layout': 'normal',
    });
    expect(golem?.isCreature, isTrue);
    expect(golem?.isArtifact, isTrue);
    expect(golem?.isEnchantment, isFalse);

    final sol = extractCreature({
      'id': 'sol',
      'name': 'Sol Ring',
      'mana_cost': '{1}',
      'cmc': 1,
      'type_line': 'Artifact',
      'oracle_text': '{T}: Add {C}{C}.',
      'colors': <String>[],
      'layout': 'normal',
    });
    expect(sol?.isArtifact, isTrue);
    expect(sol?.isCreature, isFalse);
    expect(sol?.power, isNull);

    final saga = extractCreature({
      'id': 'saga',
      'name': 'The Antiquities War',
      'cmc': 3,
      'type_line': 'Enchantment — Saga',
      'oracle_text': 'I — ...',
      'colors': ['U'],
      'layout': 'saga',
    });
    expect(saga?.isEnchantment, isTrue);
    expect(saga?.isCreature, isFalse);

    expect(
      extractCreature({
        'id': 'aura',
        'name': 'Giant Growth',
        'cmc': 1,
        'type_line': 'Enchantment — Aura',
        'oracle_text': 'Enchant creature\nEnchanted creature gets +3/+3.',
        'colors': ['G'],
        'layout': 'normal',
      }),
      isNull,
    );
    expect(
      extractCreature({
        'id': 'weird-aura',
        'name': 'Nameless Aura',
        'cmc': 1,
        'type_line': 'Enchantment — Aura',
        'oracle_text': 'Enchanted permanent is weird.',
        'colors': <String>[],
        'layout': 'normal',
      }),
      isNull,
    );
    expect(
      extractCreature({
        'id': 'or-vehicle',
        'name': 'Or Vehicle',
        'cmc': 2,
        'type_line': 'Enchantment — Aura',
        'oracle_text': 'Enchant creature or Vehicle\n...',
        'colors': <String>[],
        'layout': 'normal',
      }),
      isNull,
    );

    final landAura = extractCreature({
      'id': 'land-aura',
      'name': 'Fertile Ground',
      'cmc': 2,
      'type_line': 'Enchantment — Aura',
      'oracle_text':
          'Enchant land\nEnchanted land has "{T}: Add one mana of any color."',
      'colors': ['G'],
      'layout': 'normal',
    });
    expect(landAura?.name, 'Fertile Ground');
    expect(landAura?.isEnchantment, isTrue);
    expect(landAura?.isCreature, isFalse);

    final walker = extractCreature({
      'id': 'jace',
      'name': 'Jace, the Mind Sculptor',
      'cmc': 4,
      'type_line': 'Legendary Planeswalker — Jace',
      'oracle_text': '+2: ...',
      'loyalty': '4',
      'colors': ['U'],
      'layout': 'normal',
    });
    expect(walker?.isPlaneswalker, isTrue);
    expect(walker?.loyalty, '4');
    expect(walker?.isCreature, isFalse);

    final numeric = extractCreature({
      'id': 'num',
      'name': 'Walker',
      'cmc': 3,
      'type_line': 'Planeswalker — Test',
      'loyalty': 3,
      'colors': <String>[],
      'layout': 'normal',
    });
    expect(numeric?.loyalty, '3');

    expect(
      extractCreature({
        'id': 'bolt',
        'name': 'Lightning Bolt',
        'cmc': 1,
        'type_line': 'Instant',
        'oracle_text': 'Deal 3 damage.',
        'colors': ['R'],
        'layout': 'normal',
      }),
      isNull,
    );
  });

  test('bulkDownloadUri prefers jsonl_download_uri', () {
    expect(
      bulkDownloadUri({
        'type': 'oracle_cards',
        'jsonl_download_uri': 'https://example.com/oracle.jsonl.gz',
      }),
      'https://example.com/oracle.jsonl.gz',
    );
    expect(isGzipUri('https://x/oracle.jsonl.gz'), isTrue);
    expect(isJsonlUri('https://x/oracle.jsonl.gz'), isTrue);
  });

  test('jsonl reader yields objects', () async {
    final dir = await Directory.systemTemp.createTemp('momir');
    final file = File('${dir.path}/cards.jsonl');
    await file.writeAsString(
      '${jsonEncode({'id': '1', 'name': 'A'})}\n${jsonEncode({'id': '2', 'name': 'B'})}\n',
    );
    final items = await readBulkCardObjects(
      file,
      gzipped: false,
      jsonl: true,
    ).toList();
    expect(items.length, 2);
    expect(items.first['name'], 'A');
    await dir.delete(recursive: true);
  });

  test('json array scanner yields objects', () async {
    final dir = await Directory.systemTemp.createTemp('momir');
    final file = File('${dir.path}/cards.json');
    await file.writeAsString(
      jsonEncode([
        {'id': '1', 'name': 'A'},
        {'id': '2', 'name': 'B'},
      ]),
    );
    final items = await readBulkCardObjects(
      file,
      gzipped: false,
      jsonl: false,
    ).toList();
    expect(items.length, 2);
    expect(items.first['name'], 'A');
    await dir.delete(recursive: true);
  });

  test('syncErrorMessage hides the Dio timeout dump', () {
    final timeout = DioException(
      requestOptions: RequestOptions(path: 'https://api.scryfall.com'),
      type: DioExceptionType.connectionTimeout,
      message: 'The request connection took longer than 0:00:30.000000',
    );
    expect(
      syncErrorMessage(timeout),
      'Нет ответа от Scryfall. Проверьте интернет и повторите.',
    );
    expect(isRetryableSyncError(timeout), isTrue);
    expect(
      syncErrorMessage(StateError('Не найден пакет oracle_cards.')),
      'Не найден пакет oracle_cards.',
    );
    expect(isRetryableSyncError(StateError('x')), isFalse);
  });
}

int _indexOf(Uint8List data, List<int> needle) {
  for (var i = 0; i <= data.length - needle.length; i++) {
    var found = true;
    for (var j = 0; j < needle.length; j++) {
      if (data[i + j] != needle[j]) {
        found = false;
        break;
      }
    }
    if (found) return i;
  }
  return -1;
}
