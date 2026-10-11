import 'package:ub_domain/ub_domain.dart';

import 'journal.dart';
import 'references.dart';
import 'revision_input.dart';

/// Immutable semantic indexes over admitted versions. References resolve in
/// the selected candidate, never against labels or a later head.
final class DefinitionIndex {
  DefinitionIndex(this.journal);
  final SqliteJournal journal;

  void index(StoredVersion record, Membership membership) {
    final database = journal.database;
    if (database.autocommit) {
      throw StateError('Definition indexes require an owned transaction');
    }
    if (record.identity.universeId != journal.universe) {
      throw const FormatException('Definition index universe mismatch');
    }
    final u = journal.universe.value;
    final v = record.versionId.value;
    final id = record.identity.recordId.value;
    switch (record.identity.recordKind) {
      case RecordKind.entityType:
        final type = EntityTypeRecord.fromWire(record.payload);
        final applicability = type.applicability;
        database.execute('INSERT INTO type_definition VALUES(?,?,?,?,?,?,?)', [
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
        ]);
        if (applicability is WorldsApplicability) {
          final worlds = applicability.worldIds;
          for (var ordinal = 0; ordinal < worlds.length; ordinal++) {
            database.execute('INSERT INTO type_world VALUES(?,?,?,?)', [
              u,
              v,
              ordinal,
              worldRecord(worlds[ordinal]).value,
            ]);
          }
        }
      case RecordKind.entity:
        final entity = EntityRecord.fromWire(record.payload);
        database.execute(
          'INSERT INTO instance_classification VALUES(?,?,?,?,?)',
          [
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
        final proposition = journal.load(version);
        if (proposition.identity.recordKind != RecordKind.proposition) {
          throw const FormatException('Invalid definition proposition');
        }
        final body = PropositionRecord.fromWire(proposition.payload);
        database.execute('INSERT INTO definition_attribute VALUES(?,?,?,?,?)', [
          u,
          v,
          body.subject.record.value,
          body.predicate.record.value,
          mode.wireName,
        ]);
      default:
        break;
    }
  }
}
