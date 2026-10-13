import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

DefineCalendarOperation calendarOperation(UnfinishedCalendarForm form) {
  if ([form.namespace, form.key, form.clientRef].any((v) => v.trim().isEmpty)) {
    throw const FormatException('Enter a namespace and calendar key.');
  }
  final labels = <String, String>{}, units = <String, String>{};
  for (final l in form.labels) {
    if (labels.containsKey(l.language)) {
      throw const FormatException('Give each label a distinct language key.');
    }
    labels[l.language] = l.text;
  }
  for (final u in form.units) {
    if (units.containsKey(u.name)) {
      throw const FormatException(
        'Give each unit-structure entry a distinct key.',
      );
    }
    units[u.name] = u.structure;
  }
  return DefineCalendarOperation(
    clientRef: form.clientRef,
    record: CalendarRecord(
      namespace: form.namespace,
      key: form.key,
      labels: labels,
      epoch: form.hasEpoch ? form.epoch : null,
      unitStructure: units,
      conversions: form.conversions.map(
        (c) => CalendarConversion(
          target: CalendarId.parse(c.target),
          expression: c.hasExpression ? c.expression : null,
          valid: c.valid,
        ),
      ),
    ),
  );
}

UnfinishedCalendarForm calendarFormFromDraft(SavedDraft draft, int index) {
  final op = draft.content.operations[index];
  if (op is! DefineCalendarOperation) {
    throw const FormatException('Choose a calendar definition from Changes.');
  }
  final c = op.record;
  return UnfinishedCalendarForm(
    baseRevision: draft.content.baseRevision,
    representedContext: draft.content.representedContext,
    clientRef: op.clientRef,
    namespace: c.namespace,
    key: c.key,
    labels: c.labels.entries.map(
      (e) => PropertyLabelInput(language: e.key, text: e.value),
    ),
    hasEpoch: c.epoch != null,
    epoch: c.epoch ?? '',
    units: c.unitStructure.entries.map(
      (e) => CalendarUnitInput(name: e.key, structure: e.value),
    ),
    conversions: c.conversions.map(
      (v) => CalendarConversionInput(
        target: v.target.value,
        hasExpression: v.expression != null,
        expression: v.expression ?? '',
        valid: v.valid,
      ),
    ),
    draftVersion: draft.version,
  );
}

SaveDraftEngineRequest calendarDraftRequest({
  required SavedDraft draft,
  required UnfinishedCalendarForm form,
  required Selector universe,
  required ContinuityId continuity,
  int? index,
}) {
  if (draft.content.proposal != null ||
      draft.content.baseRevision != form.baseRevision ||
      draft.content.representedContext != form.representedContext) {
    throw const FormatException(
      'Review Changes before adding this calendar definition.',
    );
  }
  final operation = calendarOperation(form),
      operations = [...draft.content.operations];
  if (index != null) {
    final before = calendarFormFromDraft(draft, index);
    if (form.draftVersion != draft.version ||
        form.clientRef != before.clientRef) {
      throw const FormatException(
        'The draft changed. Reopen its current calendar fields.',
      );
    }
    operations[index] = operation;
  } else {
    for (final existing in operations) {
      final ref = Map.fromEntries(existing.toWire().fields)['client_ref'];
      if (ref is CanonicalString && ref.value == form.clientRef) {
        if (existing.toWire().toText() != operation.toWire().toText()) {
          throw const FormatException(
            'This calendar is already in Changes. Edit it there.',
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
