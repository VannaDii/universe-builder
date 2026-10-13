import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'qualifier_draft.dart';
import 'temporal_validity_draft.dart';

UnfinishedAttributeForm attributeFormFromDraft(SavedDraft draft, int index) {
  final op = draft.content.operations[index];
  if (op is! AddNamedAttributeOperation) {
    throw const FormatException('Choose an attribute from Changes.');
  }
  return UnfinishedAttributeForm(
    baseRevision: draft.content.baseRevision,
    representedContext: draft.content.representedContext,
    clientRef: op.clientRef,
    draftVersion: draft.version,
    value: qualifierInput('value', op.value),
  );
}

DraftContent replaceDraftAttribute({
  required SavedDraft draft,
  required int index,
  required UnfinishedAttributeForm form,
}) {
  final old = attributeFormFromDraft(draft, index);
  if (draft.content.proposal != null ||
      form.draftVersion != draft.version ||
      form.baseRevision != old.baseRevision ||
      form.representedContext != old.representedContext ||
      form.clientRef != old.clientRef) {
    throw const FormatException(
      'The draft changed. Reopen its current attribute before saving.',
    );
  }
  final op = draft.content.operations[index] as AddNamedAttributeOperation;
  final edited = AddNamedAttributeOperation(
    clientRef: op.clientRef,
    subject: op.subject,
    namespace: op.namespace,
    key: op.key,
    valueShape: op.valueShape,
    subjectTypes: op.subjectTypes,
    multiplicity: op.multiplicity,
    value: buildQualifierValue(form.value, op.value),
    evidence: AttributeEvidence(
      attributeMode: op.evidence.attributeMode,
      polarity: form.evidenceInput?.polarity ?? op.evidence.polarity,
      scope: op.evidence.scope,
      validity: form.evidenceInput?.temporalValidity != null
          ? buildTemporalValidity(
              form.evidenceInput!.temporalValidity!,
              op.evidence.validity,
            )
          : form.evidenceInput?.validity ?? op.evidence.validity,
      persistence: form.evidenceInput?.persistence ?? op.evidence.persistence,
      precision: form.evidenceInput?.precision ?? op.evidence.precision,
      alternatives: form.evidenceInput?.alternatives == null
          ? op.evidence.alternatives
          : form.evidenceInput!.alternatives!.map(
              (input) => buildQualifierValue(
                input,
                qualifierChildren(
                  SequenceValue(op.evidence.alternatives),
                )[input.originalKey],
              ),
            ),
      basis: op.evidence.basis,
    ),
  );
  return DraftContent(
    baseRevision: draft.content.baseRevision,
    representedContext: draft.content.representedContext,
    operations: [
      for (var i = 0; i < draft.content.operations.length; i++)
        i == index ? edited : draft.content.operations[i],
    ],
    rationale: draft.content.rationale,
  );
}
