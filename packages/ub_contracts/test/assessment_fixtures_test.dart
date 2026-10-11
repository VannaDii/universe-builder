@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

Map<String, CanonicalValue> object(CanonicalValue value) => {
  for (final e in (value as CanonicalObject).fields) e.key: e.value,
};
String string(CanonicalValue value) => (value as CanonicalString).value;
CanonicalValue file(String name) => CanonicalValue.parseJson(
  File('../../fixtures/source-assessments/$name.json').readAsStringSync(),
);

void main() {
  final examples = object(file('relational-examples'));
  final proofs = object(object(file('relational-proofs'))['bindings']!);
  for (final (raw, key, bindingKey) in [
    (examples, 'assessment', 'final_validation'),
    (
      object(examples['production_bound_example']!),
      'production_assessment',
      'production_final_validation',
    ),
  ]) {
    test('independent assessment wire bytes:$key', () {
      final envelope = AssessmentEnvelope.fromWire(raw['assessment']!);
      final body = envelope.body;
      final proof = object(proofs[key]!);
      expect(body.toWire().toText(), string(proof['canonical_utf8']!));
      // Serialization parity, not accounting/attachment admission.
      expect(
        payloadDigest('source-assessment:v1', body.toWire()),
        string(proof['sha256']!),
      );
      expect(envelope.toWire().toText(), raw['assessment']!.toText());
      expect(
        AssessmentSelection.fromWire(raw['selection']!).toWire().toText(),
        raw['selection']!.toText(),
      );
    });
    test('independent final binding bytes and digest:$bindingKey', () {
      final binding = SourceValidationBindingV1.fromWire(raw['final_binding']!);
      final proof = object(proofs[bindingKey]!);
      expect(binding.toWire().toText(), string(proof['canonical_utf8']!));
      expect(binding.digest().value, string(proof['sha256']!));
      expect(
        executionResultDigest(Validation.fromWire(raw['execution_core']!)),
        binding.executionResultDigest,
      );
    });
  }
  test('fresh record-only binding preserves unavailable assessment', () {
    final binding = SourceValidationBindingV1.fromWire(
      examples['fresh_record_only_binding']!,
    );
    expect(binding.assessmentState, isA<UnavailableAssessment>());
    expect(
      binding.digest().value,
      string(object(proofs['fresh_record_only_final_validation']!)['sha256']!),
    );
  });
  test('Unicode escapes and exact u64 body fixture keeps independent canonical bytes', () {
    final edge = object(file('edge'));
    final body = SourceAssessmentV1.fromWire(edge['body']!);
    expect(body.toWire().toText(), string(edge['canonical_utf8']!));
    expect(
      payloadDigest('source-assessment:v1', body.toWire()),
      string(edge['digest']!),
    );
  });
}
