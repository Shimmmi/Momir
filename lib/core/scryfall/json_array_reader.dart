import 'dart:convert';
import 'dart:io';

/// Streams card objects from a Scryfall bulk file (JSON array or JSONL, optional gzip).
Stream<Map<String, dynamic>> readBulkCardObjects(
  File file, {
  required bool gzipped,
  required bool jsonl,
}) async* {
  Stream<List<int>> bytes = file.openRead();
  if (gzipped) {
    final header = await file.openRead(0, 2).fold<List<int>>(
      <int>[],
      (prev, chunk) => prev..addAll(chunk),
    );
    final isGzipMagic =
        header.length >= 2 && header[0] == 0x1f && header[1] == 0x8b;
    if (isGzipMagic) {
      bytes = file.openRead().transform(gzip.decoder);
    }
  }
  if (jsonl) {
    await for (final line
        in bytes.transform(utf8.decoder).transform(const LineSplitter())) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      yield _asMap(jsonDecode(trimmed));
    }
    return;
  }

  final tmp = File('${file.path}.json');
  final sink = tmp.openWrite();
  await bytes.forEach(sink.add);
  await sink.close();
  try {
    yield* _readJsonArray(tmp);
  } finally {
    try {
      await tmp.delete();
    } catch (_) {}
  }
}

Stream<Map<String, dynamic>> _readJsonArray(File file) async* {
  final scanner = _JsonArrayScanner();
  await for (final chunk in file.openRead().transform(utf8.decoder)) {
    for (final raw in scanner.add(chunk)) {
      yield _asMap(jsonDecode(raw));
    }
  }
  for (final raw in scanner.flush()) {
    yield _asMap(jsonDecode(raw));
  }
}

Map<String, dynamic> _asMap(dynamic decoded) {
  if (decoded is Map<String, dynamic>) return decoded;
  if (decoded is Map) return Map<String, dynamic>.from(decoded);
  throw FormatException('Expected JSON object');
}

class _JsonArrayScanner {
  var _buf = '';
  var _i = 0;
  var _seenArray = false;
  var _inString = false;
  var _escape = false;
  var _depth = 0;
  var _objStart = -1;

  List<String> add(String chunk) {
    _buf += chunk;
    return _pull(endOfInput: false);
  }

  List<String> flush() => _pull(endOfInput: true);

  List<String> _pull({required bool endOfInput}) {
    final out = <String>[];
    while (_i < _buf.length) {
      final c = _buf.codeUnitAt(_i);

      if (!_seenArray) {
        if (c == 0x5b) _seenArray = true;
        _i++;
        continue;
      }

      if (_inString) {
        if (_escape) {
          _escape = false;
        } else if (c == 0x5c) {
          _escape = true;
        } else if (c == 0x22) {
          _inString = false;
        }
        _i++;
        continue;
      }

      if (c == 0x22) {
        _inString = true;
        _i++;
        continue;
      }

      if (c == 0x7b) {
        if (_depth == 0) _objStart = _i;
        _depth++;
        _i++;
        continue;
      }

      if (c == 0x7d) {
        if (_depth > 0) _depth--;
        if (_depth == 0 && _objStart >= 0) {
          out.add(_buf.substring(_objStart, _i + 1));
          _objStart = -1;
        }
        _i++;
        continue;
      }

      _i++;
    }

    if (_objStart >= 0) {
      _buf = _buf.substring(_objStart);
      _i -= _objStart;
      _objStart = 0;
    } else {
      _buf = endOfInput ? '' : _buf.substring(_i);
      _i = 0;
    }
    return out;
  }
}
