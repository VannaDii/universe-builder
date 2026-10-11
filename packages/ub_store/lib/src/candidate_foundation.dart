import 'package:ub_domain/ub_domain.dart';

import 'catalog.dart';
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
      final fields = objectFields(record.payload);
      switch (record.identity.recordKind) {
        case RecordKind.entityType:
          final parent = _optionalId(fields['parent']);
          if ((_string(fields['parentResolution']) == 'resolved') !=
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
            next = _optionalId(objectFields(definition.payload)['parent']);
          }
          finished.addAll(path);
        case RecordKind.entity:
          final classification = _optionalId(fields['classification']);
          if ((_string(fields['classificationResolution']) == 'resolved') !=
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
          _values(fields['metadata']!);
          for (final association
              in (fields['worldAssociations'] as CanonicalArray).items) {
            _values(objectFields(association)['qualifiers']!);
          }
        case RecordKind.world:
        case RecordKind.realm:
          _values(fields['metadata'] ?? CanonicalObject([]));
        case RecordKind.proposition:
          if (!hasKind(
            _reference(fields['context']!),
            RecordKind.representedContext,
          )) {
            throw const FormatException('Proposition context has wrong kind');
          }
          final subject = _reference(fields['subject']!);
          if (!hasKind(subject, RecordKind.entity) &&
              !hasKind(subject, RecordKind.entityType)) {
            throw const FormatException('Proposition subject has wrong kind');
          }
          final predicate = _reference(fields['predicate']!);
          if (!hasKind(predicate, RecordKind.property) &&
              !hasKind(predicate, RecordKind.relation)) {
            throw const FormatException('Proposition predicate has wrong kind');
          }
          final value = fields['value'];
          if (value != null && value is! CanonicalNull) {
            DomainValue.fromWire(value).validate();
          }
        case RecordKind.assertion:
          final proposition = bodies[_reference(fields['proposition']!)];
          if (proposition == null ||
              proposition.identity.recordKind != RecordKind.proposition) {
            throw const FormatException(
              'Assertion must reference a proposition',
            );
          }
          final kind = _string(fields['attributeMode']) == 'instance'
              ? RecordKind.entity
              : RecordKind.entityType;
          if (!hasKind(
            _reference(objectFields(proposition.payload)['subject']!),
            kind,
          )) {
            throw const FormatException(
              'Attribute mode disagrees with subject kind',
            );
          }
          final scope = objectFields(fields['scope']!);
          final realm = scope['realm'];
          if (!hasKind(
                _reference(scope['context']!),
                RecordKind.representedContext,
              ) ||
              (realm != null &&
                  realm is! CanonicalNull &&
                  !hasKind(_reference(realm), RecordKind.realm))) {
            throw const FormatException(
              'Attribute scope has wrong reference kind',
            );
          }
          final basis = objectFields(fields['basis']!);
          if (_string(basis['kind']) == 'source_anchor' &&
              !hasKind(_reference(basis['anchor']!), RecordKind.anchor)) {
            throw const FormatException('Evidence is not an anchor');
          }
          for (final value
              in (fields['alternatives'] as CanonicalArray?)?.items ??
                  <CanonicalValue>[]) {
            DomainValue.fromWire(value).validate();
          }
        default:
          break;
      }
    }
  }

  void _values(CanonicalValue values) {
    for (final value in objectFields(values).values) {
      DomainValue.fromWire(value).validate();
    }
  }

  String _string(CanonicalValue? value) => (value as CanonicalString).value;
  RecordId? _optionalId(CanonicalValue? value) =>
      value == null || value is CanonicalNull
      ? null
      : RecordId.parse(_string(value));
  RecordId _reference(CanonicalValue value) =>
      RecordRef.fromCanonical(value).record;
}
