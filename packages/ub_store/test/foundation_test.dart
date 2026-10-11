@TestOn('vm')
library;

import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/src/candidate_foundation.dart';
import 'package:ub_store/src/catalog.dart';
import 'package:ub_store/src/database.dart';
import 'package:ub_store/src/journal.dart';
import 'package:ub_store/src/revision_input.dart';
import 'package:ub_store/src/world_names.dart';

void main() {
  final oracle = objectFields(
    CanonicalValue.parseJson(
      File('../../docs/decisions/relational-storage/semantic-oracle.json')
          .readAsStringSync(),
    ),
  );
  final universe = UniverseId.parse(
    (oracle['universe'] as CanonicalString).value,
  );
  final versions = <String, StoredVersion>{};
  for (final raw in (oracle['versions'] as CanonicalArray).items) {
    final item = objectFields(raw);
    final id = (item['version'] as CanonicalString).value;
    final version = StoredVersion(
      versionId: RecordVersionId.parse(id),
      identity: RecordIdentity(
        universeId: universe,
        recordId: RecordId.parse((item['identity'] as CanonicalString).value),
        recordKind: RecordKind.parse((item['kind'] as CanonicalString).value),
      ),
      payload: item['value']!,
      digest: (item['digest'] as CanonicalString).value,
    );
    version.verify();
    versions[id] = version;
  }
  final selected = [
    for (final id in objectFields(oracle['membership']!).values)
      versions[(id as CanonicalString).value]!,
  ];
  late Directory directory;
  late Database database;
  late CandidateFoundation foundation;
  setUp(() {
    directory = Directory.systemTemp.createTempSync(
      'universe-builder-foundation-',
    );
    database = SqliteDatabase.open('${directory.path}/package.sqlite');
    foundation = CandidateFoundation(SqliteJournal(database, universe));
  });
  tearDown(() {
    database.close();
    directory.deleteSync(recursive: true);
  });

  StoredVersion replace(
    StoredVersion version,
    Map<String, CanonicalValue> changes,
  ) => StoredVersion.build(
    version.versionId,
    version.identity,
    CanonicalObject({...objectFields(version.payload), ...changes}.entries),
  );
  List<StoredVersion> changed(StoredVersion replacement) => [
    for (final record in selected)
      record.identity.recordId == replacement.identity.recordId
          ? replacement
          : record,
  ];

  test(
    'existing Cedar and Pistol selected membership passes factual foundation',
    () {
      expect(selected, hasLength(48));
      foundation.validateRecords(selected);
    },
  );
  test(
    'typed world admission honors defaults without rewriting retained bytes',
    () {
      final payload = CanonicalValue.parseJson(
        '{"record_kind":"world","selector":"Memoir setting"}',
      );
      final world = StoredVersion.build(
        RecordVersionId.parse('ver_0000000000000000000000ff'),
        RecordIdentity(
          universeId: universe,
          recordId: RecordId.parse('rec_0000000000000000000000ff'),
          recordKind: RecordKind.world,
        ),
        payload,
      );
      final retained = world.toCanonical().toText();
      foundation.validateRecords([world]);
      WorldNames.validateRecords([world]);
      database.execute('BEGIN IMMEDIATE');
      final journal = foundation.journal;
      final continuity = ContinuityId.parse('cont_0000000000000000000000ff');
      final principal = PrincipalId.parse('prn_0000000000000000000000ff');
      final head = journal.initialize(
        'Disposable setting',
        continuity,
        principal,
      );
      journal.stageVersions(
        CommitInput(
          universe: universe,
          continuity: continuity,
          expectedHead: head,
          principal: principal,
          decision: 'test admission',
          reason: 'test',
          idempotencyKey: 'typed-world-defaults',
          changes: [Assignment(recordId: world.identity.recordId, next: world)],
        ),
      );
      database.execute('COMMIT');
      expect(journal.load(world.versionId).toCanonical().toText(), retained);
      expect(world.payload.toText(), payload.toText());
      expect(WorldRecord.fromWire(world.payload).metadata, isEmpty);
    },
  );
  test('parent resolution and ancestry cannot fabricate a type chain', () {
    final types = selected
        .where((r) => r.identity.recordKind == RecordKind.entityType)
        .toList();
    final root = types.firstWhere(
      (r) => objectFields(r.payload)['parent'] is CanonicalNull,
    );
    final child = types.firstWhere(
      (r) =>
          objectFields(r.payload)['parent'] is CanonicalString &&
          (objectFields(r.payload)['parent'] as CanonicalString).value ==
              root.identity.recordId.value,
    );
    expect(
      () => foundation.validateRecords(
        changed(
          replace(root, {'parentResolution': CanonicalString('resolved')}),
        ),
      ),
      throwsFormatException,
    );
    expect(
      () => foundation.validateRecords(
        changed(
          replace(root, {
            'parentResolution': CanonicalString('resolved'),
            'parent': CanonicalString(child.identity.recordId.value),
          }),
        ),
      ),
      throwsFormatException,
    );
    final entity = selected.firstWhere(
      (r) => r.identity.recordKind == RecordKind.entity,
    );
    expect(
      () => foundation.validateRecords(
        changed(
          replace(child, {
            'parent': CanonicalString(entity.identity.recordId.value),
          }),
        ),
      ),
      throwsFormatException,
    );
  });
  test(
    'classification and typed metadata must remain valid in selected canon',
    () {
      final entity = selected.firstWhere(
        (r) =>
            r.identity.recordKind == RecordKind.entity &&
            objectFields(r.payload)['classification'] is CanonicalString,
      );
      expect(
        () => foundation.validateRecords(
          changed(replace(entity, {'classification': const CanonicalNull()})),
        ),
        throwsFormatException,
      );
      expect(
        () => foundation.validateRecords(
          changed(
            replace(entity, {
              'classification': CanonicalString(entity.identity.recordId.value),
            }),
          ),
        ),
        throwsFormatException,
      );
      expect(
        () => foundation.validateRecords(
          changed(
            replace(entity, {
              'metadata': CanonicalObject([
                MapEntry('quantity', const DecimalValue('NaN').toWire()),
              ]),
            }),
          ),
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'proposition roles and assertion attribute modes cannot substitute kinds',
    () {
      final proposition = selected.firstWhere(
        (r) => r.identity.recordKind == RecordKind.proposition,
      );
      final entity = selected.firstWhere(
        (r) => r.identity.recordKind == RecordKind.entity,
      );
      expect(
        () => foundation.validateRecords(
          changed(
            replace(proposition, {
              'predicate': RecordRef(
                universe: universe,
                record: entity.identity.recordId,
              ).toCanonical(),
            }),
          ),
        ),
        throwsFormatException,
      );
      final assertion = selected.firstWhere(
        (r) =>
            r.identity.recordKind == RecordKind.assertion &&
            (objectFields(r.payload)['attributeMode'] as CanonicalString)
                    .value ==
                'shared',
      );
      expect(
        () => foundation.validateRecords(
          changed(
            replace(assertion, {'attributeMode': CanonicalString('instance')}),
          ),
        ),
        throwsFormatException,
      );
    },
  );
}
