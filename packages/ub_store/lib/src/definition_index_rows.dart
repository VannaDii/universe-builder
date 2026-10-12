import 'package:ub_domain/ub_domain.dart';

import 'journal.dart' show Membership;
import 'references.dart';
import 'revision_input.dart';

/// Fixed relational projections of an admitted version. Definition references
/// resolve against the selected candidate, never labels or a later head.
Iterable<(String, List<Object?>)> definitionIndexRows(
  StoredVersion record,
  Membership membership,
  StoredVersion Function(RecordVersionId) load,
) sync* {
  final u = record.identity.universeId.value;
  final v = record.versionId.value;
  final id = record.identity.recordId.value;
  switch (record.identity.recordKind) {
    case RecordKind.entityType:
      final type = EntityTypeRecord.fromWire(record.payload);
      final applicability = type.applicability;
      yield (
        'type_definition',
        <Object?>[
          u,
          v,
          id,
          type.name,
          type.parent?.value,
          type.parentResolution.name,
          switch (applicability) {
            UniverseApplicability() => 'universe',
            WorldsApplicability() => 'worlds',
            UnspecifiedApplicability() => 'unspecified',
            ConditionalApplicability() => 'conditional',
          },
        ],
      );
      if (applicability is WorldsApplicability) {
        final worlds = applicability.worldIds;
        for (var ordinal = 0; ordinal < worlds.length; ordinal++) {
          yield (
            'type_world',
            <Object?>[u, v, ordinal, worldRecord(worlds[ordinal]).value],
          );
        }
      }
    case RecordKind.entity:
      final entity = EntityRecord.fromWire(record.payload);
      yield (
        'instance_classification',
        <Object?>[
          u,
          v,
          id,
          entity.classification?.value,
          entity.classificationResolution.name,
        ],
      );
    case RecordKind.assertion:
      final assertion = AssertionRecord.fromWire(record.payload);
      final mode = assertion.attributeMode;
      if (mode == AttributeMode.instance) return;
      final reference = assertion.proposition;
      final version = membership[reference.record];
      if (version == null) {
        throw const FormatException('Missing definition proposition');
      }
      final proposition = load(version);
      if (proposition.identity.recordKind != RecordKind.proposition) {
        throw const FormatException('Invalid definition proposition');
      }
      final body = PropositionRecord.fromWire(proposition.payload);
      yield (
        'definition_attribute',
        <Object?>[
          u,
          v,
          body.subject.record.value,
          body.predicate.record.value,
          mode.wireName,
        ],
      );
    default:
      break;
  }
}
