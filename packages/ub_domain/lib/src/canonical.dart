import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Matches universe-domain's canonical representation. Numeric tokens never
/// pass through a host floating-point value, including in browser builds.
sealed class CanonicalValue {
  const CanonicalValue();

  Uint8List toBytes() => Uint8List.fromList(utf8.encode(toText()));

  String toText() {
    final buffer = StringBuffer();
    _write(buffer);
    return buffer.toString();
  }

  void _write(StringBuffer buffer);

  /// Reads the existing Rust canonical-byte format, preserving object order
  /// and raw number tokens. This deliberately retains that parser's rejection
  /// of Unicode escapes; use [parseJson] at ordinary JSON decoding boundaries.
  static CanonicalValue parse(List<int> bytes) =>
      _Parser(utf8.decode(bytes), canonical: true).parse();

  /// Strict JSON decoding plus the Rust serde-to-canonical bridge. Duplicate
  /// keys are rejected before a map can discard them. Integers in i64/u64 range
  /// become number tokens; other numbers become exact strings, as in Rust.
  static CanonicalValue parseJson(String text) =>
      _Parser(text, canonical: false).parse();
}

final class CanonicalNull extends CanonicalValue {
  const CanonicalNull();
  @override
  void _write(StringBuffer buffer) => buffer.write('null');
}

final class CanonicalBool extends CanonicalValue {
  const CanonicalBool(this.value);
  final bool value;
  @override
  void _write(StringBuffer buffer) => buffer.write(value ? 'true' : 'false');
}

final class CanonicalNumber extends CanonicalValue {
  const CanonicalNumber(this.digits);
  final String digits;
  @override
  void _write(StringBuffer buffer) => buffer.write(digits);
}

final class CanonicalString extends CanonicalValue {
  CanonicalString(this.value) {
    _validateUnicode(value);
  }
  final String value;
  @override
  void _write(StringBuffer buffer) => _writeString(buffer, value);
}

final class CanonicalArray extends CanonicalValue {
  CanonicalArray(Iterable<CanonicalValue> items)
    : items = List.unmodifiable(items);
  final List<CanonicalValue> items;
  @override
  void _write(StringBuffer buffer) {
    buffer.write('[');
    for (var i = 0; i < items.length; i++) {
      if (i > 0) buffer.write(',');
      items[i]._write(buffer);
    }
    buffer.write(']');
  }
}

final class CanonicalObject extends CanonicalValue {
  factory CanonicalObject(Iterable<MapEntry<String, CanonicalValue>> fields) {
    final sorted = fields.toList()
      ..sort((a, b) => _compareUnicode(a.key, b.key));
    return CanonicalObject._ordered(sorted);
  }

  CanonicalObject._ordered(Iterable<MapEntry<String, CanonicalValue>> fields)
    : fields = List.unmodifiable(fields) {
    final seen = <String>{};
    for (final field in this.fields) {
      _validateUnicode(field.key);
      if (!seen.add(field.key)) {
        throw FormatException('Duplicate object key: ${field.key}');
      }
    }
  }
  final List<MapEntry<String, CanonicalValue>> fields;
  @override
  void _write(StringBuffer buffer) {
    buffer.write('{');
    for (var i = 0; i < fields.length; i++) {
      if (i > 0) buffer.write(',');
      _writeString(buffer, fields[i].key);
      buffer.write(':');
      fields[i].value._write(buffer);
    }
    buffer.write('}');
  }
}

/// Normative digest discriminator is the record kind. Legacy import prefixes
/// are explicit inputs only when reconstructing retained historical digests.
String payloadDigest(String discriminator, CanonicalValue value) => sha256
    .convert([...utf8.encode('$discriminator:'), ...value.toBytes()])
    .toString();

/// Unprefixed canonical hash used by revision inputs and membership checksums.
String canonicalDigest(CanonicalValue value) =>
    sha256.convert(value.toBytes()).toString();

int _compareUnicode(String a, String b) {
  final left = a.runes.iterator;
  final right = b.runes.iterator;
  while (true) {
    final hasLeft = left.moveNext();
    final hasRight = right.moveNext();
    if (!hasLeft || !hasRight) {
      return hasLeft ? 1 : (hasRight ? -1 : 0);
    }
    final order = left.current.compareTo(right.current);
    if (order != 0) return order;
  }
}

void _validateUnicode(String text) {
  for (var i = 0; i < text.length; i++) {
    final unit = text.codeUnitAt(i);
    if (unit >= 0xd800 && unit <= 0xdbff) {
      if (++i >= text.length ||
          text.codeUnitAt(i) < 0xdc00 ||
          text.codeUnitAt(i) > 0xdfff) {
        throw const FormatException('Unpaired Unicode surrogate');
      }
    } else if (unit >= 0xdc00 && unit <= 0xdfff) {
      throw const FormatException('Unpaired Unicode surrogate');
    }
  }
}

void _writeString(StringBuffer buffer, String text) {
  buffer.write('"');
  for (final rune in text.runes) {
    switch (rune) {
      case 34:
        buffer.write(r'\"');
      case 92:
        buffer.write(r'\\');
      case 10:
        buffer.write(r'\n');
      case 13:
        buffer.write(r'\r');
      case 9:
        buffer.write(r'\t');
      case 8:
        buffer.write(r'\b');
      case 12:
        buffer.write(r'\f');
      default:
        if (rune < 0x20) {
          buffer.write('\\u${rune.toRadixString(16).padLeft(4, '0')}');
        } else {
          buffer.writeCharCode(rune);
        }
    }
  }
  buffer.write('"');
}

