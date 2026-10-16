import 'dart:io';
import 'dart:typed_data';

import 'package:postgres/postgres.dart';
import 'package:ub_domain/ub_domain.dart';

import 'archive_checksum.dart';
import 'database.dart' show maxPackageBytes;
import 'owned_database.dart';
import 'ownership.dart';
import 'postgres_canonical_integrity.dart';
import 'postgres_journal.dart';
import 'postgres_values.dart';
import 'postgres_workflow_storage.dart';
import 'relational.dart';
import 'revision_input.dart';
import 'workflow_storage.dart';

/// Bounded backend transfer into the existing trusted logical archive format.
/// The caller holds installation authority and owns the PostgreSQL transaction.
/// PostgreSQL row pointers are translated; installation credentials are excluded.
final class PostgresLogicalExport {
  PostgresLogicalExport(this._session, this.universe)
    : _schema = postgresUniverseSchema(universe);
  final TxSession _session;
  final UniverseId universe;
  final String _schema;
  var _rowsRead = 0;

  Stream<Map<String, dynamic>> _rows(
    String table,
    List<String> columns,
  ) async* {
    final cursor = 'ub_export_${OperationId.generate().value}';
    final selected = columns.map(quoteIdentifier).join(',');
    await _session.execute(
      'DECLARE $cursor NO SCROLL CURSOR FOR SELECT $selected FROM $_schema.${quoteIdentifier(table)} ORDER BY $selected',
    );
    try {
      while (true) {
        final rows = await _session.execute('FETCH FORWARD 64 FROM $cursor');
        if (rows.isEmpty) break;
        for (final row in rows) {
          if (++_rowsRead > maxArchiveRows) {
            throw const FormatException('Archive row budget exceeded');
          }
          yield row.toColumnMap();
        }
      }
    } finally {
      await _session.execute('CLOSE $cursor');
    }
  }

  Stream<StoredVersion> _versions(PostgresJournal journal) async* {
    var batch = <RecordVersionId>[];
    await for (final row in _rows('record_versions', ['id'])) {
      batch.add(RecordVersionId.parse(row['id'] as String));
      if (batch.length == 50) {
        yield* journal.loadMany(batch);
        batch = [];
      }
    }
    yield* journal.loadMany(batch);
  }

  Future<CanonicalObject> export(
    String destination, {
    Iterable<RecordId> recordIds = const [],
    bool completeHistory = false,
  }) => _snapshot(
    destination,
    recordIds: recordIds,
    completeHistory: completeHistory,
  );

  /// Portable retained-history backup in the existing trusted package schema.
  /// Unlike a logical archive, this includes no archive manifest/checksum tables.
  Future<CanonicalObject> backup(String destination) =>
      _snapshot(destination, backup: true);

  Future<CanonicalObject> _snapshot(
    String destination, {
    Iterable<RecordId> recordIds = const [],
    bool completeHistory = false,
    bool backup = false,
  }) async {
    final requested = recordIds.toList();
    if (completeHistory && requested.isNotEmpty) {
      throw const FormatException(
        'Complete-history export requires all records',
      );
    }
    await PostgresCanonicalIntegrity(_session, universe).verifyComplete();
    final target = File(destination).absolute;
    final temporary = privateTemporaryDirectory(
      target.parent.path,
      '.postgres-export-',
    );
    OwnedSqliteDatabase? snapshot;
    try {
      privateDirectory(temporary.path);
      final path = '${temporary.path}/snapshot.sqlite';
      snapshot = OwnedSqliteDatabase.create(path);
      final db = snapshot.database;
      final codec = RelationalCodec(db);
      final journal = PostgresJournal(_session, universe);
      final workflow = PostgresWorkflowStorage(_session, universe);
      final output = WorkflowStorage(db);
      void budget() {
        final wal = File('$path-wal');
        if (File(path).lengthSync() +
                (wal.existsSync() ? wal.lengthSync() : 0) >
            (backup ? maxPackageBytes : maxArchiveBytes)) {
          throw FormatException(
            backup
                ? 'Backup byte budget exceeded'
                : 'Archive byte budget exceeded',
          );
        }
      }

      Future<void> copy(String table) async {
        final info = db.select('PRAGMA table_info(${quoteIdentifier(table)})');
        final columns = info.map((r) => r['name'] as String).toList();
        final types = {
          for (final r in info) r['name'] as String: r['type'] as String,
        };
        final statement = db.prepare(
          'INSERT INTO ${quoteIdentifier(table)} (${columns.map(quoteIdentifier).join(',')}) VALUES (${List.filled(columns.length, '?').join(',')})',
        );
        try {
          await for (final row in _rows(table, columns)) {
            statement.execute([
              for (final column in columns)
                if (row[column] is Uint8List && types[column] == 'TEXT')
                  readPostgresAuthoredText(row[column] as Uint8List)
                else if (row[column] is bool)
                  row[column] == true ? 1 : 0
                else
                  row[column],
            ]);
            budget();
          }
        } finally {
          statement.close();
        }
      }

      db.execute('BEGIN IMMEDIATE; PRAGMA defer_foreign_keys=ON');
      try {
        await copy('universes');
        await copy('record_identities');
        await for (final record in _versions(journal)) {
          if (record.toCanonical().toBytes().length > 1048576) {
            throw const FormatException('Archive record too large');
          }
          final payload = codec.put('Payload', record.payload);
          db.execute('INSERT INTO record_versions VALUES(?,?,?,?,?,?)', [
            universe.value,
            record.versionId.value,
            record.identity.recordId.value,
            record.identity.recordKind.wireName,
            payload,
            record.digest,
          ]);
          budget();
        }
        for (final table in [
          'import_record_digest',
          'continuities',
          'commits',
          'commit_changes',
          'world_name_reservations',
          'type_definition',
          'type_world',
          'instance_classification',
          'classification_evidence',
          'definition_attribute',
          'initialization_receipt',
          'operation_receipts',
          'historical_receipt',
        ]) {
          await copy(table);
        }
        // Read all evidence, including rows hidden from active authorization.
        await for (final row in _rows('workflow_index', ['key'])) {
          final key = readPostgresAuthoredText(row['key'] as Uint8List);
          final value = await workflow.evidence(key);
          if (value == null) {
            throw const FormatException('Missing historical workflow');
          }
          output.put(key, value);
          budget();
        }
        await copy('historical_workflow');
        db.execute('COMMIT');
      } on Object {
        if (!db.autocommit) db.execute('ROLLBACK');
        rethrow;
      }
      snapshot.recover();
      if (backup) {
        snapshot.backup(destination);
        return CanonicalObject([
          MapEntry('backup', CanonicalString(destination)),
          MapEntry('universe_id', CanonicalString(universe.value)),
          const MapEntry('verified', CanonicalBool(true)),
        ]);
      }
      return snapshot.exportLogical(
        destination,
        recordIds: requested,
        completeHistory: completeHistory,
      );
    } finally {
      snapshot?.close();
      temporary.deleteSync(recursive: true);
    }
  }
}
