import 'package:ub_domain/ub_domain.dart';
import 'package:ub_rules/ub_rules.dart';

/// An internal factual check, with no publication or permission authority.
final class CheckedRule {
  const CheckedRule({
    required this.evidence,
    required this.complete,
    required this.accepted,
  });
  final Evidence evidence;
  final bool complete, accepted;
}

final _nonWhitespace = RegExp(
  r'[^\u0009-\u000d\u0020\u0085\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000]',
);
bool _subset(Applicability child, Applicability parent) => switch ((
  child,
  parent,
)) {
  (UniverseApplicability() || WorldsApplicability(), UniverseApplicability()) =>
    true,
  (
    WorldsApplicability(worldIds: final a),
    WorldsApplicability(worldIds: final b),
  ) =>
    a.isNotEmpty && a.every(b.contains),
  _ => false,
};
bool validException(ExceptionRecord e, List<RecordVersion> records) {
  RecordVersion? target;
  for (final r in records) {
    if (r.identity.recordId == e.rule.record &&
        r.recordVersionId == e.ruleVersion) {
      target = r;
      break;
    }
  }
  if (target == null) return false;
  Applicability scope;
  Validity validity;
  RecordRef? cell, realm;
  switch (target.payload) {
    case RuleRecord(
      commitPolicy: CommitPolicy.blockUnlessException,
      :final applicability,
      validity: final v,
    ):
      scope = applicability;
      validity = v;
    case BoundaryRecord(scope: final s, validity: final v):
      scope = s.applicability;
      validity = v;
      cell = s.context;
      realm = s.realm;
    default:
      return false;
  }
  final childTime = validityExpression(e.validity),
      parentTime = validityExpression(validity);
  final contained =
      e.validity is UnspecifiedValidity && validity is UnspecifiedValidity ||
      validity is UnspecifiedValidity && childTime != null ||
      childTime != null &&
          parentTime != null &&
          temporalRelation(childTime, TemporalRelation.during, parentTime) ==
              true;
  return _subset(e.scope.applicability, scope) &&
      contained &&
      e.scope.realm == realm &&
      (cell == null || cell == e.scope.context) &&
      _nonWhitespace.hasMatch(e.rationale) &&
      records.any((r) {
        final d = r.payload;
        return r.identity.recordId == e.authorizingDecision.record &&
            d is IssueDecisionRecord &&
            d.mode == IssueDecisionMode.accept &&
            d.scope == e.rule.record.value &&
            _nonWhitespace.hasMatch(d.rationale);
      });
}

bool exceptionAt(
  ExceptionRecord e,
  RecordVersion target,
  Frame frame,
  List<RecordId> worlds,
  List<RecordVersion> records,
) =>
    e.rule.record == target.identity.recordId &&
    e.scope.context == frame.context &&
    validException(e, records) &&
    switch (e.scope.applicability) {
      UniverseApplicability() => true,
      WorldsApplicability(:final worldIds) =>
        worlds.isNotEmpty &&
            worlds.every(
              (r) => worldIds.any(
                (w) => r.value.substring(4) == w.value.substring(4),
              ),
            ),
      _ => false,
    } &&
    (frame.time is TimelessFrameTime
        ? e.validity is UnspecifiedValidity
        : e.validity is UnspecifiedValidity ||
              eventApplies(e.validity, frame.time, records) == true);

final _min = -(BigInt.one << 127), _max = (BigInt.one << 127) - BigInt.one;
BigInt? _number(String value) {
  if (!RegExp(r'^[+-]?[0-9]+$').hasMatch(value)) return null;
  final n = BigInt.tryParse(value);
  return n == null || n < _min || n > _max ? null : n;
}

