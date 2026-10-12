import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_rules/ub_rules.dart' show eventApplies;

CanonicalObject _object(Map<String, CanonicalValue> fields) =>
    CanonicalObject(fields.entries);
CanonicalValue _text(String? value) =>
    value == null ? const CanonicalNull() : CanonicalString(value);
CanonicalArray _strings(Iterable<String> values) =>
    CanonicalArray(values.map(CanonicalString.new));
CanonicalValue _bool(bool? value) =>
    value == null ? const CanonicalNull() : CanonicalBool(value);

String? _firstLabel(Map<String, String> labels) => labels.isEmpty
    ? null
    : wireString(
        CanonicalObject(
          labels.entries.map((e) => MapEntry(e.key, CanonicalString(e.value))),
        ).fields.first.value,
      );

String? writingFactLabel(RecordPayload payload) => switch (payload) {
  EntityRecord(:final labels, :final names) =>
    _firstLabel(labels) ?? (names.isEmpty ? null : names.first.text),
  EntityTypeRecord(:final name) => name,
  ActionDefinitionRecord(:final key) => key,
  PropertyRecord(:final key) => key,
  UnitRecord(:final key) => key,
  WorldRecord(:final selector) => selector,
  CalendarRecord(:final labels, :final key) => _firstLabel(labels) ?? key,
  _ => null,
};

/// Plain presentation retains numeric tokens exactly, including on web.
/// Unsupported values stay unavailable instead of becoming descriptive facts.
CanonicalValue? plainWritingValue(
  DomainValue value,
  String? Function(RecordId) label,
) {
  switch (value) {
    case TextValue(:final text):
      return CanonicalString(text);
    case BooleanValue(:final value):
      return CanonicalBool(value);
    case IntegerValue(:final digits) || DecimalValue(:final digits):
      try {
        final number = CanonicalValue.parseWireJson(digits);
        return number is CanonicalNumber ? number : null;
      } on FormatException {
        return null;
      }
    case ReferenceValue(kind: ValueReferenceKind.entity, :final record):
      final name = label(record.record);
      return name == null ? null : _object({'object': CanonicalString(name)});
    case QuantityValue(:final value, :final unit):
      final amount = plainWritingValue(value, label),
          name = label(unit.toRecordId());
      return amount is! CanonicalNumber || name == null
          ? null
          : _object({'amount': amount, 'unit': CanonicalString(name)});
    default:
      return null;
  }
}

String plainWritingTime(
  CanonicalValue value,
  String? Function(RecordId) label,
) {
  final fields = value is CanonicalObject
      ? Map.fromEntries(value.fields)
      : <String, CanonicalValue>{};
  String? text(String key) => fields[key] is CanonicalString
      ? (fields[key] as CanonicalString).value
      : null;
  var calendar = 'unresolved clock';
  final calendarId = text('calendar');
  if (calendarId != null) {
    calendar = label(CalendarId.parse(calendarId).toRecordId()) ?? calendar;
  }
  String bound(CanonicalValue? value) {
    final fields = value is CanonicalObject
        ? Map.fromEntries(value.fields)
        : <String, CanonicalValue>{};
    if (fields['value'] case CanonicalString(:final value)) return value;
    return fields['kind'] is CanonicalString &&
            (fields['kind'] as CanonicalString).value == 'unbounded'
        ? 'unbounded'
        : 'unknown';
  }

  return switch (text('kind')) {
    'timeless' => 'all story-time validities (author research)',
    'at' => plainWritingTime(fields['time'] ?? const CanonicalNull(), label),
    'exact' => '$calendar: ${text('value') ?? 'unknown'}',
    'calendar_interval' =>
      '$calendar: from ${bound(fields['start'])} inclusive to ${bound(fields['end'])} exclusive',
    'instant' => plainWritingTime(fields['at'] ?? const CanonicalNull(), label),
    'unspecified' => 'no temporal claim stated',
    _ => 'temporal applicability requires authored context; no plain exact-time presentation available',
  };
}

