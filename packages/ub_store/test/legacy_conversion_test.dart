@TestOn('vm')
library;

import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/sqlite.dart';
import 'package:ub_store/ub_store.dart';
import 'package:ub_store/src/ownership.dart';

void main() {
  late Directory root;
  late String source;
  late UniverseId universe;
  late StoredVersion first, second;
  setUp(() {
    root = Directory.systemTemp.createTempSync('universe-builder-legacy-');
    privateDirectory(root.path);
    source = '${root.path}/legacy.sqlite';
    protectedFile(source, createNew: true);
    universe = UniverseId.generate();
    final record = RecordId.generate();
    StoredVersion version(String label) => StoredVersion.build(
      RecordVersionId.generate(),
      RecordIdentity(
        universeId: universe,
        recordId: record,
        recordKind: RecordKind.representedContext,
      ),
      RepresentedContextRecord(
        universe: universe,
        kind: const ObjectiveContext(),
        labels: {'name': label},
      ).toWire(),
    );
    first = version('Earlier é😀');
    second = version('Later');
    final db = sqlite3.open(source);
    try {
      db.execute(
        File('../../crates/universe-store/src/schema_v0.sql')
            .readAsStringSync(),
      );
      db.execute('INSERT INTO universes(id,name,created_at) VALUES(?,?,?)', [
        universe.value,
        'Legacy',
        'then',
      ]);
      db.execute(
        'INSERT INTO record_identities(id,universe_id,kind,created_at) VALUES(?,?,?,?)',
        [record.value, universe.value, 'represented_context', 'then'],
      );
      for (final version in [first, second]) {
        db.execute(
          'INSERT INTO record_versions(id,record_id,universe_id,kind,payload,digest,created_at) VALUES(?,?,?,?,?,?,?)',
          [
            version.versionId.value,
            record.value,
            universe.value,
            'represented_context',
            version.payload.toBytes(),
            version.digest,
            'then',
          ],
        );
      }
      for (final (id, parent) in [
        ('old-first', null),
        ('old-second', 'old-first'),
        ('old-third', 'old-second'),
      ]) {
        db.execute(
          'INSERT INTO commits(id,universe_id,continuity_id,parent_id,author,reason,created_at) VALUES(?,?,?,?,?,?,?)',
          [
            id,
            universe.value,
            'cont_main',
            parent,
            'Original author',
            'Original $id',
            'then',
          ],
        );
      }
      db.execute('INSERT INTO commit_changes VALUES(?,?,?,?,?)', [
        'change-first',
        'old-first',
        record.value,
        'create',
        first.versionId.value,
      ]);
      db.execute('INSERT INTO commit_changes VALUES(?,?,?,?,?)', [
        'change-second',
        'old-second',
        record.value,
        'replace',
        second.versionId.value,
      ]);
      db.execute('INSERT INTO commit_changes VALUES(?,?,?,?,?)', [
        'change-third',
        'old-third',
        record.value,
        'tombstone',
        null,
      ]);
      db.execute('INSERT INTO continuities VALUES(?,?,?,?,?,?)', [
        'cont_main',
        universe.value,
        'old-third',
        null,
        'then',
        'then',
      ]);
    } finally {
      db.close();
    }
  });
  tearDown(() => root.deleteSync(recursive: true));
  void noStages() => expect(
    root.listSync().where(
      (entry) => entry.uri.pathSegments.any(
        (part) =>
            part.startsWith('.legacy-conversion-') ||
            part.startsWith('.relational-export-') ||
            part.startsWith('.logical-archive-'),
      ),
    ),
    isEmpty,
  );
  test('explicit legacy conversion preserves typed versions tombstones and source bytes with visible history mappings', () {
    final original = File(source).readAsBytesSync();
    final destination = '${root.path}/converted.sqlite';
    final report = WireFields(convertLegacy(source, destination, root.path), {
      'converted',
      'canonical',
      'universe',
      'continuity_mapping',
      'revision_mapping',
      'record_and_version_ids',
      'workflow_authority',
      'next_step',
    });
    expect(report.boolean('converted'), isTrue);
    expect(report.boolean('canonical'), isFalse);
    final continuity = ContinuityId.parse(
      wireString(
        WireFields(report.require('continuity_mapping'), {
          'cont_main',
        }).require('cont_main'),
      ),
    );
    final revisions = WireFields(report.require('revision_mapping'), {
      'old-first',
      'old-second',
      'old-third',
    });
    final archive = OwnedSqliteDatabase.stageLogicalArchive(
      destination,
      root.path,
    );
    final staged = archive.reconstruct(
      root.path,
      target: universe,
      name: 'Restored',
    );
    try {
      final journal = SqliteJournal(staged.package.database, universe);
      expect(
        journal.load(first.versionId).toCanonical().toText(),
        first.toCanonical().toText(),
      );
      expect(
        journal.load(second.versionId).toCanonical().toText(),
        second.toCanonical().toText(),
      );
      expect(
        journal.snapshot(
          continuity,
          RevisionId.parse(revisions.string('old-first')),
        )[first.identity.recordId],
        first.versionId,
      );
      expect(
        journal.snapshot(
          continuity,
          RevisionId.parse(revisions.string('old-second')),
        )[first.identity.recordId],
        second.versionId,
      );
      expect(journal.snapshot(continuity, journal.head(continuity)), isEmpty);
      expect(
        staged.package.database
            .select('SELECT count(*) AS n FROM operation_receipts')
            .single['n'],
        0,
      );
    } finally {
      staged.close();
      archive.close();
    }
    expect(File(source).readAsBytesSync(), orderedEquals(original));
    expect(
      () => convertLegacy(source, destination, root.path),
      throwsA(isA<FileSystemException>()),
    );
    noStages();
  });
  test('legacy conversion refuses unsafe and oversized input before creating staging', () {
    final scratch = '${root.path}/absent-scratch';
    final linked = Link('${root.path}/linked.sqlite')..createSync(source);
    expect(
      () => convertLegacy(linked.path, '${root.path}/refused.sqlite', scratch),
      throwsA(isA<FileSystemException>()),
    );
    expect(Directory(scratch).existsSync(), isFalse);
    final oversized = File('${root.path}/oversized.sqlite');
    protectedFile(oversized.path, createNew: true);
    final handle = oversized.openSync(mode: FileMode.writeOnly);
    try {
      handle.truncateSync(512 * 1024 * 1024 + 1);
    } finally {
      handle.closeSync();
    }
    expect(
      () =>
          convertLegacy(oversized.path, '${root.path}/refused.sqlite', scratch),
      throwsFormatException,
    );
    expect(Directory(scratch).existsSync(), isFalse);
    expect(File('${root.path}/refused.sqlite').existsSync(), isFalse);
  });

  test('legacy unsupported assets digest mismatch inherited baselines and cycles refuse publication and retain original', () {
    for (final sql in [
      "INSERT INTO source_versions VALUES('old-source','${universe.value}','missing','digest','text/plain','then')",
      "UPDATE record_versions SET digest='broken'",
      "UPDATE record_identities SET kind='entity'",
      "UPDATE continuities SET baseline_commit='old-first'",
      "UPDATE commits SET parent_id='old-third' WHERE id='old-first'",
      "UPDATE commit_changes SET action='replace' WHERE commit_id='old-first'",
      "PRAGMA user_version=1",
    ]) {
      final path = '${root.path}/input-copy.sqlite';
      File(source).copySync(path);
      final db = sqlite3.open(path);
      try {
        db.execute(sql);
      } finally {
        db.close();
      }
      final original = File(path).readAsBytesSync();
      expect(
        () => convertLegacy(path, '${root.path}/refused.sqlite', root.path),
        throwsFormatException,
      );
      expect(File('${root.path}/refused.sqlite').existsSync(), isFalse);
      expect(File(path).readAsBytesSync(), orderedEquals(original));
      noStages();
      File(path).deleteSync();
    }
  });
}