BigInt? _exactBound(TemporalBound b, bool start) => switch (b) {
  ExactBound(:final value) => switch (_number(value)) {
    final n? when n > _min && n < _max => n,
    _ => null,
  },
  UnboundedBound() => start ? _min + BigInt.one : _max,
  _ => null,
};
Frame _frame(Frame base, {FrameTime? time, RecordRef? context}) => Frame(
  universe: base.universe,
  continuity: base.continuity,
  revision: base.revision,
  context: context ?? base.context,
  time: time ?? base.time,
  perspective: base.perspective,
  readerScene: base.readerScene,
  personalSequence: base.personalSequence,
);
List<Frame>? _frames(
  Validity validity,
  List<RecordVersion> records,
  Frame base,
) {
  if (validity is UnspecifiedValidity) return [base];
  CalendarId calendar;
  BigInt start, end;
  switch (validity) {
    case InstantValidity(at: ExactTime(calendar: final c, :final value)):
      final at = _number(value);
      if (at == null || at == _max) return null;
      calendar = c;
      start = at;
      end = at + BigInt.one;
    case CalendarIntervalValidity(
      calendar: final c,
      start: final a,
      end: final b,
    ):
      final lo = _exactBound(a, true), hi = _exactBound(b, false);
      if (lo == null || hi == null) return null;
      calendar = c;
      start = lo;
      end = hi;
    default:
      return null;
  }
  if (start >= end || start == _min) return null;
  final points = <BigInt>{start};
  for (final r in records) {
    final v = switch (r.payload) {
      AssertionRecord(:final validity) ||
      EpistemicAttitudeRecord(:final validity) ||
      CompletenessRecord(:final validity) ||
      ExceptionRecord(:final validity) => validity,
      _ => null,
    };
    if (v == null) continue;
    List<BigInt>? bounds;
    switch (v) {
      case CalendarIntervalValidity(
            calendar: final c,
            start: final a,
            end: final b,
          )
          when c == calendar:
        final lo = _exactBound(a, true), hi = _exactBound(b, false);
        if (lo == null || hi == null) return null;
        bounds = [lo, hi];
      case InstantValidity(at: ExactTime(calendar: final c, :final value))
          when c == calendar:
        final n = _number(value);
        if (n == null || n == _max) return null;
        bounds = [n, n + BigInt.one];
      default:
        break;
    }
    for (final n in bounds ?? const <BigInt>[]) {
      if (start <= n && n < end) points.add(n);
    }
    if (points.length > 1000) return null;
  }
  final sorted = points.toList()..sort();
  return sorted
      .map((n) => _frame(base, time: AtFrameTime(ExactTime(calendar, '$n'))))
      .toList();
}

typedef _OpposingOperand = (RecordRef?, String, RecordRef?);
void _opposingOperands(Expr e, List<_OpposingOperand> out) {
  RecordRef? reference(Operand o) => switch (o) {
    RecordOperand(:final reference) => reference,
    ValueOperand(value: ReferenceValue(:final kind, :final record))
        when kind == ValueReferenceKind.record ||
            kind == ValueReferenceKind.entity =>
      record,
    _ => null,
  };
  switch (e) {
    case NoOpposingEvidenceExpr(
      :final subject,
      :final predicate,
      :final context,
    ):
      out.add((reference(subject), predicate, reference(context)));
    case NotExpr(:final expr):
      _opposingOperands(expr, out);
    case AllExpr(:final exprs) || AnyExpr(:final exprs):
      for (final child in exprs) {
        _opposingOperands(child, out);
      }
    case QuantifyExpr(:final body):
      _opposingOperands(body, out);
    default:
      break;
  }
}

