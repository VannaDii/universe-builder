@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/operation_compilation.dart';

void main() {
  final fixtures = CanonicalValue.parseJson(
    File('../../fixtures/dart-domain/operations.json').readAsStringSync(),
  ) as CanonicalArray;
  final universe = UniverseId.parse('unv_000000000000000000000001'),
      revision = RevisionId.parse('rev_000000000000000000000001');
  for (final fixture in fixtures.items) {
    final fields = {
      for (final f in (fixture as CanonicalObject).fields) f.key: f.value,
    };
    final op = DomainOperation.fromWire(fields['input']!);
    final expected = CanonicalValue.parseJson(
      (fields['canonical'] as CanonicalString).value,
    ) as CanonicalObject;
    final wire = {for (final f in expected.fields) f.key: f.value};
    // Occurrences need an exact semantic coordinate; their structural fixture
    // intentionally contains prose. They have dedicated end-to-end cases.
    if (wire['client_ref'] == null ||
        wire['record'] is! CanonicalObject ||
        op is RecordEventOperation) {
      continue;
    }
    test('freeze Rust creation fixture: ${op.kind.wireName}', () {
      final changes = compileOperations(
        universe: universe,
        revision: revision,
        base: [],
        operations: [op],
      );
      expect(changes, hasLength(1));
      final stored = changes.single.next!;
      stored.verify();
      expect(stored.identity.universeId, universe);
      expect(changes.single.expected, isNull);
      final payload = stored.payload as CanonicalObject;
      expect(
        CanonicalObject(payload.fields.where((f) => f.key != 'record_kind'))
            .toText(),
        wire['record']!.toText(),
      );
    });
  }
}
