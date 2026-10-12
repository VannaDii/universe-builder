@TestOn('vm')
library;

import 'dart:io';

import 'package:sqlite3/sqlite3.dart' show sqlite3, OpenMode;
import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/sqlite.dart';
import 'package:ub_store/src/archive_checksum.dart';
import 'package:ub_store/src/ownership.dart';
import 'package:ub_store/src/relational.dart';

void main() {
  late Directory root;
  late OwnedSqliteDatabase source;
  late UniverseId universe;
  late ContinuityId continuity;
  late RevisionId revision;
  setUp(() {
    root = Directory.systemTemp.createTempSync('universe-builder-archive-');
    privateDirectory(root.path);
    source = OwnedSqliteDatabase.create('${root.path}/source.sqlite');
    universe = UniverseId.generate();
    continuity = ContinuityId.generate();
    source.database.execute('BEGIN IMMEDIATE');
    revision = SqliteJournal(
      source.database,
      universe,
    ).initialize('Archive é😀', continuity, PrincipalId.generate());
    WorkflowStorage(source.database).put(
      'cursor:one',
      CanonicalValue.parseJson('{"binding":"exact binding","offset":0}'),
    );
    source.database.execute('COMMIT');
  });
  tearDown(() {
    source.close();
    root.deleteSync(recursive: true);
  });
  String export() {
    final path = '${root.path}/archive.sqlite';
    source.exportCompleteHistory(path);
    return path;
  }

  void noStages() => expect(
    root.listSync().where(
      (entry) => entry.uri.pathSegments.any(
        (part) =>
            part.startsWith('.logical-archive-') ||
            part.startsWith('.logical-import-') ||
            part.startsWith('.relational-export-'),
      ),
    ),
    isEmpty,
  );

  test('complete history publishes verified manifest and exact workflow without mutating source', () {
    final path = export();
    final original = File(path).readAsBytesSync();
    final verified = OwnedSqliteDatabase.stageLogicalArchive(path, root.path);
    final stagePath = verified.package.path;
    try {
      final manifest = WireFields(verified.manifest, {
        'format',
        'universe',
        'name',
        'complete',
        'omitted_records',
        'includes_history',
        'includes_workflow',
      });
      expect(manifest.string('format'), 'universe-relational');
      expect(manifest.string('universe'), universe.value);
      expect(manifest.string('name'), 'Archive é😀');
      expect(manifest.boolean('complete'), isTrue);
      expect(manifest.boolean('includes_history'), isTrue);
      expect(manifest.boolean('includes_workflow'), isTrue);
      expect(manifest.u64('omitted_records'), BigInt.zero);
      expect(verified.package.universeId, universe);
      expect(
        SqliteJournal(verified.package.database, universe).head(continuity),
        revision,
      );
      expect(
        WorkflowStorage(verified.package.database).get('cursor:one')!.toText(),
        WorkflowStorage(source.database).get('cursor:one')!.toText(),
      );
      final db = sqlite3.open(path, mode: OpenMode.readOnly);
      try {
        final checksum = archiveChecksum(db);
        final header = db.select('SELECT * FROM archive_integrity').single;
        expect(header['sha256'], checksum.digest);
        expect(header['row_count'], checksum.rows);
        expect(
          verified.digest,
          archiveReviewDigest(
            checksum.digest,
            canonicalDigest(verified.manifest),
          ),
        );
      } finally {
        db.close();
      }
    } finally {
      verified.close();
    }
    verified.close();
    expect(File(stagePath).existsSync(), isFalse);
    expect(File(path).readAsBytesSync(), orderedEquals(original));
    expect(SqliteJournal(source.database, universe).head(continuity), revision);
    noStages();
  });

  test('identity-preserving import strips archive metadata and keeps imported workflow historical', () {
    final path = export();
    final original = File(path).readAsBytesSync();
    final archive = OwnedSqliteDatabase.stageLogicalArchive(path, root.path);
    final stage = archive.stageRestore(root.path, name: 'Imported name');
    final stagedPath = stage.package.path;
    try {
      final copy = stage.package;
      expect(copy.universeId, universe);
      expect(SqliteJournal(copy.database, universe).head(continuity), revision);
      expect(
        copy.database.select('SELECT name FROM universes').single['name'],
        'Imported name',
      );
      expect(
        copy.database
            .select(
              "SELECT count(*) AS n FROM sqlite_master WHERE name='archive_integrity'",
            )
            .single['n'],
        0,
      );
      expect(
        copy.database
            .select('SELECT count(*) AS n FROM r_archive_manifest')
            .single['n'],
        0,
      );
      final workflow = WorkflowStorage(copy.database);
      expect(workflow.get('cursor:one'), isNull);
      expect(
        workflow.evidence('cursor:one')!.toText(),
        WorkflowStorage(source.database).get('cursor:one')!.toText(),
      );
      expect(workflow.keys('logical-import-origin:'), hasLength(1));
      final origin = WireFields(
        workflow.get('logical-import-origin:${archive.digest}')!,
        {
          'digest',
          'source_universe',
          'target_universe',
          'complete',
          'omitted_records',
        },
      );
      expect(origin.string('digest'), archive.digest);
      expect(origin.string('source_universe'), universe.value);
      expect(origin.string('target_universe'), universe.value);
      expect(origin.boolean('complete'), isTrue);
      expect(
        WorkflowStorage(archive.package.database).get('cursor:one'),
        isNotNull,
      );
      final backupPath = '${root.path}/imported.sqlite';
      copy.backup(backupPath);
      final reopened = OwnedSqliteDatabase.openExisting(backupPath);
      try {
        reopened.recover();
        expect(WorkflowStorage(reopened.database).get('cursor:one'), isNull);
        expect(
          SqliteJournal(reopened.database, universe).head(continuity),
          revision,
        );
      } finally {
        reopened.close();
      }
    } finally {
      stage.close();
      archive.close();
    }
    expect(File(stagedPath).existsSync(), isFalse);
    expect(File(path).readAsBytesSync(), orderedEquals(original));
    noStages();
  });

  test('invalid import names and closed archives refuse staging before directory creation', () {
    final path = export();
    final archive = OwnedSqliteDatabase.stageLogicalArchive(path, root.path);
    final scratch = '${root.path}/absent-staging';
    expect(
      () => archive.stageRestore(scratch, name: ' '),
      throwsFormatException,
    );
    expect(Directory(scratch).existsSync(), isFalse);
    archive.close();
    expect(
      () => archive.stageRestore(scratch, name: 'Closed'),
      throwsStateError,
    );
    expect(Directory(scratch).existsSync(), isFalse);
    noStages();
  });

  test(
    'failed imported evidence validation deletes only the unpublished stage',
    () {
      final path = export();
      final original = File(path).readAsBytesSync();
      final archive = OwnedSqliteDatabase.stageLogicalArchive(path, root.path);
      try {
        archive.package.database.execute(
          'DROP TRIGGER workflow_entries_no_update',
        );
        archive.package.database.execute(
          'UPDATE workflow_entries SET digest=?',
          ['0' * 64],
        );
        expect(
          () => archive.stageRestore(root.path, name: 'Rejected'),
          throwsFormatException,
        );
        expect(
          root.listSync().where(
            (entry) => entry.uri.pathSegments.any(
              (part) => part.startsWith('.logical-import-'),
            ),
          ),
          isEmpty,
        );
        expect(File(path).readAsBytesSync(), orderedEquals(original));
        expect(File(archive.package.path).existsSync(), isTrue);
      } finally {
        archive.close();
      }
      noStages();
    },
  );

  test('filtered and canon-only archives refuse the retained-history restore path before staging IO', () {
    final empty = OwnedSqliteDatabase.create('${root.path}/empty.sqlite');
    try {
      empty.database.execute('BEGIN IMMEDIATE');
      SqliteJournal(empty.database, UniverseId.generate()).initialize(
        'Canon only',
        ContinuityId.generate(),
        PrincipalId.generate(),
      );
      empty.database.execute('COMMIT');
      for (final complete in [true, false]) {
        final path = '${root.path}/canon-only-$complete.sqlite';
        empty.exportCompleteHistory(path);
        final db = sqlite3.open(path, mode: OpenMode.readWrite);
        try {
          db.execute('BEGIN IMMEDIATE');
          final codec = RelationalCodec(db);
          final old = codec.get(
            'ArchiveManifest',
            db
                .select('SELECT manifest_row FROM archive_integrity')
                .single['manifest_row'],
          ) as CanonicalObject;
          final replacements = <String, CanonicalValue>{
            'includes_workflow': const CanonicalBool(false),
            'complete': CanonicalBool(complete),
            'omitted_records': CanonicalNumber(complete ? '0' : '1'),
          };
          final manifest = CanonicalObject(
            old.fields.map(
              (entry) =>
                  MapEntry(entry.key, replacements[entry.key] ?? entry.value),
            ),
          );
          final guard =
              db
                      .select(
                        "SELECT sql FROM sqlite_master WHERE name='r_archive_manifest_no_delete'",
                      )
                      .single['sql']
                  as String;
          db.execute(
            'DROP TRIGGER r_archive_manifest_no_delete; DELETE FROM archive_integrity; DELETE FROM r_archive_manifest',
          );
          db.execute(guard);
          final row = codec.put('ArchiveManifest', manifest);
          final checksum = archiveChecksum(db);
          db.execute(
            "INSERT INTO archive_integrity VALUES(1,?,'typed-row-stream',?,?,'historical_evidence_only',?)",
            [row, checksum.digest, checksum.rows, canonicalDigest(manifest)],
          );
          db.execute('COMMIT');
        } finally {
          db.close();
        }
        final original = File(path).readAsBytesSync();
        final verified = OwnedSqliteDatabase.stageLogicalArchive(
          path,
          root.path,
        );
        final scratch = '${root.path}/unsupported-$complete';
        try {
          expect(
            () =>
                verified.stageRestore(scratch, name: 'Requires reconstruction'),
            throwsFormatException,
          );
          expect(Directory(scratch).existsSync(), isFalse);
          expect(File(path).readAsBytesSync(), orderedEquals(original));
        } finally {
          verified.close();
        }
      }
    } finally {
      empty.close();
    }
    noStages();
  });

  test('export refuses existing destinations and source remains available', () {
    final target = File('${root.path}/existing.sqlite')
      ..writeAsStringSync('Existing data');
    expect(
      () => source.exportCompleteHistory(target.path),
      throwsA(isA<FileSystemException>()),
    );
    expect(target.readAsStringSync(), 'Existing data');
    expect(SqliteJournal(source.database, universe).head(continuity), revision);
    noStages();
  });

  test('schema checksum manifest and authority tampering are refused without changing input', () {
    final path = export();
    for (final mutation in [
      'CREATE TABLE untrusted(value TEXT)',
      "UPDATE archive_integrity SET sha256=printf('%064d',0)",
      'UPDATE archive_integrity SET row_count=row_count+1',
      "UPDATE archive_integrity SET manifest_sha256=printf('%064d',0)",
    ]) {
      final copyPath = '${root.path}/tampered-${mutation.hashCode}.sqlite';
      File(path).copySync(copyPath);
      protectedFile(copyPath);
      final db = sqlite3.open(copyPath, mode: OpenMode.readWrite);
      try {
        db.execute(mutation);
      } finally {
        db.close();
      }
      final original = File(copyPath).readAsBytesSync();
      expect(
        () => OwnedSqliteDatabase.stageLogicalArchive(copyPath, root.path),
        throwsFormatException,
      );
      expect(File(copyPath).readAsBytesSync(), orderedEquals(original));
      noStages();
    }
  });

  test(
    'rechecksummed canon-only manifest cannot disguise retained workflow',
    () {
      final path = export();
      final db = sqlite3.open(path, mode: OpenMode.readWrite);
      try {
        db.execute('BEGIN IMMEDIATE');
        final codec = RelationalCodec(db);
        final manifest = codec.get(
          'ArchiveManifest',
          db
              .select('SELECT manifest_row FROM archive_integrity')
              .single['manifest_row'],
        ) as CanonicalObject;
        final changed = CanonicalObject(
          manifest.fields.map(
            (entry) => entry.key == 'includes_workflow'
                ? const MapEntry('includes_workflow', CanonicalBool(false))
                : entry,
          ),
        );
        final guard =
            db
                    .select(
                      "SELECT sql FROM sqlite_master WHERE name='r_archive_manifest_no_delete'",
                    )
                    .single['sql']
                as String;
        db.execute(
          'DROP TRIGGER r_archive_manifest_no_delete; DELETE FROM archive_integrity; DELETE FROM r_archive_manifest',
        );
        db.execute(guard);
        final row = codec.put('ArchiveManifest', changed);
        final checksum = archiveChecksum(db);
        db.execute(
          "INSERT INTO archive_integrity VALUES(1,?,'typed-row-stream',?,?,'historical_evidence_only',?)",
          [row, checksum.digest, checksum.rows, canonicalDigest(changed)],
        );
        db.execute('COMMIT');
      } finally {
        db.close();
      }
      final original = File(path).readAsBytesSync();
      expect(
        () => OwnedSqliteDatabase.stageLogicalArchive(path, root.path),
        throwsFormatException,
      );
      expect(File(path).readAsBytesSync(), orderedEquals(original));
      noStages();
    },
  );

  test('oversized and symlink archives fail before scratch creation', () {
    final oversized = '${root.path}/oversized.sqlite';
    protectedFile(oversized, createNew: true);
    final file = File(oversized).openSync(mode: FileMode.writeOnly);
    try {
      file.truncateSync(maxArchiveBytes + 1);
    } finally {
      file.closeSync();
    }
    final scratch = '${root.path}/absent-scratch';
    expect(
      () => OwnedSqliteDatabase.stageLogicalArchive(oversized, scratch),
      throwsFormatException,
    );
    expect(Directory(scratch).existsSync(), isFalse);
    final archive = export();
    final link = Link('${root.path}/linked.sqlite')..createSync(archive);
    expect(
      () => OwnedSqliteDatabase.stageLogicalArchive(link.path, scratch),
      throwsA(isA<FileSystemException>()),
    );
    expect(Directory(scratch).existsSync(), isFalse);
    noStages();
  });
}
