import 'package:ub_domain/ub_domain.dart';

import 'journal.dart';
import 'revision_input.dart';

/// Factual foundation gates in the selected immutable membership, rather than
/// in the current head or a convenient default world.
final class CandidateFoundation {
  CandidateFoundation(this.journal);
  final SqliteJournal journal;
  void validate(Membership membership) => validateRecords([
    for (final version in membership.values) journal.load(version),
  ]);

  void validateRecords(List<StoredVersion> records) {
    final bodies = {
      for (final record in records) record.identity.recordId: record,
    };
    bool hasKind(RecordId id, RecordKind kind) =>
        bodies[id]?.identity.recordKind == kind;
    final finished = <RecordId>{};
    for (final record in records) {
      switch (record.identity.recordKind) {
        case RecordKind.entityType:
          final type = EntityTypeRecord.fromWire(record.payload);
          final parent = type.parent;
          if ((type.parentResolution == ParentResolution.resolved) !=
              (parent != null)) {
            throw const FormatException(
              'Parent resolution disagrees with parent identity',
            );
          }
          final path = <RecordId>{};
          RecordId? next = record.identity.recordId;
          while (next != null) {
            if (finished.contains(next)) break;
            if (!path.add(next)) {
              throw const FormatException('Cyclic definition ancestry');
            }
            final definition = bodies[next];
            if (definition == null ||
                definition.identity.recordKind != RecordKind.entityType) {
              throw const FormatException(
                'Parent is not a type in the selected revision',
              );
            }
            next = EntityTypeRecord.fromWire(definition.payload).parent;
          }
          finished.addAll(path);
        case RecordKind.entity:
          final entity = EntityRecord.fromWire(record.payload);
          final classification = entity.classification;
          if ((entity.classificationResolution ==
                  ClassificationResolution.resolved) !=
              (classification != null)) {
            throw const FormatException(
              'Classification resolution disagrees with type identity',
            );
          }
          if (classification != null &&
              !hasKind(classification, RecordKind.entityType)) {
            throw const FormatException(
              'Classification is not a type in the selected revision',
            );
          }
          _values(entity.metadata);
          for (final association in entity.worldAssociations) {
            _values(association.qualifiers);
          }
        case RecordKind.world:
          _values(WorldRecord.fromWire(record.payload).metadata);
        case RecordKind.realm:
          _values(RealmRecord.fromWire(record.payload).metadata);
        case RecordKind.proposition:
          final proposition = PropositionRecord.fromWire(record.payload);
          if (!hasKind(
            proposition.context.record,
            RecordKind.representedContext,
          )) {
            throw const FormatException('Proposition context has wrong kind');
          }
          final subject = proposition.subject.record;
          if (!hasKind(subject, RecordKind.entity) &&
              !hasKind(subject, RecordKind.entityType)) {
            throw const FormatException('Proposition subject has wrong kind');
          }
          final predicate = proposition.predicate.record;
          if (!hasKind(predicate, RecordKind.property) &&
              !hasKind(predicate, RecordKind.relation)) {
            throw const FormatException('Proposition predicate has wrong kind');
          }
          proposition.value?.validate();
        case RecordKind.assertion:
          final assertion = AssertionRecord.fromWire(record.payload);
          final proposition = bodies[assertion.proposition.record];
          if (proposition == null ||
              proposition.identity.recordKind != RecordKind.proposition) {
            throw const FormatException(
              'Assertion must reference a proposition',
            );
          }
          final kind = assertion.attributeMode == AttributeMode.instance
              ? RecordKind.entity
              : RecordKind.entityType;
          if (!hasKind(
            PropositionRecord.fromWire(proposition.payload).subject.record,
            kind,
          )) {
            throw const FormatException(
              'Attribute mode disagrees with subject kind',
            );
          }
          final scope = assertion.scope;
          if (!hasKind(scope.context.record, RecordKind.representedContext) ||
              (scope.realm != null &&
                  !hasKind(scope.realm!.record, RecordKind.realm))) {
            throw const FormatException(
              'Attribute scope has wrong reference kind',
            );
          }
          final basis = assertion.basis;
          if (basis is SourceAnchorBasis &&
              !hasKind(basis.anchor.record, RecordKind.anchor)) {
            throw const FormatException('Evidence is not an anchor');
          }
          for (final value in assertion.alternatives) {
            value.validate();
          }
        default:
          break;
      }
    }
  }

  void _values(Map<String, DomainValue> values) {
    for (final value in values.values) {
      value.validate();
    }
  }
}
