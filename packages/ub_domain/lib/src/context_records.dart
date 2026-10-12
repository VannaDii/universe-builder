part of 'records.dart';

sealed class RepresentedContextKind {
  const RepresentedContextKind();
  CanonicalObject toWire();
  static RepresentedContextKind fromWire(CanonicalValue value) {
    final f = Fields(value);
    switch (f.string('kind')) {
      case 'objective':
        f.allow({'kind'});
        return const ObjectiveContext();
      case 'character':
        f.allow({'kind', 'holder'});
        return CharacterContext(RecordRef.fromCanonical(f.require('holder')));
      case 'source':
        f.allow({'kind', 'source'});
        return SourceContext(RecordRef.fromCanonical(f.require('source')));
      case 'narrator':
        f.allow({'kind', 'narrator'});
        return NarratorContext(RecordRef.fromCanonical(f.require('narrator')));
      case 'authored':
        f.allow({'kind', 'label'});
        return AuthoredContext(f.string('label'));
      default:
        throw const FormatException('Unknown represented context');
    }
  }
}

final class ObjectiveContext extends RepresentedContextKind {
  const ObjectiveContext();
  @override
  CanonicalObject toWire() => tagged('objective', []);
}

final class CharacterContext extends RepresentedContextKind {
  const CharacterContext(this.holder);
  final RecordRef holder;
  @override
  CanonicalObject toWire() =>
      tagged('character', [MapEntry('holder', holder.toCanonical())]);
}

final class SourceContext extends RepresentedContextKind {
  const SourceContext(this.source);
  final RecordRef source;
  @override
  CanonicalObject toWire() =>
      tagged('source', [MapEntry('source', source.toCanonical())]);
}

final class NarratorContext extends RepresentedContextKind {
  const NarratorContext(this.narrator);
  final RecordRef narrator;
  @override
  CanonicalObject toWire() =>
      tagged('narrator', [MapEntry('narrator', narrator.toCanonical())]);
}

final class AuthoredContext extends RepresentedContextKind {
  const AuthoredContext(this.label);
  final String label;
  @override
  CanonicalObject toWire() =>
      tagged('authored', [MapEntry('label', CanonicalString(label))]);
}

sealed class ClockSystem {
  const ClockSystem();
  CanonicalObject toWire();
  static ClockSystem fromWire(CanonicalValue value) {
    final f = Fields(value);
    switch (f.string('kind')) {
      case 'gregorian':
        f.allow({'kind', 'offset_seconds'});
        final offset = f.require('offset_seconds');
        if (offset is! CanonicalNumber ||
            !RegExp(r'^-?(0|[1-9][0-9]*)$').hasMatch(offset.digits)) {
          throw const FormatException('Expected i32 offset');
        }
        final n = BigInt.parse(offset.digits);
        if (n < BigInt.from(-2147483648) || n > BigInt.from(2147483647)) {
          throw const FormatException('Offset outside i32');
        }
        return GregorianClock(n.toInt());
      case 'fictional':
        f.allow({'kind', 'tick_label', 'ticks_per_month'});
        return FictionalClock(
          f.string('tick_label'),
          f.values['ticks_per_month'] == null ||
                  f.values['ticks_per_month'] is CanonicalNull
              ? null
              : _u32(f, 'ticks_per_month'),
        );
      default:
        throw const FormatException('Unknown clock system');
    }
  }
}

final class GregorianClock extends ClockSystem {
  GregorianClock(this.offsetSeconds) {
    if (offsetSeconds < -2147483648 || offsetSeconds > 2147483647) {
      throw const FormatException('Offset outside i32');
    }
  }
  final int offsetSeconds;
  @override
  CanonicalObject toWire() => tagged('gregorian', [
    MapEntry('offset_seconds', CanonicalNumber(offsetSeconds.toString())),
  ]);
}

final class FictionalClock extends ClockSystem {
  FictionalClock(this.tickLabel, int? ticksPerMonth)
    : ticksPerMonth = ticksPerMonth == null ? null : _checkedU32(ticksPerMonth);
  final String tickLabel;
  final int? ticksPerMonth;
  @override
  CanonicalObject toWire() => tagged('fictional', [
    MapEntry('tick_label', CanonicalString(tickLabel)),
    MapEntry(
      'ticks_per_month',
      ticksPerMonth == null
          ? const CanonicalNull()
          : CanonicalNumber(ticksPerMonth!.toString()),
    ),
  ]);
}

