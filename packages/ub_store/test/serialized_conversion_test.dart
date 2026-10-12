@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/src/serialized_conversion.dart';

Map<String, CanonicalValue> fields(CanonicalValue value) => {
  for (final entry in (value as CanonicalObject).fields) entry.key: entry.value,
};

void main() {
  final universe = UniverseId.parse('unv_000000000000000000000001');
  final recordId = RecordId.generate(), versionId = RecordVersionId.generate();
  final fixtures = (CanonicalValue.parseJson(
    File('../../fixtures/dart-domain/typed-record-digests.json')
        .readAsStringSync(),
  ) as CanonicalArray).items;
  for (final fixture in fixtures) {
    final f = fields(fixture);
    test(
      'serialized conversion retains frozen Rust digest and body: ${(f['name'] as CanonicalString).value}',
      () {
        final body = f['value']!;
        final kind = RecordKind.parse(
          (fields(body)['record_kind'] as CanonicalString).value,
        );
        final converted = convertSerializedRecord(
          universe: universe,
          recordId: recordId,
          versionId: versionId,
          kind: kind,
          bytes: body.toBytes(),
          sourceDigest: (f['digest'] as CanonicalString).value,
        );
        expect(converted.record.digest, (f['digest'] as CanonicalString).value);
        expect(
          converted.record.payload.toText(),
          (f['canonical'] as CanonicalString).value,
        );
        expect(converted.classification, isNull);
      },
    );
  }
  CanonicalObject entity(List<RecordId> candidates) => CanonicalObject([
    MapEntry('record_kind', CanonicalString('entity')),
    MapEntry(
      'types',
      CanonicalArray(candidates.map((id) => CanonicalString(id.value))),
    ),
    MapEntry('names', CanonicalArray([])),
    MapEntry('worldAssociations', CanonicalArray([])),
    MapEntry('labels', CanonicalObject([])),
    MapEntry('metadata', CanonicalObject([])),
  ]);
  test('legacy classification vectors preserve ordered ambiguity without choosing an executable identity', () {
    final a = RecordId.generate(), b = RecordId.generate();
    for (final candidates in [
      <RecordId>[],
      [a],
      [b, a],
    ]) {
      final body = entity(candidates);
      final original = payloadDigest('entity:v1:v1', body);
      final converted = convertSerializedRecord(
        universe: universe,
        recordId: recordId,
        versionId: versionId,
        kind: RecordKind.entity,
        bytes: body.toBytes(),
        schemaVersion: 'v1',
        sourceDigest: original,
      );
      final payload = EntityRecord.fromWire(converted.record.payload);
      expect(payload.classification, candidates.length == 1 ? a : null);
      expect(payload.classificationResolution, switch (candidates.length) {
        0 => ClassificationResolution.unclassified,
        1 => ClassificationResolution.resolved,
        _ => ClassificationResolution.ambiguous,
      });
      expect(converted.classification!.candidates, candidates);
      expect(converted.classification!.relationship, 'membership');
      expect(converted.sourceDigest, original);
      expect(converted.record.versionId, versionId);
      expect(converted.record.identity.recordId, recordId);
    }
  });
  test('legacy parent vectors preserve authored names nonexecutable ancestry and unspecified applicability', () {
    final a = RecordId.generate(), b = RecordId.generate();
    final body = CanonicalObject([
      MapEntry('record_kind', CanonicalString('entity_type')),
      MapEntry('namespace', CanonicalString('world')),
      MapEntry('key', CanonicalString('authored-type')),
      MapEntry('name', CanonicalString('Authored type')),
      MapEntry('labels', CanonicalObject([])),
      MapEntry(
        'parents',
        CanonicalArray([CanonicalString(b.value), CanonicalString(a.value)]),
      ),
      MapEntry('classificationExecutable', CanonicalBool(false)),
    ]);
    final converted = convertSerializedRecord(
      universe: universe,
      recordId: recordId,
      versionId: versionId,
      kind: RecordKind.entityType,
      bytes: body.toBytes(),
      sourceDigest: payloadDigest('entity_type', body),
    );
    final payload = EntityTypeRecord.fromWire(converted.record.payload);
    expect(payload.parent, isNull);
    expect(payload.parentResolution, ParentResolution.ambiguous);
    expect(payload.applicability, isA<UnspecifiedApplicability>());
    expect(payload.classificationExecutable, isFalse);
    expect(converted.classification!.candidates, [b, a]);
    final unnamed = CanonicalObject(
      body.fields.where((entry) => entry.key != 'name'),
    );
    expect(
      () => convertSerializedRecord(
        universe: universe,
        recordId: recordId,
        versionId: versionId,
        kind: RecordKind.entityType,
        bytes: unnamed.toBytes(),
        sourceDigest: payloadDigest('entity_type', unnamed),
      ),
      throwsFormatException,
    );
  });
  test(
    'source digest corruption and unknown recipes never normalize into success',
    () {
      final body = entity([]);
      expect(
        () => convertSerializedRecord(
          universe: universe,
          recordId: recordId,
          versionId: versionId,
          kind: RecordKind.entity,
          bytes: body.toBytes(),
          sourceDigest: '0' * 64,
        ),
        throwsFormatException,
      );
      expect(
        () => convertSerializedRecord(
          universe: universe,
          recordId: recordId,
          versionId: versionId,
          kind: RecordKind.entity,
          bytes: body.toBytes(),
          schemaVersion: 'guessed',
          sourceDigest: payloadDigest('entity', body),
        ),
        throwsFormatException,
      );
    },
  );
  test('serialized drafts decode all frozen Rust operation alternatives in order without partial recovery', () {
    final cases = (CanonicalValue.parseJson(
      File('../../fixtures/dart-domain/operations.json').readAsStringSync(),
    ) as CanonicalArray).items;
    final input = CanonicalArray(cases.map((value) => fields(value)['input']!));
    CanonicalObject draft(String text) => CanonicalObject([
      MapEntry('rationale', CanonicalString('Authored é😀')),
      MapEntry(
        'content',
        CanonicalObject([
          MapEntry('operations', CanonicalString(text)),
          MapEntry('other', CanonicalString('Retained value')),
        ]),
      ),
    ]);
    final original = draft(input.toText());
    final result = fields(
      convertSerializedWorkflow(
        'draft:original',
        original.toBytes(),
        canonicalDigest(original),
      ),
    );
    final content = fields(result['content']!);
    final expected = CanonicalArray(
      cases.map(
        (value) => CanonicalValue.parseJson(
          (fields(value)['canonical'] as CanonicalString).value,
        ),
      ),
    );
    expect(content['operations']!.toText(), expected.toText());
    expect(result['rationale']!.toText(), '"Authored é😀"');
    expect(content['other']!.toText(), '"Retained value"');
    final malformed = draft('[{"kind":"unsupported"}]');
    expect(
      () => convertSerializedWorkflow(
        'draft:bad',
        malformed.toBytes(),
        canonicalDigest(malformed),
      ),
      throwsFormatException,
    );
    expect(
      () => convertSerializedWorkflow(
        'draft:original',
        original.toBytes(),
        '0' * 64,
      ),
      throwsFormatException,
    );
    expect(
      convertSerializedWorkflow(
        'other:original',
        original.toBytes(),
        canonicalDigest(original),
      ).toText(),
      original.toText(),
    );
  });
}
