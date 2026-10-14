import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

SaveDraftEngineRequest typeDraftRequest({
  required Selector universe,
  required ContinuityId continuity,
  required UnfinishedTypeForm form,
  required SavedDraft? previous,
}) {
  final operation = form.revisionTarget == null
      ? _typeOperation(form)
      : typeRevisionOperation(form);
  final old = previous?.content;
  if (old != null &&
      (old.baseRevision != form.baseRevision ||
          old.representedContext != form.representedContext)) {
    throw const FormatException(
      'These changes use another revision or context. Review them before adding this definition.',
    );
  }
  for (final existing in old?.operations ?? <DomainOperation>[]) {
    if (operation is ReviseDefinitionOperation &&
        existing is ReviseDefinitionOperation &&
        existing.record == operation.record) {
      if (existing.toWire().toText() != operation.toWire().toText()) {
        throw const FormatException(
          'This type already has a revision. Edit it in Changes.',
        );
      }
      return SaveDraftEngineRequest(
        universe: universe,
        continuityId: continuity,
        expectedVersion: previous!.version,
        content: old!,
      );
    }
    final reference = Map.fromEntries(existing.toWire().fields)['client_ref'];
    if (reference is CanonicalString && reference.value == form.clientRef) {
      if (existing.toWire().toText() != operation.toWire().toText()) {
        throw const FormatException(
          'This definition reference is already used in Changes. Review that operation before replacing it.',
        );
      }
      return SaveDraftEngineRequest(
        universe: universe,
        continuityId: continuity,
        expectedVersion: previous!.version,
        content: old!,
      );
    }
  }
  if (old?.proposal != null) {
    throw const FormatException(
      'Continue editing separately in Changes before adding to a submitted proposal.',
    );
  }
  return SaveDraftEngineRequest(
    universe: universe,
    continuityId: continuity,
    expectedVersion: previous?.version ?? BigInt.zero,
    content: DraftContent(
      baseRevision: form.baseRevision,
      representedContext: form.representedContext,
      operations: [...?old?.operations, operation],
      rationale: [
        if (old != null && old.rationale.isNotEmpty) old.rationale,
        if (form.rationale.isNotEmpty) form.rationale,
      ].join('\n\n'),
    ),
  );
}

IntroduceDefinitionOperation _typeOperation(UnfinishedTypeForm form) {
  if (form.namespace.trim().isEmpty ||
      form.key.trim().isEmpty ||
      form.clientRef.trim().isEmpty) {
    throw const FormatException('Enter a namespace and definition key.');
  }
  if (form.parentChoice.isEmpty) {
    throw const FormatException(
      'Choose a parent or explicitly choose no parent.',
    );
  }
  final applicability = switch (form.applicabilityChoice) {
    'unspecified' => const UnspecifiedApplicability(),
    'conditional' => const ConditionalApplicability(),
    'universe_wide' => const UniverseApplicability(),
    'worlds' => WorldsApplicability(form.worlds),
    _ => throw const FormatException('Choose where this definition applies.'),
  };
  if (form.classificationExecutable == null) {
    throw const FormatException(
      'Choose whether classification can be executed.',
    );
  }
  return IntroduceDefinitionOperation(
    clientRef: form.clientRef,
    namespace: form.namespace,
    key: form.key,
    name: form.name.trim().isEmpty ? form.key : form.name,
    parent: form.parentChoice == 'none'
        ? null
        : RecordId.parse(form.parentChoice),
    applicability: applicability,
    classificationExecutable: form.classificationExecutable!,
  );
}

ReviseDefinitionOperation typeRevisionOperation(UnfinishedTypeForm form) {
  if (form.revisionTarget == null ||
      form.expectedRecordVersion == null ||
      form.original == null) {
    throw const FormatException(
      'Open a published type definition to revise it.',
    );
  }
  if (form.namespace != form.original!.namespace ||
      form.key != form.original!.key) {
    throw const FormatException('Type revisions retain namespace and key.');
  }
  final entered = _typeOperation(form), labels = <String, String>{};
  for (final l in form.labels) {
    if (labels.containsKey(l.language)) {
      throw const FormatException('Give each label a distinct language key.');
    }
    labels[l.language] = l.text;
  }
  return ReviseDefinitionOperation(
    record: form.revisionTarget!,
    expectedVersion: form.expectedRecordVersion!,
    replacement: EntityTypeRecord(
      namespace: form.namespace,
      key: form.key,
      name: form.name,
      labels: labels,
      parent: entered.parent,
      parentResolution: ParentResolution.fromName(form.parentResolution),
      applicability: entered.applicability,
      classificationExecutable: entered.classificationExecutable,
    ),
  );
}

