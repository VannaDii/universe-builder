import 'dart:convert';

import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

const communicationChronologyCapability = 'communications.chronology.v1';
final _nonWhitespace = RegExp(
  r'[^\u0009-\u000d\u0020\u0085\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000]',
);
final _min = -(BigInt.one << 127), _max = (BigInt.one << 127) - BigInt.one;
BigInt? _ticks(String s) {
  if (!RegExp(r'^[+-]?[0-9]+$').hasMatch(s)) {
    return null;
  }
  final n = BigInt.tryParse(s);
  return n != null && n >= _min && n <= _max ? n : null;
}

InvalidArgumentError _invalid(String message) =>
    InvalidArgumentError(field: 'channelChronology', message: message);

void validateChannelChronologyRule(RuleRecord rule) {
  final contract = rule.channelChronology;
  if (contract == null) {
    if (rule.capabilities.contains(communicationChronologyCapability)) {
      throw _invalid(
        'chronology capability requires an authored channel contract',
      );
    }
    return;
  }
  if (!rule.executable ||
      rule.kind != RuleKind.physicalConstraint ||
      rule.commitPolicy != CommitPolicy.alwaysBlock ||
      rule.applicability is! UniverseApplicability ||
      rule.validity is! UnspecifiedValidity ||
      rule.subjectTypes.isNotEmpty ||
      rule.targetPredicates.isNotEmpty ||
      rule.expression is! LiteralExpr ||
      !(rule.expression as LiteralExpr).value ||
      rule.capabilities.length != 1 ||
      rule.capabilities.single != communicationChronologyCapability ||
      !_nonWhitespace.hasMatch(contract.channel) ||
      utf8.encode(contract.channel).length > 256) {
    throw _invalid(
      'chronology needs an executable universe-wide physical constraint with always_block, unspecified validity, literal true and only its capability',
    );
  }
  final minimum = contract.minimumDelay == null
          ? null
          : _ticks(contract.minimumDelay!),
      maximum = contract.maximumDelay == null
          ? null
          : _ticks(contract.maximumDelay!);
  if (contract.minimumDelay != null && minimum == null ||
      contract.maximumDelay != null && maximum == null) {
    throw _invalid('delay must be signed i128 clock ticks');
  }
  if (minimum != null && maximum != null && minimum > maximum ||
      contract.forwardOnly && maximum != null && maximum < BigInt.zero) {
    throw _invalid('authored delay bounds are inconsistent');
  }
}

BigInt? _delay(CommunicationRecord c) {
  if (c.actualRecipients.isEmpty) {
    return null;
  }
  final sent = c.sentAt, received = c.receivedAt;
  if (sent is! ExactTime ||
      received is! ExactTime ||
      sent.calendar != received.calendar) {
    return null;
  }
  final a = _ticks(sent.value), b = _ticks(received.value);
  if (a == null || b == null) {
    return null;
  }
  final d = b - a;
  return d < _min || d > _max ? null : d;
}

/// Opt-in authored transmission timing; all messages are reassessed when rules
/// change. Recipients, receipt times and cross-clock mappings are never inferred.
List<Finding> assessCommunicationChronology(List<RecordVersion> records) {
  final policies = <(RecordVersion, ChannelChronology)>[
    for (final r in records)
      if (r.payload is RuleRecord &&
          (r.payload as RuleRecord).channelChronology != null)
        (r, (r.payload as RuleRecord).channelChronology!),
  ];
  if (policies.isEmpty) {
    return const [];
  }
  final findings = <Finding>[];
  for (final row in records) {
    final c = row.payload;
    if (c is! CommunicationRecord) {
      continue;
    }
    final matching = policies.where((p) => c.channel == p.$2.channel).toList();
    if (matching.isEmpty) {
      findings.add(
        Finding(
          message: 'No authored chronology contract matches this communication channel. Retrieve the channel policies or correct the declared channel.',
          fingerprint: FindingFingerprint(''),
          ruleId: row.identity.recordId,
          outcome: EvidenceOutcome.notEstablished,
          evidence: [row.recordVersionId],
          coverage: Coverage.unsupported,
        ),
      );
    }
    for (final (rule, contract) in matching) {
      final d = _delay(c);
      final min = contract.minimumDelay == null
              ? null
              : _ticks(contract.minimumDelay!),
          max = contract.maximumDelay == null
              ? null
              : _ticks(contract.maximumDelay!);
      final pass = d == null
          ? null
          : (!contract.forwardOnly || d >= BigInt.zero) &&
                (contract.minimumDelay == null || min != null && d >= min) &&
                (contract.maximumDelay == null || max != null && d <= max);
      findings.add(
        Finding(
          message: switch (pass) {
            true => 'Authored channel chronology is satisfied.',
            false => 'Transmission violates the authored forward-order or delay bounds. Retrieve this communication and its channel rule; correct send/receipt times or explicitly revise the policy.',
            null => 'Chronology needs an actual recipient, receipt time and comparable exact same-clock send/receipt ticks. Repair the missing fact; delivery and clock conversion are not inferred.',
          },
          fingerprint: FindingFingerprint(''),
          ruleId: rule.identity.recordId,
          outcome: pass == null
              ? EvidenceOutcome.notEstablished
              : pass
              ? EvidenceOutcome.supported
              : EvidenceOutcome.refuted,
          evidence: [rule.recordVersionId, row.recordVersionId],
          coverage: pass == null ? Coverage.unsupported : Coverage.complete,
        ),
      );
    }
  }
  return List.unmodifiable(findings);
}
