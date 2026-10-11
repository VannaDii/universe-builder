@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_domain/ub_domain.dart';

Map<String, CanonicalValue> fields(CanonicalValue value) => {
  for (final entry in (value as CanonicalObject).fields) entry.key: entry.value,
};
void main() {
  const root = '../../docs/decisions/relational-storage';
  final canonical = (CanonicalValue.parseJson(
    File('$root/canonical-oracle.json').readAsStringSync(),
  ) as CanonicalArray).items;
  final semantic = fields(
    CanonicalValue.parseJson(
      File('$root/semantic-oracle.json').readAsStringSync(),
    ),
  );
  // Relational examples intentionally retain omitted fields. Typed Rust
  // deserialization expands defaults before serialization; the frozen typed
  // fixtures capture that existing behavior independently of the Dart port.
  final typed = {
    for (final row in (CanonicalValue.parseJson(
      File('../../fixtures/dart-domain/typed-record-digests.json')
          .readAsStringSync(),
    ) as CanonicalArray).items)
      (fields(row)['name'] as CanonicalString).value: fields(row),
  };
  final fixtures = [
    ...canonical,
    ...(semantic['versions'] as CanonicalArray).items,
  ];
  const supported = {
    'proposition',
    'assertion',
    'world',
    'realm',
    'entity',
    'entity_type',
    'property',
    'relation',
    'unit',
    'calendar',
    'value_definition',
    'domain_pack',
    'work',
    'work_version',
    'scene_ref',
    'passage_ref',
    'saga',
    'source',
    'source_version',
    'anchor',
    'epistemic_attitude',
    'observation',
    'communication',
    'memory',
    'secret',
    'completeness',
    'appearance',
    'image_asset',
    'goal',
    'commitment',
  };
  final covered = <String>{};
  var count = 0;
  for (final fixture in fixtures) {
    final item = fields(fixture);
    final payload = item['value']!;
    final kind = (fields(payload)['record_kind'] as CanonicalString).value;
    if (!supported.contains(kind)) continue;
    covered.add(kind);
    final n = count++;
    final name = item['name'] is CanonicalString
        ? (item['name'] as CanonicalString).value
        : 'semantic:${(item['version'] as CanonicalString).value}';
    test('typed record retains Rust wire digest $kind:$n', () {
      final record = RecordPayload.fromWire(payload);
      final expected = typed[name]!;
      expect(
        record.toWire().toText(),
        (expected['canonical'] as CanonicalString).value,
      );
      expect(record.digest, (expected['digest'] as CanonicalString).value);
      expect(RecordPayload.fromWire(expected['value']!), record);
      // Decoding a typed view must not rewrite the retained source bytes.
      expect(
        payloadDigest(kind, payload),
        (item['digest'] as CanonicalString).value,
      );
    });
  }
  test('existing fixtures exercise every ported record family', () {
    expect(covered, supported);
  });
}
