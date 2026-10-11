import 'package:ub_domain/ub_domain.dart';

import 'catalog.dart';
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
    final fields = objectFields(record.payload);
    String string(String key) => (fields[key] as CanonicalString).value;
    String? optional(String key) =>
        fields[key] == null || fields[key] is CanonicalNull
        ? null
        : string(key);
    switch (record.identity.recordKind) {
      case RecordKind.entityType:
        final applicability = objectFields(fields['applicability']!);
        final kind = (applicability['kind'] as CanonicalString).value;
        database.execute('INSERT INTO type_definition VALUES(?,?,?,?,?,?,?)', [
          u,
          v,
          id,
          string('name'),
          optional('parent'),
          string('parentResolution'),
          switch (kind) {
            'universe_wide' => 'universe',
            'worlds' => 'worlds',
            'unspecified' => 'unspecified',
            'conditional' => 'conditional',
            _ => throw const FormatException('Invalid type applicability'),
          },
        ]);
        if (kind == 'worlds') {
          final worlds = (applicability['world_ids'] as CanonicalArray).items;
          for (var ordinal = 0; ordinal < worlds.length; ordinal++) {
            database.execute('INSERT INTO type_world VALUES(?,?,?,?)', [
              u,
              v,
              ordinal,
              worldRecord(
                WorldId.parse((worlds[ordinal] as CanonicalString).value),
              ).value,
            ]);
          }
        }
      case RecordKind.entity:
        database.execute(
          'INSERT INTO instance_classification VALUES(?,?,?,?,?)',
          [
            u,
            v,
            id,
            optional('classification'),
            string('classificationResolution'),
          ],
        );
      case RecordKind.assertion:
        final mode = string('attributeMode');
        if (mode == 'instance') return;
        final reference = RecordRef.fromCanonical(fields['proposition']!);
        final version = membership[reference.record];
        if (version == null) {
          throw const FormatException('Missing definition proposition');
        }
        final proposition = journal.load(version);
        if (proposition.identity.recordKind != RecordKind.proposition) {
          throw const FormatException('Invalid definition proposition');
        }
        final body = objectFields(proposition.payload);
        database.execute('INSERT INTO definition_attribute VALUES(?,?,?,?,?)', [
          u,
          v,
          RecordRef.fromCanonical(body['subject']!).record.value,
          RecordRef.fromCanonical(body['predicate']!).record.value,
          switch (mode) {
            'shared' => 'shared',
            'initial_value' => 'initial_value',
            _ => throw const FormatException(
              'Invalid definition attribute mode',
            ),
          },
        ]);
      default:
        break;
    }
  }
}
