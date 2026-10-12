import 'package:ub_domain/ub_domain.dart';

import 'events.dart';

/// Derived from custody and the owning rule, never persisted as a new assertion.
final class PowerFact {
  PowerFact({
    required this.subject,
    required this.predicate,
    required this.value,
    required Iterable<RecordVersionId> evidence,
    required this.rule,
  }) : evidence = List.unmodifiable(evidence);
  final RecordRef subject, predicate;
  final DomainValue value;
  final List<RecordVersionId> evidence;
  final RecordId rule;
}

final class PowerEvaluationError implements Exception {
  const PowerEvaluationError();
  @override
  String toString() =>
      'Possession-effect work budget exhausted; narrow the requested state.';
}

List<PowerFact> derivePowers({
  required List<RecordVersion> records,
  required List<RecordId> subjects,
  required List<RecordId> predicates,
  required RecordRef context,
  required FrameTime time,
  WorldId? world,
}) {
  if (time is TimelessFrameTime) return const [];
  var remaining = 1000000;
  void charge(int cost) {
    if (cost > remaining) throw const PowerEvaluationError();
    remaining -= cost;
  }

  charge(records.length);
  final propositions = <(RecordId, RecordId), List<RecordVersion>>{};
  final equivalent = <String, List<RecordId>>{};
  final assertions = <RecordId, List<RecordVersion>>{};
  for (final r in records) {
    switch (r.payload) {
      case PropositionRecord(:final subject, :final predicate):
        propositions
            .putIfAbsent((subject.record, predicate.record), () => [])
            .add(r);
        equivalent
            .putIfAbsent(r.payloadDigest, () => [])
            .add(r.identity.recordId);
      case AssertionRecord(:final proposition):
        assertions.putIfAbsent(proposition.record, () => []).add(r);
      default:
        break;
    }
  }
  final eventRecords = time is AtEventFrameTime
      ? records.where((r) => r.identity.recordId == time.event.record).toList()
      : const <RecordVersion>[];
  bool? active(Validity validity) => eventApplies(validity, time, eventRecords);
  bool applies(Applicability scope) => switch (scope) {
    UniverseApplicability() => true,
    WorldsApplicability(:final worldIds) =>
      world != null && worldIds.contains(world),
    _ => false,
  };
  bool scoped(Scope scope) =>
      scope.context == context &&
      scope.realm == null &&
      applies(scope.applicability);
  final out = <PowerFact>[];
  final recipients = <RecordId, Set<RecordRef>>{};
  final uncertain = <RecordId>{};
  for (final rule in records) {
    charge(1);
    final power = rule.payload;
    if (power is! ItemPowerRecord) continue;
    if (power.scope.realm != null ||
        power.scope.context != context ||
        predicates.isNotEmpty &&
            !predicates.contains(power.powerPredicate.record)) {
      continue;
    }
    if (!applies(power.scope.applicability) || active(power.validity) != true) {
      continue;
    }
    final seen = <String>{};
    for (final prop
        in propositions[(power.item.record, power.holderPredicate.record)] ??
            const <RecordVersion>[]) {
      charge(1);
      final p = prop.payload as PropositionRecord;
      if (p.subject != power.item ||
          p.predicate != power.holderPredicate ||
          p.context != context ||
          !seen.add(prop.payloadDigest)) {
        continue;
      }
      final value = p.value;
      if (value is! ReferenceValue || value.kind != ValueReferenceKind.entity) {
        continue;
      }
      final holder = value.record;
      final chain = <RecordVersionId>[];
      var refuted = false;
      for (final id in equivalent[prop.payloadDigest] ?? const <RecordId>[]) {
        for (final r in assertions[id] ?? const <RecordVersion>[]) {
          charge(1);
          final a = r.payload as AssertionRecord;
          if (!scoped(a.scope)) continue;
          final applies = active(a.validity);
          if (a.polarity == Polarity.support &&
              applies != false &&
              (a.precision != Precision.exact ||
                  a.alternatives.isNotEmpty ||
                  applies == null)) {
            uncertain.add(rule.identity.recordId);
          }
          if (a.polarity == Polarity.refutation && applies != false) {
            refuted = true;
          }
          if (a.polarity == Polarity.support &&
              a.precision == Precision.exact &&
              a.alternatives.isEmpty &&
              applies == true) {
            chain.add(r.recordVersionId);
          }
        }
      }
      if (refuted || chain.isEmpty) continue;
      recipients.putIfAbsent(rule.identity.recordId, () => {}).add(holder);
      if (!subjects.contains(holder.record)) continue;
      var muted = false;
      for (final prop
          in propositions[(holder.record, power.powerPredicate.record)] ??
              const <RecordVersion>[]) {
        charge(1);
        final p = prop.payload as PropositionRecord;
        if (p.subject != holder || p.context != context) continue;
        for (final assertion
            in assertions[prop.identity.recordId] ?? const <RecordVersion>[]) {
          charge(1);
          final a = assertion.payload as AssertionRecord;
          final denies =
              a.polarity == Polarity.refutation && p.value == power.value ||
              a.polarity == Polarity.support &&
                  power.value is BooleanValue &&
                  (power.value as BooleanValue).value &&
                  p.value is BooleanValue &&
                  !(p.value! as BooleanValue).value;
          if (scoped(a.scope) && denies && active(a.validity) != false) {
            muted = true;
          }
        }
      }
      if (muted) continue;
      chain.addAll([prop.recordVersionId, rule.recordVersionId]);
      final evidence = chain.toSet().toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      if (!out.any(
        (f) => f.subject == holder && f.rule == rule.identity.recordId,
      )) {
        out.add(
          PowerFact(
            subject: holder,
            predicate: power.powerPredicate,
            value: power.value,
            evidence: evidence,
            rule: rule.identity.recordId,
          ),
        );
      }
    }
  }
  return List.unmodifiable(
    out.where(
      (f) => !uncertain.contains(f.rule) && recipients[f.rule]?.length == 1,
    ),
  );
}
