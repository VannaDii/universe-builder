import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'qualifier_draft.dart';
import 'evidence_basis_draft.dart';
import 'scope_draft.dart';
import 'temporal_validity_draft.dart';

bool isEditableAttribute(DomainOperation op) =>
    op is AddNamedAttributeOperation ||
    op is AssertPropositionOperation ||
    op is RecordRelationOperation;

String attributeClientRef(DomainOperation op) => switch (op) {
  AddNamedAttributeOperation(:final clientRef) => clientRef,
  AssertPropositionOperation(:final clientRef) ||
  RecordRelationOperation(:final clientRef) => clientRef,
  _ => throw const FormatException('Choose an attribute from Changes.'),
};

DomainValue? attributeValue(DomainOperation op) => switch (op) {
  AddNamedAttributeOperation(:final value) => value,
  AssertPropositionOperation(:final proposition) ||
  RecordRelationOperation(:final proposition) => proposition.value,
  _ => throw const FormatException('Choose an attribute from Changes.'),
};

bool isRelationshipAssertion(DomainOperation op) =>
    (op is AssertPropositionOperation || op is RecordRelationOperation) &&
    attributeValue(op) == null;

AttributeEvidence attributeEvidence(DomainOperation op) => switch (op) {
  AddNamedAttributeOperation(:final evidence) => evidence,
  AssertPropositionOperation(:final assertion) ||
  RecordRelationOperation(:final assertion) => AttributeEvidence(
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
    value: attributeValue(op) == null
        ? const QualifierInput(kind: 'retain')
        : qualifierInput('value', attributeValue(op)!),
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
  final originalValue = attributeValue(op);
  if (originalValue == null && form.value.kind != 'retain') {
    throw const FormatException(
      'A relationship assertion has no attribute value.',
    );
  }
  final value = originalValue == null
      ? null
      : buildQualifierValue(form.value, originalValue);
  final evidence = editAttributeEvidence(form.evidenceInput, originalEvidence);
  final DomainOperation edited;
  if (op is AddNamedAttributeOperation) {
    if (form.roles != null) {
      throw const FormatException(
        'Named attributes do not have role bindings.',
      );
    }
    edited = AddNamedAttributeOperation(
      clientRef: op.clientRef,
      subject: op.subject,
      namespace: op.namespace,
      key: op.key,
      valueShape: op.valueShape,
      subjectTypes: op.subjectTypes,
      multiplicity: op.multiplicity,
      value: value!,
      evidence: evidence,
    );
  } else if (op is AssertPropositionOperation ||
      op is RecordRelationOperation) {
    final (proposition, assertion) = switch (op) {
      AssertPropositionOperation(:final proposition, :final assertion) ||
      RecordRelationOperation(
        :final proposition,
        :final assertion,
      ) => (proposition, assertion),
      _ => throw const FormatException('Choose an assertion from Changes.'),
    };
    final nextProposition = PropositionRecord(
      predicate: proposition.predicate,
      subject: proposition.subject,
      roles: form.roles == null
          ? proposition.roles
          : form.roles!.map(
              (r) => PropositionRole(
                r.role,
                RecordRef(
                  record: RecordId.parse(r.record),
                  universe: r.universe.isEmpty
                      ? null
                      : UniverseId.parse(r.universe),
                ),
              ),
            ),
      value: value,
      quantification: proposition.quantification,
      context: form.evidenceInput?.scope == null
          ? proposition.context
          : evidence.scope.context,
    );
    final nextAssertion = AssertionRecord(
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
    );
    edited = op is RecordRelationOperation
        ? RecordRelationOperation(
            clientRef: op.clientRef,
            proposition: nextProposition,
            assertion: nextAssertion,
          )
        : AssertPropositionOperation(
            clientRef: attributeClientRef(op),
            proposition: nextProposition,
            assertion: nextAssertion,
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

AttributeEvidence editAttributeEvidence(
  AttributeEvidenceInput? input,
  AttributeEvidence originalEvidence,
) {
  return AttributeEvidence(
    attributeMode: input?.attributeMode ?? originalEvidence.attributeMode,
    polarity: input?.polarity ?? originalEvidence.polarity,
    scope: input?.scope == null
        ? originalEvidence.scope
        : buildScope(input!.scope!),
    validity: input?.temporalValidity != null
        ? buildTemporalValidity(
            input!.temporalValidity!,
            originalEvidence.validity,
          )
        : input?.validity ?? originalEvidence.validity,
    persistence: input?.persistence ?? originalEvidence.persistence,
    precision: input?.precision ?? originalEvidence.precision,
    alternatives: input?.alternatives == null
        ? originalEvidence.alternatives
        : input!.alternatives!.map(
            (input) => buildQualifierValue(
              input,
              qualifierChildren(
                SequenceValue(originalEvidence.alternatives),
              )[input.originalKey],
            ),
          ),
    basis: input?.basis == null
        ? originalEvidence.basis
        : buildEvidenceBasis(input!.basis!, originalEvidence.basis),
  );
}

AttributeEvidence newAttributeEvidence(UniverseId universe, RecordId context) =>
    AttributeEvidence(
      attributeMode: AttributeMode.instance,
      polarity: Polarity.support,
      scope: Scope(
        context: RecordRef(universe: universe, record: context),
        applicability: const UnspecifiedApplicability(),
      ),
      validity: const UnknownValidity(),
      persistence: PersistenceSemantics.unspecified,
      precision: Precision.unresolved,
      basis: const AuthorDecisionBasis(''),
    );

UnfinishedAttributeForm newAttributeForm({
  required SavedDraft draft,
  required RecordVersion entity,
  RevisionId? baseRevision,
  RecordId? representedContext,
}) {
  if (entity.payload is! EntityRecord) {
    throw const FormatException('Choose an entity for this fact.');
  }
  return UnfinishedAttributeForm(
    baseRevision: baseRevision ?? draft.content.baseRevision,
    representedContext: representedContext ?? draft.content.representedContext,
    clientRef: 'new-attribute:${entity.identity.recordId.value}',
    draftVersion: draft.version,
    value: const QualifierInput(kind: 'text'),
    creationInput: AttributeCreationInput(
      subject: VersionRef(
        universe: entity.identity.universeId,
        record: entity.identity.recordId,
        version: entity.recordVersionId,
      ),
      operationRef: RecordId.generate().value,
    ),
  );
}

DraftContent appendDraftAttribute({
  required SavedDraft draft,
  required UnfinishedAttributeForm form,
  required RecordVersion entity,
  required RecordVersion property,
}) {
  final creation = form.creationInput;
  if (creation == null ||
      entity.payload is! EntityRecord ||
      property.payload is! PropertyRecord ||
      creation.subject.record != entity.identity.recordId ||
      creation.subject.universe != entity.identity.universeId ||
      creation.subject.version != entity.recordVersionId ||
      creation.propertyRecord != property.identity.recordId.value ||
      creation.propertyUniverse != property.identity.universeId.value ||
      entity.identity.universeId != property.identity.universeId ||
      form.clientRef != 'new-attribute:${entity.identity.recordId.value}') {
    throw const FormatException(
      'Reopen the entity and choose an existing property.',
    );
  }
  if (draft.content.proposal != null ||
      form.baseRevision != draft.content.baseRevision ||
      form.representedContext != draft.content.representedContext) {
    throw const FormatException(
      'Reopen the dossier at the current draft revision.',
    );
  }
  final evidence = editAttributeEvidence(
    form.evidenceInput,
    newAttributeEvidence(entity.identity.universeId, form.representedContext),
  );
  final op = AssertPropositionOperation(
    clientRef: creation.operationRef,
    proposition: PropositionRecord(
      predicate: RecordRef(
        universe: property.identity.universeId,
        record: property.identity.recordId,
      ),
      subject: RecordRef(
        universe: entity.identity.universeId,
        record: entity.identity.recordId,
      ),
      value: buildQualifierValue(form.value, null),
      quantification: Quantification.particular,
      context: evidence.scope.context,
    ),
    assertion: AssertionRecord(
      proposition: RecordRef(
        universe: entity.identity.universeId,
        record: RecordId.parse(creation.operationRef),
      ),
      attributeMode: evidence.attributeMode,
      polarity: evidence.polarity,
      scope: evidence.scope,
      validity: evidence.validity,
      persistence: evidence.persistence,
      precision: evidence.precision,
      alternatives: evidence.alternatives,
      basis: evidence.basis,
    ),
  );
  final existing = draft.content.operations
      .where(
        (other) => other.toWire().fields.any(
          (field) =>
              field.key == 'client_ref' &&
              switch (field.value) {
                CanonicalString(:final value) => value == creation.operationRef,
                _ => false,
              },
        ),
      )
      .toList();
  if (existing.isNotEmpty) {
    if (existing.length == 1 &&
        existing.single.toWire().toText() == op.toWire().toText()) {
      return draft.content;
    }
    throw const FormatException(
      'This fact is already in Changes. Edit it there.',
    );
  }
  if (form.draftVersion != draft.version) {
    throw const FormatException(
      'Changes were edited elsewhere. Use current draft fields before adding this fact.',
    );
  }
  return DraftContent(
    baseRevision: draft.content.baseRevision,
    representedContext: draft.content.representedContext,
    operations: [...draft.content.operations, op],
    rationale: draft.content.rationale,
  );
}
