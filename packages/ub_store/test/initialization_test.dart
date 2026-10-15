@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/src/candidate_foundation.dart';
import 'package:ub_store/src/archive_selection.dart';
import 'package:ub_store/src/candidate_references.dart';
import 'package:ub_store/src/database.dart';
import 'package:ub_store/src/definition_index.dart';
import 'package:ub_store/src/initialization.dart';
import 'package:ub_store/src/journal.dart';
import 'package:ub_store/src/projections.dart';
import 'package:ub_store/src/revision_input.dart';

void main() {
  String id(String prefix, int n) =>
      '${prefix}_${n.toRadixString(16).padLeft(24, '0')}';
  final universe = UniverseId.parse(id('unv', 1));
  final continuity = ContinuityId.parse(id('cont', 1));
  final principal = PrincipalId.parse(id('prn', 1));
  Map<String, Object> rr(int n) => {
    'universe': universe.value,
    'record': id('rec', n),
  };
  StoredVersion record(int n, int v, Map<String, Object?> payload) =>
      StoredVersion.build(
        RecordVersionId.parse(id('ver', v)),
        RecordIdentity(
          universeId: universe,
          recordId: RecordId.parse(id('rec', n)),
          recordKind: RecordKind.parse(payload['record_kind']! as String),
        ),
        CanonicalValue.parseJson(jsonEncode(payload)),
      );
  Map<String, Object?> payload(StoredVersion r) =>
      jsonDecode(r.payload.toText()) as Map<String, Object?>;
  StoredVersion changed(StoredVersion r, int v, Map<String, Object?> changes) =>
      record(int.parse(r.identity.recordId.value.substring(4), radix: 16), v, {
        ...payload(r),
        ...changes,
      });
  StoredVersion proposition(int n, int v, int subject, String digits) =>
      record(n, v, {
        'record_kind': 'proposition',
        'subject': rr(subject),
        'predicate': rr(2),
        'value': {'kind': 'integer', 'digits': digits},
        'quantification': 'particular',
        'context': rr(3),
      });
  StoredVersion assertion(
    int n,
    int v,
    int proposition,
    String mode,
    Map<String, Object?> basis,
  ) => record(n, v, {
    'record_kind': 'assertion',
    'attributeMode': mode,
    'proposition': rr(proposition),
    'polarity': 'support',
    'scope': {
      'context': rr(3),
      'applicability': {'kind': 'universe_wide'},
    },
    'validity': {
      'kind': 'calendar_interval',
      'calendar': id('cal', 4),
      'start': {'kind': 'exact', 'value': '10'},
      'end': {'kind': 'exact', 'value': '11'},
    },
    'persistence': 'explicit_interval',
    'precision': 'exact',
    'basis': basis,
  });
  late Directory directory;
  late Database database;
  late SqliteJournal journal;
  late RevisionId baseRevision;
  late List<StoredVersion> baseRows;
  CommitInput request(String key, List<StoredVersion> records) {
    final head = journal.head(continuity);
    final membership = journal.snapshot(continuity, head);
    return CommitInput(
      universe: universe,
      continuity: continuity,
      expectedHead: head,
      principal: principal,
      decision: 'reviewed fixture',
      reason: key,
      idempotencyKey: key,
      changes: [
        for (final r in records)
          Assignment(
            recordId: r.identity.recordId,
            expected: membership[r.identity.recordId],
            next: r,
          ),
      ],
    );
  }

  RevisionId publish(CommitInput input, {String? failAfter}) {
    void checkpoint(String stage) {
      if (stage == failAfter) throw StateError('Interrupted $stage');
    }

    database.execute('BEGIN IMMEDIATE');
    try {
      final retry = journal.receipt(input);
      if (retry != null) {
        database.execute('ROLLBACK');
        return retry;
      }
      final base = journal.snapshot(input.continuity, input.expectedHead);
      final candidate = journal.stageVersions(input);
      checkpoint('versions');
      CandidateFoundation(journal).validate(candidate);
      CandidateReferences(journal).validate(candidate);
      for (final change in input.changes) {
        if (change.next != null) {
          DefinitionIndex(journal).index(change.next!, candidate);
        }
      }
      final evidence = InitializationEvidence(journal);
      final pending = evidence.pending(input, base, candidate);
      final revision = journal.append(input);
      for (final receipt in pending) {
        evidence.insert(receipt.admittedAt(revision));
      }
      checkpoint('changes');
      journal.advanceHead(
        input.continuity,
        input.expectedHead,
        revision,
        candidate,
      );
      checkpoint('head');
      final generation =
          database
                  .select('SELECT generation FROM projection_state')
                  .single['generation']
              as int;
      for (final change in input.changes) {
        if (change.next != null) {
          RecordProjections(database).project(generation, change.next!);
        }
      }
      checkpoint('projections');
      journal.writeReceipt(input, revision);
      checkpoint('receipt');
      checkpoint('beforeCommit');
      database.execute('COMMIT');
      return revision;
    } catch (_) {
      if (!database.autocommit) database.execute('ROLLBACK');
      rethrow;
    }
  }

  List<StoredVersion> initial(int instance, int offset) => [
    record(offset, offset, {
      'record_kind': 'event',
      'occurrence': 'occurred',
      'time': {'kind': 'exact', 'calendar': id('cal', 4), 'value': '10'},
      'participants': [
        {'record': rr(instance), 'role': 'starting_instance'},
      ],
      'labels': <String, Object>{},
    }),
    proposition(offset + 1, offset + 1, instance, '12'),
    assertion(offset + 2, offset + 2, offset + 1, 'instance', {
      'kind': 'instance_initialization',
      'start': {...rr(offset), 'version': id('ver', offset)},
      'definition': {...rr(6), 'version': id('ver', 6)},
      'source_revision': journal.head(continuity).value,
    }),
  ];
  setUp(() {
    directory = Directory.systemTemp.createTempSync(
      'universe-builder-initialization-',
    );
    database = SqliteDatabase.open('${directory.path}/package.sqlite');
    journal = SqliteJournal(database, universe);
    database.execute('BEGIN IMMEDIATE');
    journal.initialize('Initialization', continuity, principal);
    database.execute('COMMIT');
    baseRows = [
      record(1, 1, {
        'record_kind': 'entity_type',
        'namespace': 'pistol',
        'key': 'gun',
        'name': 'Gun',
        'labels': <String, Object>{},
        'parent': null,
        'parentResolution': 'root',
        'applicability': {'kind': 'universe_wide'},
        'classificationExecutable': true,
      }),
      record(2, 2, {
        'record_kind': 'property',
        'namespace': 'pistol',
        'key': 'rounds',
        'labels': <String, Object>{},
        'subjectTypes': [id('rec', 1)],
        'value': {'kind': 'integer'},
        'multiplicity': 'single',
        'persistence': 'explicit_interval',
        'exclusive': false,
        'symmetric': false,
        'transitive': false,
      }),
      record(3, 3, {
        'record_kind': 'represented_context',
        'universe': universe.value,
        'kind': {'kind': 'objective'},
        'labels': <String, Object>{},
      }),
      record(4, 4, {
        'record_kind': 'calendar',
        'namespace': 'pistol',
        'key': 'clock',
        'labels': <String, Object>{},
        'unitStructure': <String, Object>{},
      }),
      proposition(5, 5, 1, '12'),
      assertion(6, 6, 5, 'initial_value', {
        'kind': 'author_decision',
        'note': 'Starts with twelve',
      }),
      for (final n in [7, 8])
        record(n, n, {
          'record_kind': 'entity',
          'names': <Object>[],
          'classification': id('rec', 1),
          'classificationResolution': 'resolved',
          'worldAssociations': <Object>[],
          'labels': <String, Object>{},
          'metadata': <String, Object>{},
        }),
    ];
    baseRevision = publish(request('base', baseRows));
  });
  tearDown(() {
    database.close();
    directory.deleteSync(recursive: true);
  });

  test(
    'semantic indexes preserve selected definition and instance identities',
    () {
      final type = database.select('SELECT * FROM type_definition').single;
      expect(type['record_id'], id('rec', 1));
      expect(type['parent_id'], isNull);
      expect(type['applicability'], 'universe');
      expect(
        database.select('SELECT * FROM instance_classification'),
        hasLength(2),
      );
      final attribute = database
          .select('SELECT * FROM definition_attribute')
          .single;
      expect(attribute['subject_id'], id('rec', 1));
      expect(attribute['predicate_id'], id('rec', 2));
      expect(attribute['mode'], 'initial_value');
      expect(
        () => DefinitionIndex(journal)
            .index(baseRows.first, journal.snapshot(continuity, baseRevision)),
        throwsStateError,
      );
    },
  );
  test('filtered archive selection retains initialization attachments only for included instances', () {
    publish(request('initialize-both', [...initial(7, 20), ...initial(8, 30)]));
    final selected = archiveSelection(database, universe, [
      RecordId.parse(id('rec', 7)),
    ]);
    expect(
      selected,
      containsAll([
        for (final n in [1, 2, 3, 4, 5, 6, 7, 20, 21, 22])
          RecordId.parse(id('rec', n)),
      ]),
    );
    for (final n in [8, 30, 31, 32]) {
      expect(selected, isNot(contains(RecordId.parse(id('rec', n)))));
    }
  });

  test('type world indexes preserve authored order and earlier definition versions', () {
    final worlds = [
      for (final n in [9, 10])
        record(n, n, {
          'record_kind': 'world',
          'selector': 'World $n',
          'aliases': <Object>[],
          'labels': <String, Object>{},
          'metadata': <String, Object>{},
        }),
    ];
    final scoped = changed(baseRows.first, 16, {
      'applicability': {
        'kind': 'worlds',
        'world_ids': [id('wld', 10), id('wld', 9)],
      },
    });
    publish(request('scoped-definition', [scoped, ...worlds]));
    expect(
      database.select(
        'SELECT applicability FROM type_definition WHERE version_id=?',
        [id('ver', 1)],
      ).single['applicability'],
      'universe',
    );
    expect(
      database.select(
        'SELECT applicability FROM type_definition WHERE version_id=?',
        [id('ver', 16)],
      ).single['applicability'],
      'worlds',
    );
    final rows = database.select(
      'SELECT ordinal,world_id FROM type_world WHERE version_id=? ORDER BY ordinal',
      [id('ver', 16)],
    );
    expect(rows.map((r) => r['world_id']), [id('rec', 10), id('rec', 9)]);
    expect(rows.map((r) => r['ordinal']), [0, 1]);
    expect(database.select('PRAGMA foreign_key_check'), isEmpty);
  });
  test('initialization receipts retain exact provenance across corrections and restart', () {
    final first = request('first', initial(7, 10));
    final revision = publish(first);
    final evidence = InitializationEvidence(journal);
    final receipts = evidence.read();
    expect(receipts, hasLength(1));
    expect(receipts.single.instance, RecordId.parse(id('rec', 7)));
    expect(receipts.single.assertion, RecordVersionId.parse(id('ver', 12)));
    expect(receipts.single.sourceRevision, baseRevision);
    expect(receipts.single.revision, revision);
    publish(request('second', initial(8, 20)));
    expect(publish(first), revision);
    publish(request('correct-value', [proposition(11, 31, 7, '7')]));
    final currentAssertion = journal.load(RecordVersionId.parse(id('ver', 12)));
    publish(
      request('correct-assertion', [
        changed(currentAssertion, 32, {'precision': 'approximate'}),
      ]),
    );
    expect(evidence.read().first, receipts.single);
    expect(
      journal.load(RecordVersionId.parse(id('ver', 11))).digest,
      proposition(11, 11, 7, '12').digest,
    );
    database.close();
    database = SqliteDatabase.open(
      '${directory.path}/package.sqlite',
      existing: true,
    );
    journal = SqliteJournal(database, universe);
    expect(InitializationEvidence(journal).read().first, receipts.single);
    expect(
      () => publish(request('refill', initial(7, 40))),
      throwsFormatException,
    );
    expect(database.select('PRAGMA foreign_key_check'), isEmpty);
  });
  test('recovery checks initialization after multiple batches of ordinary assertions', () {
    publish(request('mixed-assertions', [
      proposition(100, 100, 7, '12'),
      for (var n = 101; n < 156; n++)
        assertion(n, n, 100, 'instance', {
          'kind': 'author_decision',
          'note': 'Ordinary authored assertion',
        }),
      ...initial(8, 200),
    ]));
    final receipts = InitializationEvidence(journal).read();
    expect(receipts, hasLength(1));
    expect(receipts.single.instance, RecordId.parse(id('rec', 8)));
    InitializationEvidence(journal).verify();
    database.close();
    database = SqliteDatabase.open(
      '${directory.path}/package.sqlite',
      existing: true,
    );
    journal = SqliteJournal(database, universe);
    InitializationEvidence(journal).verify();
    expect(InitializationEvidence(journal).read(), receipts);
    database.execute('BEGIN IMMEDIATE');
    try {
      database.execute('DELETE FROM initialization_receipt');
      expect(InitializationEvidence(journal).verify, throwsFormatException);
    } finally {
      database.execute('ROLLBACK');
    }
    expect(InitializationEvidence(journal).read(), receipts);
  });

  test('duplicate initialization and a forged value publish no records or receipts', () {
    final head = journal.head(continuity);
    final count = database
        .select('SELECT count(*) AS n FROM record_versions')
        .single['n'];
    expect(
      () =>
          publish(request('duplicate', [...initial(7, 10), ...initial(7, 20)])),
      throwsFormatException,
    );
    final wrong = initial(7, 30);
    wrong[1] = proposition(31, 31, 7, '13');
    expect(() => publish(request('forged', wrong)), throwsFormatException);
    expect(journal.head(continuity), head);
    expect(
      database.select('SELECT count(*) AS n FROM record_versions').single['n'],
      count,
    );
    expect(InitializationEvidence(journal).read(), isEmpty);
  });
  test('interruption rolls back definition indexes and immutable initialization receipts', () {
    final input = request('interrupt', [
      ...initial(7, 10),
      changed(baseRows.first, 50, {'name': 'Renamed gun type'}),
      changed(baseRows[6], 51, {
        'labels': {'en': 'Renamed instance'},
      }),
    ]);
    for (final stage in [
      'versions',
      'changes',
      'head',
      'projections',
      'receipt',
      'beforeCommit',
    ]) {
      expect(() => publish(input, failAfter: stage), throwsStateError);
      expect(journal.head(continuity), baseRevision);
      expect(InitializationEvidence(journal).read(), isEmpty);
      expect(database.select('SELECT * FROM record_versions'), hasLength(8));
      expect(
        database.select('SELECT * FROM definition_attribute'),
        hasLength(1),
      );
      expect(
        database.select('SELECT * FROM instance_classification'),
        hasLength(2),
      );
      expect(database.select('SELECT * FROM type_definition'), hasLength(1));
    }
    publish(input);
    expect(InitializationEvidence(journal).read(), hasLength(1));
  });
  test('initialization requires exact authored occurrence and unchanged executable ancestry', () {
    final rows = initial(7, 10);
    for (final occurrence in <Object>[
      'planned',
      'hypothetical',
      {
        'descriptive': {'label': 'authored mode'},
      },
    ]) {
      final changedRows = [...rows];
      changedRows[0] = changed(rows[0], 10, {'occurrence': occurrence});
      expect(
        () => publish(request('occurrence-$occurrence', changedRows)),
        throwsFormatException,
      );
    }
    final changedTime = [...rows];
    changedTime[0] = changed(rows[0], 10, {
      'time': {'kind': 'unspecified'},
    });
    expect(
      () => publish(request('no-exact-time', changedTime)),
      throwsFormatException,
    );
    final changedDefinition = changed(baseRows[5], 30, {
      'precision': 'approximate',
    });
    expect(
      () =>
          publish(request('changed-definition', [...rows, changedDefinition])),
      throwsFormatException,
    );
    final changedProposition = proposition(5, 31, 1, '13');
    expect(
      () => publish(
        request('changed-proposition', [...rows, changedProposition]),
      ),
      throwsFormatException,
    );
    final changedType = changed(baseRows[0], 32, {
      'classificationExecutable': false,
    });
    expect(
      () => publish(request('unresolved-ancestry', [...rows, changedType])),
      throwsFormatException,
    );
    final noNamespace = [...rows];
    final basis = {...payload(rows[2])['basis']! as Map<String, Object?>};
    basis['definition'] = {'record': id('rec', 6), 'version': id('ver', 6)};
    noNamespace[2] = changed(rows[2], 12, {'basis': basis});
    expect(
      () => publish(request('no-namespace', noNamespace)),
      throwsFormatException,
    );
    expect(journal.head(continuity), baseRevision);
    expect(InitializationEvidence(journal).read(), isEmpty);
  });
  test('receipts follow pinned ancestry and historical restoration preserves the original', () {
    final rows = initial(7, 10);
    final first = publish(request('first', rows));
    final evidence = InitializationEvidence(journal);
    final original = evidence.read();
    expect(evidence.readAt(continuity, baseRevision), isEmpty);
    expect(evidence.readAt(continuity, first), original);
    final branch = ContinuityId.parse(id('cont', 2));
    database.execute('BEGIN IMMEDIATE');
    final branchRevision = journal.branch(branch, continuity, first, principal);
    database.execute('COMMIT');
    publish(request('second-instance', initial(8, 20)));
    expect(evidence.readAt(branch, branchRevision), original);
    final remove = CommitInput(
      universe: universe,
      continuity: continuity,
      expectedHead: journal.head(continuity),
      principal: principal,
      decision: 'reviewed retraction',
      reason: 'retract',
      idempotencyKey: 'retract',
      changes: [
        Assignment(
          recordId: rows[2].identity.recordId,
          expected: rows[2].versionId,
        ),
      ],
    );
    publish(remove);
    publish(request('restore', [changed(rows[2], 99, {})]));
    expect(evidence.read().first, original.single);
    evidence.verify();
    database.execute('BEGIN IMMEDIATE');
    database.execute('DELETE FROM initialization_receipt');
    expect(evidence.verify, throwsFormatException);
    database.execute('ROLLBACK');
    evidence.verify();
  });
}
