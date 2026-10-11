@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

void main() {
  final cases = CanonicalValue.parseJson(
    File('../../fixtures/dart-contracts/validation.json').readAsStringSync(),
  ) as CanonicalArray;
  for (var i = 0; i < cases.items.length; i++) {
    final f = {
      for (final e in (cases.items[i] as CanonicalObject).fields)
        e.key: e.value,
    };
    final type = (f['type'] as CanonicalString).value;
    test('Rust validation contract parity:$type:$i', () {
      final input = f['input']!;
      final wire = switch (type) {
        'finding' => Finding.fromWire(input).toWire(),
        'intersection' => OpposingIntersection.fromWire(input).toWire(),
        'chain' => OpposingChain.fromWire(input).toWire(),
        'opposing' => OpposingEvidence.fromWire(input).toWire(),
        'validation' => Validation.fromWire(input).toWire(),
        'status' => OperationStatus.fromWire(input).toWire(),
        'source_binding' => SourceBinding.fromWire(input).toWire(),
        'submitted_input' => SubmittedInput.fromWire(input).toWire(),
        'assessment_state' => AssessmentState.fromWire(input).toWire(),
        'report' => ValidationV3.fromWire(input).toWire(),
        'status_v3' => OperationStatusV3.fromWire(input).toWire(),
        _ => throw StateError('Unknown fixture type'),
      };
      expect(wire.toText(), (f['wire'] as CanonicalString).value);
      if (type == 'validation') {
        expect(
          executionResultDigest(Validation.fromWire(input)).value,
          (f['execution_digest'] as CanonicalString).value,
        );
      }
    });
  }
}
