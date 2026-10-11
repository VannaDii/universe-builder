@TestOn('vm')
library;

import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'assessment_integrity_test.dart' show replace;

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
      // Independent owning bytes exercise accounting before hashing.
      expect(body.digest().value, string(proof['sha256']!));
      envelope.verify();
      expect(utf8.decode(body.canonicalBytes()), body.toWire().toText());
      expect(
        SourceAssessmentV1.decode(body.canonicalBytes()).digest(),
        body.digest(),
      );
      body.verifySourceBytes(
        (_) => Uint8List.fromList(utf8.encode(string(examples['source_a']!))),
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
    expect(body.digest().value, string(edge['digest']!));
  });
  final original = object(examples['assessment']!)['body']!;
  test(
    'material accounting rejects dangling duplicate and unaccounted links',
    () {
      for (final (path, value) in <(List<Object>, CanonicalValue)>[
        (['declared_inventory', 0, 'mapping_ids'], CanonicalArray([])),
        (
          ['declared_inventory', 0, 'mapping_ids'],
          CanonicalArray([CanonicalString('missing')]),
        ),
        (
          ['declared_inventory', 0, 'mapping_ids'],
          CanonicalArray([
            CanonicalString('speech'),
            CanonicalString('speech'),
          ]),
        ),
        (
          ['claim_mappings', 0, 'item_ids'],
          CanonicalArray([CanonicalString('waiting')]),
        ),
        (['claim_mappings', 0, 'mapping_id'], CanonicalString('waiting')),
        (['claim_mappings', 0, 'occurrence'], CanonicalString('unknown')),
        (['claim_mappings', 0, 'judgment'], CanonicalString('unresolved')),
        (['claim_mappings', 0, 'judgment'], CanonicalString('contradicted')),
        (
          ['declared_inventory', 0, 'range', 'end'],
          const CanonicalNumber('48'),
        ),
        (['dependencies'], CanonicalArray([])),
        (
          ['claim_mappings', 0, 'context', 'universe'],
          CanonicalString('unv_000000000000000000000002'),
        ),
      ]) {
        expect(
          SourceAssessmentV1.fromWire(replace(original, path, value)).validate,
          throwsFormatException,
          reason: path.toString(),
        );
      }
    },
  );
  test(
    'unknown material needs reciprocal disposition and unresolved conclusion',
    () {
      var tree = replace(original, [
        'claim_mappings',
        0,
        'occurrence',
      ], CanonicalString('unknown'));
      tree = replace(tree, [
        'claim_mappings',
        0,
        'judgment',
      ], CanonicalString('unresolved'));
      tree = replace(tree, [
        'declared_inventory',
        0,
        'unresolved_ids',
      ], CanonicalArray([CanonicalString('pending')]));
      tree = replace(
        tree,
        ['unresolved'],
        CanonicalArray([
          UnresolvedDisposition(
            unresolvedId: 'pending',
            itemIds: ['utterance'],
            reason: UnresolvedReason.missingEvidence,
            detail: 'Requires external research',
          ).toWire(),
        ]),
      );
      expect(SourceAssessmentV1.fromWire(tree).validate, throwsFormatException);
      tree = replace(tree, ['conclusion'], CanonicalString('unresolved'));
      SourceAssessmentV1.fromWire(tree).validate();
      expect(
        SourceAssessmentV1.fromWire(
          replace(tree, [
            'unresolved',
            0,
            'item_ids',
          ], CanonicalArray([CanonicalString('waiting')])),
        ).validate,
        throwsFormatException,
      );
      final contradicted = replace(
        replace(original, [
          'claim_mappings',
          0,
          'judgment',
        ], CanonicalString('contradicted')),
        ['conclusion'],
        CanonicalString('inconsistent'),
      );
      SourceAssessmentV1.fromWire(contradicted).validate();
    },
  );
  test('conflicting versions require an explicit historical evidence link', () {
    final dependencies =
        (object(original)['dependencies']! as CanonicalArray).items;
    final old = replace(dependencies.first, [
      'version',
    ], CanonicalString('ver_0000000000000000000000ff'));
    var tree = replace(original, [
      'dependencies',
    ], CanonicalArray([...dependencies, old]));
    expect(SourceAssessmentV1.fromWire(tree).validate, throwsFormatException);
    final links =
        (object(
                  (object(tree)['claim_mappings']! as CanonicalArray)
                      .items
                      .first,
                )['candidate_links']!
                as CanonicalArray)
            .items;
    tree = replace(
      tree,
      ['claim_mappings', 0, 'candidate_links'],
      CanonicalArray([
        ...links,
        CanonicalObject([
          MapEntry('kind', CanonicalString('historical_evidence')),
          MapEntry('version', old),
        ]),
      ]),
    );
    SourceAssessmentV1.fromWire(tree).validate();
    expect(
      SourceAssessmentV1.fromWire(
        replace(tree, [
          'claim_mappings',
          0,
          'candidate_links',
          1,
          'kind',
        ], CanonicalString('unchanged_record')),
      ).validate,
      throwsFormatException,
    );
  });
  test(
    'inventory item byte boundaries and changed envelope digest are checked',
    () {
      final body = SourceAssessmentV1.fromWire(
        replace(original, [
          'declared_inventory',
          1,
          'range',
          'start',
        ], const CanonicalNumber('12')),
      );
      body.validate();
      expect(
        () => body.verifySourceBytes(
          (_) => Uint8List.fromList(utf8.encode(string(examples['source_a']!))),
        ),
        throwsFormatException,
      );
      final envelope = AssessmentEnvelope.fromWire(examples['assessment']!);
      expect(
        AssessmentEnvelope(
          assessmentId: envelope.assessmentId,
          digest: Sha256Hex('a' * 64),
          body: envelope.body,
        ).verify,
        throwsFormatException,
      );
    },
  );
}
