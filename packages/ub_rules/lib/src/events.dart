import 'dart:collection';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:ub_domain/ub_domain.dart';

import 'definitions.dart';
import 'time.dart';

const eventExpansionVersion = 'events-v1';
final _min = -(BigInt.one << 127), _max = (BigInt.one << 127) - BigInt.one;
final _digits = RegExp(r'^[+-]?[0-9]+$');
// Rust Unicode White_Space excludes U+FEFF; Dart trim additionally removes it.
bool _blankSlot(String slot) => slot.runes.every(
  (c) =>
      c >= 9 && c <= 13 ||
      c == 0x20 ||
      c == 0x85 ||
      c == 0xa0 ||
      c == 0x1680 ||
      c >= 0x2000 && c <= 0x200a ||
      c == 0x2028 ||
      c == 0x2029 ||
      c == 0x202f ||
      c == 0x205f ||
      c == 0x3000,
);
BigInt? _coordinate(String value) {
  if (_digits.stringMatch(value) != value) return null;
  final n = BigInt.tryParse(value, radix: 10);
  return n == null || n < _min || n > _max ? null : n;
}

final class EventEvaluationError implements Exception {
  const EventEvaluationError(this.message);
  final String message;
  @override
  String toString() => message;
}

({CalendarId calendar, BigInt coordinate}) exactEventTime(
  TemporalExpression time,
) {
  if (time is! ExactTime) {
    throw const EventEvaluationError(
      'Event effects require an exact named-calendar time',
    );
  }
  final n = _coordinate(time.value);
  if (n == null) {
    throw const EventEvaluationError(
      'Event time needs an exact integer coordinate',
    );
  }
  if (n == _min || n == _max) {
    throw const EventEvaluationError(
      'Event coordinate outside supported bounds',
    );
  }
  return (calendar: time.calendar, coordinate: n);
}

RecordId eventEffectId(RecordId event, String slot) => RecordId.parse(
  'rec_${sha256.convert(utf8.encode('$eventExpansionVersion:${event.value}:$slot')).toString().substring(0, 24)}',
);

bool? eventApplies(
  Validity validity,
  FrameTime time,
  List<RecordVersion> records,
) {
  if (time is! AtEventFrameTime) return temporalApplies(validity, time);
  RecordVersion? found;
  for (final r in records) {
    if (r.identity.recordId == time.event.record &&
        time.event.universe == r.identity.universeId) {
      found = r;
      break;
    }
  }
  return _atEvent(validity, time, found);
}

bool? eventAppliesIndexed(
  Validity validity,
  FrameTime time,
  RecordIndex index,
) {
  if (time is! AtEventFrameTime) return temporalApplies(validity, time);
  final found = index.get(time.event.record);
  return _atEvent(
    validity,
    time,
    found?.identity.universeId == time.event.universe ? found : null,
  );
}

bool? _atEvent(
  Validity validity,
  AtEventFrameTime time,
  RecordVersion? record,
) {
  final e = record?.payload;
  if (e is! EventRecord ||
      e.occurrence is! SimpleOccurrence ||
      (e.occurrence as SimpleOccurrence).kind != OccurrenceKind.occurred) {
    return null;
  }
  late final ({CalendarId calendar, BigInt coordinate}) exact;
  try {
    exact = exactEventTime(e.time);
  } on EventEvaluationError {
    return null;
  }
  if (time.side == EventTimeSide.after) {
    return temporalApplies(validity, AtFrameTime(e.time));
  }
  if (validity is CalendarIntervalValidity &&
      validity.calendar == exact.calendar) {
    bool? start(TemporalBound b) => switch (b) {
      UnboundedBound() => true,
      ExactBound(:final value) =>
        _coordinate(value) == null
            ? null
            : _coordinate(value)! < exact.coordinate,
      _ => null,
    };
    bool? end(TemporalBound b) => switch (b) {
      UnboundedBound() => true,
      ExactBound(:final value) =>
        _coordinate(value) == null
            ? null
            : exact.coordinate <= _coordinate(value)!,
      _ => null,
    };
    final a = start(validity.start), b = end(validity.end);
    return a == null || b == null ? null : a && b;
  }
  if (validity is InstantValidity) {
    try {
      return exactEventTime(validity.at).calendar == exact.calendar
          ? false
          : null;
    } on EventEvaluationError {
      return null;
    }
  }
  return null;
}

