@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/src/candidate_references.dart';
import 'package:ub_store/src/catalog.dart';
import 'package:ub_store/src/database.dart';
import 'package:ub_store/src/journal.dart';
import 'package:ub_store/src/projections.dart';
import 'package:ub_store/src/references.dart';
import 'package:ub_store/src/revision_input.dart';

void main() {
  final universe = UniverseId.parse('unv_000000000000000000000001');
  const record = 'rec_00000000000000000000000f';
  const other = 'unv_000000000000000000000002';
  final fixtures = jsonDecode(
    File('../../fixtures/normalized-foundation/historical-digests.json')
        .readAsStringSync(),
  ) as List<dynamic>;
  CanonicalValue canonical(Object? value) =>
      CanonicalValue.parseJson(jsonEncode(value));

  test(
    'consequence fixtures preserve predicate paths, units and namespace guards',
    () {
      final grant =
          (fixtures[5] as Map<String, dynamic>)['payload']
              as Map<String, dynamic>;
      final refs = ReferenceScan.collect(canonical(grant), universe);
      for (final path in [
        '/consequenceContract/slots/0/target/predicate',
        '/consequenceContract/slots/0/condition/predicate',
      ]) {
        expect(refs.records.any((r) => r.path == path), isTrue);
        for (final replacement in [null, other]) {
          final changed = jsonDecode(jsonEncode(grant)) as Map<String, dynamic>;
          dynamic node = changed;
          for (final segment in path.substring(1).split('/')) {
            node = node is List<dynamic>
                ? node[int.parse(segment)]
                : (node as Map<String, dynamic>)[segment];
          }
          (node as Map<String, dynamic>)['universe'] = replacement;
          expect(
            () => ReferenceScan.collect(canonical(changed), universe),
            throwsFormatException,
          );
        }
      }
      final transfer = (fixtures[4] as Map<String, dynamic>)['payload'];
      expect(
        ReferenceScan.collect(canonical(transfer), universe).typed.where(
          (r) =>
              r.record.value == 'rec_000000000000000000000007' &&
              r.kind == RecordKind.unit,
        ),
        hasLength(2),
      );
    },
  );

  test(
    'authored prose is ignored while declared map names retain references',
    () {
      final refs = ReferenceScan.collect(
        CanonicalValue.parseJson('''{
      "labels":{"en":"$record"},"description":"$record","text":"$record",
      "metadata":{"text":{"kind":"entity_ref","ref":{"universe":"${universe.value}","record":"$record"}}}
    }'''),
        universe,
      );
      expect(refs.records, hasLength(1));
      expect(refs.records.single.path, '/metadata/text/ref');
      expect(refs.scalars.any((r) => r.$2 == record), isFalse);
      expect(
        () => ReferenceScan.collect(
          CanonicalValue.parseJson('''{
      "metadata":{"text":{"kind":"entity_ref","ref":{"universe":"$other","record":"$record"}}}
    }'''),
          universe,
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'exact version pins never acquire a second current-state dependency',
    () {
      final refs = ReferenceScan.collect(
        CanonicalValue.parseJson('''{
      "ref":{"universe":"${universe.value}","record":"$record","version":"ver_000000000000000000000001"}
    }'''),
        universe,
      );
      expect(refs.records, hasLength(1));
      expect(
        refs.records.single.version?.value,
        'ver_000000000000000000000001',
      );
      expect(refs.records.any((r) => r.version == null), isFalse);
      expect(
        () => ReferenceScan.collect(
          CanonicalValue.parseJson('{"ref":{"record":"$record"}}'),
          universe,
        ),
        throwsFormatException,
      );
    },
  );

  late Directory directory;
  late Database database;
  late SqliteJournal journal;
  late RevisionId genesis;
  final continuity = ContinuityId.parse('cont_000000000000000000000001');
  final principal = PrincipalId.parse('prn_000000000000000000000001');
  setUp(() {
    directory = Directory.systemTemp.createTempSync(
      'universe-builder-references-',
    );
    database = SqliteDatabase.open('${directory.path}/package.sqlite');
    journal = SqliteJournal(database, universe);
    database.execute('BEGIN IMMEDIATE');
    genesis = journal.initialize('Disposable world', continuity, principal);
    database.execute('COMMIT');
  });
  tearDown(() {
    database.close();
    directory.deleteSync(recursive: true);
  });
  StoredVersion version(String id, String version, CanonicalValue payload) =>
      StoredVersion.build(
        RecordVersionId.parse(version),
        RecordIdentity(
          universeId: universe,
          recordId: RecordId.parse(id),
          recordKind: RecordKind.parse(
            (objectFields(payload)['record_kind'] as CanonicalString).value,
          ),
        ),
        payload,
      );
  CanonicalValue entity({String? pin}) => CanonicalValue.parseJson('''{
    "record_kind":"entity","names":[],"labels":{"en":"Café campaign"},
    "classification":null,"classificationResolution":"unclassified","worldAssociations":[],
    "metadata":${pin ?? '{}'}
  }''');
  CommitInput request(List<StoredVersion> versions) => CommitInput(
    universe: universe,
    continuity: continuity,
    expectedHead: genesis,
    principal: principal,
    decision: 'fixture admission',
    reason: 'fixture',
    idempotencyKey: 'fixture',
    changes: [
      for (final v in versions)
        Assignment(recordId: v.identity.recordId, next: v),
    ],
  );

  test('selected membership must contain current references but not historical pins', () {
    final work = version(
      'rec_00000000000000000000000e',
      'ver_000000000000000000000005',
      CanonicalValue.parseJson(
        '{"record_kind":"work","kind":"novel","title":"Test novel","labels":{},"sourceRefs":[],"versions":[],"worldAssociations":[]}',
      ),
    );
    final target = version(
      record,
      'ver_000000000000000000000001',
      CanonicalValue.parseJson('''{
      "record_kind":"work_version","work":{"universe":"${universe.value}","record":"${work.identity.recordId.value}"},
      "versionLabel":"Original","binding":{"kind":"unbound"}
    }'''),
    );
    final referring = version(
      'rec_000000000000000000000010',
      'ver_000000000000000000000002',
      CanonicalValue.parseJson('''{
      "record_kind":"scene_ref","sceneId":"scene-one","depictedEvents":[],"worldAssociations":[],
      "workVersion":{"universe":"${universe.value}","record":"$record","version":"${target.versionId.value}"}
    }'''),
    );
    database.execute('BEGIN IMMEDIATE');
    final membership = journal.stageVersions(
      request([work, target, referring]),
    );
    final checks = CandidateReferences(journal);
    checks.validate(membership);
    checks.validate({referring.identity.recordId: referring.versionId});
    expect(checks.dependencies(referring), {target.identity.recordId});
    RecordProjections(database).project(0, referring);
    final projected = database
        .select('SELECT target_record,target_version,path FROM reference_index')
        .single;
    expect(projected['target_record'], target.identity.recordId.value);
    expect(projected['target_version'], target.versionId.value);
    expect(projected['path'], '/workVersion');
    expect(database.select('SELECT * FROM narrative_projection'), hasLength(1));
    final current = version(
      'rec_000000000000000000000011',
      'ver_000000000000000000000003',
      entity(
        pin:
            '''{
      "current":{"kind":"record_ref","ref":{"universe":"${universe.value}","record":"$record"}}
    }''',
      ),
    );
    journal.stageVersions(request([current]));
    expect(
      () => checks.validate({current.identity.recordId: current.versionId}),
      throwsFormatException,
    );
    final mismatch = version(
      'rec_000000000000000000000012',
      'ver_000000000000000000000004',
      CanonicalValue.parseJson('''{
      "record_kind":"scene_ref","sceneId":"wrong-pin","depictedEvents":[],"worldAssociations":[],
      "workVersion":{"universe":"${universe.value}","record":"rec_000000000000000000000099","version":"${target.versionId.value}"}
    }'''),
    );
    journal.stageVersions(request([mismatch]));
    expect(
      () => checks.validate({mismatch.identity.recordId: mismatch.versionId}),
      throwsFormatException,
    );
    final wrongKind = version(
      'rec_000000000000000000000013',
      'ver_000000000000000000000006',
      CanonicalValue.parseJson('''{
      "record_kind":"scene_ref","sceneId":"wrong-edition","depictedEvents":[],"worldAssociations":[],
      "workVersion":{"universe":"${universe.value}","record":"${current.identity.recordId.value}","version":"${current.versionId.value}"}
    }'''),
    );
    journal.stageVersions(request([wrongKind]));
    expect(
      () => checks.validate({wrongKind.identity.recordId: wrongKind.versionId}),
      throwsFormatException,
    );
    database.execute('ROLLBACK');
  });

  test('reference and search projections share the owning transaction', () {
    final target = version(record, 'ver_000000000000000000000001', entity());
    database.execute('BEGIN IMMEDIATE');
    journal.stageVersions(request([target]));
    RecordProjections(database).project(0, target);
    expect(
      database
          .select(
            "SELECT version_id FROM search_index WHERE search_index MATCH 'campaign'",
          )
          .single['version_id'],
      target.versionId.value,
    );
    database.execute('ROLLBACK');
    expect(database.select('SELECT * FROM search_index'), isEmpty);
    expect(database.select('SELECT * FROM typed_projection'), isEmpty);
    expect(
      () => RecordProjections(database).project(0, target),
      throwsStateError,
    );
  });

  test('typed unit and world aliases require their actual record kinds', () {
    final wrong = version(record, 'ver_000000000000000000000001', entity());
    final quantity = version(
      'rec_000000000000000000000010',
      'ver_000000000000000000000002',
      entity(
        pin: '{"distance":{"kind":"quantity","unit":"unit_00000000000000000000000f","value":{"kind":"decimal","digits":"30.00"}}}',
      ),
    );
    final visitorBody = jsonDecode(entity().toText()) as Map<String, dynamic>;
    visitorBody['worldAssociations'] = [
      {
        'world': 'wld_00000000000000000000000f',
        'role': 'setting',
        'validity': {'kind': 'unspecified'},
        'qualifiers': <String, Object?>{},
      },
    ];
    final visitor = version(
      'rec_000000000000000000000011',
      'ver_000000000000000000000003',
      canonical(visitorBody),
    );
    database.execute('BEGIN IMMEDIATE');
    final membership = journal.stageVersions(
      request([wrong, quantity, visitor]),
    );
    final checks = CandidateReferences(journal);
    expect(
      () => checks.validate({
        wrong.identity.recordId: wrong.versionId,
        quantity.identity.recordId: quantity.versionId,
      }),
      throwsFormatException,
    );
    expect(
      () => checks.validate({
        wrong.identity.recordId: wrong.versionId,
        visitor.identity.recordId: visitor.versionId,
      }),
      throwsFormatException,
    );
    expect(membership, hasLength(3));
    database.execute('ROLLBACK');
    final unit = version(
      record,
      'ver_000000000000000000000001',
      CanonicalValue.parseJson('''{
      "record_kind":"unit","namespace":"author","key":"metres","dimension":"distance",
      "symbol":"m","labels":{},"base":null,"validity":{"kind":"unspecified"}
    }'''),
    );
    database.execute('BEGIN IMMEDIATE');
    checks.validate(journal.stageVersions(request([unit, quantity])));
    RecordProjections(database).project(0, quantity);
    expect(
      database
          .select('SELECT target_record,path FROM reference_index')
          .single['target_record'],
      record,
    );
    expect(
      database
          .select(
            "SELECT value FROM typed_projection WHERE path='/metadata/distance/value/digits'",
          )
          .single['value'],
      '30.00',
    );
    database.execute('ROLLBACK');
    final world = version(
      record,
      'ver_000000000000000000000001',
      CanonicalValue.parseJson('''{
      "record_kind":"world","selector":"Real setting","aliases":[],"labels":{},"metadata":{}
    }'''),
    );
    database.execute('BEGIN IMMEDIATE');
    checks.validate(journal.stageVersions(request([world, visitor])));
    RecordProjections(database).project(0, visitor);
    expect(
      database
          .select('SELECT world_id FROM world_projection')
          .single['world_id'],
      'wld_00000000000000000000000f',
    );
    database.execute('ROLLBACK');
  });

  test('work versions bind only to revisions in the named continuity', () {
    final work = version(
      'rec_00000000000000000000000e',
      'ver_000000000000000000000001',
      CanonicalValue.parseJson('''{
      "record_kind":"work","kind":"novel","title":"Test novel","labels":{},"sourceRefs":[],"versions":[],"worldAssociations":[]
    }'''),
    );
    CanonicalValue edition(String continuityId) => CanonicalValue.parseJson('''{
      "record_kind":"work_version","work":{"universe":"${universe.value}","record":"${work.identity.recordId.value}"},
      "versionLabel":"Original","binding":{"kind":"bound","continuity":"$continuityId","revision":"${genesis.value}"}
    }''');
    database.execute('BEGIN IMMEDIATE');
    final valid = version(
      record,
      'ver_000000000000000000000002',
      edition(continuity.value),
    );
    CandidateReferences(journal)
        .validate(journal.stageVersions(request([work, valid])));
    database.execute('ROLLBACK');
    database.execute('BEGIN IMMEDIATE');
    final wrong = version(
      record,
      'ver_000000000000000000000002',
      edition('cont_000000000000000000000002'),
    );
    final membership = journal.stageVersions(request([work, wrong]));
    expect(
      () => CandidateReferences(journal).validate(membership),
      throwsFormatException,
    );
    database.execute('ROLLBACK');
  });
}
