import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart' as p;
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/validation_findings.dart';

import 'operation_compilation_test.dart' as f;
import 'action_checks_test.dart' as a;
import '../../ub_rules/test/opposing_test.dart' as opposing;

List<RecordVersion> fixture(List<Expr> expressions) {
  final rows = a.fixture();
  a.edit(rows, 6, {
    'preconditions': CanonicalArray(expressions.map((e) => e.toWire())),
  });
  return rows;
}

List<p.Finding> assess(List<RecordVersion> rows, {Frame? frame}) =>
    assessEventPreconditions(candidate: rows, frame: frame ?? a.frame);
Expr claim() => ClaimExpr(
  subject: RecordOperand(f.ref(1)),
  predicate: 'test:charged',
  value: const ValueOperand(BooleanValue(true)),
  polarity: Polarity.support,
);
p.Finding finding({
  List<RecordRef> records = const [],
  String fingerprint = '',
}) => p.Finding(
  message: 'repair',
  records: records,
  fingerprint: FindingFingerprint(fingerprint),
  ruleId: opposing.id(30),
  outcome: p.EvidenceOutcome.refuted,
  evidence: [opposing.version(30), opposing.version(31), opposing.version(10)],
  coverage: p.Coverage.complete,
);
List<p.Finding> finalize(
  List<p.Finding> findings, {
  List<RecordVersion>? rows,
  Frame? frame,
  String digest = 'candidate-digest',
  String evaluator = 'evaluator-v1',
}) => finalizeCandidateFindings(
  findings: findings,
  candidate: rows ?? opposing.base(),
  frame: frame ?? opposing.frame(),
  digest: digest,
  evaluator: evaluator,
);

