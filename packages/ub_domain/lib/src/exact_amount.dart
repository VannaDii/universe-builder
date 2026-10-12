/// Existing i128 coefficient/scale semantics, expressed with BigInt so native
/// and browser calculations retain the same checked bounds.
final class ExactAmount {
  const ExactAmount(this.coefficient, this.scale);
  final BigInt coefficient;
  final int scale;
  BigInt? _aligned(int target) {
    final exponent = target - scale;
    if (exponent < 0 || exponent > 38) return null;
    final n = coefficient * BigInt.from(10).pow(exponent);
    return n < minimum || n > maximum ? null : n;
  }

  int? compareChecked(ExactAmount other) {
    final target = scale > other.scale ? scale : other.scale;
    final a = _aligned(target), b = other._aligned(target);
    return a == null || b == null ? null : a.compareTo(b);
  }

  ExactAmount? addChecked(ExactAmount other) {
    var target = scale > other.scale ? scale : other.scale;
    final a = _aligned(target), b = other._aligned(target);
    if (a == null || b == null) return null;
    var n = a + b;
    if (n < minimum || n > maximum) return null;
    while (target > 0 && n % BigInt.from(10) == BigInt.zero) {
      n ~/= BigInt.from(10);
      target--;
    }
    return ExactAmount(n, target);
  }

  String get digits {
    if (scale == 0) return coefficient.toString();
    final magnitude = coefficient.abs().toString().padLeft(scale + 1, '0');
    final at = magnitude.length - scale;
    return '${coefficient.isNegative ? '-' : ''}${magnitude.substring(0, at)}.${magnitude.substring(at)}';
  }

  static final minimum = -(BigInt.one << 127);
  static final maximum = (BigInt.one << 127) - BigInt.one;

  static ExactAmount? tryParse(String text) {
    if (text.length > 80 ||
        !RegExp(r'^-?[0-9]+(?:\.[0-9]+)?$').hasMatch(text)) {
      return null;
    }
    final parts = text.split('.');
    final fraction = parts.length == 1
        ? ''
        : parts[1].replaceFirst(RegExp(r'0+$'), '');
    final scale = fraction.length;
    if (BigInt.from(10).pow(scale) > maximum) return null;
    final coefficient = BigInt.tryParse('${parts[0]}$fraction');
    if (coefficient == null || coefficient < minimum || coefficient > maximum) {
      return null;
    }
    return ExactAmount(coefficient, scale);
  }

  /// Mirrors ConsequenceDecimal's stricter wire constructor, including its
  /// canonical integer spelling check. Decimal trailing zeros are preserved
  /// in the caller's authored token, not in this calculation key.
  static bool isConsequenceDecimal(String text) {
    if (!text.contains('.')) {
      final integer = BigInt.tryParse(text);
      if (integer == null || integer.toString() != text) return false;
    }
    final whole = text.split('.').first.replaceFirst(RegExp(r'^-'), '');
    if (text.contains('.') && whole.length > 1 && whole.startsWith('0')) {
      return false;
    }
    return tryParse(text) != null;
  }
}
