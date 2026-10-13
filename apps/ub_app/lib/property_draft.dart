import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

ValueShapeInput valueShapeInput(ValueShape shape) => switch (shape) {
  SimpleValueShape(:final kind) => ValueShapeInput(kind: kind.name),
  QuantityShape(:final unit) => ValueShapeInput(
    kind: 'quantity',
    unit: unit.value,
  ),
  RangeShape(:final unit) => ValueShapeInput(
    kind: 'range',
    unit: unit?.value ?? '',
  ),
  EntityRefShape(:final subjectTypes) => ValueShapeInput(
    kind: 'entity_ref',
    subjectTypes: subjectTypes.map((id) => id.value),
  ),
  EnumShape(:final definition) => ValueShapeInput(
    kind: 'enum',
    definition: definition.value,
  ),
  StructuredShape(:final definition) => ValueShapeInput(
    kind: 'structured',
    definition: definition.value,
  ),
  SequenceShape(:final item) => ValueShapeInput(
    kind: 'sequence',
    item: valueShapeInput(item),
  ),
};
ValueShape buildValueShape(ValueShapeInput input) => switch (input.kind) {
  'quantity' => QuantityShape(UnitId.parse(input.unit)),
  'range' => RangeShape(input.unit.isEmpty ? null : UnitId.parse(input.unit)),
  'entity_ref' => EntityRefShape(input.subjectTypes.map(RecordId.parse)),
  'enum' => EnumShape(ValueDefinitionId.parse(input.definition)),
  'structured' => StructuredShape(ValueDefinitionId.parse(input.definition)),
  'sequence' when input.item != null => SequenceShape(
    buildValueShape(input.item!),
  ),
  _ when SimpleShapeKind.values.any((kind) => kind.name == input.kind) =>
    SimpleValueShape(SimpleShapeKind.fromName(input.kind)),
  _ => throw const FormatException('Choose a complete value shape.'),
};

DefinePropertyOperation propertyOperation(UnfinishedPropertyForm form) {
  if (form.namespace.trim().isEmpty ||
      form.key.trim().isEmpty ||
      form.clientRef.trim().isEmpty) {
    throw const FormatException('Enter a namespace and property key.');
  }
  final labels = <String, String>{};
  for (final label in form.labels) {
    if (labels.containsKey(label.language)) {
      throw const FormatException('Give each label a distinct language key.');
    }
    labels[label.language] = label.text;
  }
  return DefinePropertyOperation(
    clientRef: form.clientRef,
    record: PropertyRecord(
      namespace: form.namespace,
      key: form.key,
      labels: labels,
      subjectTypes: form.subjectTypes.map(RecordId.parse),
      value: buildValueShape(form.shape),
      multiplicity: Multiplicity.fromName(form.multiplicity),
      persistence: PersistenceSemantics.fromWire(
        CanonicalString(form.persistence),
      ),
      unitDimension: form.hasUnitDimension ? form.unitDimension : null,
      inverse: form.hasInverse ? form.inverse : null,
      exclusive: form.exclusive,
      symmetric: form.symmetric,
      transitive: form.transitive,
    ),
  );
}

UnfinishedPropertyForm propertyFormFromDraft(SavedDraft draft, int index) {
  final op = draft.content.operations[index];
  if (op is! DefinePropertyOperation) {
    throw const FormatException('Choose a property definition from Changes.');
  }
  final p = op.record;
  return UnfinishedPropertyForm(
    baseRevision: draft.content.baseRevision,
    representedContext: draft.content.representedContext,
    clientRef: op.clientRef,
    namespace: p.namespace,
    key: p.key,
    labels: p.labels.entries.map(
      (e) => PropertyLabelInput(language: e.key, text: e.value),
    ),
    subjectTypes: p.subjectTypes.map((id) => id.value),
    shape: valueShapeInput(p.value),
    multiplicity: p.multiplicity.name,
    persistence: p.persistence.wireName,
    hasUnitDimension: p.unitDimension != null,
    unitDimension: p.unitDimension ?? '',
    hasInverse: p.inverse != null,
    inverse: p.inverse ?? '',
    exclusive: p.exclusive,
    symmetric: p.symmetric,
    transitive: p.transitive,
    draftVersion: draft.version,
  );
}

SaveDraftEngineRequest propertyDraftRequest({
  required SavedDraft draft,
  required UnfinishedPropertyForm form,
  required Selector universe,
  required ContinuityId continuity,
  int? index,
}) {
  if (draft.content.proposal != null ||
      draft.content.baseRevision != form.baseRevision ||
      draft.content.representedContext != form.representedContext) {
    throw const FormatException(
      'Review Changes before adding this property definition.',
    );
  }
  final operation = propertyOperation(form);
  final operations = [...draft.content.operations];
  if (index != null) {
    final original = propertyFormFromDraft(draft, index);
    if (form.draftVersion != draft.version ||
        original.clientRef != form.clientRef) {
      throw const FormatException(
        'The draft changed. Reopen its current property fields.',
      );
    }
    operations[index] = operation;
  } else {
    for (final existing in operations) {
      final ref = Map.fromEntries(existing.toWire().fields)['client_ref'];
      if (ref is CanonicalString && ref.value == form.clientRef) {
        if (existing.toWire().toText() != operation.toWire().toText()) {
          throw const FormatException(
            'This property is already in Changes. Edit it there.',
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
