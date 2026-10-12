@TestOn('vm')
library;

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/sqlite.dart';
import 'package:ub_store/ub_store.dart';
import 'package:ub_store/src/package_conversion.dart';

void main() {
  late Directory root;
  late String source, destination;
  late UniverseId universe;
  late ContinuityId continuity;
  late RevisionId head;
  late StoredVersion entity;
  setUp(() {
    root = Directory.systemTemp.createTempSync(
      'universe-builder-package-conversion-',
    );
    source = '${root.path}/source.sqlite';
    destination = '${root.path}/converted.sqlite';
    universe = UniverseId.generate();
    continuity = ContinuityId.generate();
    final original = OwnedSqliteDatabase.create(source);
    try {
      final kernel = SqliteKernel(original.database, universe);
      final principal = PrincipalId.generate();
      original.database.execute('BEGIN IMMEDIATE');
      final genesis = kernel.journal.initialize(
        'Retained universe',
        continuity,
        principal,
      );
      WorkflowStorage(original.database).put(
        'cursor:retained',
        CanonicalValue.parseJson('{"offset":17,"binding":"é😀"}'),
      );
      original.database.execute('COMMIT');
      entity = StoredVersion.build(
        RecordVersionId.generate(),
        RecordIdentity(
          universeId: universe,
          recordId: RecordId.generate(),
          recordKind: RecordKind.entity,
        ),
        EntityRecord(
          names: [],
          worldAssociations: [],
          labels: {},
          metadata: {},
          classificationResolution: ClassificationResolution.unclassified,
        ).toWire(),
      );
      head = kernel.commit(
        CommitInput(
          universe: universe,
          continuity: continuity,
          expectedHead: genesis,
          principal: principal,
          decision: 'Exact decision',
          reason: 'Exact reason',
          idempotencyKey: 'exact-original-receipt',
          changes: [
            Assignment(recordId: entity.identity.recordId, next: entity),
          ],
        ),
      );
      original.database.execute(
        'PRAGMA wal_checkpoint(TRUNCATE); PRAGMA journal_mode=DELETE',
      );
    } finally {
      original.close();
    }
  });
  tearDown(() => root.deleteSync(recursive: true));
  void noStages() => expect(
    root.listSync().where(
      (entry) => entry.uri.pathSegments.any(
        (part) => part.startsWith('.operator-conversion-'),
      ),
    ),
    isEmpty,
  );
  void edit(void Function(Database) action) {
    final database = sqlite3.open(source);
    try {
      action(database);
    } finally {
      database.close();
    }
  }

  test('offline relational conversion preserves exact history workflow authority and original bytes', () {
    final bytes = File(source).readAsBytesSync();
    expect(Process.runSync('chmod', ['400', source]).exitCode, 0);
    final report = convertPackage(source, destination).toText();
    expect(report, contains(sha256.convert(bytes).toString()));
    expect(report, contains('"records":1'));
    expect(report, contains('"workflows":1'));
    expect(File(source).readAsBytesSync(), orderedEquals(bytes));
    expect(File(source).statSync().mode & 0x1ff, 0x100);
    final target = OwnedSqliteDatabase.openExisting(destination);
    try {
      target.recover();
      final journal = SqliteJournal(target.database, universe);
      expect(journal.head(continuity), head);
      expect(
        journal.load(entity.versionId).toCanonical().toText(),
        entity.toCanonical().toText(),
      );
      expect(
        WorkflowStorage(target.database).get('cursor:retained')!.toText(),
        '{"binding":"é😀","offset":17}',
      );
      expect(
        target.database
            .select('SELECT count(*) AS n FROM historical_workflow')
            .single['n'],
        0,
      );
      expect(
        target.database
            .select('SELECT count(*) AS n FROM historical_receipt')
            .single['n'],
        0,
      );
      expect(
        target.database
            .select('SELECT idempotency_key FROM operation_receipts')
            .single['idempotency_key'],
        'exact-original-receipt',
      );
    } finally {
      target.close();
    }
    noStages();
  });

  test(
    'recognizes only the maintained missing workflow-provenance table variant',
    () {
      edit((db) => db.execute('DROP TABLE import_workflow_digest'));
      final bytes = File(source).readAsBytesSync();
      convertPackage(source, destination);
      final target = OwnedSqliteDatabase.openExisting(destination);
      try {
        target.recover();
        expect(
          target.database
              .select('SELECT count(*) AS n FROM import_workflow_digest')
              .single['n'],
          0,
        );
        expect(SqliteJournal(target.database, universe).head(continuity), head);
      } finally {
        target.close();
      }
      expect(File(source).readAsBytesSync(), orderedEquals(bytes));
      noStages();
    },
  );

  test('unknown schema and corrupt retained body are rejected without target publication', () {
    edit((db) => db.execute('CREATE TABLE unrecognized_evidence(value TEXT)'));
    expect(() => convertPackage(source, destination), throwsFormatException);
    expect(File(destination).existsSync(), isFalse);
    noStages();
    edit((db) {
      db.execute('DROP TABLE unrecognized_evidence');
      final triggers = db.select(
        "SELECT name,sql FROM sqlite_master WHERE type='trigger' AND tbl_name='record_versions'",
      );
      for (final trigger in triggers) {
        db.execute(
          'DROP TRIGGER "${(trigger['name'] as String).replaceAll('"', '""')}"',
        );
      }
      db.execute("UPDATE record_versions SET digest='broken'");
      for (final trigger in triggers) {
        db.execute(trigger['sql'] as String);
      }
    });
    expect(() => convertPackage(source, destination), throwsFormatException);
    expect(File(destination).existsSync(), isFalse);
    noStages();
  });

  test('source replacement immediately before publication is detected', () {
    final bytes = File(source).readAsBytesSync();
    expect(
      () => convertPackageWithHook(source, destination, (point) {
        if (point != PackageConversionPoint.beforePublish) return;
        File(source).renameSync('$source.retained');
        File('$source.retained').copySync(source);
        edit((db) => db.execute("UPDATE universes SET name='Changed source'"));
      }),
      throwsFormatException,
    );
    expect(File(destination).existsSync(), isFalse);
    expect(File('$source.retained').readAsBytesSync(), orderedEquals(bytes));
    noStages();
  });

  test('publication race and interruption preserve existing destinations and clean private staging', () {
    final bytes = File(source).readAsBytesSync();
    expect(
      () => convertPackageWithHook(source, destination, (point) {
        if (point == PackageConversionPoint.verified) {
          throw StateError('Interrupted before publication');
        }
      }),
      throwsStateError,
    );
    expect(File(destination).existsSync(), isFalse);
    noStages();
    expect(
      () => convertPackageWithHook(source, destination, (point) {
        if (point == PackageConversionPoint.beforePublish) {
          File(destination).writeAsStringSync('Retain raced destination');
        }
      }),
      throwsA(isA<FileSystemException>()),
    );
    expect(File(destination).readAsStringSync(), 'Retain raced destination');
    expect(() => convertPackage(source, destination), throwsFormatException);
    expect(File(source).readAsBytesSync(), orderedEquals(bytes));
    noStages();
  });
}