void main() {
  test('opposing prerequisites retain both evidence sides and declared world scope', () {
    final rows = fixture([claim()]);
    final assertion = rows
        .firstWhere((r) => r.identity.recordId == f.id(4))
        .payload;
    rows.add(
      f.row(
        90,
        f.patch(assertion, {'polarity': CanonicalString('refutation')}),
      ),
    );
    final result = assess(rows).single;
    expect(result.outcome, p.EvidenceOutcome.conflicting);
    expect(result.coverage, p.Coverage.complete);
    expect(result.evidence, [f.ver(4), f.ver(90), f.ver(6), f.ver(5)]);
    rows.removeLast();
    final world = WorldId.parse('wld_${f.suffix(21)}');
    a.edit(rows, 4, {
      'scope': Scope(
        context: f.ref(10),
        applicability: WorldsApplicability([world]),
      ).toWire(),
    });
    a.edit(rows, 6, {
      'worlds': CanonicalArray([CanonicalString(world.value)]),
    });
    expect(assess(rows), isEmpty);
    a.edit(rows, 6, {
      'worlds': CanonicalArray([CanonicalString('wld_${f.suffix(22)}')]),
    });
    expect(assess(rows).single.outcome, p.EvidenceOutcome.notEstablished);
  });
  test('occurred preconditions need complete support and retain numbered repairs and action evidence', () {
    final result = assess(
      fixture([const LiteralExpr(true), const LiteralExpr(false)]),
    ).single;
    expect(result.ruleId, f.id(6));
    expect(result.message, contains('prerequisite 2'));
    expect(result.outcome, p.EvidenceOutcome.refuted);
    expect(result.coverage, p.Coverage.complete);
    expect(result.evidence, [f.ver(6), f.ver(5)]);
    expect(result.fingerprint.value, isEmpty);
    expect(result.records, isEmpty);
  });
  test('planned events skip prerequisites and unchanged occurred events are reassessed', () {
    final rows = fixture([const LiteralExpr(false)]);
    a.edit(rows, 6, {
      'occurrence': const SimpleOccurrence(OccurrenceKind.planned).toWire(),
    });
    expect(assess(rows), isEmpty);
    a.edit(rows, 6, {
      'occurrence': const SimpleOccurrence(OccurrenceKind.occurred).toWire(),
    });
    expect(assess(rows), hasLength(1));
  });
  test('unbound prerequisites remain unsupported rather than refuted', () {
    final result = assess(
      fixture([
        ClaimExpr(
          subject: const VariableOperand('missing'),
          predicate: 'test:charged',
          polarity: Polarity.support,
        ),
      ]),
    ).single;
    expect(result.outcome, p.EvidenceOutcome.notEstablished);
    expect(result.coverage, p.Coverage.unsupported);
  });
  test('own event time cannot establish its pre-event attribute', () {
    final rows = fixture([claim()]);
    expect(assess(rows), isEmpty);
    a.edit(rows, 4, {
      'validity': CalendarIntervalValidity(
        a.cal,
        const ExactBound('11'),
        const UnboundedBound(),
      ).toWire(),
    });
    expect(assess(rows).single.outcome, p.EvidenceOutcome.notEstablished);
  });
  test('first effect context precedes action context and proposal context', () {
    final rows = fixture([claim()]);
    final otherFrame = Frame(
      universe: a.u,
      continuity: a.frame.continuity,
      revision: a.frame.revision,
      context: f.ref(99),
      time: a.frame.time,
      perspective: a.frame.perspective,
    );
    expect(assess(rows, frame: otherFrame), isEmpty);
    a.edit(rows, 6, {
      'effects': CanonicalArray([
        EntityEffect(
          slot: 'x',
          proposition: f.ref(3),
          polarity: Polarity.support,
          scope: Scope(
            context: f.ref(99),
            applicability: const UniverseApplicability(),
          ),
          validity: const UnspecifiedValidity(),
          order: BigInt.zero,
        ).toWire(),
      ]),
    });
    expect(
      assess(rows, frame: a.frame).single.outcome,
      p.EvidenceOutcome.notEstablished,
    );
  });
  test('cancelled validation propagates at candidate record boundaries', () {
    var calls = 0;
    expect(
      () => assessEventPreconditions(
        candidate: fixture([]),
        frame: a.frame,
        checkCancelled: () {
          if (++calls == 2) throw StateError('cancelled');
        },
      ),
      throwsStateError,
    );
    expect(calls, 2);
  });
  test('finding finalization binds exact tuple and fills references in candidate order', () {
    final result = finalize([finding()]).single;
    expect(result.records.map((r) => r.record), [
      opposing.id(10),
      opposing.id(30),
      opposing.id(31),
    ]);
    expect(result.evidence, finding().evidence);
    expect(
      result.fingerprint.value,
      '168f36895f5ed3e078fe8e6148353ed9d242382868d35d705e16823af734347f',
    );
    expect(
      p.Finding.fromWire(result.toWire()).toWire().toText(),
      result.toWire().toText(),
    );
  });
  test('existing fingerprints and authored references are retained', () {
    final original = finding(
      records: [opposing.ref(99)],
      fingerprint: 'resource-fingerprint',
    );
    final result = finalize([original]).single;
    expect(result.fingerprint, original.fingerprint);
    expect(result.records, original.records);
    expect(original.records, [opposing.ref(99)]);
  });
  test('candidate archive does not manufacture references and metadata changes invalidate new fingerprint', () {
    final original = finalize([finding()]).single;
    final missing = finalize([finding()], rows: []).single;
    expect(missing.records, isEmpty);
    expect(missing.fingerprint, original.fingerprint);
    expect(
      finalize([finding()], digest: 'different').single.fingerprint,
      isNot(original.fingerprint),
    );
    expect(
      finalize([finding()], evaluator: 'different').single.fingerprint,
      isNot(original.fingerprint),
    );
    expect(
      finalize(
        [finding()],
        frame: opposing.frame(time: const TimelessFrameTime()),
      ).single.fingerprint,
      isNot(original.fingerprint),
    );
  });
}
