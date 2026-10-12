import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart' as p;
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/opposing_diagnostics.dart';

import '../../ub_rules/test/opposing_test.dart' as f;

List<RecordVersion> fixture() => f
    .base()
    .where(
      (r) => [1, 3, 10, 20, 30, 31].map(f.id).contains(r.identity.recordId),
    )
    .toList();
List<p.OpposingEvidence> diagnostics(
  List<RecordVersion> rows, {
  Frame? frame,
  String digest = 'candidate-digest',
  String evaluator = 'evaluator-v1',
  List<String>? unsupported,
}) => buildOpposingDiagnostics(
  records: rows,
  frame: frame ?? f.frame(),
  digest: digest,
  evaluator: evaluator,
  unsupported: unsupported ?? [],
);

void main() {
  test('all policy and exception versions are sorted and bound without waiving opposition', () {
    final rows = fixture();
    final original = diagnostics(rows).single;
    final scope = Scope(
      context: f.ref(3),
      applicability: const UniverseApplicability(),
    );
    for (final n in [90, 80]) {
      rows.add(
        f.record(
          n,
          RuleRecord(
            namespace: 'test',
            key: 'rule$n',
            labels: {},
            kind: RuleKind.physicalConstraint,
            commitPolicy: CommitPolicy.advisory,
            applicability: const UniverseApplicability(),
            targetPredicates: [],
            expression: const LiteralExpr(true),
            capabilities: [],
            executable: true,
            validity: const UnspecifiedValidity(),
          ),
        ),
      );
      rows.add(
        f.record(
          n + 1,
          ExceptionRecord(
            rule: f.ref(n),
            scope: scope,
            validity: const UnspecifiedValidity(),
            authorizingDecision: f.ref(1),
            rationale: 'Explicit exception',
          ),
        ),
      );
    }
    final result = diagnostics(rows).single;
    expect(result.policyVersions, [f.version(80), f.version(90)]);
    expect(result.exceptionVersions, [f.version(81), f.version(91)]);
    expect(result.fingerprint, isNot(original.fingerprint));
    expect(result.kind, p.OpposingKind.definite);
    expect(
      diagnostics(rows.reversed.toList()).single.fingerprint,
      result.fingerprint,
    );
    f.replace(
      rows,
      f.record(
        81,
        rows.firstWhere((r) => r.identity.recordId == f.id(81)).payload,
        v: 92,
      ),
    );
    expect(diagnostics(rows).single.fingerprint, isNot(result.fingerprint));
  });
  test(
    'missing provenance remains a partial chain even with definite opposition',
    () {
      final rows = fixture();
      f.replace(
        rows,
        f.assertion(30, basis: SourceAnchorBasis(f.ref(99), true)),
      );
      final result = diagnostics(rows).single;
      expect(result.kind, p.OpposingKind.definite);
      expect(result.coverage, p.Coverage.partial);
      expect(result.support.complete, isFalse);
      expect(result.unresolvedReasons, [p.OpposingReason.provenance]);
    },
  );
  test('exact diagnostics retain original chains and Rust fingerprint', () {
    final gaps = <String>[];
    final result = diagnostics(fixture(), unsupported: gaps).single;
    expect(gaps, isEmpty);
    expect(result.kind, p.OpposingKind.definite);
    expect(result.coverage, p.Coverage.complete);
    expect(result.support.assertion, f.version(30));
    expect(result.refutation.assertion, f.version(31));
    expect(result.support.proposition, f.version(20));
    expect(result.intersection, isA<p.ExactIntersection>());
    expect(
      result.fingerprint.value,
      'b5f1c19d724e99922199fdeb559aba812d343ee47e06e86bcd04b08d8e176e8f',
    );
    expect(
      p.OpposingEvidence.fromWire(result.toWire()).toWire().toText(),
      result.toWire().toText(),
    );
  });
  test('fingerprints bind candidate digest evaluator and frame without selecting UI time', () {
    final rows = fixture(), original = diagnostics(fixture()).single;
    for (final changed in [
      diagnostics(rows, digest: 'changed').single,
      diagnostics(rows, evaluator: 'changed').single,
      diagnostics(rows, frame: f.frame(time: const TimelessFrameTime())).single,
    ]) {
      expect(changed.fingerprint, isNot(original.fingerprint));
      expect(changed.support.assertion, original.support.assertion);
    }
    expect(
      diagnostics(rows.reversed.toList()).single.toWire().toText(),
      original.toWire().toText(),
    );
  });
  test(
    'uncertain time carries unresolved reasons instead of definite conflict',
    () {
      final rows = fixture();
      f.replace(rows, f.assertion(31, validity: const UnknownValidity()));
      final result = diagnostics(rows).single;
      expect(result.kind, p.OpposingKind.unresolved);
      expect(result.coverage, p.Coverage.partial);
      expect(result.unresolvedReasons, contains(p.OpposingReason.time));
      expect(result.intersection, isA<p.UnresolvedIntersection>());
      expect(
        result.fingerprint.value,
        '10d7c17f07d326708986dc6e876d2ef745a973a4cb860bbee8ec93eb628ede0e',
      );
    },
  );
  test(
    'bounded uncertainty preserves its Rust fingerprint and guaranteed cell',
    () {
      final rows = fixture();
      f.replace(
        rows,
        f.assertion(
          31,
          validity: CalendarIntervalValidity(
            f.calendar,
            const UncertainBound('10', '12'),
            const ExactBound('20'),
          ),
        ),
      );
      final result = diagnostics(rows).single;
      expect(result.intersection, isA<p.UncertainIntersection>());
      expect(
        (result.intersection as p.UncertainIntersection).guaranteed,
        isNotNull,
      );
      expect(
        result.fingerprint.value,
        '5e881c46f96a7ac859d3501f3f6cb464c949f2f7778375b44c42326d167071fc',
      );
    },
  );
  test('invalid active membership becomes an unsupported diagnostic lane', () {
    final gaps = <String>['existing'];
    final rows = fixture()..add(f.prop(20, value: const BooleanValue(false)));
    expect(diagnostics(rows, unsupported: gaps), isEmpty);
    expect(gaps, [
      'existing',
      'opposing_evidence.v1:ambiguous active membership',
    ]);
  });
}
