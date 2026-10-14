import 'package:ub_domain/ub_domain.dart';

/// Resolves against the supplied pinned clock, without changing it.
String resolveStoryMonthsAgo(Chronology clock, String input) {
  if (!RegExp(r'^\+?[0-9]+$').hasMatch(input)) {
    throw const FormatException('Enter a nonnegative whole number of months.');
  }
  final months = BigInt.parse(input);
  if (months > BigInt.from(4294967295)) {
    throw const FormatException(
      'The number of months is outside the supported range.',
    );
  }
  return clock.display(clock.monthsAgo(clock.current, months.toInt()));
}
