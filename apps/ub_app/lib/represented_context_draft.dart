import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

ExpressionReferenceInput _input(RecordRef? ref) => ExpressionReferenceInput(
  record: ref?.record.value ?? '',
  universe: ref?.universe?.value ?? '',
);
RecordRef _reference(ExpressionReferenceInput input) => RecordRef(
  record: RecordId.parse(input.record),
  universe: input.universe.isEmpty ? null : UniverseId.parse(input.universe),
);
ChronologyInput chronologyInput(Chronology? clock) {
  if (clock == null) return const ChronologyInput();
  return ChronologyInput(
    enabled: true,
    calendar: clock.calendar.value,
    system: clock.system is GregorianClock ? 'gregorian' : 'fictional',
    offsetSeconds: clock.system is GregorianClock
        ? (clock.system as GregorianClock).offsetSeconds.toString()
        : '',
    tickLabel: clock.system is FictionalClock
        ? (clock.system as FictionalClock).tickLabel
        : '',
    ticksPerMonthEnabled:
        clock.system is FictionalClock &&
        (clock.system as FictionalClock).ticksPerMonth != null,
    ticksPerMonth: clock.system is FictionalClock
        ? (clock.system as FictionalClock).ticksPerMonth?.toString() ?? ''
        : '',
    firstInteraction: clock.system is GregorianClock
        ? clock.display(clock.firstInteraction)
        : clock.firstInteraction,
    current: clock.system is GregorianClock
        ? clock.display(clock.current)
        : clock.current,
  );
}

Chronology? buildChronology(ChronologyInput input, Chronology? original) {
  if (!input.enabled) return null;
  final template = Chronology(
    calendar: CalendarId.parse(input.calendar),
    system: switch (input.system) {
      'gregorian' => GregorianClock(int.parse(input.offsetSeconds)),
      'fictional' => FictionalClock(
        input.tickLabel,
        input.ticksPerMonthEnabled ? int.parse(input.ticksPerMonth) : null,
      ),
      _ => throw const FormatException('Choose an authored clock system.'),
    },
    firstInteraction: '0',
    current: '0',
  );
  final before = chronologyInput(original);
  String coordinate(String value, String previous, String? retained) {
    if (input.system != 'gregorian') return value;
    // Historical sub-minute offsets round for display. Unchanged fields must
    // retain the original exact coordinate, not parse the rounded display.
    if (original?.system is GregorianClock && value == previous) {
      return retained!;
    }
    return template.coordinate(value);
  }

  final clock = Chronology(
    calendar: template.calendar,
    system: template.system,
    firstInteraction: coordinate(
      input.firstInteraction,
      before.firstInteraction,
      original?.firstInteraction,
    ),
    current: coordinate(input.current, before.current, original?.current),
  );
  clock.validate();
  return clock;
}

RecordNarrativeReferenceOperation representedContextOperation(
  UnfinishedRepresentedContextForm form,
) {
  final labels = <String, String>{};
  for (final label in form.labels) {
    if (labels.containsKey(label.language)) {
      throw const FormatException(
        'Give each context label a distinct language key.',
      );
    }
    labels[label.language] = label.text;
  }
  return RecordNarrativeReferenceOperation(
    clientRef: form.clientRef,
    record: RecordKind.representedContext,
    payload: RepresentedContextRecord(
      universe: form.universe,
      kind: switch (form.kind) {
        'objective' => const ObjectiveContext(),
        'character' => CharacterContext(_reference(form.reference)),
        'source' => SourceContext(_reference(form.reference)),
        'narrator' => NarratorContext(_reference(form.reference)),
        'authored' => AuthoredContext(form.authoredLabel),
        _ => throw const FormatException('Choose a represented context kind.'),
      },
      parent: form.parentEnabled ? _reference(form.parent) : null,
      chronology: buildChronology(form.chronology, form.original?.chronology),
      labels: labels,
    ),
  );
}

UnfinishedRepresentedContextForm representedContextFormFromDraft(
  SavedDraft draft,
  int index,
) {
  final operation = draft.content.operations[index];
  if (operation is! RecordNarrativeReferenceOperation ||
      operation.record != RecordKind.representedContext ||
      operation.payload is! RepresentedContextRecord) {
    throw const FormatException('Choose a represented context from Changes.');
  }
  final record = operation.payload as RepresentedContextRecord;
  return UnfinishedRepresentedContextForm(
    baseRevision: draft.content.baseRevision,
    representedContext: draft.content.representedContext,
    universe: record.universe,
    clientRef: operation.clientRef,
    kind: switch (record.kind) {
      ObjectiveContext() => 'objective',
      CharacterContext() => 'character',
      SourceContext() => 'source',
      NarratorContext() => 'narrator',
      AuthoredContext() => 'authored',
    },
    authoredLabel: record.kind is AuthoredContext
        ? (record.kind as AuthoredContext).label
        : '',
    reference: _input(switch (record.kind) {
      CharacterContext(:final holder) => holder,
      SourceContext(:final source) => source,
      NarratorContext(:final narrator) => narrator,
      _ => null,
    }),
    parentEnabled: record.parent != null,
    parent: _input(record.parent),
    chronology: chronologyInput(record.chronology),
    labels: record.labels.entries.map(
      (e) => PropertyLabelInput(language: e.key, text: e.value),
    ),
    original: record,
    draftVersion: draft.version,
  );
}

SaveDraftEngineRequest representedContextDraftRequest({
  required SavedDraft draft,
  required UnfinishedRepresentedContextForm form,
  required Selector universe,
  required ContinuityId continuity,
  int? index,
}) {
  if (draft.content.proposal != null ||
      draft.content.baseRevision != form.baseRevision ||
      draft.content.representedContext != form.representedContext) {
    throw const FormatException(
      'Review Changes before adding this represented context declaration.',
    );
  }
  final operation = representedContextOperation(form);
  final operations = [...draft.content.operations];
  if (index != null) {
    final before = representedContextFormFromDraft(draft, index);
    if (form.draftVersion != draft.version ||
        form.clientRef != before.clientRef) {
      throw const FormatException(
        'The draft changed. Reopen its current represented context fields.',
      );
    }
    operations[index] = operation;
  } else {
    for (final existing in operations) {
      final ref = Map.fromEntries(existing.toWire().fields)['client_ref'];
      if (ref is CanonicalString && ref.value == form.clientRef) {
        if (existing.toWire().toText() != operation.toWire().toText()) {
          throw const FormatException(
            'This represented context declaration is already in Changes. Edit it there.',
          );
        }
        return SaveDraftEngineRequest(
          universe: universe,
          continuityId: continuity,
          expectedVersion: draft.version,
          content: draft.content,
        );
      }
    }
    operations.add(operation);
  }
  return SaveDraftEngineRequest(
    universe: universe,
    continuityId: continuity,
    expectedVersion: draft.version,
    content: DraftContent(
      baseRevision: draft.content.baseRevision,
      representedContext: draft.content.representedContext,
      operations: operations,
      rationale: index == null
          ? [
              if (draft.content.rationale.isNotEmpty) draft.content.rationale,
              if (form.rationale.isNotEmpty) form.rationale,
            ].join('\n\n')
          : draft.content.rationale,
    ),
  );
}
