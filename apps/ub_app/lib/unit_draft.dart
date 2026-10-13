import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'qualifier_draft.dart';
import 'temporal_validity_draft.dart';

DefineUnitOperation unitOperation(
  UnfinishedUnitForm form, {
  UnitRecord? original,
}) {
  if ([form.namespace, form.key, form.clientRef].any((v) => v.trim().isEmpty)) {
    throw const FormatException('Enter a namespace and unit key.');
  }
  final labels = <String, String>{};
  for (final label in form.labels) {
    if (label.language.isEmpty || labels.containsKey(label.language)) {
      throw const FormatException('Give each label a distinct language key.');
    }
    labels[label.language] = label.text;
  }
  final validity = switch (form.validityChoice) {
    'unspecified' => const UnspecifiedValidity(),
    'unknown' => const UnknownValidity(),
    'conditional' => const ConditionalValidity(),
    'retain' when original != null => original.validity,
    'temporal' when form.temporalValidity != null => buildTemporalValidity(
      form.temporalValidity!,
      original?.validity,
    ),
    _ => throw const FormatException('Choose the unit validity.'),
  };
  return DefineUnitOperation(
    clientRef: form.clientRef,
    record: UnitRecord(
      namespace: form.namespace,
      key: form.key,
      dimension: form.dimension,
      symbol: form.symbol,
      labels: labels,
      base: form.hasBase ? UnitId.parse(form.base) : null,
      scaleToBase: form.hasScale
          ? buildQualifierValue(form.scale, original?.scaleToBase)
          : null,
      validity: validity,
    ),
  );
}

UnfinishedUnitForm unitFormFromDraft(SavedDraft draft, int index) {
  final op = draft.content.operations[index];
  if (op is! DefineUnitOperation) {
    throw const FormatException('Choose a unit definition from Changes.');
  }
  final u = op.record;
  return UnfinishedUnitForm(
    baseRevision: draft.content.baseRevision,
    representedContext: draft.content.representedContext,
    clientRef: op.clientRef,
    namespace: u.namespace,
    key: u.key,
    dimension: u.dimension,
    symbol: u.symbol,
    labels: u.labels.entries.map(
      (e) => PropertyLabelInput(language: e.key, text: e.value),
    ),
    hasBase: u.base != null,
    base: u.base?.value ?? '',
    hasScale: u.scaleToBase != null,
    scale: u.scaleToBase == null
        ? const QualifierInput(kind: 'rational', value: '1', denominator: '1')
        : qualifierInput('scale', u.scaleToBase!),
    validityChoice: switch (u.validity) {
      UnspecifiedValidity() => 'unspecified',
      UnknownValidity() => 'unknown',
      ConditionalValidity() => 'conditional',
      _ => 'retain',
    },
    temporalValidity: temporalValidityInput(u.validity),
    draftVersion: draft.version,
  );
}

SaveDraftEngineRequest unitDraftRequest({
  required SavedDraft draft,
  required UnfinishedUnitForm form,
  required Selector universe,
  required ContinuityId continuity,
  int? index,
}) {
  if (draft.content.proposal != null ||
      draft.content.baseRevision != form.baseRevision ||
      draft.content.representedContext != form.representedContext) {
    throw const FormatException(
      'Review Changes before adding this unit definition.',
    );
  }
  UnitRecord? original;
  if (index != null) {
    final before = unitFormFromDraft(draft, index);
    if (form.draftVersion != draft.version ||
        form.clientRef != before.clientRef) {
      throw const FormatException(
        'The draft changed. Reopen its current unit fields.',
      );
    }
    original = (draft.content.operations[index] as DefineUnitOperation).record;
  }
  final operation = unitOperation(form, original: original);
  final operations = [...draft.content.operations];
  if (index != null) {
    operations[index] = operation;
  } else {
    for (final existing in operations) {
      final ref = Map.fromEntries(existing.toWire().fields)['client_ref'];
      if (ref is CanonicalString && ref.value == form.clientRef) {
        if (existing.toWire().toText() != operation.toWire().toText()) {
          throw const FormatException(
            'This unit is already in Changes. Edit it there.',
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