/// The caller admits permissions/perspective before resolving names or counts.
/// State reads must use the same pinned frame and the selected world scope.
CanonicalObject projectWritingFacts({
  required ReadFactsRequest request,
  required List<RecordVersion> records,
  required Frame frame,
  required bool restricted,
  required State Function(RecordId) readState,
}) {
  final byId = {for (final row in records) row.identity.recordId: row};
  String? label(RecordId id) =>
      byId[id] == null ? null : writingFactLabel(byId[id]!.payload);
  final clocks = <CanonicalValue>[];
  final context = byId[frame.context.record]?.payload;
  if (context is RepresentedContextRecord && context.chronology != null) {
    final clock = context.chronology!;
    clocks.add(
      _object({
        'calendar_id': CanonicalString(clock.calendar.value),
        'calendar_name': _text(label(clock.calendar.toRecordId())),
        'current': CanonicalString(clock.current),
        'first_interaction': CanonicalString(clock.firstInteraction),
        'units': clock.system.toWire(),
        'date_format': CanonicalString(
          clock.system is GregorianClock
              ? 'RFC3339 whole-second timestamp with an explicit offset'
              : 'Exact integer in this authored fictional clock',
        ),
      }),
    );
  }
  final objects = <CanonicalValue>[];
  for (final name in request.objectNames) {
    final matches = records
        .where(
          (row) => switch (row.payload) {
            EntityRecord(:final labels, :final names) =>
              labels.values.contains(name) ||
                  names.any(
                    (n) =>
                        n.text == name &&
                        eventApplies(n.validity, frame.time, records) != false,
                  ),
            EntityTypeRecord(name: final typeName, :final key, :final labels) =>
              typeName == name || key == name || labels.values.contains(name),
            _ => false,
          },
        )
        .toList();
    if (matches.length != 1) {
      objects.add(
        _object({
          'name': CanonicalString(name),
          'identity': CanonicalString(
            matches.isEmpty ? 'not_found' : 'ambiguous',
          ),
          'matches': CanonicalNumber(matches.length.toString()),
          'coverage': CanonicalString(restricted ? 'restricted' : 'complete'),
          'facts': CanonicalArray([]),
          'unknowns': _strings([
            'No unique visible identity established; this does not introduce an object.',
          ]),
        }),
      );
      continue;
    }
    final matched = matches.single;
    final state = readState(matched.identity.recordId);
    if (state.objects.isEmpty) {
      throw const NotFoundOrNotAccessibleError(message: 'resource');
    }
    final object = state.objects.first;
    final dependencies = {
      for (final row in object.dependencies) row.identity.recordId: row.payload,
    };
    final facts = <CanonicalValue>[],
        initial = <CanonicalValue>[],
        inherited = <CanonicalValue>[];
    for (final (group, rows) in [
      ('instance', object.instanceFacts),
      ('shared', object.sharedAttributes),
      ('initial_candidate', object.initialValueCandidates),
    ]) {
      for (final row in rows) {
        final assertion = row.record.payload;
        if (assertion is! AssertionRecord) continue;
        final proposition = dependencies[assertion.proposition.record];
        if (proposition is! PropositionRecord) continue;
        final property = dependencies[proposition.predicate.record];
        if (property is! PropertyRecord) continue;
        final value = proposition.value == null
            ? null
            : plainWritingValue(proposition.value!, label);
        final conflicts = object.conflicts
            .where(
              (c) =>
                  c.initialValues == (group == 'initial_candidate') &&
                  c.assertions.contains(row.record.recordVersionId),
            )
            .toList();
        final outcome =
            row.applicability != true ||
                row.unknowns.isNotEmpty ||
                value == null
            ? 'unknown'
            : conflicts.any((c) => c.applicability == true)
            ? 'conflicting'
            : conflicts.isNotEmpty
            ? 'unknown'
            : assertion.polarity == Polarity.support
            ? 'supported'
            : 'refuted';
        final scope = switch (assertion.scope.applicability) {
          UniverseApplicability() => 'universe',
          UnspecifiedApplicability() => 'unspecified',
          ConditionalApplicability() => 'conditional, unresolved',
          WorldsApplicability(:final worldIds) =>
            worldIds
                .map(
                  (id) =>
                      label(
                        RecordId.parse(id.value.replaceFirst('wld_', 'rec_')),
                      ) ??
                      'unknown world',
                )
                .join(', '),
        };
        final item = _object({
          'fact_handle': _text(
            assertion.establishedBy == null
                ? row.record.recordVersionId.value
                : null,
          ),
          'property': CanonicalString(property.key),
          'value': value ?? const CanonicalNull(),
          'state': CanonicalString(outcome),
          'group': CanonicalString(group),
          'scope': CanonicalString(scope),
          'time': CanonicalString(
            plainWritingTime(assertion.validity.toWire(), label),
          ),
          'unknowns': _strings(row.unknowns),
          'value_type': Map.fromEntries(
            property.value.toWire().fields,
          )['kind']!,
          'unit': _text(
            proposition.value is QuantityValue
                ? label((proposition.value as QuantityValue).unit.toRecordId())
                : null,
          ),
          'unsupported_plain_value': CanonicalBool(value == null),
          'multiple_values_allowed': CanonicalBool(
            property.multiplicity == Multiplicity.multiple,
          ),
          'exclusive': CanonicalBool(property.exclusive),
        });
        (group == 'initial_candidate'
                ? initial
                : group == 'shared'
                ? inherited
                : facts)
            .add(item);
      }
    }
    for (final derived in state.derived.where(
      (d) => d.subject.record == matched.identity.recordId,
    )) {
      final property = byId[derived.predicate.record]?.payload;
      if (property is! PropertyRecord) continue;
      final value = plainWritingValue(derived.value, label);
      facts.add(
        _object({
          'property': CanonicalString(property.key),
          'state': CanonicalString(value == null ? 'unknown' : 'supported'),
          'value': value ?? const CanonicalNull(),
          'value_type': Map.fromEntries(
            property.value.toWire().fields,
          )['kind']!,
          'unit': _text(
            derived.value is QuantityValue
                ? label((derived.value as QuantityValue).unit.toRecordId())
                : null,
          ),
          'unsupported_plain_value': CanonicalBool(value == null),
          'group': CanonicalString('derived'),
          'scope': CanonicalString('pinned research context'),
          'time': CanonicalString(plainWritingTime(frame.time.toWire(), label)),
          'unknowns': _strings(
            value == null ? ['plain value presentation unavailable'] : [],
          ),
        }),
      );
    }
    final events = <CanonicalValue>[];
    for (final row in records) {
      final event = row.payload;
      if (event is! EventRecord ||
          event.occurrence is! SimpleOccurrence ||
          (event.occurrence as SimpleOccurrence).kind !=
              OccurrenceKind.occurred ||
          !event.participants.any(
            (p) => p.record.record == matched.identity.recordId,
          )) {
        continue;
      }
      final action = event.action == null
          ? null
          : byId[event.action!.record]?.payload;
      if (frame.perspective is AuthorPerspective &&
          !(action is ActionDefinitionRecord &&
              action.scope.context == frame.context) &&
          !(event.action == null &&
              event.effects.isNotEmpty &&
              event.effects.every(
                (effect) => effect.scope.context == frame.context,
              ))) {
        continue;
      }
      final knowledge = <CanonicalValue>[];
      for (final condition in event.preconditions) {
        if (condition is! AttitudeExpr ||
            condition.attitude != EpistemicAttitudeKind.knows) {
          continue;
        }
        final p = byId[condition.proposition.record]?.payload;
        if (p is! PropositionRecord) continue;
        knowledge.add(
          _object({
            'holder': _text(label(condition.holder.record)),
            'claim': _object({
              'subject': _text(label(p.subject.record)),
              'property': _text(label(p.predicate.record)),
              'value': p.value == null
                  ? const CanonicalNull()
                  : plainWritingValue(p.value!, label) ?? const CanonicalNull(),
            }),
          }),
        );
      }
      events.add(
        _object({
          'handle': CanonicalString(row.identity.recordId.value),
          'event_edit_handle': _text(
            frame.perspective is AuthorPerspective
                ? row.recordVersionId.value
                : null,
          ),
          'time': CanonicalString(
            plainWritingTime(event.time.encode(canonical: false), label),
          ),
          'action': _text(
            event.action == null ? null : label(event.action!.record),
          ),
          'participants': CanonicalArray(
            event.participants.map(
              (p) => _object({
                'role': CanonicalString(p.role),
                'object': _text(label(p.record.record)),
              }),
            ),
          ),
          'requires_knowledge': CanonicalArray(knowledge),
          'worlds': _strings(
            event.worlds
                .map(
                  (w) => label(
                    RecordId.parse(w.value.replaceFirst('wld_', 'rec_')),
                  ),
                )
                .whereType<String>(),
          ),
        }),
      );
    }
    final names = <CanonicalValue>[];
    if (matched.payload is EntityRecord &&
        frame.perspective is AuthorPerspective) {
      for (final n in (matched.payload as EntityRecord).names) {
        final applies = eventApplies(n.validity, frame.time, records);
        if (applies == false) continue;
        names.add(
          _object({
            'text': CanonicalString(n.text),
            'language': _text(n.language),
            'community': _text(n.community),
            'role': _text(n.role),
            'time': CanonicalString(
              plainWritingTime(n.validity.toWire(), label),
            ),
            'time_applicable': _bool(applies),
          }),
        );
      }
    }
    objects.add(
      _object({
        'name': CanonicalString(name),
        'identity': CanonicalString('resolved'),
        'kind': CanonicalString(
          matched.payload is EntityTypeRecord ? 'definition' : 'instance',
        ),
        'classification': _text(
          object.ancestry.isEmpty
              ? null
              : label(object.ancestry.first.identity.recordId),
        ),
        'ancestry': _strings(
          object.ancestry
              .map((r) => label(r.identity.recordId))
              .whereType<String>(),
        ),
        'ancestry_complete': CanonicalBool(object.ancestryComplete),
        'names': CanonicalArray(names),
        'facts': CanonicalArray(facts),
        'occurred_events': CanonicalArray(events),
        'inherited_attributes': CanonicalArray(inherited),
        'initial_value_candidates': CanonicalArray(initial),
        'coverage': CanonicalString(object.coverage.wireName),
        'unknowns': _strings(object.unknowns),
        'state_coverage': CanonicalString(state.coverage.wireName),
        'limitations': _strings(state.unsupportedCapabilities),
      }),
    );
  }
  return _object({
    'objects': CanonicalArray(objects),
    'clocks': CanonicalArray(clocks),
    'research_time': CanonicalString(
      plainWritingTime(frame.time.toWire(), label),
    ),
    'coverage': CanonicalString(restricted ? 'restricted' : 'bounded'),
    'limitation': CanonicalString(
      'Plain projection of existing effective evidence; absence is unknown, initial candidates are not current facts, and bounded evidence is not universal prose completeness.',
    ),
  });
}