/// Authored coordinates are distinct from editorial time. Decoding never reads
/// a system clock; explicit arithmetic is provided by [AuthoredChronology].
final class Chronology {
  const Chronology({
    required this.calendar,
    required this.system,
    required this.firstInteraction,
    required this.current,
  });
  final CalendarId calendar;
  final ClockSystem system;
  final String firstInteraction, current;
  factory Chronology.fromWire(CanonicalValue value) {
    final f = Fields(value)
      ..allow({'calendar', 'system', 'first_interaction', 'current'});
    return Chronology(
      calendar: CalendarId.parse(f.string('calendar')),
      system: ClockSystem.fromWire(f.require('system')),
      firstInteraction: f.string('first_interaction'),
      current: f.string('current'),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('calendar', CanonicalString(calendar.value)),
    MapEntry('system', system.toWire()),
    MapEntry('first_interaction', CanonicalString(firstInteraction)),
    MapEntry('current', CanonicalString(current)),
  ]);
}

final class RepresentedContextRecord extends RecordPayload {
  RepresentedContextRecord({
    required this.universe,
    required this.kind,
    this.parent,
    this.chronology,
    required Map<String, String> labels,
  }) : labels = Map.unmodifiable(labels);
  final UniverseId universe;
  final RepresentedContextKind kind;
  final RecordRef? parent;
  final Chronology? chronology;
  final Map<String, String> labels;
  factory RepresentedContextRecord.fromWire(CanonicalValue value) {
    final f = _recordFields(value, RecordKind.representedContext, {
      'universe',
      'kind',
      'parent',
      'chronology',
      'labels',
    });
    return RepresentedContextRecord(
      universe: UniverseId.parse(f.string('universe')),
      kind: RepresentedContextKind.fromWire(f.require('kind')),
      parent: _optionalRef(f, 'parent'),
      chronology: _optionalObject(f, 'chronology', Chronology.fromWire),
      labels: _strings(f, 'labels'),
    );
  }
  @override
  RecordKind get recordKind => RecordKind.representedContext;
  @override
  CanonicalObject toWire() => _recordWire(recordKind, [
    MapEntry('universe', CanonicalString(universe.value)),
    MapEntry('kind', kind.toWire()),
    if (parent != null) MapEntry('parent', parent!.toCanonical()),
    if (chronology != null) MapEntry('chronology', chronology!.toWire()),
    MapEntry('labels', _stringMap(labels)),
  ]);
}

/// Authored starting coordinates. Decoding never supplies a current timestamp
/// or builds a calendar; semantic validation belongs to chronology creation.
sealed class UniverseStart {
  const UniverseStart();
  CanonicalObject toWire();
  static UniverseStart fromWire(CanonicalValue value) {
    final f = Fields(value);
    switch (f.string('kind')) {
      case 'gregorian':
        f.allow({'kind', 'timestamp'});
        return GregorianUniverseStart(f.string('timestamp'));
      case 'fictional':
        f.allow({
          'kind',
          'calendar_name',
          'initial_tick',
          'tick_label',
          'ticks_per_month',
        });
        return FictionalUniverseStart(
          calendarName: f.string('calendar_name'),
          initialTick: f.string('initial_tick'),
          tickLabel: f.string('tick_label'),
          ticksPerMonth:
              f.values['ticks_per_month'] == null ||
                  f.values['ticks_per_month'] is CanonicalNull
              ? null
              : _u32(f, 'ticks_per_month'),
        );
      default:
        throw const FormatException('Unknown universe start');
    }
  }
}

final class GregorianUniverseStart extends UniverseStart {
  const GregorianUniverseStart(this.timestamp);
  final String timestamp;
  @override
  CanonicalObject toWire() =>
      tagged('gregorian', [MapEntry('timestamp', CanonicalString(timestamp))]);
}

final class FictionalUniverseStart extends UniverseStart {
  FictionalUniverseStart({
    required this.calendarName,
    required this.initialTick,
    required this.tickLabel,
    int? ticksPerMonth,
  }) : ticksPerMonth = ticksPerMonth == null
           ? null
           : _checkedU32(ticksPerMonth);
  final String calendarName, initialTick, tickLabel;
  final int? ticksPerMonth;
  @override
  CanonicalObject toWire() => tagged('fictional', [
    MapEntry('calendar_name', CanonicalString(calendarName)),
    MapEntry('initial_tick', CanonicalString(initialTick)),
    MapEntry('tick_label', CanonicalString(tickLabel)),
    MapEntry(
      'ticks_per_month',
      ticksPerMonth == null
          ? const CanonicalNull()
          : CanonicalNumber(ticksPerMonth!.toString()),
    ),
  ]);
}
