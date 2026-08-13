import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:momir/core/ble/escpos_encoder.dart';
import 'package:momir/core/mana/mana_cost_parser.dart';
import 'package:momir/core/scryfall/bulk_uri.dart';
import 'package:momir/core/scryfall/card_extractor.dart';
import 'package:momir/core/scryfall/json_array_reader.dart';

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
  });

  test('oraclePieces keeps spaces and paragraph breaks', () {
    final pieces = oraclePieces('{T}: Draw a card.\nFlying');
    expect(
      pieces.map((p) => p.kind).toList(),
      [
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
      ],
    );
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
      'layout': 'normal',
      'image_uris': {
        'art_crop': 'https://example.com/art.jpg',
        'normal': 'https://example.com/n.jpg',
      },
    });
    expect(creature?.name, 'Grizzly Bears');
    expect(creature?.cmc, 2);
    expect(creature?.imageUriArtCrop, contains('art.jpg'));

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
}
