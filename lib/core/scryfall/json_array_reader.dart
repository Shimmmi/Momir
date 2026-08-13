import 'dart:convert';
import 'dart:io';

/// Streams top-level objects from a JSON array file without loading it all.
Stream<Map<String, dynamic>> readJsonArrayObjects(File file) async* {
  final scanner = _JsonArrayScanner();
  await for (final chunk in file.openRead().transform(utf8.decoder)) {
    for (final raw in scanner.add(chunk)) {
      yield _asMap(raw);
    }
  }
  for (final raw in scanner.flush()) {
    yield _asMap(raw);
  }
}

Map<String, dynamic> _asMap(String raw) {
  final decoded = jsonDecode(raw);
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
        if (c == 0x5b) _seenArray = true; // [
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
