import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

CanonicalValue wire(String text) => CanonicalValue.parseWireJson(text);
final claim = WritingClaim(
  subject: 'Door',
  property: 'open',
  value: const FactBooleanValue(true),
);
CanonicalObject add(CanonicalObject value, String key, CanonicalValue item) =>
    CanonicalObject([...value.fields, MapEntry(key, item)]);

void main() {
  test('intended recipients receipt and understanding remain separate immutable declarations', () {
    final to = ['Iven', 'Mara'];
    final receipt = ['Iven'];
    final understood = ['Iven'];
    final message = WritingMessage(
      label: 'm1',
      from: 'Mara',
      to: to,
      receivedBy: receipt,
      claim: claim,
      understoodBy: understood,
    );
    to.clear();
    receipt.clear();
    understood.clear();
    expect(message.to, ['Iven', 'Mara']);
    expect(message.receivedBy, ['Iven']);
    expect(message.understoodBy, ['Iven']);
    expect(message.to.clear, throwsUnsupportedError);
    expect(message.receivedBy.clear, throwsUnsupportedError);
    expect(message.sentTick, isNull);
    expect(message.receivedTick, isNull);
    expect(message.distorted, isFalse);
    final empty = WritingMessage.fromWire(
      wire(
        '{"label":"m2","from":"Mara","to":[],"received_by":[],"claim":{"subject":"Door","property":"open","value":true}}',
      ),
    );
    expect(empty.to, isEmpty);
    expect(empty.receivedBy, isEmpty);
    expect(empty.understoodBy, isEmpty);
    expect(empty.toWire().toText(), isNot(contains('sent_date')));
    expect(empty.toWire().toText(), contains('"sent_tick":null'));
  });
  test('message correction preserves absent versus explicit empty list replacement', () {
    final absent = WritingMessageCorrection(
      messageEditHandle: 'opaque message version',
      reason: 'correct history',
    );
    final empty = WritingMessageCorrection(
      messageEditHandle: 'opaque message version',
      reason: 'clear audience',
      to: [],
      receivedBy: [],
      claims: [],
      clearChannel: true,
      clearReceipt: true,
      distorted: false,
    );
    expect(absent.to, isNull);
    expect(empty.to, isEmpty);
    expect(empty.claims, isEmpty);
    expect(WritingMessageCorrection.fromWire(absent.toWire()).to, isNull);
    expect(WritingMessageCorrection.fromWire(empty.toWire()).to, isEmpty);
    expect(absent.toWire().toText(), contains('"to":null'));
    expect(empty.toWire().toText(), contains('"to":[]'));
    expect(empty.clearReceipt, isTrue);
    expect(empty.distorted, isFalse);
  });
  test('event participants and authored knowledge dependencies stay explicit and immutable', () {
    final participants = {'actor': 'Mara', 'target': 'Door'};
    final requirements = [
      WritingKnowledgeRequirement(holder: 'Mara', claim: claim),
    ];
    final event = WritingEvent(
      action: 'Open door',
      participants: participants,
      requiresKnowledge: requirements,
    );
    participants.clear();
    requirements.clear();
    expect(event.participants, {'actor': 'Mara', 'target': 'Door'});
    expect(event.requiresKnowledge, hasLength(1));
    expect(event.participants.clear, throwsUnsupportedError);
    expect(event.requiresKnowledge.clear, throwsUnsupportedError);
    expect(event.atTick, isNull);
    expect(event.world, isNull);
    expect(
      () => WritingEvent.fromWire(
        add(event.toWire(), 'effects', CanonicalArray([])),
      ),
      throwsFormatException,
    );
    final none = WritingEvent.fromWire(
      wire('{"action":"Open door","participants":{}}'),
    );
    expect(none.requiresKnowledge, isEmpty);
    expect(none.participants, isEmpty);
  });
  test('event correction keeps unedited roles distinct from explicitly replacing all roles', () {
    final unchanged = WritingEventCorrection(
      eventHandle: 'opaque event version',
      reason: 'correct history',
    );
    final participants = <String, String>{};
    final requirements = <WritingKnowledgeRequirement>[];
    final cleared = WritingEventCorrection(
      eventHandle: 'opaque event version',
      reason: 'clear roles and direct prerequisites',
      participants: participants,
      requiresKnowledge: requirements,
    );
    participants['actor'] = 'Mara';
    requirements.add(WritingKnowledgeRequirement(holder: 'Mara', claim: claim));
    expect(unchanged.participants, isNull);
    expect(cleared.participants, isEmpty);
    expect(cleared.requiresKnowledge, isEmpty);
    expect(
      WritingEventCorrection.fromWire(unchanged.toWire()).requiresKnowledge,
      isNull,
    );
    expect(
      WritingEventCorrection.fromWire(cleared.toWire()).requiresKnowledge,
      isEmpty,
    );
    expect(
      WritingEventWithdrawal(
        eventHandle: 'opaque event version',
        reason: 'withdraw support',
      ).toWire().toText(),
      isNot(contains('non_occurrence')),
    );
  });
  test('attitudes preserve distinct epistemic modes without promoting belief to knowledge', () {
    for (final attitude in WritingAttitudeKind.values) {
      final value = WritingAttitude(
        holder: 'Iven',
        claim: claim,
        attitude: attitude,
      );
      final back = WritingAttitude.fromWire(value.toWire());
      expect(back.attitude, attitude);
      expect(back.message, isNull);
      expect(back.lifetime, isA<FactUnspecifiedLifetime>());
    }
    final knows = WritingAttitude(
      holder: 'Iven',
      claim: claim,
      attitude: WritingAttitudeKind.knows,
      message: 'm1',
      atTick: '9007199254740993',
      lifetime: const FactUntilChangedLifetime(),
    );
    expect(WritingAttitude.fromWire(knows.toWire()).message, 'm1');
    expect(WritingAttitude.fromWire(knows.toWire()).atTick, '9007199254740993');
    expect(
      () => WritingAttitudeKind.fromName('understands'),
      throwsFormatException,
    );
  });
  test('explicit knowledge absence requires authored lifetime and retains nullable date field', () {
    final boundary = WritingKnowledgeBoundary(
      name: 'Iven lacks this knowledge',
      holder: 'Iven',
      claim: claim,
      scope: 'Earth',
      lifetime: const FactUntilChangedLifetime(),
    );
    expect(boundary.toWire().toText(), contains('"at_date":null'));
    final absent = CanonicalObject(
      boundary.toWire().fields.where((e) => e.key != 'lifetime'),
    );
    expect(
      () => WritingKnowledgeBoundary.fromWire(absent),
      throwsFormatException,
    );
    expect(WritingKnowledgeBoundary.fromWire(boundary.toWire()).scope, 'Earth');
  });
  test('interpretation corrections preserve explicit removal and attributed content', () {
    final removal = WritingInterpretationCorrection(
      attitudeHandle: 'opaque attitude version',
      reason: 'remove unsupported interpretation',
      clearInterpretation: true,
    );
    expect(removal.interpretation, isNull);
    expect(
      WritingInterpretationCorrection.fromWire(removal.toWire())
          .clearInterpretation,
      isTrue,
    );
    final correction = WritingInterpretationCorrection(
      attitudeHandle: 'opaque attitude version',
      reason: 'correct interpretation',
      interpretation: claim,
    );
    expect(
      WritingInterpretationCorrection.fromWire(correction.toWire())
          .interpretation!
          .subject,
      'Door',
    );
    expect(
      () => WritingInterpretationCorrection.fromWire(
        add(correction.toWire(), 'knows', const CanonicalBool(true)),
      ),
      throwsFormatException,
    );
  });
  test('attitude corrections retain numeric amounts explicit certainty removal and exclusive ending', () {
    final correction = WritingAttitudeCorrection.fromWire(
      wire(
        '{"attitude_handle":"opaque attitude version","reason":"correct recorded account","value":{"amount":30.00,"unit":"m"},"clear_certainty":true,"end_tick":"0009","end_date":"1900-01-01"}',
      ),
    );
    expect((correction.value! as FactQuantityValue).amount.digits, '30.00');
    expect(correction.clearCertainty, isTrue);
    expect(correction.certainty, isNull);
    expect(correction.endTick, '0009');
    expect(correction.atTick, isNull);
    expect(
      WritingAttitudeCorrection.fromWire(correction.toWire()).endDate,
      '1900-01-01',
    );
  });
  test('knowledge and channel policy retain authored modes and exact delays with no defaults', () {
    for (final mode in KnowledgeMode.values) {
      final policy = WritingKnowledgeModePolicy(
        name: 'Knowledge rules',
        mode: mode,
      );
      expect(
        (WritingKnowledgePolicy.fromWire(
          policy.toWire(),
        ) as WritingKnowledgeModePolicy).mode,
        mode,
      );
    }
    final channel = WritingKnowledgePolicy.fromWire(
      wire(
        '{"kind":"channel","name":"Radio chronology","channel":"Radio","forward_only":true}',
      ),
    ) as WritingChannelPolicy;
    expect(channel.minimumDelay, isNull);
    expect(channel.maximumDelay, isNull);
    expect(channel.forwardOnly, isTrue);
    expect(channel.toWire().toText(), contains('"minimum_delay":null'));
    final correction = WritingPolicyCorrection(
      policyHandle: 'opaque policy version',
      reason: 'explicit correction',
      minimumDelay: '0003',
      clearMaximumDelay: true,
      mode: KnowledgeMode.justified,
    );
    expect(
      WritingPolicyCorrection.fromWire(correction.toWire()).minimumDelay,
      '0003',
    );
    expect(correction.scope, isNull);
    expect(
      () => WritingKnowledgePolicy.fromWire(
        wire('{"kind":"channel","name":"Radio chronology","channel":"Radio"}'),
      ),
      throwsFormatException,
    );
  });
  test('author knowledge declarations keep private input separate from communication acquisition', () {
    final declaration = AuthorKnowledgeDeclaration(
      holder: 'Iven',
      claim: claim,
      lifetime: const FactUntilChangedLifetime(),
    );
    expect(declaration.atTick, '');
    expect(declaration.world, isNull);
    expect(declaration.toWire().toText(), isNot(contains('message')));
    expect(
      AuthorKnowledgeDeclaration.fromWire(declaration.toWire()).atTick,
      '',
    );
    final missing = CanonicalObject(
      declaration.toWire().fields.where((e) => e.key != 'lifetime'),
    );
    expect(
      () => AuthorKnowledgeDeclaration.fromWire(missing),
      throwsFormatException,
    );
  });
  test('closed inputs reject unknown fields wrong list types and implicit recipients', () {
    for (final raw in [
      '{"label":"m1","from":"Mara","received_by":[],"claim":{"subject":"Door","property":"open","value":true}}',
      '{"label":"m1","from":"Mara","to":[],"claim":{"subject":"Door","property":"open","value":true}}',
      '{"label":"m1","from":"Mara","to":[],"received_by":[],"claim":{"subject":"Door","property":"open","value":true},"understood_by":null}',
    ]) {
      expect(() => WritingMessage.fromWire(wire(raw)), throwsFormatException);
    }
    expect(
      () => WritingMessageCorrection.fromWire(
        wire(
          '{"message_edit_handle":"opaque","reason":"correction","claims":[true]}',
        ),
      ),
      throwsFormatException,
    );
    expect(
      () => WritingEventCorrection.fromWire(
        wire(
          '{"event_handle":"opaque","reason":"correction","participants":{"actor":true}}',
        ),
      ),
      throwsFormatException,
    );
    expect(
      () => WritingPolicyCorrection.fromWire(
        wire(
          '{"policy_handle":"opaque","reason":"correction","clear_minimum_delay":null}',
        ),
      ),
      throwsFormatException,
    );
  });
}
