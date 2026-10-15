import 'dart:js_interop';

import 'package:ub_domain/ub_domain.dart';

/// Retained chronology uses named scalars, preserving authored coordinates.
@JS()
extension type BrowserChronologyFields._(JSObject _) implements JSObject {
  external factory BrowserChronologyFields({
    required String calendar,
    required String kind,
    required String firstInteraction,
    required String current,
    String? offsetSeconds,
    String? tickLabel,
    String? ticksPerMonth,
  });
  external String get calendar;
  external String get kind;
  external String get firstInteraction;
  external String get current;
  external String? get offsetSeconds;
  external String? get tickLabel;
  external String? get ticksPerMonth;
}

BrowserChronologyFields encodeBrowserChronology(Chronology value) =>
    BrowserChronologyFields(
      calendar: value.calendar.value,
      kind: value.system is GregorianClock ? 'gregorian' : 'fictional',
      firstInteraction: value.firstInteraction,
      current: value.current,
      offsetSeconds: switch (value.system) {
        GregorianClock(:final offsetSeconds) => offsetSeconds.toString(),
        FictionalClock() => null,
      },
      tickLabel: switch (value.system) {
        GregorianClock() => null,
        FictionalClock(:final tickLabel) => tickLabel,
      },
      ticksPerMonth: switch (value.system) {
        GregorianClock() => null,
        FictionalClock(:final ticksPerMonth) => ticksPerMonth?.toString(),
      },
    );
Chronology decodeBrowserChronology(BrowserChronologyFields value) => Chronology(
  calendar: CalendarId.parse(value.calendar),
  system: switch (value.kind) {
    'gregorian' => GregorianClock(int.parse(value.offsetSeconds!)),
    'fictional' => FictionalClock(
      value.tickLabel!,
      value.ticksPerMonth == null ? null : int.parse(value.ticksPerMonth!),
    ),
    _ => throw const FormatException('Unknown clock system'),
  },
  firstInteraction: value.firstInteraction,
  current: value.current,
);
