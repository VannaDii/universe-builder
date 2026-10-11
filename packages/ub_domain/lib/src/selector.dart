import 'dart:convert';

import 'selector_tables.dart';

/// Persisted identity format shared with the original storage implementation.
const selectorNormalizationVersion = 'nfc-0.1.22-casefold-0.2.0-v1';

String selectorKey(String name) {
  final scalars = name.runes.toList();
  // Dart strings can contain unpaired UTF-16 surrogates; Rust UTF-8 cannot.
  if (scalars.any((c) => c >= 0xd800 && c <= 0xdfff) ||
      utf8.encode(name).length > 640 ||
      scalars.length > 160 ||
      scalars.any(_forbidden)) {
    throw const FormatException('Invalid selector');
  }
  var first = 0;
  var end = scalars.length;
  while (first < end && _whiteSpace(scalars[first])) {
    first++;
  }
  while (end > first && _whiteSpace(scalars[end - 1])) {
    end--;
  }
  final normalized = _nfc(scalars.sublist(first, end));
  final key = String.fromCharCodes(
    _nfc([
      for (final scalar in normalized) ...fullCaseFolds[scalar] ?? [scalar],
    ]),
  );
  if (key.isEmpty || key == '*' || key == 'all' || key == '.') {
    throw const FormatException('Invalid selector');
  }
  return key;
}

bool _forbidden(int c) =>
    c <= 0x1f ||
    (c >= 0x7f && c <= 0x9f) ||
    c == 0x061c ||
    c == 0x200e ||
    c == 0x200f ||
    (c >= 0x202a && c <= 0x202e) ||
    (c >= 0x2066 && c <= 0x2069);

// Rust str::trim uses Unicode White_Space, which does not include U+FEFF.
bool _whiteSpace(int c) =>
    (c >= 9 && c <= 13) ||
    c == 0x20 ||
    c == 0x85 ||
    c == 0xa0 ||
    c == 0x1680 ||
    (c >= 0x2000 && c <= 0x200a) ||
    c == 0x2028 ||
    c == 0x2029 ||
    c == 0x202f ||
    c == 0x205f ||
    c == 0x3000;

List<int> _nfc(List<int> input) {
  final decomposed = <int>[];
  for (final scalar in input) {
    final hangul = scalar - 0xac00;
    if (hangul >= 0 && hangul < 11172) {
      decomposed.add(0x1100 + hangul ~/ 588);
      decomposed.add(0x1161 + (hangul % 588) ~/ 28);
      if (hangul % 28 != 0) decomposed.add(0x11a7 + hangul % 28);
    } else {
      decomposed.addAll(canonicalDecompositions[scalar] ?? [scalar]);
    }
  }
  // Stable ordering leaves equal classes in authored order and never crosses
  // a starter. Input is bounded to 160 scalars before expansion.
  for (var i = 1; i < decomposed.length; i++) {
    final c = decomposed[i];
    final cls = combiningClasses[c] ?? 0;
    if (cls == 0) continue;
    var j = i;
    while (j > 0 && (combiningClasses[decomposed[j - 1]] ?? 0) > cls) {
      decomposed[j] = decomposed[j - 1];
      j--;
    }
    decomposed[j] = c;
  }
  final result = <int>[];
  int? starter;
  var previousClass = 0;
  for (final scalar in decomposed) {
    final cls = combiningClasses[scalar] ?? 0;
    final composed = starter == null ? null : _compose(result[starter], scalar);
    if (composed != null && (previousClass == 0 || previousClass < cls)) {
      result[starter!] = composed;
    } else {
      if (cls == 0) starter = result.length;
      result.add(scalar);
      previousClass = cls;
    }
  }
  return result;
}

int? _compose(int a, int b) {
  final leading = a - 0x1100;
  final vowel = b - 0x1161;
  if (leading >= 0 && leading < 19 && vowel >= 0 && vowel < 21) {
    return 0xac00 + (leading * 21 + vowel) * 28;
  }
  final syllable = a - 0xac00;
  final trailing = b - 0x11a7;
  if (syllable >= 0 &&
      syllable < 11172 &&
      syllable % 28 == 0 &&
      trailing > 0 &&
      trailing < 28) {
    return a + trailing;
  }
  return canonicalCompositions[(a, b)];
}
