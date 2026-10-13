import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

SaveDraftEngineRequest typeDraftRequest({
  required Selector universe,
  required ContinuityId continuity,
  required UnfinishedTypeForm form,
  required SavedDraft? previous,
}) {
  final operation = _typeOperation(form);
  final old = previous?.content;
  if (old != null &&
      (old.baseRevision != form.baseRevision ||
          old.representedContext != form.representedContext)) {
    throw const FormatException(
      'These changes use another revision or context. Review them before adding this definition.',
    );
  }
  for (final existing in old?.operations ?? <DomainOperation>[]) {
    final reference = Map.fromEntries(existing.toWire().fields)['client_ref'];
    if (reference is CanonicalString &&
        reference.value == operation.clientRef) {
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

UnfinishedTypeForm typeFormFromDraft(SavedDraft draft, int index) {
  final operation = draft.content.operations[index];
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
      form.baseRevision != old.baseRevision ||
      form.representedContext != old.representedContext) {
    throw const FormatException(
      'The draft changed. Reopen its current type fields before saving.',
    );
  }
  final operation = _typeOperation(form);
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
