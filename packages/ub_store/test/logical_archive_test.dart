@TestOn('vm')
library;

import 'dart:io';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;
import 'package:sqlite3/sqlite3.dart' show sqlite3, OpenMode;
import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/sqlite.dart';
import 'package:ub_store/ub_store.dart';
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

  test('clone reconstruction preserves history identities and original editorial evidence in a new universe', () {
    final path = export();
    final original = File(path).readAsBytesSync();
    final archive = OwnedSqliteDatabase.stageLogicalArchive(path, root.path);
    final target = UniverseId.generate();
    final clone = archive.reconstruct(
      root.path,
      target: target,
      name: 'Named clone',
    );
    try {
      final copy = clone.package;
      expect(copy.universeId, target);
      expect(SqliteJournal(copy.database, target).head(continuity), revision);
      expect(
        copy.database.select('SELECT name FROM universes').single['name'],
        'Named clone',
      );
      final workflow = WorkflowStorage(copy.database);
      expect(workflow.get('cursor:one'), isNull);
      expect(
        workflow.evidence('cursor:one')!.toText(),
        WorkflowStorage(source.database).get('cursor:one')!.toText(),
      );
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
      expect(origin.string('source_universe'), universe.value);
      expect(origin.string('target_universe'), target.value);
      expect(File(path).readAsBytesSync(), orderedEquals(original));
    } finally {
      clone.close();
      archive.close();
    }
    noStages();
  });

  test('clone remaps record and version references retains pinned branches and keeps earliest digest provenance', () {
    const text = 'Aé😀\r\nZ';
    String hash(String value) => sha256.convert(utf8.encode(value)).toString();
    final actor = PrincipalId.generate();
    source.database.execute('BEGIN IMMEDIATE');
    WorkflowStorage(source.database)
        .put('source:${hash(text)}', CanonicalString(text));
    source.database.execute('COMMIT');
    final sourceId = RecordId.generate(),
        versionId = RecordId.generate(),
        anchorId = RecordId.generate();
    StoredVersion version(RecordId id, RecordPayload payload) =>
        StoredVersion.build(
          RecordVersionId.generate(),
          RecordIdentity(
            universeId: universe,
            recordId: id,
            recordKind: payload.recordKind,
          ),
          payload.toWire(),
        );
    final sourceRecord = version(
      sourceId,
      SourceRecord(
        label: 'Authored ${universe.value}',
        origin: const OriginMetadata(),
        versions: [versionId],
      ),
    );
    final sourceVersion = version(
      versionId,
      SourceVersionRecord(
        source: RecordRef(universe: universe, record: sourceId),
        contentDigest: hash(text),
        mediaType: 'text/plain; charset=utf-8',
        byteSize: BigInt.from(utf8.encode(text).length),
        importActor: actor,
        importTime: '2026-10-12T00:00:00Z',
        decoding: DecodingDescriptor(
          encoding: 'UTF-8',
          representation: 'exact-utf8-v1',
          byteLength: BigInt.from(utf8.encode(text).length),
        ),
        origin: const OriginMetadata(),
      ),
    );
    final anchor = version(
      anchorId,
      AnchorRecord(
        sourceVersion: VersionRef(
          universe: universe,
          record: versionId,
          version: sourceVersion.versionId,
        ),
        locator: ByteRangeLocator(BigInt.one, BigInt.from(7)),
        excerpt: 'é😀',
        excerptDigest: hash('é😀'),
      ),
    );
    final kernel = SqliteKernel(source.database, universe);
    final canonical = kernel.commit(
      CommitInput(
        universe: universe,
        continuity: continuity,
        expectedHead: revision,
        principal: actor,
        decision: 'Admitted fixture',
        reason: 'Reference pins',
        idempotencyKey: 'source-canon',
        changes: [
          for (final value in [sourceRecord, sourceVersion, anchor])
            Assignment(recordId: value.identity.recordId, next: value),
        ],
      ),
    );
    final branch = ContinuityId.generate();
    source.database.execute('BEGIN IMMEDIATE');
    final branchHead = kernel.journal.branch(
      branch,
      continuity,
      canonical,
      actor,
    );
    source.database.execute('COMMIT');
    final head = kernel.commit(
      CommitInput(
        universe: universe,
        continuity: continuity,
        expectedHead: canonical,
        principal: actor,
        decision: 'Admitted fixture',
        reason: 'Historical anchor',
        idempotencyKey: 'retire-anchor',
        changes: [Assignment(recordId: anchorId, expected: anchor.versionId)],
      ),
    );
    final path = export();
    final original = File(path).readAsBytesSync();
    final archive = OwnedSqliteDatabase.stageLogicalArchive(path, root.path);
    final target = UniverseId.generate();
    final clone = archive.reconstruct(
      root.path,
      target: target,
      name: 'Reference clone',
    );
    try {
      final journal = SqliteJournal(clone.package.database, target);
      expect(journal.head(continuity), head);
      expect(journal.head(branch), branchHead);
      expect(journal.snapshot(branch, branchHead)[anchorId], anchor.versionId);
      final mappedVersion = journal.load(sourceVersion.versionId);
      expect(
        SourceVersionRecord.fromWire(mappedVersion.payload).source.universe,
        target,
      );
      final mappedAnchor = AnchorRecord.fromWire(
        journal.load(anchor.versionId).payload,
      );
      expect(mappedAnchor.sourceVersion.universe, target);
      expect(mappedAnchor.sourceVersion.version, sourceVersion.versionId);
      expect(
        SourceRecord.fromWire(journal.load(sourceRecord.versionId).payload)
            .label,
        'Authored ${universe.value}',
      );
      expect(journal.load(sourceRecord.versionId).digest, sourceRecord.digest);
      final provenance = clone.package.database.select(
        'SELECT source_digest,normalized_digest FROM import_record_digest WHERE version_id=?',
        [sourceVersion.versionId.value],
      ).single;
      expect(provenance['source_digest'], sourceVersion.digest);
      expect(provenance['normalized_digest'], mappedVersion.digest);
      expect(mappedVersion.digest, isNot(sourceVersion.digest));
      expect(
        WorkflowStorage(clone.package.database)
            .evidence('source:${hash(text)}')!
            .toText(),
        CanonicalString(text).toText(),
      );
      expect(
        clone.package.database
            .select('SELECT count(*) AS n FROM historical_receipt')
            .single['n'],
        2,
      );
      final nextPath = '${root.path}/cloned-history.sqlite';
      clone.package.exportCompleteHistory(nextPath);
      final nextArchive = OwnedSqliteDatabase.stageLogicalArchive(
        nextPath,
        root.path,
      );
      final nextTarget = UniverseId.generate();
      final next = nextArchive.reconstruct(
        root.path,
        target: nextTarget,
        name: 'Second clone',
      );
      try {
        final current = SqliteJournal(
          next.package.database,
          nextTarget,
        ).load(sourceVersion.versionId);
        final retained = next.package.database.select(
          'SELECT source_digest,normalized_digest FROM import_record_digest WHERE version_id=?',
          [sourceVersion.versionId.value],
        ).single;
        expect(retained['source_digest'], sourceVersion.digest);
        expect(retained['normalized_digest'], current.digest);
        expect(
          SourceVersionRecord.fromWire(current.payload).source.universe,
          nextTarget,
        );
      } finally {
        next.close();
        nextArchive.close();
      }
    } finally {
      clone.close();
      archive.close();
    }
    expect(File(path).readAsBytesSync(), orderedEquals(original));
    noStages();
  });

  test('canon-only export excludes editorial authority and reconstructs under the retained identity', () {
    final path = '${root.path}/canon-only-export.sqlite';
    final manifest = source.exportCanonOnly(path);
    final archive = OwnedSqliteDatabase.stageLogicalArchive(path, root.path);
    final rebuilt = archive.reconstruct(
      root.path,
      target: universe,
      name: 'Canon only',
    );
    try {
      expect(archive.manifest.toText(), manifest.toText());
      expect(
        WireFields(manifest, {
          'format',
          'universe',
          'name',
          'complete',
          'omitted_records',
          'includes_history',
          'includes_workflow',
        }).boolean('includes_workflow'),
        isFalse,
      );
      expect(
        WorkflowStorage(archive.package.database).keys('cursor:'),
        isEmpty,
      );
      expect(rebuilt.package.universeId, universe);
      expect(
        SqliteJournal(rebuilt.package.database, universe).head(continuity),
        revision,
      );
      expect(
        WorkflowStorage(rebuilt.package.database).keys('cursor:'),
        isEmpty,
      );
      expect(WorkflowStorage(source.database).get('cursor:one'), isNotNull);
    } finally {
      rebuilt.close();
      archive.close();
    }
    noStages();
  });

  test('canon-only reconstruction retains a canonical image across multiple byte chunks', () {
    final bytes = img.encodePng(img.Image(width: 400, height: 400), level: 0);
    expect(bytes.length, greaterThan(imageChunkBytes));
    final kernel = SqliteKernel(source.database, universe);
    final staged = kernel.stageImageBytes(bytes, 'canonical.png');
    final assetVersion = StoredVersion.build(
      RecordVersionId.generate(),
      RecordIdentity(
        universeId: universe,
        recordId: staged.record,
        recordKind: RecordKind.imageAsset,
      ),
      staged.asset.toWire(),
    );
    final head = kernel.commit(
      CommitInput(
        universe: universe,
        continuity: continuity,
        expectedHead: revision,
        principal: PrincipalId.generate(),
        decision: 'Admitted fixture',
        reason: 'Canonical image',
        idempotencyKey: 'canonical-image',
        changes: [Assignment(recordId: staged.record, next: assetVersion)],
      ),
    );
    final path = '${root.path}/canon-image.sqlite';
    source.exportCanonOnly(path);
    final archive = OwnedSqliteDatabase.stageLogicalArchive(path, root.path);
    final target = UniverseId.generate();
    final rebuilt = archive.reconstruct(
      root.path,
      target: target,
      name: 'Image clone',
    );
    try {
      expect(
        SqliteJournal(rebuilt.package.database, target).head(continuity),
        head,
      );
      expect(
        SqliteKernel(rebuilt.package.database, target).imageBytes(staged.asset),
        orderedEquals(bytes),
      );
      expect(
        WorkflowStorage(rebuilt.package.database).keys('cursor:'),
        isEmpty,
      );
      expect(
        rebuilt.package.database
            .select('SELECT count(*) AS n FROM operation_receipts')
            .single['n'],
        0,
      );
      expect(
        rebuilt.package.database
            .select('SELECT count(*) AS n FROM media_chunk')
            .single['n'],
        2,
      );
    } finally {
      rebuilt.close();
      archive.close();
    }
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
    expect(
      () => archive.reconstruct(scratch, target: universe, name: ' '),
      throwsFormatException,
    );
    expect(Directory(scratch).existsSync(), isFalse);
    archive.close();
    expect(
      () => archive.stageRestore(scratch, name: 'Closed'),
      throwsStateError,
    );
    expect(
      () => archive.reconstruct(scratch, target: universe, name: 'Closed'),
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
          () => archive.reconstruct(
            root.path,
            target: UniverseId.generate(),
            name: 'Rejected clone',
          ),
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
          if (!complete) {
            expect(
              () => verified.reconstruct(
                scratch,
                target: empty.universeId,
                name: 'Invalid retained identity',
              ),
              throwsFormatException,
            );
            expect(Directory(scratch).existsSync(), isFalse);
          }
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

  test('filtered export closes historical dependencies and preserves tombstones while requiring a clone', () {
    final actor = PrincipalId.generate();
    final selectedId = RecordId.generate(),
        earlierId = RecordId.generate(),
        laterId = RecordId.generate(),
        omittedId = RecordId.generate();
    StoredVersion make(RecordId id, List<RecordId> dependencies) =>
        StoredVersion.build(
          RecordVersionId.generate(),
          RecordIdentity(
            universeId: universe,
            recordId: id,
            recordKind: RecordKind.source,
          ),
          SourceRecord(
            label: 'Source ${id.value}',
            origin: const OriginMetadata(),
            versions: dependencies,
          ).toWire(),
        );
    const text = 'Retained source bytes é😀';
    final bytes = utf8.encode(text);
    final digest = sha256.convert(bytes).toString();
    source.database.execute('BEGIN IMMEDIATE');
    WorkflowStorage(source.database)
        .put('source:$digest', CanonicalString(text));
    source.database.execute('COMMIT');
    StoredVersion asset(RecordId id) => StoredVersion.build(
      RecordVersionId.generate(),
      RecordIdentity(
        universeId: universe,
        recordId: id,
        recordKind: RecordKind.sourceVersion,
      ),
      SourceVersionRecord(
        source: RecordRef(universe: universe, record: selectedId),
        contentDigest: digest,
        mediaType: 'text/plain; charset=utf-8',
        byteSize: BigInt.from(bytes.length),
        importActor: actor,
        importTime: '2026-10-12T00:00:00Z',
        decoding: DecodingDescriptor(
          encoding: 'UTF-8',
          representation: 'exact-utf8-v1',
          byteLength: BigInt.from(bytes.length),
        ),
        origin: const OriginMetadata(),
      ).toWire(),
    );
    final earlier = asset(earlierId),
        later = asset(laterId),
        omitted = make(omittedId, []);
    final first = make(selectedId, [earlierId]);
    final kernel = SqliteKernel(source.database, universe);
    RevisionId commit(RevisionId head, String key, List<Assignment> changes) =>
        kernel.commit(
          CommitInput(
            universe: universe,
            continuity: continuity,
            expectedHead: head,
            principal: actor,
            decision: 'Filtered fixture',
            reason: 'Historical dependencies',
            idempotencyKey: key,
            changes: changes,
          ),
        );
    final initial = commit(revision, 'filtered-initial', [
      Assignment(recordId: selectedId, next: first),
      Assignment(recordId: earlierId, next: earlier),
      Assignment(recordId: laterId, next: later),
      Assignment(recordId: omittedId, next: omitted),
    ]);
    final second = make(selectedId, [laterId]);
    final updated = commit(initial, 'filtered-update', [
      Assignment(recordId: selectedId, expected: first.versionId, next: second),
    ]);
    final head = commit(updated, 'filtered-retire', [
      Assignment(recordId: selectedId, expected: second.versionId, next: null),
      Assignment(recordId: earlierId, expected: earlier.versionId, next: null),
      Assignment(recordId: laterId, expected: later.versionId, next: null),
    ]);
    final path = '${root.path}/filtered.sqlite';
    final manifest = source.exportLogical(
      path,
      recordIds: [selectedId, selectedId],
    );
    final fields = WireFields(manifest, {
      'format',
      'universe',
      'name',
      'complete',
      'omitted_records',
      'includes_history',
      'includes_workflow',
    });
    expect(fields.boolean('complete'), isFalse);
    expect(fields.require('omitted_records').toText(), '1');
    final archive = OwnedSqliteDatabase.stageLogicalArchive(path, root.path);
    try {
      expect(
        () => archive.reconstruct(
          '${root.path}/invalid-filter-restore',
          target: universe,
          name: 'Invalid',
        ),
        throwsFormatException,
      );
      expect(
        Directory('${root.path}/invalid-filter-restore').existsSync(),
        isFalse,
      );
      final target = UniverseId.generate();
      final clone = archive.reconstruct(
        root.path,
        target: target,
        name: 'Filtered clone',
      );
      try {
        final journal = SqliteJournal(clone.package.database, target);
        expect(journal.head(continuity), head);
        expect(journal.load(first.versionId).digest, first.digest);
        expect(journal.load(second.versionId).digest, second.digest);
        expect(
          journal.snapshot(continuity, head).containsKey(selectedId),
          isFalse,
        );
        expect(
          clone.package.database
              .select('SELECT count(*) AS n FROM record_identities')
              .single['n'],
          3,
        );
        expect(
          clone.package.database.select(
            'SELECT count(*) AS n FROM record_versions WHERE record_id=?',
            [omittedId.value],
          ).single['n'],
          0,
        );
      } finally {
        clone.close();
      }
    } finally {
      archive.close();
    }
    noStages();
  });

  test('filtered export keeps global contexts and appearances and only selected entry attachments', () {
    StoredVersion make(RecordPayload payload) => StoredVersion.build(
      RecordVersionId.generate(),
      RecordIdentity(
        universeId: universe,
        recordId: RecordId.generate(),
        recordKind: payload.recordKind,
      ),
      payload.toWire(),
    );
    final selected = make(
      SourceRecord(
        label: 'Selected',
        origin: const OriginMetadata(),
        versions: [],
      ),
    );
    final omitted = make(
      SourceRecord(
        label: 'Omitted',
        origin: const OriginMetadata(),
        versions: [],
      ),
    );
    StoredVersion appearance(AppearanceTarget target) => make(
      AppearanceRecord(
        target: target,
        label: 'Appearance',
        physicalDescription: 'Authored',
        atmosphere: '',
        images: [],
        links: [],
        validity: const UnspecifiedValidity(),
      ),
    );
    final global = appearance(const UniverseAppearance());
    final attached = appearance(
      EntryAppearance(
        RecordRef(universe: universe, record: selected.identity.recordId),
      ),
    );
    final excluded = appearance(
      EntryAppearance(
        RecordRef(universe: universe, record: omitted.identity.recordId),
      ),
    );
    final context = make(
      RepresentedContextRecord(
        universe: universe,
        kind: const ObjectiveContext(),
        labels: {'name': 'Global context'},
      ),
    );
    SqliteKernel(source.database, universe).commit(
      CommitInput(
        universe: universe,
        continuity: continuity,
        expectedHead: revision,
        principal: PrincipalId.generate(),
        decision: 'Attachments',
        reason: 'Filtered fixture',
        idempotencyKey: 'attachments',
        changes: [
          for (final record in [
            selected,
            omitted,
            global,
            attached,
            excluded,
            context,
          ])
            Assignment(recordId: record.identity.recordId, next: record),
        ],
      ),
    );
    final path = '${root.path}/filtered-attachments.sqlite';
    source.exportLogical(path, recordIds: [selected.identity.recordId]);
    final archive = OwnedSqliteDatabase.stageLogicalArchive(path, root.path);
    try {
      final ids = archive.package.database
          .select('SELECT id FROM record_identities')
          .map((row) => row['id'])
          .toSet();
      expect(ids, {
        selected.identity.recordId.value,
        global.identity.recordId.value,
        attached.identity.recordId.value,
        context.identity.recordId.value,
      });
    } finally {
      archive.close();
    }
    noStages();
  });

  test('filtered export rejects unavailable identities and complete-history selection before publication', () {
    final path = '${root.path}/refused.sqlite';
    expect(
      () => source.exportLogical(path, recordIds: [RecordId.generate()]),
      throwsFormatException,
    );
    expect(File(path).existsSync(), isFalse);
    expect(
      () => source.exportLogical(
        '${root.path}/absent/refused.sqlite',
        recordIds: [RecordId.generate()],
        completeHistory: true,
      ),
      throwsFormatException,
    );
    expect(Directory('${root.path}/absent').existsSync(), isFalse);
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
