@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/src/canonical_integrity.dart';
import 'package:ub_store/src/database.dart';
import 'package:ub_store/src/journal.dart';
import 'package:ub_store/src/revision_input.dart';
import 'package:ub_store/src/workflow_storage.dart';

void main() {
  late Directory directory;
  late Database database;
  late WorkflowStorage workflow;
  late SqliteJournal journal;
  final universe = UniverseId.parse('unv_000000000000000000000001');
  final continuity = ContinuityId.parse('cont_000000000000000000000001');
  final principal = PrincipalId.parse('prn_000000000000000000000001');
  CanonicalValue value(Object? v) => CanonicalValue.parseJson(jsonEncode(v));
  void write(void Function() action) {
    database.execute('BEGIN IMMEDIATE');
    try {
      action();
      database.execute('COMMIT');
    } catch (_) {
      if (!database.autocommit) database.execute('ROLLBACK');
      rethrow;
    }
  }

  setUp(() {
    directory = Directory.systemTemp.createTempSync(
      'universe-builder-workflow-',
    );
    database = SqliteDatabase.open('${directory.path}/package.sqlite');
    workflow = WorkflowStorage(database);
    journal = SqliteJournal(database, universe);
    write(() {
      journal.initialize('Disposable workflow', continuity, principal);
    });
  });
  tearDown(() {
    database.close();
    directory.deleteSync(recursive: true);
  });
  final approval = value({
    'author': 'author-one',
    'proposal': {
      'proposal_id': 'prp_000000000000000000000001',
      'version': 1,
      'digest': 'a' * 64,
    },
    'validation_digest': 'b' * 64,
    'evaluator': 'rules-one',
  });

  test('awaited verification holds writer isolation and failure rolls back without retaining entries', () async {
    final entered = Completer<void>(), resume = Completer<void>();
    final original = StateError('Interrupted revalidation');
    final append = workflow.compareAppendWithVerification(
      verify: () async {
        entered.complete();
        await resume.future;
        throw original;
      },
      entries: [
        MapEntry('cancel:pending', value({'cancelled': true})),
      ],
    );
    final failed = expectLater(append, throwsA(same(original)));
    await entered.future;
    final competitor = sqlite3.open('${directory.path}/package.sqlite');
    try {
      competitor.execute('PRAGMA busy_timeout=0');
      expect(
        () => competitor.execute('BEGIN IMMEDIATE'),
        throwsA(isA<SqliteException>()),
      );
      expect(workflow.get('cancel:pending'), isNull);
    } finally {
      competitor.close();
      resume.complete();
    }
    await failed;
    expect(database.autocommit, isTrue);
    expect(workflow.get('cancel:pending'), isNull);
  });

  test(
    'verified append rolls back every earlier entry on an immutable conflict',
    () async {
      workflow.compareAppend({}, [
        MapEntry('cancel:occupied', value({'cancelled': false})),
      ]);
      await expectLater(
        workflow.compareAppendWithVerification(
          verify: () => const {},
          entries: [
            MapEntry('cancel:new', value({'cancelled': true})),
            MapEntry('cancel:occupied', value({'cancelled': true})),
          ],
        ),
        throwsFormatException,
      );
      expect(workflow.get('cancel:new'), isNull);
      expect(
        workflow.get('cancel:occupied')!.toText(),
        value({'cancelled': false}).toText(),
      );
      expect(database.autocommit, isTrue);
    },
  );

  test('typed envelopes and exact retry digests survive restart without JSON bodies', () {
    final entries = {
      'cancel:one': value({'cancelled': false}),
      'reserved-record:one': value({
        'proposal_id': 'prp_000000000000000000000001',
      }),
      'cursor:one': CanonicalValue.parseJson(
        '{"binding":"selected snapshot","offset":18446744073709551615}',
      ),
      'approval:one': approval,
    };
    write(() {
      for (final entry in entries.entries) {
        workflow.put(entry.key, entry.value);
        workflow.put(entry.key, entry.value);
      }
    });
    expect(database.select('SELECT * FROM workflow_entries'), hasLength(4));
    expect(
      database
          .select('PRAGMA table_info(workflow_entries)')
          .map((r) => r['name']),
      isNot(contains('payload')),
    );
    database.close();
    database = SqliteDatabase.open(
      '${directory.path}/package.sqlite',
      existing: true,
    );
    workflow = WorkflowStorage(database);
    for (final entry in entries.entries) {
      expect(workflow.evidence(entry.key)!.toText(), entry.value.toText());
    }
    expect(
      () => write(() {
        workflow.put('cancel:one', value({'cancelled': true}));
      }),
      throwsFormatException,
    );
    expect(
      () => workflow.put('cancel:two', value({'cancelled': true})),
      throwsStateError,
    );
    expect(
      () => write(() {
        workflow.put('unknown:one', value({}));
      }),
      throwsFormatException,
    );
    expect(
      () => write(() {
        workflow.put(
          'cancel:two',
          value({'cancelled': true, 'invented': 'field'}),
        );
      }),
      throwsFormatException,
    );
    expect(database.select('SELECT * FROM workflow_entries'), hasLength(4));
  });
  test('historical approvals and cursors remain evidence but cannot regain active authority', () {
    final cursor = value({'binding': 'old installation', 'offset': 0});
    write(() {
      workflow.put('approval:one', approval);
      workflow.put('cursor:one', cursor);
      database.execute('INSERT INTO historical_workflow VALUES(?)', [
        'approval:one',
      ]);
      database.execute('INSERT INTO historical_workflow VALUES(?)', [
        'cursor:one',
      ]);
    });
    expect(workflow.get('approval:one'), isNull);
    expect(workflow.get('cursor:one'), isNull);
    expect(workflow.evidence('approval:one')!.toText(), approval.toText());
    expect(
      () => write(() {
        workflow.put('approval:one', approval);
      }),
      throwsFormatException,
    );
    write(() {
      workflow.put('approval:fresh', approval);
    });
    expect(workflow.get('approval:fresh'), isNotNull);
    CanonicalIntegrity(journal).verify();
  });
  test('workflow compare and append publishes all entries or none under the selected key', () {
    final cursor = value({'binding': 'selected generation', 'offset': 0});
    workflow.compareAppend(
      {'cursor:': null},
      [MapEntry('cursor:0001', cursor)],
    );
    expect(workflow.latestKey('cursor:'), 'cursor:0001');
    expect(workflow.keys('cursor:'), ['cursor:0001']);
    expect(
      () => workflow.compareAppend(
        {'cursor:': null},
        [MapEntry('cursor:0002', cursor)],
      ),
      throwsFormatException,
    );
    expect(
      () => workflow.compareAppend(
        {'cursor:': 'cursor:0001'},
        [
          MapEntry('cursor:0002', cursor),
          MapEntry('cancel:invalid', value({'invented': true})),
        ],
      ),
      throwsFormatException,
    );
    expect(workflow.evidence('cursor:0002'), isNull);
    workflow.compareAppend(
      {'cursor:': 'cursor:0001'},
      [
        MapEntry('cursor:0002', cursor),
        MapEntry('cancel:one', value({'cancelled': false})),
      ],
    );
    expect(workflow.latestKey('cursor:'), 'cursor:0002');
    expect(workflow.keys('cursor:'), ['cursor:0001', 'cursor:0002']);
    expect(workflow.evidence('cancel:one'), isNotNull);
    expect(database.autocommit, isTrue);
  });
  test('source and media content retain exact bytes and canonical workflow bindings', () {
    const text = '\uFEFFA café\r\nwith exact source bytes 🌲';
    final digest = sha256.convert(utf8.encode(text)).toString();
    write(() {
      workflow.put('source:$digest', CanonicalString(text));
      workflow.put(
        'image-bytes:asset:0',
        CanonicalString(base64.encode([0, 255, 10])),
      );
      workflow.put(
        'continuity-name:${continuity.value}',
        CanonicalString('Campaign branch'),
      );
    });
    expect(workflow.get('source:$digest'), isA<CanonicalString>());
    expect((workflow.get('source:$digest')! as CanonicalString).value, text);
    expect(
      (workflow.get('image-bytes:asset:0')! as CanonicalString).value,
      'AP8K',
    );
    for (final ordinal in ['01', '+1', '-1', '9223372036854775808']) {
      expect(
        () => write(() {
          workflow.put('image-bytes:asset:$ordinal', CanonicalString('AA=='));
        }),
        throwsFormatException,
      );
    }
    expect(
      () => write(() {
        workflow.put('image-bytes:asset:1', CanonicalString('AA'));
      }),
      throwsFormatException,
    );
    expect(
      () => write(() {
        workflow.put('source:${'0' * 64}', CanonicalString(text));
      }),
      throwsFormatException,
    );
    CanonicalIntegrity(journal).verify();
    database.execute('DROP TRIGGER source_content_no_update');
    database.execute('UPDATE source_content SET utf8_content=?', [
      utf8.encode('corrupt'),
    ]);
    expect(() => workflow.evidence('source:$digest'), throwsFormatException);
    expect(CanonicalIntegrity(journal).verify, throwsFormatException);
  });
  test('identical workflow retry reconstructs a corrupt body instead of trusting its envelope', () {
    final cursor = value({'binding': 'exact binding', 'offset': 0});
    write(() {
      workflow.put('cursor:one', cursor);
    });
    database.execute('DROP TRIGGER workflow_entries_no_update');
    database.execute('UPDATE workflow_entries SET digest=?', ['0' * 64]);
    expect(
      () => write(() {
        workflow.put('cursor:one', cursor);
      }),
      throwsFormatException,
    );
    expect(CanonicalIntegrity(journal).verify, throwsFormatException);
    expect(database.autocommit, isTrue);
  });
  test('conversion provenance must bind the retained normalized workflow', () {
    final cursor = value({'binding': 'imported binding', 'offset': 0});
    write(() {
      workflow.put('cursor:one', cursor);
      database.execute('INSERT INTO import_workflow_digest VALUES(?,?,?)', [
        'cursor:one',
        'a' * 64,
        canonicalDigest(cursor),
      ]);
    });
    CanonicalIntegrity(journal).verify();
    database.execute('DROP TRIGGER import_workflow_digest_no_update');
    database.execute('UPDATE import_workflow_digest SET normalized_digest=?', [
      'b' * 64,
    ]);
    expect(CanonicalIntegrity(journal).verify, throwsFormatException);
    expect(database.autocommit, isTrue);
  });
  test('source and image staging retain typed payloads and enforce their key families', () {
    final source = value({
      'record_kind': 'source_version',
      'source': {
        'universe': universe.value,
        'record': 'rec_000000000000000000000001',
      },
      'digest': 'a' * 64,
      'mediaType': 'text/plain',
      'byteSize': 3,
      'importActor': principal.value,
      'importTime': '2026-10-11T12:00:00Z',
      'decoding': {
        'encoding': 'utf-8',
        'representation': 'unicode',
        'byteLength': 3,
      },
      'origin': <String, Object?>{},
    });
    final image = value({
      'record_kind': 'image_asset',
      'digest': 'b' * 64,
      'media_type': 'image/png',
      'byte_size': 68,
      'width': 1,
      'height': 1,
      'original_name': 'map.png',
    });
    write(() {
      workflow.put('source-version:one', source);
      workflow.put('image-asset:one', image);
    });
    expect(workflow.evidence('source-version:one')!.toText(), source.toText());
    expect(workflow.evidence('image-asset:one')!.toText(), image.toText());
    expect(
      () => write(() {
        workflow.put('image-asset:wrong', source);
      }),
      throwsFormatException,
    );
    expect(database.select('SELECT * FROM source_staging'), hasLength(1));
    expect(database.select('SELECT * FROM image_staging'), hasLength(1));
    // Staging metadata is retained evidence; content-link admission is separate.
    CanonicalIntegrity(journal).verify();
  });
  test('startup verifies original image content and metadata against retained chunks', () {
    final bytes = base64.decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aBdwAAAAASUVORK5CYII=',
    );
    final digest = sha256.convert(bytes).toString();
    final asset = StoredVersion.build(
      RecordVersionId.parse('ver_000000000000000000000001'),
      RecordIdentity(
        universeId: universe,
        recordId: RecordId.parse('rec_000000000000000000000001'),
        recordKind: RecordKind.imageAsset,
      ),
      value({
        'record_kind': 'image_asset',
        'digest': digest,
        'media_type': 'image/png',
        'byte_size': bytes.length,
        'width': 1,
        'height': 1,
        'original_name': 'map.png',
      }),
    );
    write(() {
      workflow.put(
        'image-bytes:$digest:0',
        CanonicalString(base64.encode(bytes)),
      );
      final head = journal.head(continuity);
      final input = CommitInput(
        universe: universe,
        continuity: continuity,
        expectedHead: head,
        principal: principal,
        decision: 'reviewed fixture',
        reason: 'retained image',
        idempotencyKey: 'image',
        changes: [Assignment(recordId: asset.identity.recordId, next: asset)],
      );
      final candidate = journal.stageVersions(input);
      final revision = journal.append(input);
      journal.advanceHead(continuity, head, revision, candidate);
      journal.writeReceipt(input, revision);
    });
    CanonicalIntegrity(journal).verify();
    database.execute('INSERT INTO import_record_digest VALUES(?,?,?,?)', [
      universe.value,
      asset.versionId.value,
      'a' * 64,
      asset.digest,
    ]);
    CanonicalIntegrity(journal).verify();
    database.execute('BEGIN IMMEDIATE');
    database.execute('DROP TRIGGER immutable_import_digest_update');
    database.execute('UPDATE import_record_digest SET normalized_digest=?', [
      '0' * 64,
    ]);
    expect(CanonicalIntegrity(journal).verify, throwsFormatException);
    expect(database.autocommit, isFalse);
    database.execute('ROLLBACK');
    CanonicalIntegrity(journal).verify();
    database.execute('DROP TRIGGER media_chunk_no_update');
    bytes[bytes.length - 1] ^= 1;
    database.execute(
      'UPDATE media_chunk SET content=?,historical_workflow_digest=?',
      [bytes, canonicalDigest(CanonicalString(base64.encode(bytes)))],
    );
    // The chunk's own envelope is consistent; the original asset digest is not.
    expect(workflow.evidence('image-bytes:$digest:0'), isNotNull);
    expect(CanonicalIntegrity(journal).verify, throwsFormatException);
  });
}
