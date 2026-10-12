import 'package:test/test.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_rules/ub_rules.dart';

String suffix(int n) => n.toRadixString(16).padLeft(24, '0');
RecordId id(int n) => RecordId.parse('rec_${suffix(n)}');
final universe = UniverseId.parse('unv_${suffix(1)}');
final calendar = CalendarId.parse('cal_${suffix(1)}');
RecordRef ref(int n) => RecordRef(universe: universe, record: id(n));
RecordVersion record(int n, RecordPayload payload) => RecordVersion.build(
  recordVersionId: RecordVersionId.parse('ver_${suffix(n)}'),
  identity: RecordIdentity(
    universeId: universe,
    recordId: id(n),
    recordKind: payload.recordKind,
  ),
  payload: payload,
);
final proposition = record(
  4,
  PropositionRecord(
    predicate: ref(2),
    subject: ref(1),
    quantification: Quantification.particular,
    context: ref(3),
    value: const BooleanValue(true),
  ),
);
final interval = CalendarIntervalValidity(
  calendar,
  const ExactBound('10'),
  const ExactBound('20'),
);
RecordVersion attitude(
  int n, {
  EpistemicAttitudeKind kind = EpistemicAttitudeKind.knows,
  Validity? validity,
  RecordRef? holder,
  RecordRef? target,
}) => record(
  n,
  EpistemicAttitudeRecord(
    holder: holder ?? ref(1),
    proposition: target ?? ref(4),
    attitude: kind,
    validity: validity ?? interval,
    basis: const AuthorDecisionBasis('attributed account'),
  ),
);
Frame frame({FrameTime? time, RecordRef? context}) => Frame(
  universe: universe,
  continuity: ContinuityId.parse('cont_${suffix(1)}'),
  revision: RevisionId.parse('rev_${suffix(1)}'),
  context: context ?? ref(3),
  time: time ?? AtFrameTime(ExactTime(calendar, '10')),
  perspective: const AuthorPerspective(),
);
(Evidence, bool) run(
  List<RecordVersion> snapshot, {
  Frame? selected,
  EpistemicAttitudeKind kind = EpistemicAttitudeKind.knows,
  RecordRef? holder,
  RecordRef? target,
}) => evaluateExpression(
  AttitudeExpr(holder ?? ref(1), target ?? ref(4), kind),
  EvaluationContext(baseSnapshot: snapshot, frame: selected ?? frame()),
);

void main() {
  test('all five attitudes remain distinct attributed evidence without objective assertions', () {
    for (final kind in EpistemicAttitudeKind.values) {
      final a = attitude(20, kind: kind);
      final (e, complete) = run([proposition, a], kind: kind);
      expect(e.outcome, EvidenceOutcome.supported);
      expect(e.support.sources, [a.recordVersionId]);
      expect(e.refutation.sources, isEmpty);
      expect(complete, isTrue);
      for (final other in EpistemicAttitudeKind.values.where(
        (v) => v != kind,
      )) {
        expect(
          run([proposition, a], kind: other).$1.outcome,
          EvidenceOutcome.notEstablished,
        );
      }
    }
  });

  test('missing attitudes do not refute and missing propositions or frames stay unsupported', () {
    final (absent, complete) = run([proposition]);
    expect(absent.outcome, EvidenceOutcome.notEstablished);
    expect(complete, isTrue);
    final a = attitude(20);
    expect(run([a]).$2, isFalse);
    expect(run([proposition, a], selected: frame(context: ref(9))).$2, isFalse);
    expect(
      evaluateExpression(
        AttitudeExpr(ref(1), ref(4), EpistemicAttitudeKind.knows),
        EvaluationContext(baseSnapshot: [proposition, a]),
      ).$2,
      isFalse,
    );
    expect(
      run([proposition, a], holder: RecordRef(record: id(1))).$1.outcome,
      EvidenceOutcome.notEstablished,
    );
    expect(
      run([proposition, a], target: RecordRef(record: id(4))).$1.outcome,
      EvidenceOutcome.notEstablished,
    );
  });

  test(
    'authored interval boundaries retain absence and coverage independently',
    () {
      final records = [proposition, attitude(20)];
      for (final (n, expected) in [
        (9, EvidenceOutcome.notEstablished),
        (10, EvidenceOutcome.supported),
        (19, EvidenceOutcome.supported),
        (20, EvidenceOutcome.notEstablished),
      ]) {
        final (e, complete) = run(
          records,
          selected: frame(time: AtFrameTime(ExactTime(calendar, '$n'))),
        );
        expect(e.outcome, expected);
        expect(complete, isTrue);
      }
      final (e, complete) = run([
        ...records,
        attitude(21, validity: const UnknownValidity()),
      ]);
      expect(e.outcome, EvidenceOutcome.supported);
      expect(e.support.sources, [records.last.recordVersionId]);
      expect(complete, isFalse);
    },
  );

  test('timeless queries accept only unspecified attitude validity', () {
    final timeless = frame(time: const TimelessFrameTime());
    expect(run([proposition, attitude(20)], selected: timeless).$2, isFalse);
    final unspecified = attitude(21, validity: const UnspecifiedValidity());
    expect(
      run([proposition, unspecified], selected: timeless).$1.outcome,
      EvidenceOutcome.supported,
    );
    expect(run([proposition, unspecified], selected: timeless).$2, isTrue);
    expect(run([proposition, unspecified]).$2, isFalse);
  });

  test('event-relative knowledge respects before and after instead of guessed current time', () {
    RecordVersion event(int n, int time) => record(
      n,
      EventRecord(
        occurrence: const SimpleOccurrence(OccurrenceKind.occurred),
        time: ExactTime(calendar, '$time'),
        participants: [],
        labels: {},
      ),
    );
    final records = [proposition, attitude(20), event(5, 10), event(6, 20)];
    for (final (n, side, expected) in [
      (5, EventTimeSide.before, EvidenceOutcome.notEstablished),
      (5, EventTimeSide.after, EvidenceOutcome.supported),
      (6, EventTimeSide.before, EvidenceOutcome.supported),
      (6, EventTimeSide.after, EvidenceOutcome.notEstablished),
    ]) {
      final (e, complete) = run(
        records,
        selected: frame(time: AtEventFrameTime(ref(n), side)),
      );
      expect(e.outcome, expected);
      expect(complete, isTrue);
    }
  });

  test('attitude snapshot traversal consumes the shared exact work budget', () {
    final filler = record(99, WorldRecord(selector: 'unused'));
    final allowed = [
      proposition,
      attitude(20),
      ...List<RecordVersion>.filled(9997, filler),
    ];
    expect(run(allowed).$2, isTrue);
    expect(run([...allowed, filler]).$2, isFalse);
  });

  test('attitude evidence uses the selected base snapshot without applying candidate deltas', () {
    final a = attitude(20);
    final context = EvaluationContext(
      frame: frame(),
      baseSnapshot: [proposition, a],
      candidateChanges: [(id(20), null)],
    );
    final (e, complete) = evaluateExpression(
      AttitudeExpr(ref(1), ref(4), EpistemicAttitudeKind.knows),
      context,
    );
    expect(e.support.sources, [a.recordVersionId]);
    expect(complete, isTrue);
  });
}
