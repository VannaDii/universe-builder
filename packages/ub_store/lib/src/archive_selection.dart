import 'package:sqlite3/sqlite3.dart';
import 'package:ub_domain/ub_domain.dart';

import 'journal.dart';
import 'references.dart';

/// Retain identity sets, never an in-memory archive of payloads or asset bytes.
/// Dependencies are closed over every version, including tombstoned history.
Set<RecordId> archiveSelection(
  Database input,
  UniverseId universe,
  Iterable<RecordId> requested,
) {
  // Temporary keyed lookup avoids a full history scan for every included ID.
  input.execute(
    'CREATE TEMP TABLE archive_export_versions(record TEXT NOT NULL, version TEXT NOT NULL, PRIMARY KEY(record,version)) WITHOUT ROWID',
  );
  try {
    final all = <RecordId>{};
    final pending = requested.toSet();
    final attachments = <RecordId, Set<RecordId>>{};
    final journal = SqliteJournal(input, universe);
    final versions = input.prepare(
      'SELECT id,record_id,kind FROM record_versions ORDER BY id',
    );
    try {
      final rows = versions.selectCursor();
      while (rows.moveNext()) {
        final row = rows.current;
        final id = RecordId.parse(row['record_id'] as String);
        all.add(id);
        input.execute('INSERT INTO temp.archive_export_versions VALUES(?,?)', [
          id.value,
          row['id'],
        ]);
        final kind = RecordKind.parse(row['kind'] as String);
        if (const {
          RecordKind.representedContext,
          RecordKind.entityType,
          RecordKind.property,
          RecordKind.relation,
          RecordKind.unit,
          RecordKind.calendar,
          RecordKind.valueDefinition,
          RecordKind.rule,
          RecordKind.domainPack,
          RecordKind.boundary,
          RecordKind.completeness,
          RecordKind.exception,
        }.contains(kind)) {
          pending.add(id);
        }
        if (kind == RecordKind.appearance) {
          final record = journal.load(
            RecordVersionId.parse(row['id'] as String),
          );
          switch (AppearanceRecord.fromWire(record.payload).target) {
            case UniverseAppearance():
              pending.add(id);
            case EntryAppearance(:final entry):
              attachments.putIfAbsent(entry.record, () => {}).add(id);
          }
        }
      }
    } finally {
      versions.close();
    }
    final receipts = input.prepare(
      'SELECT instance_id,assertion_version FROM initialization_receipt',
    );
    try {
      final rows = receipts.selectCursor();
      while (rows.moveNext()) {
        final record = journal.load(
          RecordVersionId.parse(rows.current['assertion_version'] as String),
        );
        if (AssertionRecord.fromWire(record.payload).basis
            is InstanceInitializationBasis) {
          attachments
              .putIfAbsent(
                RecordId.parse(rows.current['instance_id'] as String),
                () => {},
              )
              .add(record.identity.recordId);
        }
      }
    } finally {
      receipts.close();
    }
    final included = <RecordId>{};
    final versionsFor = input.prepare(
      'SELECT version AS id FROM temp.archive_export_versions WHERE record=? ORDER BY version',
    );
    try {
      while (pending.isNotEmpty) {
        final id = pending.first;
        pending.remove(id);
        if (!all.contains(id)) {
          throw const FormatException('Export identity unavailable');
        }
        if (!included.add(id)) continue;
        pending.addAll(attachments[id] ?? const {});
        final rows = versionsFor.selectCursor([id.value]);
        while (rows.moveNext()) {
          final record = journal.load(
            RecordVersionId.parse(rows.current['id'] as String),
          );
          pending.addAll(recordDependencies(record));
        }
      }
    } finally {
      versionsFor.close();
    }
    return Set.unmodifiable(included);
  } finally {
    input.execute('DROP TABLE temp.archive_export_versions');
  }
}
