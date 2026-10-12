import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/communication_checks.dart';

import 'operation_compilation_test.dart' as fixtures;

final cal = CalendarId.parse('cal_000000000000000000000009');
final otherCal = CalendarId.parse('cal_000000000000000000000008');
final min = -(BigInt.one << 127), max = (BigInt.one << 127) - BigInt.one;

RuleRecord policy({
  String channel = 'speech',
  bool forward = true,
  String? minimum,
  String? maximum,
}) => RuleRecord(
  namespace: 'test',
  key: 'channel',
  labels: {},
  kind: RuleKind.physicalConstraint,
  commitPolicy: CommitPolicy.alwaysBlock,
  applicability: const UniverseApplicability(),
  targetPredicates: [],
  expression: const LiteralExpr(true),
  capabilities: [communicationChronologyCapability],
  executable: true,
  validity: const UnspecifiedValidity(),
  channelChronology: ChannelChronology(
    channel: channel,
    forwardOnly: forward,
    minimumDelay: minimum,
    maximumDelay: maximum,
  ),
);

CommunicationRecord message({
  String? channel = 'speech',
  String sent = '10',
  String? received = '11',
  CalendarId? receiptClock,
  bool delivered = true,
  bool distorted = false,
}) => CommunicationRecord(
  sender: fixtures.ref(1),
  intendedRecipients: [fixtures.ref(2)],
  actualRecipients: delivered ? [fixtures.ref(2)] : [],
  content: [fixtures.ref(3)],
  channel: channel,
  sentAt: ExactTime(cal, sent),
  receivedAt: received == null
      ? null
      : ExactTime(receiptClock ?? cal, received),
  distorted: distorted,
);

List<Finding> assess(CommunicationRecord c, {RuleRecord? rule}) =>
    assessCommunicationChronology([
      fixtures.row(4, rule ?? policy()),
      fixtures.row(5, c),
    ]);

