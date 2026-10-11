@TestOn('vm')
library;

import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/src/candidate_foundation.dart';
import 'package:ub_store/src/candidate_references.dart';
import 'package:ub_store/src/database.dart';
import 'package:ub_store/src/definition_index.dart';
import 'package:ub_store/src/journal.dart';
import 'package:ub_store/src/initialization.dart';
import 'package:ub_store/src/projections.dart';
import 'package:ub_store/src/revision_input.dart';

void main() {
  late Directory directory;
  late Database database;
  late SqliteJournal journal;
  late RevisionId genesis;
  final universe = UniverseId.parse('unv_000000000000000000000001');
  final continuity = ContinuityId.parse('cont_000000000000000000000001');
  final principal = PrincipalId.parse('prn_000000000000000000000001');
  final record = RecordId.parse('rec_000000000000000000000001');

  setUp(() {
    directory = Directory.systemTemp.createTempSync(
      'universe-builder-journal-',
    );
    database = SqliteDatabase.open('${directory.path}/package.sqlite');
    journal = SqliteJournal(database, universe);
    database.execute('BEGIN IMMEDIATE');
    genesis = journal.initialize('Disposable campaign', continuity, principal);
    database.execute('COMMIT');
  });
  tearDown(() {
    database.close();
    directory.deleteSync(recursive: true);
  });

  StoredVersion version(String body, String label) => StoredVersion.build(
    RecordVersionId.parse('ver_$body'),
    RecordIdentity(
      universeId: universe,
      recordId: record,
      recordKind: RecordKind.entity,
    ),
    CanonicalValue.parseJson(
      '{"record_kind":"entity","names":[],"worldAssociations":[],"labels":{"en":"$label"},"metadata":{},"classification":null,"classificationResolution":"unclassified"}',
    ),
  );
  CommitInput input(
    RevisionId head,
    String key,
    StoredVersion? next, {
    RecordVersionId? expected,
    String decision = 'exact approval',
  }) => CommitInput(
    universe: universe,
    continuity: continuity,
    expectedHead: head,
    principal: principal,
    decision: decision,
    reason: 'authored decision',
    idempotencyKey: key,
    changes: [Assignment(recordId: record, expected: expected, next: next)],
  );

  // Exercises the internal primitives with already-admitted unclassified
  // entities. This is a test transaction, not an author publication API.
  RevisionId publish(CommitInput request, {String? failAfter}) {
    void checkpoint(String stage) {
      if (failAfter == stage) throw StateError('Interrupted $stage');
    }

    database.execute('BEGIN IMMEDIATE');
    try {
      final retry = journal.receipt(request);
      if (retry != null) {
        database.execute('ROLLBACK');
        return retry;
      }
      journal.compareWorkflow({});
      final base = journal.snapshot(request.continuity, request.expectedHead);
      final candidate = journal.stageVersions(request);
      checkpoint('versions');
      CandidateFoundation(journal).validate(candidate);
      CandidateReferences(journal).validate(candidate);
      for (final change in request.changes) {
        if (change.next != null) {
          DefinitionIndex(journal).index(change.next!, candidate);
        }
      }
      final initialization = InitializationEvidence(journal);
      final receipts = initialization.pending(request, base, candidate);
      final revision = journal.append(request);
      for (final receipt in receipts) {
        initialization.insert(receipt.admittedAt(revision));
      }
      checkpoint('changes');
      journal.advanceHead(
        request.continuity,
        request.expectedHead,
        revision,
        candidate,
      );
      checkpoint('head');
      for (final assignment in request.changes) {
        if (assignment.next != null) {
          RecordProjections(database).project(0, assignment.next!);
        }
      }
      checkpoint('projections');
      journal.writeReceipt(request, revision);
      checkpoint('receipt');
      checkpoint('beforeCommit');
      database.execute('COMMIT');
      return revision;
    } catch (_) {
      if (!database.autocommit) database.execute('ROLLBACK');
      rethrow;
    }
  }

  StoredVersion world(
    int identity,
    int versionNumber,
    String name, [
    List<String> aliases = const [],
  ]) => StoredVersion.build(
    RecordVersionId.parse('ver_${versionNumber.toString().padLeft(24, '0')}'),
    RecordIdentity(
      universeId: universe,
      recordId: RecordId.parse('rec_${identity.toString().padLeft(24, '0')}'),
      recordKind: RecordKind.world,
    ),
    CanonicalObject(
      {
        'record_kind': CanonicalString('world'),
        'selector': CanonicalString(name),
        'aliases': CanonicalArray(aliases.map(CanonicalString.new)),
        'labels': CanonicalObject([]),
        'metadata': CanonicalObject([]),
      }.entries,
    ),
  );

  CommitInput worldInput(String key, List<Assignment> changes) => CommitInput(
    universe: universe,
    continuity: continuity,
    expectedHead: journal.head(continuity),
    principal: principal,
    decision: 'exact world approval',
    reason: 'authored worlds',
    idempotencyKey: key,
    changes: changes,
  );

  test(
    'world names reject candidate collisions without partial publication',
    () {
      final a = world(1, 1, 'Straße');
      final b = world(2, 2, 'Elsewhere', [' STRASSE ']);
      expect(
        () => publish(
          worldInput('collision', [
            Assignment(recordId: a.identity.recordId, next: a),
            Assignment(recordId: b.identity.recordId, next: b),
          ]),
        ),
        throwsFormatException,
      );
      expect(journal.head(continuity), genesis);
      expect(database.select('SELECT * FROM record_versions'), isEmpty);
      expect(database.select('SELECT * FROM world_name_reservations'), isEmpty);
      final invalid = world(1, 3, 'ALL');
      expect(
        () => publish(
          worldInput('invalid-name', [
            Assignment(recordId: invalid.identity.recordId, next: invalid),
          ]),
        ),
        throwsFormatException,
      );
      expect(journal.head(continuity), genesis);
    },
  );

  test(
    'world reservations survive rename, removal and restart without rebinding',
    () {
      final a = world(1, 1, 'Straße', ['cafe\u0301', 'STRASSE']);
      final first = publish(
        worldInput('first-world', [
          Assignment(recordId: a.identity.recordId, next: a),
        ]),
      );
      expect(
        database.select('SELECT * FROM world_name_reservations'),
        hasLength(2),
      );
      final renamed = world(1, 2, 'New Earth');
      publish(
        worldInput('rename', [
          Assignment(
            recordId: a.identity.recordId,
            expected: a.versionId,
            next: renamed,
          ),
        ]),
      );
      final removed = publish(
        worldInput('remove', [
          Assignment(
            recordId: a.identity.recordId,
            expected: renamed.versionId,
          ),
        ]),
      );
      database.close();
      database = SqliteDatabase.open(
        '${directory.path}/package.sqlite',
        existing: true,
      );
      journal = SqliteJournal(database, universe);
      for (final (i, name) in [(3, 'STRASSE'), (4, 'café'), (5, 'new earth')]) {
        final stolen = world(2, i, name);
        expect(
          () => publish(
            worldInput('steal-$i', [
              Assignment(recordId: stolen.identity.recordId, next: stolen),
            ]),
          ),
          throwsFormatException,
        );
        expect(journal.head(continuity), removed);
        expect(database.select('SELECT * FROM record_versions'), hasLength(2));
      }
      final restored = world(1, 6, 'STRASSE', ['café']);
      publish(
        worldInput('restore-same-world', [
          Assignment(recordId: a.identity.recordId, next: restored),
        ]),
      );
      expect(
        database.select(
          'SELECT first_revision FROM world_name_reservations WHERE name=?',
          ['strasse'],
        ).single['first_revision'],
        first.value,
      );
      expect(
        database.select('SELECT * FROM world_name_reservations'),
        hasLength(3),
      );
      expect(
        () => database.execute('DELETE FROM world_name_reservations'),
        throwsA(isA<SqliteException>()),
      );
      expect(database.select('PRAGMA foreign_key_check'), isEmpty);
    },
  );

  test(
    'typed history and exact receipt retries survive restart and later edits',
    () {
      final original = version('000000000000000000000001', 'Café 🌲');
      final first = input(genesis, 'publish-one', original);
      final revision = publish(first);
      final corrected = version('000000000000000000000002', 'Corrected');
      final second = publish(
        input(revision, 'publish-two', corrected, expected: original.versionId),
      );
      expect(journal.snapshot(continuity, genesis), isEmpty);
      expect(journal.snapshot(continuity, revision), {
        record: original.versionId,
      });
      expect(journal.snapshot(continuity, second), {
        record: corrected.versionId,
      });
      expect(publish(first), revision);
      expect(journal.head(continuity), second);
      expect(
        () => publish(
          input(
            genesis,
            'publish-one',
            original,
            decision: 'different approval',
          ),
        ),
        throwsFormatException,
      );
      database.close();
      database = SqliteDatabase.open(
        '${directory.path}/package.sqlite',
        existing: true,
      );
      journal = SqliteJournal(database, universe);
      expect(publish(first), revision);
      expect(
        journal.load(original.versionId).toCanonical().toBytes(),
        original.toCanonical().toBytes(),
      );
      expect(journal.load(corrected.versionId).digest, corrected.digest);
      expect(journal.head(continuity), second);
      expect(
        database
            .select('SELECT count(*) AS n FROM operation_receipts')
            .single['n'],
        2,
      );
      expect(database.select('PRAGMA foreign_key_check'), isEmpty);
    },
  );

  test(
    'interruption at each publication stage rolls back every authoritative row',
    () {
      final original = version('000000000000000000000001', 'Original');
      final request = input(genesis, 'interrupted', original);
      for (final stage in [
        'versions',
        'changes',
        'head',
        'projections',
        'receipt',
        'beforeCommit',
      ]) {
        expect(() => publish(request, failAfter: stage), throwsStateError);
        expect(journal.head(continuity), genesis);
        expect(journal.snapshot(continuity, genesis), isEmpty);
        expect(journal.receipt(request), isNull);
        for (final table in [
          'record_identities',
          'record_versions',
          'r_payload',
          'commit_changes',
          'head_membership',
          'operation_receipts',
          'instance_classification',
          'type_definition',
          'type_world',
          'definition_attribute',
          'initialization_receipt',
          'reference_index',
          'typed_projection',
          'world_projection',
          'narrative_projection',
          'search_index',
        ]) {
          expect(
            database.select('SELECT count(*) AS n FROM $table').single['n'],
            0,
            reason: '$stage/$table',
          );
        }
        expect(
          database.select('SELECT count(*) AS n FROM commits').single['n'],
          1,
        );
      }
      expect(publish(request), isNot(genesis));
    },
  );

  test('stale heads, prior versions and changed digests cannot publish', () {
    final original = version('000000000000000000000001', 'Original');
    final head = publish(input(genesis, 'one', original));
    final corrected = version('000000000000000000000002', 'Corrected');
    expect(
      () => publish(input(genesis, 'stale', corrected)),
      throwsFormatException,
    );
    expect(
      () => publish(input(head, 'prior', corrected)),
      throwsFormatException,
    );
    final tampered = StoredVersion(
      versionId: corrected.versionId,
      identity: corrected.identity,
      payload: corrected.payload,
      digest: original.digest,
    );
    expect(
      () => publish(
        input(head, 'tampered', tampered, expected: original.versionId),
      ),
      throwsFormatException,
    );
    expect(journal.head(continuity), head);
    expect(
      database.select('SELECT count(*) AS n FROM record_versions').single['n'],
      1,
    );
  });

  test('tombstones preserve original records and history', () {
    final original = version('000000000000000000000001', 'Original');
    final head = publish(input(genesis, 'one', original));
    final removed = publish(
      input(head, 'remove', null, expected: original.versionId),
    );
    expect(journal.snapshot(continuity, removed), isEmpty);
    expect(journal.snapshot(continuity, head), {record: original.versionId});
    expect(journal.load(original.versionId).digest, original.digest);
    expect(
      () => publish(input(removed, 'remove-again', null)),
      throwsFormatException,
    );
  });

  test('historical imported receipts cannot satisfy active retries', () {
    final original = version('000000000000000000000001', 'Original');
    final request = input(genesis, 'one', original);
    final head = publish(request);
    database.execute("INSERT INTO historical_receipt VALUES(?,?,'commit',?)", [
      universe.value,
      principal.value,
      request.idempotencyKey,
    ]);
    expect(journal.receipt(request), isNull);
    expect(() => publish(request), throwsFormatException);
    expect(journal.head(continuity), head);
  });

  test('journal mutations require a caller-owned transaction', () {
    final original = version('000000000000000000000001', 'Original');
    final request = input(genesis, 'one', original);
    expect(() => journal.stageVersions(request), throwsStateError);
    expect(() => journal.append(request), throwsStateError);
    expect(() => journal.writeReceipt(request, genesis), throwsStateError);
    expect(
      () => journal.compareWorkflow({'proposal:': 'unmatched'}),
      throwsFormatException,
    );
  });

  test(
    'alternate continuity pins its parent revision through edits and restart',
    () {
      final original = version('000000000000000000000001', 'Original');
      final parent = publish(input(genesis, 'one', original));
      final alternate = ContinuityId.parse('cont_000000000000000000000002');
      database.execute('BEGIN IMMEDIATE');
      final branch = journal.branch(alternate, continuity, parent, principal);
      database.execute('COMMIT');
      final corrected = version('000000000000000000000002', 'Corrected');
      final parentLater = publish(
        input(parent, 'two', corrected, expected: original.versionId),
      );
      expect(journal.snapshot(alternate, branch), {record: original.versionId});
      database.execute('BEGIN IMMEDIATE');
      expect(journal.branch(alternate, continuity, parent, principal), branch);
      expect(
        () => journal.branch(alternate, continuity, parentLater, principal),
        throwsFormatException,
      );
      database.execute('ROLLBACK');
      database.close();
      database = SqliteDatabase.open(
        '${directory.path}/package.sqlite',
        existing: true,
      );
      journal = SqliteJournal(database, universe);
      expect(journal.head(continuity), parentLater);
      expect(journal.head(alternate), branch);
      expect(journal.snapshot(alternate, branch), {record: original.versionId});
      expect(journal.snapshot(continuity, parentLater), {
        record: corrected.versionId,
      });
      expect(
        () => journal.snapshot(alternate, parentLater),
        throwsFormatException,
      );
    },
  );
}
