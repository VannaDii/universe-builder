@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_rules/ub_rules.dart';

void main() {
  final fixtures = (CanonicalValue.parseJson(
    File('../../fixtures/dart-domain/typed-record-digests.json')
        .readAsStringSync(),
  ) as CanonicalArray).items;
  for (final fixture in fixtures) {
    final fields = {
      for (final e in (fixture as CanonicalObject).fields) e.key: e.value,
    };
    final payload = RecordPayload.fromWire(fields['value']!);
    if (payload is! RuleRecord) continue;
    final expected = fields['compiled']!;
    test(
      'Rust rule compiler parity: ${(fields['name'] as CanonicalString).value}',
      () {
        final compiled = compileRule(
          RecordId.parse('rec_000000000000000000000001'),
          payload,
        );
        final output = CanonicalObject([
          MapEntry(
            'node_count',
            CanonicalNumber(compiled.nodeCount.toString()),
          ),
          MapEntry('executable', CanonicalBool(compiled.executable)),
          MapEntry(
            'referenced_records',
            CanonicalArray(
              compiled.referencedRecords.map((id) => CanonicalString(id.value)),
            ),
          ),
        ]);
        expect(output.toText(), expected.toText());
      },
    );
  }
}