/// Recompiles occurred effects only; authored non-event evidence stays intact.
Map<RecordId, AssertionRecord> expandEvents(List<RecordVersion> records) {
  final map = {for (final r in records) r.identity.recordId: r};
  final events =
      <
        ({
          CalendarId calendar,
          BigInt time,
          RecordVersion record,
          EventRecord event,
        })
      >[];
  var preconditions = 0, effects = 0, remaining = 1000000;
  for (final r in records) {
    final e = r.payload;
    if (e is! EventRecord) continue;
    preconditions += e.preconditions.length;
    effects += e.effects.length;
    if (preconditions > 1000 ||
        effects > 10000 ||
        e.effects.length > 100 ||
        e.preconditions.length > 100) {
      throw const EventEvaluationError('Event work budget exceeded');
    }
    if (e.occurrence is! SimpleOccurrence ||
        (e.occurrence as SimpleOccurrence).kind != OccurrenceKind.occurred) {
      continue;
    }
    final exact = exactEventTime(e.time);
    if (e.expansionVersion != eventExpansionVersion) {
      throw const EventEvaluationError(
        'Event expansion version is missing or unsupported',
      );
    }
    events.add((
      calendar: exact.calendar,
      time: exact.coordinate,
      record: r,
      event: e,
    ));
  }
  if (events.length > 1000) {
    throw const EventEvaluationError('Event work budget exceeded');
  }
  events.sort((a, b) {
    final c = a.calendar.value.compareTo(b.calendar.value);
    if (c != 0) return c;
    final t = a.time.compareTo(b.time);
    return t == 0
        ? a.record.identity.recordId.value.compareTo(
            b.record.identity.recordId.value,
          )
        : t;
  });
  final out = SplayTreeMap<RecordId, AssertionRecord>(
    (a, b) => a.value.compareTo(b.value),
  );
  final groups = <String, List<(BigInt, RecordId, RecordId, Polarity)>>{};
  for (final item in events) {
    final slots = <String>{}, orders = <BigInt>{};
    final ordered = item.event.effects.toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    for (final effect in ordered) {
      if (_blankSlot(effect.slot) ||
          utf8.encode(effect.slot).length > 120 ||
          !slots.add(effect.slot) ||
          !orders.add(effect.order)) {
        throw const EventEvaluationError(
          'Event slots and effect orders must be explicit and unique',
        );
      }
      final p = map[effect.proposition.record]?.payload;
      if (p == null) {
        throw const EventEvaluationError('Event proposition unavailable');
      }
      if (p is! PropositionRecord) {
        throw const EventEvaluationError(
          'Event effect target must be a proposition',
        );
      }
      if (effect.scope.context != p.context) {
        throw const EventEvaluationError(
          'Event effect context differs from proposition',
        );
      }
      if (effect.scope.applicability is! UniverseApplicability &&
          effect.scope.applicability is! WorldsApplicability) {
        throw const EventEvaluationError('Event effect scope must be explicit');
      }
      final validity = effect.validity;
      if (validity is! CalendarIntervalValidity ||
          validity.start is! ExactBound) {
        throw const EventEvaluationError(
          'Effects require a half-open named-calendar interval',
        );
      }
      if (validity.calendar != item.calendar ||
          _coordinate((validity.start as ExactBound).value) != item.time) {
        throw const EventEvaluationError(
          "Effect must start at its event's exact time and calendar",
        );
      }
      final end = validity.end;
      final endTime = end is ExactBound ? _coordinate(end.value) : null;
      if (end is! UnboundedBound && (endTime == null || endTime <= item.time)) {
        throw const EventEvaluationError(
          'Effect end must be exact and later, or explicitly unbounded',
        );
      }
      final definition = map[p.predicate.record]?.payload;
      final single =
          definition is PropertyRecord &&
          definition.multiplicity == Multiplicity.single;
      final key = CanonicalArray([
        CanonicalString(item.calendar.value),
        p.subject.toCanonical(),
        p.predicate.toCanonical(),
        effect.scope.toWire(),
      ]).toText();
      final id = eventEffectId(item.record.identity.recordId, effect.slot);
      final previous = groups.putIfAbsent(key, () => []);
      for (final (oldTime, oldId, oldProp, polarity) in previous) {
        if (remaining == 0) {
          throw const EventEvaluationError(
            'Event expansion work budget exhausted',
          );
        }
        remaining--;
        if (map[oldProp]?.payload == p ||
            single &&
                polarity == Polarity.support &&
                effect.polarity == Polarity.support) {
          final old = out[oldId];
          if (oldTime == item.time &&
              old?.establishedBy?.event.record !=
                  item.record.identity.recordId) {
            throw const EventEvaluationError(
              'Noncommuting effects at the same time need distinct authored times; no record-ID ordering is inferred',
            );
          }
          if (old != null && old.validity is CalendarIntervalValidity) {
            final v = old.validity as CalendarIntervalValidity;
            final end = v.end;
            final endTime = end is ExactBound ? _coordinate(end.value) : null;
            if (end is UnboundedBound ||
                endTime != null && endTime > item.time) {
              out[oldId] = AssertionRecord(
                attributeMode: old.attributeMode,
                proposition: old.proposition,
                polarity: old.polarity,
                scope: old.scope,
                validity: CalendarIntervalValidity(
                  v.calendar,
                  v.start,
                  ExactBound('${item.time}'),
                ),
                persistence: old.persistence,
                precision: old.precision,
                alternatives: old.alternatives,
                basis: old.basis,
                establishedBy: old.establishedBy,
              );
            }
          }
        }
      }
      previous.add((item.time, id, effect.proposition.record, effect.polarity));
      out[id] = AssertionRecord(
        attributeMode: AttributeMode.instance,
        proposition: effect.proposition,
        polarity: effect.polarity,
        scope: effect.scope,
        validity: effect.validity,
        persistence: PersistenceSemantics.explicitInterval,
        precision: Precision.exact,
        basis: AuthorDecisionBasis(
          'Compiled event ${item.record.identity.recordId.value} slot ${effect.slot}',
        ),
        establishedBy: EventEffectRef(
          RecordRef(
            universe: item.record.identity.universeId,
            record: item.record.identity.recordId,
          ),
          effect.slot,
        ),
      );
    }
  }
  return Map.unmodifiable(out);
}

void verifyEventEffects(List<RecordVersion> records) {
  final expected = Map<RecordId, AssertionRecord>.of(expandEvents(records));
  for (final r in records) {
    if (r.payload case final AssertionRecord a when a.establishedBy != null) {
      if (expected.remove(r.identity.recordId) != a) {
        throw const EventEvaluationError(
          'Generated effect assertion does not match its event',
        );
      }
    }
  }
  if (expected.isNotEmpty) {
    throw const EventEvaluationError(
      'Event is missing a compiled effect assertion',
    );
  }
}