final class _Parser {
  _Parser(this.text, {required this.canonical}) {
    _validateUnicode(text);
  }
  final String text;
  final bool canonical;
  int position = 0;
  static final _jsonNumber = RegExp(
    r'-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?',
  );
  static final _minimum = BigInt.parse('-9223372036854775808');
  static final _maximum = BigInt.parse('18446744073709551615');

  Never _fail(String message) => throw FormatException(message, text, position);
  int get _peek => position < text.length ? text.codeUnitAt(position) : -1;
  bool _take(int unit) {
    if (_peek != unit) return false;
    position++;
    return true;
  }

  void _space() {
    // Rust's canonical parser applies char::is_whitespace to each UTF-8 byte.
    // Ordinary JSON uses only its four permitted whitespace characters.
    while (_peek == 32 ||
        _peek == 9 ||
        _peek == 10 ||
        _peek == 13 ||
        (canonical && (_peek == 11 || _peek == 12))) {
      position++;
    }
  }

  CanonicalValue parse() {
    final value = _value();
    _space();
    if (position != text.length) _fail('Trailing data');
    return value;
  }

  CanonicalValue _value() {
    _space();
    if (_take(123)) {
      final fields = <MapEntry<String, CanonicalValue>>[];
      final seen = <String>{};
      _space();
      if (!_take(125)) {
        while (true) {
          _space();
          final key = _string();
          if (!seen.add(key)) _fail('Duplicate object key: $key');
          _space();
          if (!_take(58)) _fail('Expected colon');
          fields.add(MapEntry(key, _value()));
          _space();
          if (_take(125)) break;
          if (!_take(44)) _fail('Expected comma or closing brace');
        }
      }
      return canonical
          ? CanonicalObject._ordered(fields)
          : CanonicalObject(fields);
    }
    if (_take(91)) {
      final items = <CanonicalValue>[];
      _space();
      if (!_take(93)) {
        while (true) {
          items.add(_value());
          _space();
          if (_take(93)) break;
          if (!_take(44)) _fail('Expected comma or closing bracket');
        }
      }
      return CanonicalArray(items);
    }
    if (_peek == 34) return CanonicalString(_string());
    for (final token in ['true', 'false', 'null']) {
      if (text.startsWith(token, position)) {
        position += token.length;
        return switch (token) {
          'true' => const CanonicalBool(true),
          'false' => const CanonicalBool(false),
          _ => const CanonicalNull(),
        };
      }
    }
    if (_peek == 45 || (_peek >= 48 && _peek <= 57)) {
      if (canonical) {
        final start = position;
        while (_peek == 45 || _peek == 46 || (_peek >= 48 && _peek <= 57)) {
          position++;
        }
        return CanonicalNumber(text.substring(start, position));
      }
      final match = _jsonNumber.matchAsPrefix(text, position);
      if (match == null) _fail('Invalid JSON number');
      var digits = match.group(0)!;
      position = match.end;
      // serde_json's arbitrary-precision scanner normalizes the exponent
      // marker to lowercase and inserts an explicit positive sign.
      digits = digits.replaceFirstMapped(RegExp(r'[eE]([+-]?)([0-9]+)$'), (m) {
        return 'e${m[1]!.isEmpty ? '+' : m[1]}${m[2]}';
      });
      final integer = BigInt.tryParse(digits);
      return integer != null && integer >= _minimum && integer <= _maximum
          ? CanonicalNumber(integer.toString())
          : CanonicalString(digits);
    }
    _fail('Expected value');
  }

  String _string() {
    if (!_take(34)) _fail('Expected string');
    final buffer = StringBuffer();
    while (position < text.length) {
      final unit = text.codeUnitAt(position++);
      if (unit == 34) {
        final value = buffer.toString();
        _validateUnicode(value);
        return value;
      }
      if (unit < 32) _fail('Raw control character in string');
      if (unit != 92) {
        buffer.writeCharCode(unit);
        continue;
      }
      if (position == text.length) _fail('Dangling escape');
      switch (text.codeUnitAt(position++)) {
        case 34:
          buffer.write('"');
        case 92:
          buffer.write(r'\');
        case 47:
          buffer.write('/');
        case 98:
          buffer.writeCharCode(8);
        case 102:
          buffer.writeCharCode(12);
        case 110:
          buffer.writeCharCode(10);
        case 114:
          buffer.writeCharCode(13);
        case 116:
          buffer.writeCharCode(9);
        case 117:
          if (canonical) _fail('Non-canonical Unicode escape');
          if (position + 4 > text.length) _fail('Truncated Unicode escape');
          final hex = text.substring(position, position + 4);
          if (!RegExp(r'^[0-9a-fA-F]{4}$').hasMatch(hex)) {
            _fail('Invalid Unicode escape');
          }
          buffer.writeCharCode(int.parse(hex, radix: 16));
          position += 4;
        default:
          _fail('Invalid string escape');
      }
    }
    _fail('Unterminated string');
  }
}