UnfinishedTypeForm typeRevisionFormFromRecord({
  required RecordVersion record,
  required RevisionId baseRevision,
  required RecordId representedContext,
}) {
  if (record.payload is! EntityTypeRecord) {
    throw const FormatException('Choose a published type definition.');
  }
  return _revisionForm(
    record.payload as EntityTypeRecord,
    baseRevision,
    representedContext,
    RecordRef(
      universe: record.identity.universeId,
      record: record.identity.recordId,
    ),
    record.recordVersionId,
    null,
  );
}

UnfinishedTypeForm _revisionForm(
  EntityTypeRecord p,
  RevisionId base,
  RecordId context,
  RecordRef target,
  RecordVersionId expected,
  BigInt? draftVersion,
) => UnfinishedTypeForm(
  baseRevision: base,
  representedContext: context,
  clientRef: target.record.value,
  revisionTarget: target,
  expectedRecordVersion: expected,
  original: p,
  namespace: p.namespace,
  key: p.key,
  name: p.name,
  parentChoice: p.parent?.value ?? 'none',
  parentResolution: p.parentResolution.name,
  labels: p.labels.entries.map(
    (e) => PropertyLabelInput(language: e.key, text: e.value),
  ),
  classificationExecutable: p.classificationExecutable,
  applicabilityChoice: switch (p.applicability) {
    UnspecifiedApplicability() => 'unspecified',
    UniverseApplicability() => 'universe_wide',
    WorldsApplicability() => 'worlds',
    ConditionalApplicability() => 'conditional',
  },
  worlds: p.applicability is WorldsApplicability
      ? (p.applicability as WorldsApplicability).worldIds
      : const [],
  rationale: '',
  draftVersion: draftVersion,
);
UnfinishedTypeForm typeFormFromDraft(SavedDraft draft, int index) {
  final operation = draft.content.operations[index];
  if (operation is ReviseDefinitionOperation &&
      operation.replacement is EntityTypeRecord) {
    return _revisionForm(
      operation.replacement as EntityTypeRecord,
      draft.content.baseRevision,
      draft.content.representedContext,
      operation.record,
      operation.expectedVersion,
      draft.version,
    );
  }
  if (operation is! IntroduceDefinitionOperation) {
    throw const FormatException('Choose a type definition from Changes.');
  }
  return UnfinishedTypeForm(
    baseRevision: draft.content.baseRevision,
    representedContext: draft.content.representedContext,
    clientRef: operation.clientRef,
    namespace: operation.namespace,
    key: operation.key,
    name: operation.name,
    parentChoice: operation.parent?.value ?? 'none',
    applicabilityChoice: switch (operation.applicability) {
      UnspecifiedApplicability() => 'unspecified',
      UniverseApplicability() => 'universe_wide',
      WorldsApplicability() => 'worlds',
      ConditionalApplicability() => 'conditional',
    },
    classificationExecutable: operation.classificationExecutable,
    worlds: operation.applicability is WorldsApplicability
        ? (operation.applicability as WorldsApplicability).worldIds
        : const [],
    rationale: '',
    draftVersion: draft.version,
  );
}

DraftContent replaceDraftType({
  required SavedDraft draft,
  required int index,
  required UnfinishedTypeForm form,
}) {
  final old = typeFormFromDraft(draft, index);
  if (draft.content.proposal != null ||
      form.draftVersion != draft.version ||
      form.clientRef != old.clientRef ||
      form.revisionTarget != old.revisionTarget ||
      form.expectedRecordVersion != old.expectedRecordVersion ||
      form.baseRevision != old.baseRevision ||
      form.representedContext != old.representedContext) {
    throw const FormatException(
      'The draft changed. Reopen its current type fields before saving.',
    );
  }
  final operation = form.revisionTarget == null
      ? _typeOperation(form)
      : typeRevisionOperation(form);
  return DraftContent(
    baseRevision: draft.content.baseRevision,
    representedContext: draft.content.representedContext,
    operations: [
      for (var i = 0; i < draft.content.operations.length; i++)
        i == index ? operation : draft.content.operations[i],
    ],
    rationale: draft.content.rationale,
  );
}
