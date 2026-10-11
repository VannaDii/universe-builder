@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

void main() {
  final fixtures = CanonicalValue.parseJson(
    File('../../fixtures/dart-contracts/writing.json').readAsStringSync(),
  ) as CanonicalArray;
  for (final (index, raw) in fixtures.items.indexed) {
    final f = {for (final e in (raw as CanonicalObject).fields) e.key: e.value};
    final type = (f['type']! as CanonicalString).value;
    test('owning Rust ordinary writing fields $index:$type', () {
      final value = CanonicalValue.parseWireJson(
        (f['input_raw']! as CanonicalString).value,
      );
      final wire = switch (type) {
        'fact_value' => FactValue.fromWire(value).toWire(),
        'fact_lifetime' => FactLifetime.fromWire(value).toWire(),
        'fact_change' => FactChange.fromWire(value).toWire(),
        'object_change' => ObjectChange.fromWire(value).toWire(),
        'definition_change' => DefinitionChange.fromWire(value).toWire(),
        'writing_claim' => WritingClaim.fromWire(value).toWire(),
        'writing_correction' => WritingCorrection.fromWire(value).toWire(),
        'writing_fact_ending' => WritingFactEnding.fromWire(value).toWire(),
        'writing_fact_withdrawal' => WritingFactWithdrawal.fromWire(
          value,
        ).toWire(),
        'read_facts' => ReadFactsRequest.fromWire(value).toArgs(),
        'read_contracts' => ReadContractsRequest.fromWire(value).toArgs(),
        _ => throw StateError('Unknown fixture'),
      };
      expect(wire.toText(), (f['canonical_utf8']! as CanonicalString).value);
    });
  }
}
