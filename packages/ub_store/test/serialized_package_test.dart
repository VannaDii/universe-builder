@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/sqlite.dart';
import 'package:ub_store/ub_store.dart';
import 'package:ub_store/src/serialized_package.dart';

void main() {
  late Directory root;
  late Database input;
  late OwnedSqliteDatabase target;
  late UniverseId universe;
  late ContinuityId continuity, branch;
  late RevisionId initial, current, branchHead;
  late StoredVersion a, b, entity;
  const scalars = [
    'universes',
    'record_identities',
    'continuities',
    'commits',
    'commit_changes',
    'world_name_reservations',
    'head_membership',
    'operation_receipts',
  ];
  Map<String, CanonicalValue> fields(CanonicalValue body) => {
    for (final entry in (body as CanonicalObject).fields)
      entry.key: entry.value,
  };
  setUp(() {
    root = Directory.systemTemp.createTempSync(
      'universe-builder-serialized-package-',
    );
    universe = UniverseId.generate();
    continuity = ContinuityId.generate();
    branch = ContinuityId.generate();
    final source = OwnedSqliteDatabase.create('${root.path}/normal.sqlite');
    try {
      final kernel = SqliteKernel(source.database, universe);
      final principal = PrincipalId.generate();
      source.database.execute('BEGIN IMMEDIATE');
      final genesis = kernel.journal.initialize(
        'Serialized world',
        continuity,
        principal,
      );
      WorkflowStorage(source.database).put(
        'cursor:retained',
        CanonicalValue.parseJson('{"binding":"exact é😀","offset":0}'),
      );
      source.database.execute('COMMIT');
      StoredVersion make(RecordPayload payload) => StoredVersion.build(
        RecordVersionId.generate(),
        RecordIdentity(
          universeId: universe,
          recordId: RecordId.generate(),
          recordKind: payload.recordKind,
        ),
        payload.toWire(),
      );
      EntityTypeRecord type(String key) => EntityTypeRecord(
        namespace: 'world',
        key: key,
        labels: {},
        name: key,
        parentResolution: ParentResolution.root,
        applicability: const UnspecifiedApplicability(),
        classificationExecutable: false,
      );
      a = make(type('A'));
      b = make(type('B'));
      entity = make(
        EntityRecord(
          names: [],
          classificationResolution: ClassificationResolution.ambiguous,
          worldAssociations: [],
          labels: {},
          metadata: {},
        ),
      );
      initial = kernel.commit(
        CommitInput(
          universe: universe,
          continuity: continuity,
          expectedHead: genesis,
          principal: principal,
          decision: 'Original decision',
          reason: 'Original reason',
          idempotencyKey: 'original-create',
          changes: [
            for (final record in [a, b, entity])
              Assignment(recordId: record.identity.recordId, next: record),
          ],
        ),
      );
      source.database.execute('BEGIN IMMEDIATE');
      branchHead = kernel.journal.branch(
        branch,
        continuity,
        initial,
        principal,
      );
      source.database.execute('COMMIT');
      current = kernel.commit(
        CommitInput(
          universe: universe,
          continuity: continuity,
          expectedHead: initial,
          principal: principal,
          decision: 'Original ending',
          reason: 'Original correction',
          idempotencyKey: 'original-retire',
          changes: [
            Assignment(
              recordId: entity.identity.recordId,
              expected: entity.versionId,
              next: null,
            ),
          ],
        ),
      );
      input = sqlite3.openInMemory();
      input.execute('ATTACH DATABASE ? AS original', [source.path]);
      for (final table in scalars) {
        input.execute(
          'CREATE TABLE "$table" AS SELECT * FROM original."$table"',
        );
      }
      input.execute(
        'CREATE TABLE schema_meta(key TEXT,value INTEGER); INSERT INTO schema_meta VALUES(\'schema_version\',2)',
      );
      input.execute(
        'CREATE TABLE record_versions(universe_id TEXT,id TEXT,record_id TEXT,kind TEXT,schema_version TEXT,payload BLOB,digest TEXT)',
      );
      for (final record in [a, b, entity]) {
        final body = fields(record.payload);
        if (record.identity.recordKind == RecordKind.entityType) {
          body.remove('parent');
          body.remove('parentResolution');
          body.remove('applicability');
          body['parents'] = CanonicalArray([]);
        } else {
          body.remove('classification');
          body.remove('classificationResolution');
          body['types'] = CanonicalArray([
            CanonicalString(b.identity.recordId.value),
            CanonicalString(a.identity.recordId.value),
          ]);
        }
        final original = CanonicalObject(body.entries);
        input.execute('INSERT INTO record_versions VALUES(?,?,?,?,?,?,?)', [
          universe.value,
          record.versionId.value,
          record.identity.recordId.value,
          record.identity.recordKind.wireName,
          'v1',
          original.toBytes(),
          payloadDigest(
            '${record.identity.recordKind.wireName}:v1:v1',
            original,
          ),
        ]);
      }
      input.execute(
        'CREATE TABLE workflow_entries(key TEXT,payload BLOB,digest TEXT)',
      );
      final cursor = WorkflowStorage(source.database)
          .evidence('cursor:retained')!;
      input.execute('INSERT INTO workflow_entries VALUES(?,?,?)', [
        'cursor:retained',
        cursor.toBytes(),
        canonicalDigest(cursor),
      ]);
      input.execute(
        'CREATE TABLE snapshot_membership(universe_id TEXT,revision_id TEXT,membership BLOB,checksum TEXT)',
      );
      final snapshot = CanonicalObject([
        for (final entry
            in kernel.journal.snapshot(continuity, initial).entries)
          MapEntry(entry.key.value, CanonicalString(entry.value.value)),
      ]);
      input.execute('INSERT INTO snapshot_membership VALUES(?,?,?,?)', [
        universe.value,
        initial.value,
        snapshot.toBytes(),
        canonicalDigest(snapshot),
      ]);
      input.execute('DETACH DATABASE original');
    } finally {
      source.close();
    }
    input.execute('PRAGMA query_only=ON; BEGIN');
    target = OwnedSqliteDatabase.create('${root.path}/target.sqlite');
  });
  tearDown(() {
    input.close();
    target.close();
    root.deleteSync(recursive: true);
  });

  test('private serialized construction preserves history pinned branch ordered ambiguity active workflow and original receipts', () {
    final report = constructSerializedPackage(input, target.database);
    expect(report.records, 3);
    expect(report.workflows, 1);
    expect(report.comparedTables, 8);
    final journal = SqliteJournal(target.database, universe);
    expect(journal.head(continuity), current);
    expect(journal.head(branch), branchHead);
    expect(
      journal.snapshot(branch, branchHead)[entity.identity.recordId],
      entity.versionId,
    );
    expect(
      journal
          .snapshot(continuity, current)
          .containsKey(entity.identity.recordId),
      isFalse,
    );
    expect(
      journal.load(entity.versionId).toCanonical().toText(),
      entity.toCanonical().toText(),
    );
    expect(
      target.database
          .select(
            'SELECT type_id FROM classification_evidence WHERE version_id=? ORDER BY ordinal',
            [entity.versionId.value],
          )
          .map((row) => row['type_id'])
          .toList(),
      [b.identity.recordId.value, a.identity.recordId.value],
    );
    expect(
      WorkflowStorage(target.database).get('cursor:retained')!.toText(),
      '{"binding":"exact é😀","offset":0}',
    );
    expect(
      target.database
          .select('SELECT count(*) AS n FROM historical_receipt')
          .single['n'],
      0,
    );
    expect(
      target.database
          .select('SELECT count(*) AS n FROM historical_workflow')
          .single['n'],
      0,
    );
    expect(
      target.database
          .select('SELECT count(*) AS n FROM operation_receipts')
          .single['n'],
      2,
    );
    expect(
      target.database
          .select('SELECT count(*) AS n FROM snapshot_member')
          .single['n'],
      3,
    );
    final provenance = target.database.select(
      'SELECT source_digest,normalized_digest FROM import_record_digest WHERE version_id=?',
      [entity.versionId.value],
    ).single;
    expect(
      provenance['source_digest'],
      input.select('SELECT digest FROM record_versions WHERE id=?', [
        entity.versionId.value,
      ]).single['digest'],
    );
    expect(provenance['normalized_digest'], entity.digest);
    target.recover();
    expect(
      journal.snapshot(branch, branchHead)[entity.identity.recordId],
      entity.versionId,
    );
  });

  void mutate(void Function() action) {
    input.execute('COMMIT; PRAGMA query_only=OFF');
    action();
    input.execute('PRAGMA query_only=ON; BEGIN');
  }

  void refused() {
    expect(
      () => constructSerializedPackage(input, target.database),
      throwsFormatException,
    );
    expect(target.database.autocommit, isTrue);
    expect(
      target.database.select('SELECT count(*) AS n FROM universes').single['n'],
      0,
    );
    expect(
      target.database
          .select('SELECT count(*) AS n FROM record_versions')
          .single['n'],
      0,
    );
  }

  test('unversioned serialized bodies retain their original digest recipe', () {
    mutate(() {
      for (final row in input.select(
        'SELECT id,kind,payload FROM record_versions',
      )) {
        final value = CanonicalValue.parseJson(
          utf8.decode(row['payload'] as List<int>),
        );
        input.execute('UPDATE record_versions SET digest=? WHERE id=?', [
          payloadDigest(row['kind'] as String, value),
          row['id'],
        ]);
      }
      input.execute('ALTER TABLE record_versions DROP COLUMN schema_version');
      input.execute('UPDATE schema_meta SET value=1');
    });
    expect(constructSerializedPackage(input, target.database).records, 3);
    expect(
      SqliteJournal(target.database, universe).load(entity.versionId).digest,
      entity.digest,
    );
    expect(
      target.database.select(
        'SELECT source_digest FROM import_record_digest WHERE version_id=?',
        [entity.versionId.value],
      ).single['source_digest'],
      input.select('SELECT digest FROM record_versions WHERE id=?', [
        entity.versionId.value,
      ]).single['digest'],
    );
  });

  test(
    'retained head corruption is refused before recovery can replace it',
    () {
      mutate(
        () => input.execute(
          'DELETE FROM head_membership WHERE continuity_id=?',
          [branch.value],
        ),
      );
      refused();
    },
  );

  test('bad workflow digest rolls back records already converted', () {
    mutate(() => input.execute("UPDATE workflow_entries SET digest='broken'"));
    refused();
    expect(
      target.database
          .select('SELECT count(*) AS n FROM import_record_digest')
          .single['n'],
      0,
    );
  });

  test('invalid serialized snapshot with a valid checksum cannot replace factual history', () {
    mutate(() {
      final wrong = CanonicalObject([]);
      input.execute('UPDATE snapshot_membership SET membership=?,checksum=?', [
        wrong.toBytes(),
        canonicalDigest(wrong),
      ]);
    });
    refused();
  });
  test('unknown evidence tables and bad original digests roll back the private target', () {
    mutate(() => input.execute('CREATE TABLE unknown_evidence(body TEXT)'));
    refused();
    mutate(
      () => input.execute(
        'DROP TABLE unknown_evidence; UPDATE record_versions SET digest=\'broken\'',
      ),
    );
    refused();
  });
  test('ambiguous historical ancestry cycles are rejected without selecting a parent', () {
    mutate(() {
      for (final (record, parent) in [(a, b), (b, a)]) {
        final row = input.select(
          'SELECT payload FROM record_versions WHERE id=?',
          [record.versionId.value],
        ).single;
        final body = fields(
          CanonicalValue.parseJson(utf8.decode(row['payload'] as List<int>)),
        );
        body['parents'] = CanonicalArray([
          CanonicalString(parent.identity.recordId.value),
          CanonicalString(record.identity.recordId.value),
        ]);
        final value = CanonicalObject(body.entries);
        input.execute(
          'UPDATE record_versions SET payload=?,digest=? WHERE id=?',
          [
            value.toBytes(),
            payloadDigest('entity_type:v1:v1', value),
            record.versionId.value,
          ],
        );
      }
    });
    refused();
  });
}
