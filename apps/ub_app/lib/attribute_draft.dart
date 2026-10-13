import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'qualifier_draft.dart';
import 'evidence_basis_draft.dart';
import 'scope_draft.dart';
import 'temporal_validity_draft.dart';

bool isEditableAttribute(DomainOperation op) =>
    op is AddNamedAttributeOperation ||
    (op is AssertPropositionOperation && op.proposition.value != null);

String attributeClientRef(DomainOperation op) => switch (op) {
  AddNamedAttributeOperation(:final clientRef) => clientRef,
  AssertPropositionOperation(:final clientRef) => clientRef,
  _ => throw const FormatException('Choose an attribute from Changes.'),
};

DomainValue attributeValue(DomainOperation op) => switch (op) {
  AddNamedAttributeOperation(:final value) => value,
  AssertPropositionOperation(:final proposition)
      when proposition.value != null =>
    proposition.value!,
  _ => throw const FormatException('Choose an attribute from Changes.'),
};

AttributeEvidence attributeEvidence(DomainOperation op) => switch (op) {
  AddNamedAttributeOperation(:final evidence) => evidence,
  AssertPropositionOperation(:final assertion) => AttributeEvidence(
    attributeMode: assertion.attributeMode,
    polarity: assertion.polarity,
    scope: assertion.scope,
    validity: assertion.validity,
    persistence: assertion.persistence,
    precision: assertion.precision,
    alternatives: assertion.alternatives,
    basis: assertion.basis,
  ),
  _ => throw const FormatException('Choose an attribute from Changes.'),
};

UnfinishedAttributeForm attributeFormFromDraft(SavedDraft draft, int index) {
  final op = draft.content.operations[index];
  return UnfinishedAttributeForm(
    baseRevision: draft.content.baseRevision,
    representedContext: draft.content.representedContext,
    clientRef: attributeClientRef(op),
    draftVersion: draft.version,
    value: qualifierInput('value', attributeValue(op)),
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
  final op = draft.content.operations[index];
  final originalEvidence = attributeEvidence(op);
  final value = buildQualifierValue(form.value, attributeValue(op));
  final evidence = AttributeEvidence(
    attributeMode:
        form.evidenceInput?.attributeMode ?? originalEvidence.attributeMode,
    polarity: form.evidenceInput?.polarity ?? originalEvidence.polarity,
    scope: form.evidenceInput?.scope == null
        ? originalEvidence.scope
        : buildScope(form.evidenceInput!.scope!),
    validity: form.evidenceInput?.temporalValidity != null
        ? buildTemporalValidity(
            form.evidenceInput!.temporalValidity!,
            originalEvidence.validity,
          )
        : form.evidenceInput?.validity ?? originalEvidence.validity,
    persistence:
        form.evidenceInput?.persistence ?? originalEvidence.persistence,
    precision: form.evidenceInput?.precision ?? originalEvidence.precision,
    alternatives: form.evidenceInput?.alternatives == null
        ? originalEvidence.alternatives
        : form.evidenceInput!.alternatives!.map(
            (input) => buildQualifierValue(
              input,
              qualifierChildren(
                SequenceValue(originalEvidence.alternatives),
              )[input.originalKey],
            ),
          ),
    basis: form.evidenceInput?.basis == null
        ? originalEvidence.basis
        : buildEvidenceBasis(
            form.evidenceInput!.basis!,
            originalEvidence.basis,
          ),
  );
  final DomainOperation edited;
  if (op is AddNamedAttributeOperation) {
    edited = AddNamedAttributeOperation(
      clientRef: op.clientRef,
      subject: op.subject,
      namespace: op.namespace,
      key: op.key,
      valueShape: op.valueShape,
      subjectTypes: op.subjectTypes,
      multiplicity: op.multiplicity,
      value: value,
      evidence: evidence,
    );
  } else if (op is AssertPropositionOperation) {
    final proposition = op.proposition, assertion = op.assertion;
    edited = AssertPropositionOperation(
      clientRef: op.clientRef,
      proposition: PropositionRecord(
        predicate: proposition.predicate,
        subject: proposition.subject,
        roles: proposition.roles,
        value: value,
        quantification: proposition.quantification,
        context: form.evidenceInput?.scope == null
            ? proposition.context
            : evidence.scope.context,
      ),
      assertion: AssertionRecord(
        proposition: assertion.proposition,
        attributeMode: evidence.attributeMode,
        polarity: evidence.polarity,
        scope: evidence.scope,
        validity: evidence.validity,
        persistence: evidence.persistence,
        precision: evidence.precision,
        alternatives: evidence.alternatives,
        basis: evidence.basis,
        establishedBy: assertion.establishedBy,
      ),
    );
  } else {
    throw const FormatException('Choose an attribute from Changes.');
  }
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
