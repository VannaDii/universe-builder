@TestOn('vm')
library;

import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/src/database.dart';
import 'package:ub_store/src/kernel.dart';
import 'package:ub_store/src/revision_input.dart';
import 'package:ub_store/src/workflow_storage.dart';

String suffix(int n) => n.toRadixString(16).padLeft(24, '0');
RecordId record(int n) => RecordId.parse('rec_${suffix(n)}');
RecordVersionId version(int n) => RecordVersionId.parse('ver_${suffix(n)}');
final universe = UniverseId.parse('unv_${suffix(1)}'),
    continuity = ContinuityId.parse('cont_${suffix(1)}'),
    principal = PrincipalId.parse('prn_${suffix(1)}');

StoredVersion entity(int id, int ver, {RecordId? classification}) =>
    StoredVersion.build(
      version(ver),
      RecordIdentity(
        universeId: universe,
        recordId: record(id),
        recordKind: RecordKind.entity,
      ),
      EntityRecord(
        names: [],
        classification: classification,
        classificationResolution: classification == null
            ? ClassificationResolution.unclassified
            : ClassificationResolution.resolved,
        worldAssociations: [],
        labels: {'en': 'Disposable entity $ver'},
        metadata: {},
      ).toWire(),
    );

void main() {
  late Directory directory;
  late Database database;
  late SqliteKernel kernel;
  late RevisionId genesis;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('universe-builder-kernel-');
    database = SqliteDatabase.open('${directory.path}/package.sqlite');
    kernel = SqliteKernel(database, universe);
    database.execute('BEGIN IMMEDIATE');
    genesis = kernel.journal.initialize(
      'Disposable universe',
      continuity,
      principal,
    );
    database.execute('COMMIT');
  });
  tearDown(() {
    database.close();
    directory.deleteSync(recursive: true);
  });

  CommitInput input(String key, List<Assignment> changes, {RevisionId? head}) =>
      CommitInput(
        universe: universe,
        continuity: continuity,
        expectedHead: head ?? genesis,
        principal: principal,
        decision: 'Already admitted disposable input',
        reason: 'Kernel transaction regression',
        idempotencyKey: key,
        changes: changes,
      );
  Assignment create(int n) =>
      Assignment(recordId: record(n), next: entity(n, n));
  int count(String table) =>
      database.select('SELECT count(*) AS n FROM $table').single['n'] as int;
  Map<String, int> sizes() => {
    for (final table in [
      'record_identities',
      'record_versions',
      'commits',
      'commit_changes',
      'operation_receipts',
      'reference_index',
      'type_definition',
      'instance_classification',
      'definition_attribute',
      'initialization_receipt',
    ])
      table: count(table),
  };

  test('preview returns sorted candidate after full rollback, then publication survives reopen', () {
    final request = input('create', [create(2), create(1)]);
    final before = sizes();
    final preview = kernel.preview(request);
    expect(preview.map((r) => r.identity.recordId), [record(1), record(2)]);
    expect(sizes(), before);
    expect(kernel.journal.head(continuity), genesis);
    expect(kernel.identityExists(record(1)), isFalse);
    expect(kernel.journal.receipt(request), isNull);
    final revision = kernel.commit(request);
    expect(kernel.identityExists(record(1)), isTrue);
    database.close();
    database = SqliteDatabase.open(
      '${directory.path}/package.sqlite',
      existing: true,
    );
    kernel = SqliteKernel(database, universe);
    expect(kernel.journal.head(continuity), revision);
    expect(
      kernel.journal.load(version(1)).toCanonical().toText(),
      entity(1, 1).toCanonical().toText(),
    );
    final committed = sizes();
    // Exact receipt retries precede current head and workflow comparison.
    expect(
      kernel.commit(request, expectedWorkflow: {'proposal:missing:': 'stale'}),
      revision,
    );
    expect(sizes(), committed);
    expect(() => kernel.preview(request), throwsFormatException);
  });

  test(
    'every commit checkpoint rolls back head, history, projections and receipt',
    () {
      final before = sizes();
      for (final failure in CommitFaultPoint.values) {
        final seen = <CommitFaultPoint>[];
        expect(
          () => kernel.commit(
            input('failure-${failure.name}', [create(1)]),
            hook: (point) {
              seen.add(point);
              if (point == failure) {
                throw StateError('Interrupted ${point.name}');
              }
            },
          ),
          throwsStateError,
        );
        expect(seen.last, failure);
        expect(sizes(), before);
        expect(kernel.journal.head(continuity), genesis);
        expect(kernel.identityExists(record(1)), isFalse);
        expect(database.autocommit, isTrue);
      }
    },
  );

  test(
    'stale workflow capture rejects publication without staging versions',
    () {
      const key = 'reserved-record:rec_000000000000000000000001';
      final value = CanonicalObject([
        MapEntry('proposal_id', CanonicalString('prp_${suffix(1)}')),
      ]);
      WorkflowStorage(database).compareAppend({}, [MapEntry(key, value)]);
      final before = sizes();
      expect(
        () => kernel.commit(
          input('stale', [create(1)]),
          expectedWorkflow: {key: null},
        ),
        throwsFormatException,
      );
      expect(sizes(), before);
      expect(kernel.identityExists(record(1)), isFalse);
      expect(
        kernel.commit(
          input('current', [create(1)]),
          expectedWorkflow: {key: key},
        ),
        isA<RevisionId>(),
      );
    },
  );

  test('preview enforces foundation and prior-version gates without retaining rejected rows', () {
    final before = sizes();
    final invalid = input('invalid', [
      Assignment(
        recordId: record(1),
        next: entity(1, 1, classification: record(99)),
      ),
    ]);
    expect(() => kernel.preview(invalid), throwsFormatException);
    expect(sizes(), before);
    final head = kernel.commit(input('valid', [create(1)]));
    final wrong = input('wrong-prior', [
      Assignment(recordId: record(1), expected: version(2), next: entity(1, 3)),
    ], head: head);
    final committed = sizes();
    expect(() => kernel.preview(wrong), throwsFormatException);
    expect(sizes(), committed);
    final updated = input('update', [
      Assignment(recordId: record(1), expected: version(1), next: entity(1, 3)),
    ], head: head);
    expect(kernel.preview(updated).single.versionId, version(3));
    expect(kernel.journal.load(version(1)).versionId, version(1));
    expect(sizes(), committed);
  });

  test('kernel cannot take ownership of an existing transaction', () {
    database.execute('BEGIN IMMEDIATE');
    expect(() => kernel.commit(input('nested', [create(1)])), throwsStateError);
    expect(database.autocommit, isFalse);
    database.execute('ROLLBACK');
  });

  test('preview reaches durable world-name reservation checks after candidate admission', () {
    StoredVersion world(int id, int ver, String name) => StoredVersion.build(
      version(ver),
      RecordIdentity(
        universeId: universe,
        recordId: record(id),
        recordKind: RecordKind.world,
      ),
      CanonicalObject([
        MapEntry('record_kind', CanonicalString('world')),
        MapEntry('selector', CanonicalString(name)),
        MapEntry('aliases', CanonicalArray([])),
        MapEntry('labels', CanonicalObject([])),
        MapEntry('metadata', CanonicalObject([])),
      ]),
    );
    final first = kernel.commit(
      input('world', [
        Assignment(recordId: record(1), next: world(1, 1, 'Original')),
      ]),
    );
    final head = kernel.commit(
      input('rename', [
        Assignment(
          recordId: record(1),
          expected: version(1),
          next: world(1, 2, 'Renamed'),
        ),
      ], head: first),
    );
    final request = input('reuse-name', [
      Assignment(recordId: record(2), next: world(2, 3, 'Original')),
    ], head: head);
    final before = sizes(), reservations = count('world_name_reservations');
    // No current selector collides. The former name remains reserved in history.
    expect(() => kernel.preview(request), throwsFormatException);
    expect(sizes(), before);
    expect(count('world_name_reservations'), reservations);
    expect(kernel.journal.head(continuity), head);
    expect(kernel.identityExists(record(2)), isFalse);
  });

  test('image changes remain unavailable in both commit and preview until decoding admission is ported', () {
    final asset = ImageAssetRecord(
      contentDigest: '0' * 64,
      mediaType: 'image/png',
      byteSize: BigInt.one,
      width: 1,
      height: 1,
      originalName: 'disposable.png',
    );
    final next = StoredVersion.build(
      version(1),
      RecordIdentity(
        universeId: universe,
        recordId: record(1),
        recordKind: RecordKind.imageAsset,
      ),
      asset.toWire(),
    );
    final request = input('image', [
      Assignment(recordId: record(1), next: next),
    ]);
    final before = sizes();
    expect(() => kernel.preview(request), throwsUnsupportedError);
    expect(() => kernel.commit(request), throwsUnsupportedError);
    expect(sizes(), before);
    expect(kernel.identityExists(record(1)), isFalse);
  });
}
