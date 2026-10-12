@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';
import 'package:crypto/crypto.dart';
import 'package:ub_store/src/ownership.dart';
import 'package:ub_store/src/owned_database.dart';
import 'package:ub_store/src/journal.dart';
import 'package:ub_store/src/workflow_storage.dart';
import 'package:ub_store/src/revision_input.dart';
import 'package:ub_store/src/kernel.dart';
import 'package:ub_domain/ub_domain.dart';

void main() {
  late Directory directory;
  setUp(() {
    directory = Directory.systemTemp.createTempSync(
      'universe-builder-ownership-',
    );
  });
  tearDown(() {
    directory.deleteSync(recursive: true);
  });
  void chmod(String mode, String path) {
    final result = Process.runSync('chmod', [mode, path]);
    expect(result.exitCode, 0);
  }

  String executable() {
    final current = File(Platform.resolvedExecutable);
    return current.uri.pathSegments.last == 'dartvm'
        ? '${current.parent.path}/dart'
        : current.path;
  }

  Future<ProcessResult> attempt(String path) => Process.run(executable(), [
    'run',
    'test/helpers/ownership_process.dart',
    path,
  ]);

  test('owned startup verifies workflow evidence before switching projection generations', () {
    final path = '${directory.path}/package.sqlite';
    final owner = OwnedSqliteDatabase.create(path);
    try {
      final database = owner.database;
      final universe = UniverseId.parse('unv_000000000000000000000001');
      final continuity = ContinuityId.parse('cont_000000000000000000000001');
      final principal = PrincipalId.parse('prn_000000000000000000000001');
      database.execute('BEGIN IMMEDIATE');
      SqliteJournal(
        database,
        universe,
      ).initialize('Owned startup', continuity, principal);
      WorkflowStorage(database).put(
        'cursor:one',
        CanonicalValue.parseJson('{"binding":"exact binding","offset":0}'),
      );
      database.execute('COMMIT');
      owner.recover();
      expect(
        database
            .select('SELECT generation FROM projection_state')
            .single['generation'],
        1,
      );
      database.execute('DROP TRIGGER workflow_entries_no_update');
      database.execute('UPDATE workflow_entries SET digest=?', ['0' * 64]);
      expect(owner.recover, throwsFormatException);
      expect(
        database
            .select('SELECT generation FROM projection_state')
            .single['generation'],
        1,
      );
      expect(
        () => OwnedSqliteDatabase.openExisting(path),
        throwsA(isA<FileSystemException>()),
      );
      expect(database.autocommit, isTrue);
    } finally {
      owner.close();
    }
  });
  test('backup refuses missing staged source bytes without publishing a partial snapshot', () {
    final owner = OwnedSqliteDatabase.create('${directory.path}/source.sqlite');
    final destination = '${directory.path}/backup.sqlite';
    try {
      final universe = UniverseId.generate();
      final continuity = ContinuityId.generate();
      final principal = PrincipalId.generate();
      final source = SourceVersionRecord(
        source: RecordRef(universe: universe, record: RecordId.generate()),
        contentDigest: '0' * 64,
        mediaType: 'text/plain; charset=utf-8',
        byteSize: BigInt.from(5),
        importActor: principal,
        importTime: '2026-10-12T00:00:00Z',
        decoding: DecodingDescriptor(
          encoding: 'UTF-8',
          representation: 'exact-utf8-v1',
          byteLength: BigInt.from(5),
        ),
        origin: const OriginMetadata(),
      );
      final key = 'source-version:${RecordId.generate().value}';
      owner.database.execute('BEGIN IMMEDIATE');
      SqliteJournal(
        owner.database,
        universe,
      ).initialize('Missing material fixture', continuity, principal);
      WorkflowStorage(owner.database).put(key, source.toWire());
      owner.database.execute('COMMIT');
      owner.recover();
      expect(() => owner.backup(destination), throwsFormatException);
      expect(File(destination).existsSync(), isFalse);
      expect(
        WorkflowStorage(owner.database).evidence(key)!.toText(),
        source.toWire().toText(),
      );
      expect(
        directory.listSync().where(
          (f) =>
              f.uri.pathSegments.any((p) => p.startsWith('.universe-backup-')),
        ),
        isEmpty,
      );
      expect(owner.database.autocommit, isTrue);
      expect(
        () => OwnedSqliteDatabase.openExisting(owner.path),
        throwsA(isA<FileSystemException>()),
      );
    } finally {
      owner.close();
    }
  });

  test('backup retains exact multibyte anchors and rejects partial UTF-8 boundaries or changed excerpts', () {
    for (var fixture = 0; fixture < 3; fixture++) {
      final owner = OwnedSqliteDatabase.create(
        '${directory.path}/anchor-$fixture.sqlite',
      );
      final destination = '${directory.path}/anchor-backup-$fixture.sqlite';
      try {
        final universe = UniverseId.generate(),
            continuity = ContinuityId.generate();
        final principal = PrincipalId.generate();
        final kernel = SqliteKernel(owner.database, universe);
        owner.database.execute('BEGIN IMMEDIATE');
        final base = kernel.journal.initialize(
          'Anchor fixture',
          continuity,
          principal,
        );
        const text = 'Aé😀\r\nZ';
        String hash(String text) =>
            sha256.convert(utf8.encode(text)).toString();
        WorkflowStorage(owner.database)
            .put('source:${hash(text)}', CanonicalString(text));
        owner.database.execute('COMMIT');
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
        final source = version(
          sourceId,
          SourceRecord(
            label: 'Research',
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
            importActor: principal,
            importTime: '2026-10-12T00:00:00Z',
            decoding: DecodingDescriptor(
              encoding: 'UTF-8',
              representation: 'exact-utf8-v1',
              byteLength: BigInt.from(utf8.encode(text).length),
            ),
            origin: const OriginMetadata(),
          ),
        );
        final excerpt = fixture == 0
            ? 'é😀'
            : fixture == 1
            ? ''
            : 'Changed';
        final anchor = version(
          anchorId,
          AnchorRecord(
            sourceVersion: VersionRef(
              universe: universe,
              record: versionId,
              version: sourceVersion.versionId,
            ),
            locator: fixture == 1
                ? ByteRangeLocator(BigInt.two, BigInt.two)
                : ByteRangeLocator(BigInt.one, BigInt.from(7)),
            excerptDigest: hash(excerpt),
            excerpt: excerpt,
          ),
        );
        kernel.commit(
          CommitInput(
            universe: universe,
            continuity: continuity,
            expectedHead: base,
            principal: principal,
            decision: 'Admitted fixture',
            reason: 'Transfer anchor verification',
            idempotencyKey: 'anchor-fixture',
            changes: [
              for (final v in [source, sourceVersion, anchor])
                Assignment(recordId: v.identity.recordId, next: v),
            ],
          ),
        );
        if (fixture == 0) {
          owner.backup(destination);
          final copy = OwnedSqliteDatabase.openExisting(destination);
          try {
            copy.recover();
            expect(
              WorkflowStorage(copy.database)
                  .evidence('source:${hash(text)}')!
                  .toText(),
              CanonicalString(text).toText(),
            );
            expect(
              SqliteJournal(
                copy.database,
                universe,
              ).load(anchor.versionId).toCanonical().toText(),
              anchor.toCanonical().toText(),
            );
          } finally {
            copy.close();
          }
        } else {
          expect(() => owner.backup(destination), throwsFormatException);
          expect(File(destination).existsSync(), isFalse);
        }
      } finally {
        owner.close();
      }
    }
  });

  test('backup preserves historical world names and rejects missing reservations after tombstones', () {
    final owner = OwnedSqliteDatabase.create('${directory.path}/names.sqlite');
    try {
      final universe = UniverseId.generate(),
          continuity = ContinuityId.generate();
      final principal = PrincipalId.generate(), record = RecordId.generate();
      final kernel = SqliteKernel(owner.database, universe);
      owner.database.execute('BEGIN IMMEDIATE');
      final genesis = kernel.journal.initialize(
        'World names fixture',
        continuity,
        principal,
      );
      owner.database.execute('COMMIT');
      final version = StoredVersion.build(
        RecordVersionId.generate(),
        RecordIdentity(
          universeId: universe,
          recordId: record,
          recordKind: RecordKind.world,
        ),
        WorldRecord(
          selector: 'Historical World',
          aliases: ['Old Alias'],
        ).toWire(),
      );
      final created = kernel.commit(
        CommitInput(
          universe: universe,
          continuity: continuity,
          expectedHead: genesis,
          principal: principal,
          decision: 'Admitted fixture',
          reason: 'Named world',
          idempotencyKey: 'names-create',
          changes: [Assignment(recordId: record, next: version)],
        ),
      );
      final removed = kernel.commit(
        CommitInput(
          universe: universe,
          continuity: continuity,
          expectedHead: created,
          principal: principal,
          decision: 'Admitted fixture',
          reason: 'Removed world',
          idempotencyKey: 'names-remove',
          changes: [Assignment(recordId: record, expected: version.versionId)],
        ),
      );
      final destination = '${directory.path}/names-backup.sqlite';
      owner.backup(destination);
      final copy = OwnedSqliteDatabase.openExisting(destination);
      try {
        copy.recover();
        expect(
          copy.database.select('SELECT name FROM world_name_reservations'),
          hasLength(2),
        );
        expect(
          SqliteJournal(copy.database, universe).snapshot(continuity, created),
          hasLength(1),
        );
        expect(
          SqliteJournal(copy.database, universe).snapshot(continuity, removed),
          isEmpty,
        );
      } finally {
        copy.close();
      }
      owner.database.execute(
        'DROP TRIGGER immutable_world_name_reservations_delete',
      );
      owner.database.execute(
        'DELETE FROM world_name_reservations WHERE name=?',
        [selectorKey('Old Alias')],
      );
      final rejected = '${directory.path}/incomplete-names.sqlite';
      expect(() => owner.backup(rejected), throwsFormatException);
      expect(File(rejected).existsSync(), isFalse);
      expect(File(destination).existsSync(), isTrue);
      expect(kernel.journal.head(continuity), removed);
    } finally {
      owner.close();
    }
  });

  test('backup validates historical memberships even when the current head is empty', () {
    final owner = OwnedSqliteDatabase.create(
      '${directory.path}/history.sqlite',
    );
    final destination = '${directory.path}/backup.sqlite';
    try {
      final universe = UniverseId.generate();
      final continuity = ContinuityId.generate();
      final principal = PrincipalId.generate();
      final id = RecordId.generate();
      final journal = SqliteJournal(owner.database, universe);
      owner.database.execute('BEGIN IMMEDIATE');
      final genesis = journal.initialize(
        'Historical damage fixture',
        continuity,
        principal,
      );
      owner.database.execute('COMMIT');
      final version = StoredVersion.build(
        RecordVersionId.generate(),
        RecordIdentity(
          universeId: universe,
          recordId: id,
          recordKind: RecordKind.entity,
        ),
        EntityRecord(
          names: [],
          classification: RecordId.generate(),
          classificationResolution: ClassificationResolution.resolved,
          worldAssociations: [],
          labels: {},
          metadata: {},
        ).toWire(),
      );
      // Deliberately simulate damaged historical admission through the internal
      // journal, bypassing the kernel's normal candidate gates.
      final add = CommitInput(
        universe: universe,
        continuity: continuity,
        expectedHead: genesis,
        principal: principal,
        decision: 'Damaged fixture',
        reason: 'Missing historical classification',
        idempotencyKey: 'damaged-add',
        changes: [Assignment(recordId: id, next: version)],
      );
      owner.database.execute('BEGIN IMMEDIATE');
      final membership = journal.stageVersions(add);
      final prior = journal.append(add);
      journal.advanceHead(continuity, genesis, prior, membership);
      owner.database.execute('COMMIT');
      final remove = CommitInput(
        universe: universe,
        continuity: continuity,
        expectedHead: prior,
        principal: principal,
        decision: 'Fixture removal',
        reason: 'Empty current head',
        idempotencyKey: 'damaged-remove',
        changes: [Assignment(recordId: id, expected: version.versionId)],
      );
      owner.database.execute('BEGIN IMMEDIATE');
      final empty = journal.stageVersions(remove);
      final head = journal.append(remove);
      journal.advanceHead(continuity, prior, head, empty);
      owner.database.execute('COMMIT');
      owner.recover();
      expect(journal.snapshot(continuity, head), isEmpty);
      expect(() => owner.backup(destination), throwsFormatException);
      expect(File(destination).existsSync(), isFalse);
      expect(journal.head(continuity), head);
      expect(journal.snapshot(continuity, prior), hasLength(1));
      expect(owner.database.autocommit, isTrue);
    } finally {
      owner.close();
    }
  });

  test('maintenance verifies retained evidence before deleting reconstructible caches', () {
    final owner = OwnedSqliteDatabase.create(
      '${directory.path}/maintenance.sqlite',
    );
    try {
      final database = owner.database;
      final universe = UniverseId.generate();
      final continuity = ContinuityId.generate();
      final journal = SqliteJournal(database, universe);
      database.execute('BEGIN IMMEDIATE');
      final revision = journal.initialize(
        'Maintenance fixture',
        continuity,
        PrincipalId.generate(),
      );
      WorkflowStorage(database).put(
        'cursor:one',
        CanonicalValue.parseJson('{"binding":"pinned","offset":0}'),
      );
      database.execute('INSERT INTO snapshot_membership VALUES(?,?,?)', [
        universe.value,
        revision.value,
        canonicalDigest(CanonicalObject([])),
      ]);
      database.execute('COMMIT');
      owner.recover();
      database.execute('BEGIN');
      expect(() => owner.maintain(collect: true), throwsStateError);
      database.execute('ROLLBACK');
      database.execute('DROP TRIGGER workflow_entries_no_update');
      database.execute('UPDATE workflow_entries SET digest=?', ['0' * 64]);
      expect(() => owner.maintain(collect: true), throwsFormatException);
      expect(
        database
            .select('SELECT count(*) AS total FROM snapshot_membership')
            .single['total'],
        1,
      );
      expect(database.autocommit, isTrue);
    } finally {
      owner.close();
    }
  });

  test(
    'owned SQLite connection holds its writer lock through close and restart',
    () {
      final path = '${directory.path}/package.sqlite';
      final owner = OwnedSqliteDatabase.create(path);
      try {
        expect(File(path).statSync().mode & 0x1ff, 0x180);
        expect(
          owner.database.select('PRAGMA journal_mode').single.values.single,
          'wal',
        );
        expect(
          () => OwnedSqliteDatabase.openExisting(path),
          throwsA(isA<FileSystemException>()),
        );
      } finally {
        owner.close();
        owner.close();
      }
      expect(() => owner.database, throwsStateError);
      final reopened = OwnedSqliteDatabase.openExisting(path);
      reopened.close();
      expect(
        () => OwnedSqliteDatabase.create(path),
        throwsA(isA<FileSystemException>()),
      );
      final afterRefusal = OwnedSqliteDatabase.openExisting(path);
      afterRefusal.close();
      final absent = '${directory.path}/absent/package.sqlite';
      expect(
        () => OwnedSqliteDatabase.openExisting(absent),
        throwsA(isA<FileSystemException>()),
      );
      expect(Directory('${directory.path}/absent').existsSync(), isFalse);
    },
  );
  test('private directories and protected files preserve owners and restrictive modes', () {
    final path = '${directory.path}/instance';
    expect(privateDirectory(path), Directory(path).resolveSymbolicLinksSync());
    expect(Directory(path).statSync().mode & 0x3f, 0);
    final file = '$path/package.sqlite';
    protectedFile(file, createNew: true);
    expect(File(file).statSync().mode & 0x1ff, 0x180);
    File(file).writeAsStringSync('preserved');
    expect(
      () => protectedFile(file, createNew: true),
      throwsA(isA<FileSystemException>()),
    );
    protectedFile(file);
    expect(File(file).readAsStringSync(), 'preserved');
    chmod('644', file);
    expect(() => protectedFile(file), throwsA(isA<FileSystemException>()));
    expect(File(file).readAsStringSync(), 'preserved');
    chmod('755', path);
    expect(() => privateDirectory(path), throwsA(isA<FileSystemException>()));
    expect(Directory(path).statSync().mode & 0x3f, isNot(0));
  });
  test(
    'protected runtime paths refuse symlinks, hardlinks and nonregular files',
    () {
      final original = '${directory.path}/original';
      protectedFile(original, create: true);
      final link = '${directory.path}/symlink';
      Link(link).createSync(original);
      expect(() => protectedFile(link), throwsA(isA<FileSystemException>()));
      expect(
        () => OwnedFileLock.acquire(link),
        throwsA(isA<FileSystemException>()),
      );
      final alias = '${directory.path}/hardlink';
      expect(Process.runSync('ln', [original, alias]).exitCode, 0);
      expect(
        () => protectedFile(original),
        throwsA(isA<FileSystemException>()),
      );
      expect(() => protectedFile(alias), throwsA(isA<FileSystemException>()));
      expect(
        () => protectedFile(directory.path),
        throwsA(isA<FileSystemException>()),
      );
      final directoryLink = '${directory.path}/directory-link';
      Link(directoryLink).createSync(directory.path);
      expect(
        () => privateDirectory(directoryLink),
        throwsA(isA<FileSystemException>()),
      );
      expect(() => protectedFile('bad\u0000path'), throwsFormatException);
    },
  );
  test('descriptor ownership excludes isolates and survives unrelated descriptor close', () async {
    final path = '${directory.path}/writer.lock';
    final owner = OwnedFileLock.acquire(path);
    try {
      expect(
        () => OwnedFileLock.acquire(path),
        throwsA(isA<FileSystemException>()),
      );
      protectedFile(path);
      final admitted = await Isolate.run(() {
        try {
          final other = OwnedFileLock.acquire(path);
          other.close();
          return true;
        } on FileSystemException {
          return false;
        }
      });
      expect(admitted, isFalse);
      expect(
        () => OwnedFileLock.acquire(path),
        throwsA(isA<FileSystemException>()),
      );
    } finally {
      owner.close();
      owner.close();
    }
    final next = OwnedFileLock.acquire(path);
    next.close();
    expect(File(path).existsSync(), isTrue);
  });
  test('writer ownership excludes another process and releases after abnormal termination', () async {
    final path = '${directory.path}/writer.lock';
    final owner = OwnedFileLock.acquire(path);
    try {
      expect((await attempt(path)).exitCode, 2);
    } finally {
      owner.close();
    }
    expect((await attempt(path)).exitCode, 0);
    final child = await Process.start(executable(), [
      'run',
      'test/helpers/ownership_process.dart',
      path,
      'hold',
    ]);
    try {
      final signal = await child.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first
          .timeout(const Duration(seconds: 15));
      expect(signal, 'owned');
      expect(
        () => OwnedFileLock.acquire(path),
        throwsA(isA<FileSystemException>()),
      );
    } finally {
      child.kill(ProcessSignal.sigkill);
      await child.exitCode;
    }
    final recovered = OwnedFileLock.acquire(path);
    recovered.close();
  });
}