void main() {
  test('legacy messages have no implied channel policy', () {
    expect(
      assessCommunicationChronology([fixtures.row(5, message())]),
      isEmpty,
    );
    expect(assessCommunicationChronology([]), isEmpty);
  });

  test('inclusive delay bounds retain exact evidence and rule identity', () {
    final rule = policy(minimum: '+0002', maximum: '4');
    validateChannelChronologyRule(rule);
    for (final delay in [2, 3, 4]) {
      final finding = assess(
        message(received: '${10 + delay}'),
        rule: rule,
      ).single;
      expect(finding.outcome, EvidenceOutcome.supported);
      expect(finding.coverage, Coverage.complete);
      expect(finding.ruleId, fixtures.id(4));
      expect(finding.evidence, [fixtures.ver(4), fixtures.ver(5)]);
      expect(finding.records, isEmpty);
      expect(finding.fingerprint, FindingFingerprint(''));
    }
    for (final delay in [1, 5]) {
      final finding = assess(
        message(received: '${10 + delay}'),
        rule: rule,
      ).single;
      expect(finding.outcome, EvidenceOutcome.refuted);
      expect(finding.coverage, Coverage.complete);
    }
  });

  test(
    'forward order is explicit and authored negative delays are allowed',
    () {
      expect(
        assess(message(received: '9')).single.outcome,
        EvidenceOutcome.refuted,
      );
      expect(
        assess(message(received: '10')).single.outcome,
        EvidenceOutcome.supported,
      );
      final backwards = policy(forward: false, minimum: '-2', maximum: '-1');
      validateChannelChronologyRule(backwards);
      expect(
        assess(message(received: '9'), rule: backwards).single.outcome,
        EvidenceOutcome.supported,
      );
      validateChannelChronologyRule(policy(minimum: '-2'));
    },
  );

  test(
    'intended delivery, missing receipt and different clocks stay unresolved',
    () {
      for (final c in [
        message(delivered: false),
        message(received: null),
        message(receiptClock: otherCal),
        message(sent: '10 '),
        message(received: '11\n'),
        message(sent: '−10'),
        message(received: '${max + BigInt.one}'),
        message(sent: min.toString(), received: max.toString()),
      ]) {
        final finding = assess(c).single;
        expect(finding.outcome, EvidenceOutcome.notEstablished);
        expect(finding.coverage, Coverage.unsupported);
        expect(finding.evidence, [fixtures.ver(4), fixtures.ver(5)]);
      }
    },
  );

  test(
    'signed i128 limits and values above web integer precision stay exact',
    () {
      for (final sent in [
        min,
        max - BigInt.one,
        BigInt.parse('9007199254740993'),
      ]) {
        expect(
          assess(message(sent: '$sent', received: '${sent + BigInt.one}'))
              .single
              .outcome,
          EvidenceOutcome.supported,
        );
      }
      expect(
        assess(message(sent: max.toString(), received: min.toString()))
            .single
            .outcome,
        EvidenceOutcome.notEstablished,
      );
    },
  );

  test('active policies leave uncovered or omitted channels unresolved', () {
    for (final channel in [null, 'Speech', 'speech ']) {
      final finding = assess(message(channel: channel)).single;
      expect(finding.ruleId, fixtures.id(5));
      expect(finding.outcome, EvidenceOutcome.notEstablished);
      expect(finding.coverage, Coverage.unsupported);
      expect(finding.evidence, [fixtures.ver(5)]);
    }
  });

  test('all matching contracts reassess unchanged communications', () {
    final c = fixtures.row(5, message(received: '12'));
    final findings = assessCommunicationChronology([
      fixtures.row(4, policy(maximum: '3')),
      fixtures.row(6, policy(maximum: '1')),
      fixtures.row(7, policy(channel: 'mail')),
      c,
    ]);
    expect(findings.map((f) => f.outcome), [
      EvidenceOutcome.supported,
      EvidenceOutcome.refuted,
    ]);
    expect(findings.map((f) => f.ruleId), [fixtures.id(4), fixtures.id(6)]);
    expect(
      assessCommunicationChronology([fixtures.row(4, policy(maximum: '1')), c])
          .single
          .outcome,
      EvidenceOutcome.refuted,
    );
  });

  test('distortion does not change transmission chronology', () {
    expect(
      assess(message(distorted: true)).single.outcome,
      EvidenceOutcome.supported,
    );
  });

  test('non-exact send or receipt does not infer a usable delay', () {
    for (final field in ['sentAt', 'receivedAt']) {
      final c = fixtures.patch(message(), {
        field: const UnspecifiedTime().encode(canonical: false),
      });
      final finding = assess(c).single;
      expect(finding.outcome, EvidenceOutcome.notEstablished);
      expect(finding.coverage, Coverage.unsupported);
    }
  });

  test('rule admission requires the exact executable policy shape', () {
    final valid = policy();
    for (final change in <Map<String, CanonicalValue>>[
      {'executable': const CanonicalBool(false)},
      {
        'applicability': WorldsApplicability([
          WorldId.parse('wld_000000000000000000000008'),
        ]).encode(canonical: false),
      },
      {'validity': InstantValidity(ExactTime(cal, '10')).toWire()},
      {'kind': CanonicalString('law')},
      {'commitPolicy': CanonicalString('advisory')},
      {'expression': const LiteralExpr(false).encode(canonical: false)},
      {'capabilities': CanonicalArray([])},
      {
        'capabilities': CanonicalArray([
          CanonicalString(communicationChronologyCapability),
          CanonicalString('other'),
        ]),
      },
      {
        'subjectTypes': CanonicalArray([CanonicalString(fixtures.id(1).value)]),
      },
      {
        'targetPredicates': CanonicalArray([CanonicalString('test:foo')]),
      },
      {'channelChronology': const CanonicalNull()},
    ]) {
      final bad = fixtures.patch(valid, change);
      expect(
        () => validateChannelChronologyRule(bad),
        throwsA(isA<InvalidArgumentError>()),
      );
    }
    final ordinary = fixtures.patch(valid, {
      'channelChronology': const CanonicalNull(),
      'capabilities': CanonicalArray([]),
    });
    validateChannelChronologyRule(ordinary);
  });

  test('channel admission uses UTF8 length and Rust whitespace semantics', () {
    for (final channel in ['', ' \t\n\u0085\u3000', 'a' * 257, 'é' * 129]) {
      expect(
        () => validateChannelChronologyRule(policy(channel: channel)),
        throwsA(isA<InvalidArgumentError>()),
      );
    }
    for (final channel in ['a' * 256, 'é' * 128, '\ufeff']) {
      validateChannelChronologyRule(policy(channel: channel));
    }
  });

  test('invalid numeric bounds and inconsistent intervals are rejected', () {
    for (final bound in ['', ' 1', '1\n', '1.0', '−1', '${max + BigInt.one}']) {
      expect(
        () => validateChannelChronologyRule(policy(minimum: bound)),
        throwsA(isA<InvalidArgumentError>()),
      );
      expect(
        () => validateChannelChronologyRule(policy(maximum: bound)),
        throwsA(isA<InvalidArgumentError>()),
      );
    }
    for (final p in [
      policy(minimum: '3', maximum: '2'),
      policy(maximum: '-1'),
    ]) {
      expect(
        () => validateChannelChronologyRule(p),
        throwsA(isA<InvalidArgumentError>()),
      );
    }
    validateChannelChronologyRule(
      policy(forward: false, minimum: '$min', maximum: '$max'),
    );
  });
}
