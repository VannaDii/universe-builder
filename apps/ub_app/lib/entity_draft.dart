import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

SaveDraftEngineRequest entityDraftRequest({
  required Selector universe,
  required ContinuityId continuity,
  required UnfinishedEntityForm form,
  required SavedDraft? previous,
}) {
  if (form.name.trim().isEmpty || form.clientRef.trim().isEmpty) {
    throw const FormatException('Enter a name.');
  }
  if (form.worlds.isNotEmpty && form.worldRole.trim().isEmpty) {
    throw const FormatException('Describe the role of the selected worlds.');
  }
  final operation = IntroduceInstanceOperation(
    clientRef: form.clientRef,
    name: ContextualName(
      text: form.name,
      validity: const UnspecifiedValidity(),
    ),
    classification: form.classification.isEmpty
        ? null
        : RecordId.parse(form.classification),
    worldAssociations: form.worlds.map(
      (world) => WorldAssociation(
        world: world,
        role: form.worldRole,
        validity: const UnspecifiedValidity(),
        qualifiers: {},
      ),
    ),
  );
  final old = previous?.content;
  if (old != null &&
      (old.baseRevision != form.baseRevision ||
          old.representedContext != form.representedContext)) {
    throw const FormatException(
      'These changes use another revision or context. Review them before adding this entity.',
    );
  }
  for (final existing in old?.operations ?? <DomainOperation>[]) {
    final ref = Map.fromEntries(existing.toWire().fields)['client_ref'];
    if (ref is CanonicalString && ref.value == operation.clientRef) {
      if (existing.toWire().toText() != operation.toWire().toText()) {
        throw const FormatException(
          'This entity reference is already used in Changes. Review that operation before replacing it.',
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
