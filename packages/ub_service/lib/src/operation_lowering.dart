import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

InvalidArgumentError _invalid(String message) =>
    InvalidArgumentError(field: 'operations', message: message);
final _nonWhitespace = RegExp(
  r'[^\u0009-\u000d\u0020\u0085\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000]',
);
RecordId _id(String name, Set<String> seen) {
  if (name.isEmpty || !seen.add(name)) {
    throw _invalid('duplicate or empty client_ref');
  }
  try {
    return RecordId.parse(name);
  } on FormatException {
    return RecordId.generate();
  }
}

PropertyRecord _definition(
  AddNamedAttributeOperation op,
  Map<String, String> labels,
) => PropertyRecord(
  namespace: op.namespace,
  key: op.key,
  labels: labels,
  subjectTypes: op.subjectTypes,
  value: op.valueShape,
  multiplicity: op.multiplicity,
  persistence: op.evidence.persistence,
  exclusive: false,
  symmetric: false,
  transitive: false,
);

/// Internal preparation before full compilation, exact review and publication.
/// Names and hints do not authorize writes or resolve uncertain classifications.
List<DomainOperation> lowerAuthoringOperations({
  required UniverseId universe,
  required List<RecordVersion> base,
  required List<DomainOperation> operations,
}) {
  final lowered = <DomainOperation>[];
  final properties = <(RecordId, PropertyRecord)>[
    for (final r in base)
      if (r.payload is PropertyRecord)
        (r.identity.recordId, r.payload as PropertyRecord),
  ];
  // Explicit same-batch definitions are available regardless of input order.
  for (final op in operations) {
    if (op is! DefinePropertyOperation ||
        !operations.any(
          (named) =>
              named is AddNamedAttributeOperation &&
              named.namespace == op.record.namespace &&
              named.key == op.record.key,
        )) {
      continue;
    }
    RecordId id;
    try {
      id = RecordId.parse(op.clientRef);
    } on FormatException {
      throw _invalid(
        'a property referenced by name in this batch requires a rec_ ID',
      );
    }
    properties.add((id, op.record));
  }
  final inputRefs = <String>{};
  for (final op in operations) {
    // Read only the closed operation's own client_ref field, as in the source.
    for (final field in op.toWire().fields) {
      if (field.key == 'client_ref' && field.value is CanonicalString) {
        final name = (field.value as CanonicalString).value;
        if (name.isEmpty || !inputRefs.add(name)) {
          throw _invalid('duplicate or empty client_ref');
        }
      }
    }
  }
  final refs = <String>{};
  for (final op in operations) {
    switch (op) {
      case IntroduceDefinitionOperation():
        if (!_nonWhitespace.hasMatch(op.name)) {
          throw _invalid('definition name is required');
        }
        lowered.add(
          DefineTypeOperation(
            clientRef: op.clientRef,
            record: EntityTypeRecord(
              namespace: op.namespace,
              key: op.key,
              name: op.name,
              labels: {},
              parent: op.parent,
              parentResolution: op.parent == null
                  ? ParentResolution.root
                  : ParentResolution.resolved,
              applicability: op.applicability,
              classificationExecutable: op.classificationExecutable,
            ),
          ),
        );
      case IntroduceInstanceOperation():
        if (!_nonWhitespace.hasMatch(op.name.text)) {
          throw _invalid('instance name is required');
        }
        lowered.add(
          CreateEntityOperation(
            clientRef: op.clientRef,
            record: EntityRecord(
              names: [op.name],
              classification: op.classification,
              classificationResolution: op.classification == null
                  ? ClassificationResolution.unclassified
                  : ClassificationResolution.resolved,
              worldAssociations: op.worldAssociations,
              labels: {},
              metadata: {},
            ),
          ),
        );
      case AddNamedAttributeOperation():
        if (op.evidence.basis is EventEffectBasis) {
          throw _invalid(
            'physical transformations require the event operation path',
          );
        }
        if (op.evidence.basis is InstanceInitializationBasis) {
          throw _invalid(
            'initialization evidence requires initialize_instance',
          );
        }
        final matches = properties
            .where((p) => p.$2.namespace == op.namespace && p.$2.key == op.key)
            .toList();
        RecordId predicate;
        if (matches.isEmpty) {
          predicate = RecordId.generate();
          final definition = _definition(op, {});
          lowered.add(
            DefinePropertyOperation(
              clientRef: predicate.value,
              record: definition,
            ),
          );
          properties.add((predicate, definition));
        } else if (matches.length == 1) {
          final (id, existing) = matches.single;
          if (existing != _definition(op, existing.labels)) {
            throw _invalid(
              'named attribute definition differs; use an explicit definition revision',
            );
          }
          predicate = id;
        } else {
          throw _invalid('named attribute is ambiguous');
        }
        final propositionId = _id(op.clientRef, refs), e = op.evidence;
        lowered.add(
          AssertPropositionOperation(
            clientRef: propositionId.value,
            proposition: PropositionRecord(
              predicate: RecordRef(universe: universe, record: predicate),
              subject: op.subject,
              roles: [],
              value: op.value,
              quantification: Quantification.particular,
              context: e.scope.context,
            ),
            assertion: AssertionRecord(
              proposition: RecordRef(universe: universe, record: propositionId),
              attributeMode: e.attributeMode,
              polarity: e.polarity,
              scope: e.scope,
              validity: e.validity,
              persistence: e.persistence,
              precision: e.precision,
              alternatives: e.alternatives,
              basis: e.basis,
            ),
          ),
        );
      case RefineClassificationOperation():
        lowered.add(
          AddTypeMembershipOperation(
            record: op.record,
            expectedVersion: op.expectedVersion,
            entityType: op.entityType,
          ),
        );
      default:
        lowered.add(op);
    }
  }
  return List.unmodifiable(lowered);
}
