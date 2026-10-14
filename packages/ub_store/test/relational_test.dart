@TestOn('vm')
library;

import 'required_evidence_fixture.dart';

import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/src/catalog.dart';
import 'package:ub_store/src/database.dart';
import 'package:ub_store/src/relational.dart';

void main() {
  late Directory directory;
  late Database database;
  late RelationalCodec codec;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('universe-builder-store-');
    database = SqliteDatabase.open('${directory.path}/package.sqlite');
    codec = RelationalCodec(database);
  });
  tearDown(() {
    database.close();
    directory.deleteSync(recursive: true);
  });

  test('bundled SQLite meets required version, WAL and FTS5 capabilities', () {
    expect(sqlite3.version.versionNumber, greaterThanOrEqualTo(3051003));
    expect(database.select('PRAGMA foreign_keys').single.values.single, 1);
    expect(database.select('PRAGMA journal_mode').single.values.single, 'wal');
    expect(database.select('PRAGMA synchronous').single.values.single, 2);
    expect(database.select('PRAGMA busy_timeout').single.values.single, 2000);
    final pageSize =
        database.select('PRAGMA page_size').single.values.single as int;
    expect(
      database.select('PRAGMA max_page_count').single.values.single,
      maxPackageBytes ~/ pageSize,
    );
    database.execute('CREATE VIRTUAL TABLE temp.fts_probe USING fts5(text)');
    database.execute('INSERT INTO temp.fts_probe VALUES (?)', [
      'café campaign',
    ]);
    expect(
      database
          .select(
            "SELECT text FROM temp.fts_probe WHERE fts_probe MATCH 'campaign'",
          )
          .single['text'],
      'café campaign',
    );
  });

  test('normative payloads reconstruct after restart with frozen digests', () {
    const root = '../../docs/decisions/relational-storage';
    final cases = (CanonicalValue.parseJson(
      File('$root/canonical-oracle.json').readAsStringSync(),
    ) as CanonicalArray).items.map(objectFields).toList();
    final semantics = objectFields(
      CanonicalValue.parseJson(
        File('$root/semantic-oracle.json').readAsStringSync(),
      ),
    );
    for (final value in (semantics['versions'] as CanonicalArray).items) {
      final item = objectFields(value);
      cases.add({
        'value': item['value']!,
        'canonical': CanonicalString(item['value']!.toText()),
        'digest': item['digest']!,
      });
    }
    for (final review in [false, true]) {
      final payload = requiredEvidencePayload(
        UniverseId.parse('unv_${'1'.padLeft(24, '0')}'),
        review: review,
      );
      cases.add({
        'value': payload,
        'canonical': CanonicalString(payload.toText()),
        'digest': CanonicalString(payloadDigest('rule', payload)),
      });
    }
    database.execute('BEGIN IMMEDIATE');
    final rows = [
      for (final item in cases) codec.put('Payload', item['value']!),
    ];
    database.execute('COMMIT');
    database.close();
    database = SqliteDatabase.open(
      '${directory.path}/package.sqlite',
      existing: true,
    );
    codec = RelationalCodec(database);
    for (var i = 0; i < cases.length; i++) {
      final item = cases[i];
      final value = codec.get('Payload', rows[i]);
      expect(value.toText(), (item['canonical'] as CanonicalString).value);
      final kind =
          (objectFields(value)['record_kind'] as CanonicalString).value;
      expect(
        payloadDigest(kind, value),
        (item['digest'] as CanonicalString).value,
      );
    }
    expect(
      database.select('PRAGMA integrity_check').single.values.single,
      'ok',
    );
    expect(database.select('PRAGMA foreign_key_check'), isEmpty);
  });

  test('failed publication transaction leaves no partial typed bodies', () {
    expect(
      () => codec.put(
        'Value',
        CanonicalValue.parseJson(
          '{"kind":"integer","digits":"9007199254740993"}',
        ),
      ),
      throwsStateError,
    );
    database.execute('BEGIN IMMEDIATE');
    codec.put(
      'Value',
      CanonicalValue.parseJson(
        '{"kind":"integer","digits":"9007199254740993"}',
      ),
    );
    for (final (model, text) in [
      ('Value', '{"kind":"integer","digits":1}'),
      ('RecordRef', '{"record":"rec_invalid"}'),
      (
        'RecordRef',
        '{"record":"rec_000000000000000000000001","unexpected":true}',
      ),
      ('ConsequenceDecimal', '"1e2"'),
      ('ConsequenceDecimal', '"00.1"'),
      ('ConsequenceDecimal', '"0.000000000000000000000000000000000000001"'),
      ('ConsequenceDecimal', '"170141183460469231731687303715884105728"'),
    ]) {
      expect(
        () => codec.put(model, CanonicalValue.parseJson(text)),
        throwsFormatException,
        reason: text,
      );
    }
    database.execute('ROLLBACK');
    expect(
      database.select('SELECT count(*) FROM r_value').single.values.single,
      0,
    );
    expect(
      database.select('SELECT count(*) FROM r_value_v2').single.values.single,
      0,
    );
  });

  test(
    'absent and null fields, exact digits and collection order remain distinct',
    () {
      database.execute('BEGIN IMMEDIATE');
      for (final text in [
        '{"record":"rec_000000000000000000000001"}',
        '{"record":"rec_000000000000000000000001","universe":null}',
      ]) {
        final value = CanonicalValue.parseJson(text);
        expect(
          codec.get('RecordRef', codec.put('RecordRef', value)).toText(),
          value.toText(),
        );
      }
      for (final text in [
        '{"kind":"integer","digits":"+0007"}',
        '{"kind":"decimal","digits":"30.00"}',
        '{"kind":"rational","numerator":"0007","denominator":"03"}',
        '{"kind":"sequence","items":[{"kind":"text","text":"β"},{"kind":"text","text":"🌲"},{"kind":"text","text":"β"}]}',
        '{"kind":"structured","definition":"vdef_000000000000000000000001","fields":{"一":{"kind":"decimal","digits":"0.00"},"é":{"kind":"integer","digits":"9007199254740993"}}}',
      ]) {
        final value = CanonicalValue.parseJson(text);
        expect(
          codec.get('Value', codec.put('Value', value)).toText(),
          value.toText(),
        );
      }
      final scalar = BodyCatalog.instance.models.entries
          .firstWhere(
            (e) =>
                e.value.kind == 'integer' &&
                e.value.minimum == null &&
                e.value.maximum == null,
          )
          .key;
      for (final digits in ['18446744073709551615', '-9223372036854775808']) {
        final value = CanonicalValue.parseJson(digits);
        final stored = codec.put(scalar, value);
        expect(stored, digits);
        expect(codec.get(scalar, stored).toText(), digits);
      }
      final bounded = BodyCatalog.instance.models.entries
          .firstWhere(
            (entry) =>
                entry.value.kind == 'integer' &&
                entry.value.maximum?.toString() == '18446744073709551615',
          )
          .key;
      final upperBound = CanonicalValue.parseJson('18446744073709551615');
      expect(
        codec.get(bounded, codec.put(bounded, upperBound)).toText(),
        '18446744073709551615',
      );
      database.execute('COMMIT');
      expect(
        database
            .select('SELECT count(*) FROM r_record_ref WHERE universe__state=0')
            .single
            .values
            .single,
        1,
      );
      expect(
        database
            .select('SELECT count(*) FROM r_record_ref WHERE universe__state=1')
            .single
            .values
            .single,
        1,
      );
    },
  );

  test('immutable body rows refuse update and deletion', () {
    database.execute('BEGIN IMMEDIATE');
    final row = codec.put(
      'Value',
      CanonicalValue.parseJson('{"kind":"integer","digits":"7"}'),
    );
    database.execute('COMMIT');
    expect(
      () => database.execute('UPDATE r_value SET variant=0 WHERE __row_id=?', [
        row,
      ]),
      throwsA(isA<SqliteException>()),
    );
    expect(
      () => database.execute('DELETE FROM r_value WHERE __row_id=?', [row]),
      throwsA(isA<SqliteException>()),
    );
    expect(codec.get('Value', row).toText(), '{"digits":"7","kind":"integer"}');
  });

  test('foreign keys, ordinal gaps and recursive graphs are rejected', () {
    final input = CanonicalValue.parseJson('{"kind":"sequence","items":[]}');
    database.execute('BEGIN IMMEDIATE');
    final root = codec.put('Value', input);
    expect(
      () => database.execute(
        'INSERT INTO r_value(variant,v13) VALUES(13,999999)',
      ),
      throwsA(isA<SqliteException>()),
    );
    final owner = database
        .select('SELECT items FROM r_value_v13')
        .single['items'];
    final child = codec.put(
      'Value',
      CanonicalValue.parseJson('{"kind":"text","text":"one"}'),
    );
    database.execute('INSERT INTO r_value_v13_items_items VALUES(?,1,?)', [
      owner,
      child,
    ]);
    expect(() => codec.get('Value', root), throwsFormatException);
    database.execute('ROLLBACK');
    database.execute('BEGIN IMMEDIATE');
    final cyclic = codec.put('Value', input);
    final cyclicOwner = database
        .select('SELECT items FROM r_value_v13')
        .single['items'];
    database.execute('INSERT INTO r_value_v13_items_items VALUES(?,0,?)', [
      cyclicOwner,
      cyclic,
    ]);
    expect(() => codec.get('Value', cyclic), throwsFormatException);
    database.execute('ROLLBACK');
  });

  test(
    'opening an incompatible package preserves its contents and journal',
    () {
      final path = '${directory.path}/incompatible.sqlite';
      final original = sqlite3.open(path);
      original.execute('CREATE TABLE records(payload TEXT)');
      original.execute('INSERT INTO records VALUES (?)', [
        'original author content',
      ]);
      original.close();
      final before = File(path).readAsBytesSync();
      expect(
        () => SqliteDatabase.open(path, existing: true),
        throwsFormatException,
      );
      expect(File(path).readAsBytesSync(), before);
      final retained = sqlite3.open(path);
      expect(
        retained.select('PRAGMA journal_mode').single.values.single,
        'delete',
      );
      expect(
        retained.select('SELECT payload FROM records').single['payload'],
        'original author content',
      );
      retained.close();
      expect(
        () => SqliteDatabase.open(
          '${directory.path}/missing.sqlite',
          existing: true,
        ),
        throwsA(isA<SqliteException>()),
      );
      expect(File('${directory.path}/missing.sqlite').existsSync(), isFalse);
    },
  );
}
