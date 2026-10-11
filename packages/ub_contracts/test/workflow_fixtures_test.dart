@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

void main() {
  final cases = CanonicalValue.parseJson(
    File('../../fixtures/dart-contracts/workflow.json').readAsStringSync(),
  ) as CanonicalArray;
  for (var i = 0; i < cases.items.length; i++) {
    final f = {
      for (final e in (cases.items[i] as CanonicalObject).fields)
        e.key: e.value,
    };
    final type = (f['type'] as CanonicalString).value;
    test('Rust workflow contract parity:$type:$i', () {
      final input = f['input']!;
      final wire = switch (type) {
        'proposal' => Proposal.fromWire(input).toWire(),
        'proposal_ref' => ProposalRef.fromWire(input).toWire(),
        'compiled_change' => CompiledChange.fromWire(input).toWire(),
        'impact' => Impact.fromWire(input).toWire(),
        'commit_receipt' => CommitReceipt.fromWire(input).toWire(),
        _ => throw StateError('Unknown fixture type'),
      };
      expect(wire.toText(), (f['wire'] as CanonicalString).value);
    });
  }
}
