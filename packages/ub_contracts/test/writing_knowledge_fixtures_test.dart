@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

void main() {
  final fixtures = CanonicalValue.parseJson(
    File('../../fixtures/dart-contracts/writing-knowledge.json')
        .readAsStringSync(),
  ) as CanonicalArray;
  for (final (index, raw) in fixtures.items.indexed) {
    final f = {for (final e in (raw as CanonicalObject).fields) e.key: e.value};
    final type = (f['type']! as CanonicalString).value;
    test('owning Rust writing knowledge fields $index:$type', () {
      final value = CanonicalValue.parseWireJson(
        (f['input_raw']! as CanonicalString).value,
      );
      final encoded = switch (type) {
        'knowledge_requirement' => WritingKnowledgeRequirement.fromWire(
          value,
        ).toWire(),
        'event' => WritingEvent.fromWire(value).toWire(),
        'message' => WritingMessage.fromWire(value).toWire(),
        'attitude' => WritingAttitude.fromWire(value).toWire(),
        'knowledge_boundary' => WritingKnowledgeBoundary.fromWire(
          value,
        ).toWire(),
        'message_correction' => WritingMessageCorrection.fromWire(
          value,
        ).toWire(),
        'interpretation_correction' => WritingInterpretationCorrection.fromWire(
          value,
        ).toWire(),
        'attitude_correction' => WritingAttitudeCorrection.fromWire(
          value,
        ).toWire(),
        'policy_correction' => WritingPolicyCorrection.fromWire(value).toWire(),
        'event_correction' => WritingEventCorrection.fromWire(value).toWire(),
        'event_withdrawal' => WritingEventWithdrawal.fromWire(value).toWire(),
        'author_knowledge' => AuthorKnowledgeDeclaration.fromWire(
          value,
        ).toWire(),
        'knowledge_policy' => WritingKnowledgePolicy.fromWire(value).toWire(),
        _ => throw StateError('Unknown fixture'),
      };
      expect(encoded.toText(), (f['canonical_utf8']! as CanonicalString).value);
    });
  }
}
