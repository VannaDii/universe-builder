import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_rules/ub_rules.dart';

import 'writing_units.dart';
import 'context_binding.dart';

Applicability bindWritingApplicability(
  List<RecordVersion> rows,
  String text, {
  Set<WorldId>? worldScope,
}) => switch (text) {
  'universe' => const UniverseApplicability(),
  'unspecified' => const UnspecifiedApplicability(),
  _ => WorldsApplicability([
    resolveWorldFocus(
      world: Selector(text),
      guard: null,
      records: rows,
      scope: worldScope,
    )!,
  ]),
};

(RecordVersion, PropertyRecord) resolveWritingProperty(
  List<RecordVersion> rows,
  String name,
) {
  final found = <(RecordVersion, PropertyRecord)>[
    for (final row in rows)
      if (row.payload case final PropertyRecord property)
        if (property.key == name || property.labels.values.contains(name))
          (row, property),
  ];
  if (found.length != 1) {
    throw FormatException("Which exact authored property is '$name'?");
  }
  return found.single;
}

/// Every binding operates on rows already admitted to the pinned writer view.
RecordId? resolveWritingObject(
  List<RecordVersion> rows,
  String name,
  Frame frame,
) {
  final matches = <RecordId>{};
  for (final row in rows) {
    if (row.payload case EntityRecord(:final labels, :final names)) {
      if (labels.values.contains(name) ||
          names.any(
            (entry) =>
                entry.text == name &&
                eventApplies(entry.validity, frame.time, rows) != false,
          )) {
        matches.add(row.identity.recordId);
      }
    }
  }
  return matches.length == 1 ? matches.single : null;
}

DomainValue bindWritingValue(
  UniverseId universe,
  List<RecordVersion> rows,
  Frame frame,
  FactValue input,
) => switch (input) {
  FactTextValue(:final value) => TextValue(value),
  FactBooleanValue(:final value) => BooleanValue(value),
  FactNumberValue(:final value) =>
    value.digits.contains(RegExp('[.eE]'))
        ? DecimalValue(value.digits)
        : IntegerValue(value.digits),
  FactQuantityValue(:final amount, :final unit) => QuantityValue(
    bindWritingValue(universe, rows, frame, FactNumberValue(amount)),
    resolveWritingUnit(rows, unit),
  ),
  FactObjectValue(:final object) => ReferenceValue(
    ValueReferenceKind.entity,
    RecordRef(
      universe: universe,
      record:
          resolveWritingObject(rows, object, frame) ??
          (throw FormatException("Which exact object is '$object'?")),
    ),
  ),
};

/// Actual value shape, units and reference validity remain compiler checks.
PropositionRecord bindWritingClaim(
  UniverseId universe,
  List<RecordVersion> rows,
  Frame frame,
  WritingClaim input,
) {
  final subject =
      resolveWritingObject(rows, input.subject, frame) ??
      (throw FormatException(
        "Which exact object is '${input.subject}' in this claim?",
      ));
  final properties = <RecordVersion>[];
  for (final row in rows) {
    if (row.payload case PropertyRecord(:final key, :final labels)) {
      if (key == input.property || labels.values.contains(input.property)) {
        properties.add(row);
      }
    }
  }
  if (properties.length != 1) {
    throw FormatException(
      "Which authored property is '${input.property}' in this claim?",
    );
  }
  return PropositionRecord(
    subject: RecordRef(universe: universe, record: subject),
    predicate: RecordRef(
      universe: universe,
      record: properties.single.identity.recordId,
    ),
    value: bindWritingValue(universe, rows, frame, input.value),
    context: frame.context,
    quantification: Quantification.particular,
  );
}

TemporalExpression bindWritingTime(
  Frame frame,
  List<RecordVersion> rows,
  String? tick,
) {
  if (frame.time case AtFrameTime(
    time: ExactTime(:final calendar, :final value),
  )) {
    return ExactTime(calendar, tick ?? value);
  }
  if (frame.time is TimelessFrameTime && tick != null) {
    for (final row in rows) {
      if (row.identity.recordId != frame.context.record) continue;
      try {
        frame.context.resolveNamespace(frame.universe);
      } on FormatException {
        break;
      }
      if (row.payload case RepresentedContextRecord(:final chronology)) {
        if (chronology != null) return ExactTime(chronology.calendar, tick);
      }
      break;
    }
  }
  throw const FormatException(
    'What exact authored calendar/story time applies to this action or communication?',
  );
}

Validity bindWritingLifetime(TemporalExpression time, FactLifetime lifetime) {
  if (lifetime is FactUnspecifiedLifetime) return InstantValidity(time);
  if (time case ExactTime(:final calendar, :final value)) {
    return CalendarIntervalValidity(
      calendar,
      ExactBound(value),
      lifetime is FactUntilLifetime
          ? ExactBound(lifetime.endTick)
          : const UnboundedBound(),
    );
  }
  throw const FormatException(
    'What exact authored contract time/lifetime applies?',
  );
}

(RecordVersion, AssertionRecord) bindWritingAuthoredFact(
  List<RecordVersion> rows,
  String handle,
) {
  for (final row in rows) {
    if (row.recordVersionId.value != handle) continue;
    if (row.payload case final AssertionRecord assertion) {
      if (assertion.establishedBy != null) {
        throw const FormatException(
          'Generated event facts cannot be corrected directly; correct the authored cause',
        );
      }
      return (row, assertion);
    }
    throw const FormatException(
      'Correction handle is not an authored assertion',
    );
  }
  throw const FormatException(
    'Retrieve the current pinned authored fact handle before editing it',
  );
}

RecordRef bindWritingProposition(
  List<DomainOperation> operations,
  UniverseId universe,
  PropositionRecord proposition,
  List<RecordVersion> rows,
) {
  for (final row in rows) {
    if (row.payload is PropositionRecord && row.payload == proposition) {
      return RecordRef(universe: universe, record: row.identity.recordId);
    }
  }
  final id = RecordId.generate();
  operations.add(
    DefinePropositionOperation(clientRef: id.value, record: proposition),
  );
  return RecordRef(universe: universe, record: id);
}