/// Checks every exact evidence boundary and relevant world, without sampling.
/// Callers supply an already-selected candidate; this does not read a live head.
CheckedRule evaluateCandidateRule({
  EvaluationIndex? index,
  required RecordVersion record,
  required List<RecordVersion> records,
  required Frame base,
  required List<RecordId> footprint,
}) {
  CheckedRule unavailable() => CheckedRule(
    evidence: Evidence.notEstablished(),
    complete: false,
    accepted: false,
  );
  final rule = record.payload;
  if (rule is! RuleRecord) return unavailable();
  CompiledRule compiled;
  try {
    compiled = compileRule(record.identity.recordId, rule);
  } on RuleCompileError {
    return unavailable();
  }
  final operands = <_OpposingOperand>[];
  _opposingOperands(rule.expression, operands);
  RecordRef? normalize(RecordRef r) {
    try {
      return r.resolveNamespace(base.universe);
    } on FormatException {
      return null;
    }
  }

  final partitionRecords = records.where((r) {
    final a = r.payload;
    if (a is AssertionRecord && operands.isNotEmpty) {
      return records.any((p) {
        final prop = p.payload;
        return p.identity.recordId == a.proposition.record &&
            prop is PropositionRecord &&
            operands.any(
              (o) =>
                  (o.$1 == null ||
                      normalize(o.$1!) == normalize(prop.subject)) &&
                  (o.$3 == null ||
                      normalize(o.$3!) == normalize(prop.context)) &&
                  records.any(
                    (d) =>
                        d.identity.recordId == prop.predicate.record &&
                        switch (d.payload) {
                          PropertyRecord(:final namespace, :final key) ||
                          RelationRecord(
                            :final namespace,
                            :final key,
                          ) => '$namespace:$key' == o.$2,
                          _ => false,
                        },
                  ),
            );
      });
    }
    if (a is ExceptionRecord && operands.isNotEmpty) {
      return a.rule.record == record.identity.recordId;
    }
    return operands.isEmpty;
  }).toList();
  Validity partitionValidity = rule.validity;
  if (rule.validity is UnspecifiedValidity &&
      rule.expression.usesOpposingEvidence) {
    final calendars = partitionRecords
        .map(
          (r) => switch (r.payload) {
            AssertionRecord(:final validity) => validityExpression(validity),
            _ => null,
          },
        )
        .map(
          (e) => switch (e) {
            ExactTime(:final calendar) ||
            IntervalTime(:final calendar) => calendar,
            _ => null,
          },
        )
        .whereType<CalendarId>()
        .toSet();
    if (calendars.length > 1) return unavailable();
    if (calendars.isNotEmpty) {
      partitionValidity = CalendarIntervalValidity(
        calendars.single,
        const UnboundedBound(),
        const UnboundedBound(),
      );
    }
  }
  final frames = _frames(partitionValidity, partitionRecords, base);
  if (frames == null) return unavailable();
  final worlds = switch (rule.applicability) {
    WorldsApplicability(:final worldIds) =>
      worldIds
          .map((w) => RecordId.parse('rec_${w.value.substring(4)}'))
          .where(footprint.contains)
          .map((r) => [r])
          .toList(),
    UniverseApplicability() =>
      footprint.isEmpty
          ? <List<RecordId>>[[]]
          : footprint.map((w) => [w]).toList(),
    _ => null,
  };
  if (worlds == null ||
      worlds.isEmpty ||
      frames.length * worlds.length > 1000) {
    return unavailable();
  }
  final subjectIndex = RecordIndex(records);
  final exceptions =
      index?.exceptions(record.identity.recordId) ??
      records
          .where(
            (r) =>
                r.payload is ExceptionRecord &&
                (r.payload as ExceptionRecord).rule.record ==
                    record.identity.recordId,
          )
          .toList();
  var evidence = Evidence.supported([]), complete = true, accepted = true;
  for (final frame in frames) {
    for (final world in worlds) {
      final applies = ruleAppliesIndexed(rule, records, subjectIndex, world);
      if (applies == false) continue;
      if (applies == null) return unavailable();
      final r = evaluateRule(
        compiled,
        EvaluationContext(
          frame: frame,
          baseSnapshot: records,
          index: index,
          worldScope: world,
        ),
      );
      final checked =
          r.coverage == EvaluationCoverage.complete &&
          rule.capabilities.every(
            (c) => const {
              'basic.v1',
              'boolean.v1',
              'scalar.v1',
              'finite.v1',
              'opposing_evidence.v1',
              'resources.accounting.v1',
            }.contains(c),
          );
      final contexts = operands.isEmpty
          ? <RecordRef?>[frame.context]
          : operands.map((o) => o.$3).toList();
      final waived =
          rule.commitPolicy == CommitPolicy.blockUnlessException &&
          contexts.every((c) => c != null) &&
          contexts.every(
            (c) => exceptions.any(
              (r) =>
                  r.payload is ExceptionRecord &&
                  exceptionAt(
                    r.payload as ExceptionRecord,
                    record,
                    _frame(frame, context: c!),
                    world,
                    records,
                  ),
            ),
          );
      accepted =
          accepted &&
          checked &&
          (r.outcome == EvidenceOutcome.supported || waived);
      complete = complete && checked;
      evidence = evidence.all(r.evidence);
    }
  }
  return CheckedRule(
    evidence: evidence,
    complete: complete,
    accepted: accepted,
  );
}
