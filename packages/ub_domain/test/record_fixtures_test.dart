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
  final fixtures = [
    ...canonical,
    ...(semantic['versions'] as CanonicalArray).items,
  ];
  var count = 0;
  for (final fixture in fixtures) {
    final item = fields(fixture);
    final payload = item['value']!;
    final kind = (fields(payload)['record_kind'] as CanonicalString).value;
    if (!{'proposition', 'assertion'}.contains(kind)) continue;
    final n = count++;
    test('typed factual record retains normative wire digest $kind:$n', () {
      final record = RecordPayload.fromWire(payload);
      expect(record.toWire().toText(), payload.toText());
      expect(record.digest, (item['digest'] as CanonicalString).value);
    });
  }
  test('existing fixtures exercise both factual record families', () {
    expect(count, greaterThanOrEqualTo(2));
  });
}
