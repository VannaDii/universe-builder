import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'scope_draft.dart';

RecordRef _ref(ExpressionReferenceInput input) => RecordRef(
  record: RecordId.parse(input.record),
  universe: input.universe.isEmpty ? null : UniverseId.parse(input.universe),
);
ExpressionReferenceInput _input(RecordRef ref) => ExpressionReferenceInput(
  record: ref.record.value,
  universe: ref.universe?.value ?? '',
);
bool _local(RecordRef ref, UniverseId universe, RecordId record) =>
    ref.record == record && (ref.universe == null || ref.universe == universe);

InitializeInstanceOperation initializationOperation(
  UnfinishedInitializationForm form, {
  required UniverseId universe,
  required RecordVersion start,
  required RecordVersion definition,
  Chronology? clock,
}) {
  final instanceRef = _ref(form.instance), startRef = _ref(form.start);
  if (instanceRef.universe != null && instanceRef.universe != universe ||
      !_local(startRef, universe, start.identity.recordId) ||
      start.identity.universeId != universe) {
    throw const FormatException(
      'Choose an instance and start in this universe.',
    );
  }
  final event = start.payload;
  if (event is! EventRecord ||
      event.occurrence is! SimpleOccurrence ||
      (event.occurrence as SimpleOccurrence).kind != OccurrenceKind.occurred ||
      event.time is! ExactTime ||
      !event.participants.any(
        (p) => _local(p.record, universe, instanceRef.record),
      )) {
    throw const FormatException(
      'Choose an exact occurred start containing this instance.',
    );
  }
  final source = form.definition;
  if (source == null ||
      source.record != definition.identity.recordId ||
      source.version != definition.recordVersionId ||
      source.universe != null && source.universe != universe ||
      definition.identity.universeId != universe ||
      definition.payload is! AssertionRecord ||
      (definition.payload as AssertionRecord).attributeMode !=
          AttributeMode.initialValue) {
    throw const FormatException(
      'Choose the retained version of an initial-value assertion.',
    );
  }
  if (!{'universe_wide', 'worlds'}.contains(form.scope.applicability) ||
      form.scope.applicability == 'worlds' && form.scope.worlds.isEmpty ||
      form.scope.contextRecord != form.representedContext.value ||
      form.scope.contextUniverse.isNotEmpty &&
          form.scope.contextUniverse != universe.value) {
    throw const FormatException(
      'Choose an explicit scope in this represented context.',
    );
  }
  final time = event.time as ExactTime;
  final TemporalBound end;
  if (form.endKind == 'unbounded') {
    end = const UnboundedBound();
  } else if (form.endKind == 'exact') {
    final coordinate = clock?.calendar == time.calendar
        ? clock!.coordinate(form.endCoordinate)
        : form.endCoordinate;
    final value = BigInt.tryParse(coordinate);
    if (!RegExp(r'^[+-]?[0-9]+$').hasMatch(coordinate) ||
        value == null ||
        value < -(BigInt.one << 127) ||
        value >= (BigInt.one << 127) ||
        value <= BigInt.parse(time.value)) {
      throw const FormatException(
        'Enter an exact exclusive end after the occurred start.',
      );
    }
    end = ExactBound(value.toString());
  } else {
    throw const FormatException(
      'Choose an exclusive end or explicitly unbounded validity.',
    );
  }
  return InitializeInstanceOperation(
    clientRef: form.clientRef,
    instance: instanceRef,
    start: startRef,
    definition: source,
    scope: buildScope(form.scope),
    validity: CalendarIntervalValidity(
      time.calendar,
      ExactBound(time.value),
      end,
    ),
  );
}

UnfinishedInitializationForm initializationFormFromDraft(
  SavedDraft draft,
  int index,
) {
  final operation = draft.content.operations[index];
  if (operation is! InitializeInstanceOperation ||
      operation.validity is! CalendarIntervalValidity) {
    throw const FormatException(
      'Choose an instance initialization with a calendar interval.',
    );
  }
  final validity = operation.validity as CalendarIntervalValidity;
  if (validity.start is! ExactBound ||
      !(validity.end is ExactBound || validity.end is UnboundedBound)) {
    throw const FormatException(
      'Choose an initialization with exact or unbounded limits.',
    );
  }
  return UnfinishedInitializationForm(
    baseRevision: draft.content.baseRevision,
    representedContext: draft.content.representedContext,
    clientRef: operation.clientRef,
    instance: _input(operation.instance),
    start: _input(operation.start),
    definition: operation.definition,
    scope: scopeInput(operation.scope),
    endKind: validity.end is ExactBound ? 'exact' : 'unbounded',
    endCoordinate: validity.end is ExactBound
        ? (validity.end as ExactBound).value
        : '',
    draftVersion: draft.version,
  );
}

SaveDraftEngineRequest initializationDraftRequest({
  required SavedDraft draft,
  required UnfinishedInitializationForm form,
  required Selector universe,
  required UniverseId universeId,
  required ContinuityId continuity,
  required RecordVersion start,
  required RecordVersion definition,
  Chronology? clock,
  int? index,
}) {
  if (draft.content.proposal != null ||
      draft.content.baseRevision != form.baseRevision ||
      draft.content.representedContext != form.representedContext) {
    throw const FormatException(
      'Review Changes before adding this initialization.',
    );
  }
  final operation = initializationOperation(
    form,
    universe: universeId,
    start: start,
    definition: definition,
    clock: clock,
  );
  final operations = [...draft.content.operations];
  if (index != null) {
    final before = initializationFormFromDraft(draft, index);
    if (form.draftVersion != draft.version ||
        form.clientRef != before.clientRef) {
      throw const FormatException(
        'The draft changed. Reopen its current initialization fields.',
      );
    }
    operations[index] = operation;
  } else {
    for (final existing in operations) {
      final ref = Map.fromEntries(existing.toWire().fields)['client_ref'];
      if (ref is CanonicalString && ref.value == form.clientRef) {
        if (existing.toWire().toText() != operation.toWire().toText()) {
          throw const FormatException(
            'This initialization is already in Changes. Edit it there.',
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
