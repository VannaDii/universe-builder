import 'package:test/test.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_rules/ub_rules.dart';

RecordVersionId vid(int value) =>
    RecordVersionId.parse('ver_${value.toRadixString(16).padLeft(24, '0')}');

void main() {
  test(
    'all four evidence outcomes retain independent support and refutation',
    () {
      final examples = [
        Evidence.notEstablished(),
        Evidence.supported([vid(1)]),
        Evidence.refuted([vid(2)]),
        Evidence.conflicting([vid(1)], [vid(2)]),
      ];
      expect(examples.map((e) => e.outcome.toString()), [
        'not_established',
        'supported',
        'refuted',
        'conflicting',
      ]);
      expect(examples.first.isTrulyAbsent, isTrue);
      expect(examples.first.allSources, isEmpty);
      expect(examples.skip(1).every((e) => e.isDefinite), isTrue);
      expect(examples[3].negate().support.sources, [vid(2)]);
      expect(examples[3].negate().refutation.sources, [vid(1)]);
      for (final e in examples) {
        expect(e.negate().negate(), e);
        expect(e.negate().negate().hashCode, e.hashCode);
      }
    },
  );

  test('complete truth-order tables preserve conflict without explosion', () {
    final examples = [
      Evidence.notEstablished(),
      Evidence.supported([]),
      Evidence.refuted([]),
      Evidence.conflicting([], []),
    ];
    const all = [
      [0, 0, 2, 2],
      [0, 1, 2, 3],
      [2, 2, 2, 2],
      [2, 3, 2, 3],
    ];
    const any = [
      [0, 1, 0, 1],
      [1, 1, 1, 1],
      [0, 1, 2, 3],
      [1, 1, 3, 3],
    ];
    for (var a = 0; a < 4; a++) {
      for (var b = 0; b < 4; b++) {
        expect(
          examples[a].all(examples[b]).outcome,
          examples[all[a][b]].outcome,
          reason: 'conjunction $a, $b',
        );
        expect(
          examples[a].any(examples[b]).outcome,
          examples[any[a][b]].outcome,
          reason: 'disjunction $a, $b',
        );
      }
    }
  });

  test('conjunction retains both derivations and aggregate sources are sorted unique', () {
    final a = EvidenceBit.withSources([vid(3), vid(1), vid(3)]);
    final b = EvidenceBit.withSources([vid(2), vid(3)]);
    expect(a.and(b).sources, [vid(1), vid(2), vid(3)]);
    expect(a.or(b).sources, [vid(1), vid(2), vid(3)]);
    expect(a.and(EvidenceBit.absent()), EvidenceBit.absent());
    expect(a.or(EvidenceBit.absent()).sources, [vid(1), vid(3)]);
    final conflict = Evidence.conflicting(a.sources, b.sources);
    expect(conflict.allSources, [vid(1), vid(2), vid(3)]);
    // Authored derivations retain ordering and duplicates until composition.
    expect(conflict.support.sources, [vid(3), vid(1), vid(3)]);
  });

  test(
    'negation retains derivations and source-free presence stays indeterminate',
    () {
      final sourced = EvidenceBit.withSource(vid(1));
      final negated = sourced.negate();
      expect(negated.present, isFalse);
      expect(negated.sources, [vid(1)]);
      expect(negated.isAbsent, isFalse);
      expect(negated.negate(), sourced);
      expect(negated.or(EvidenceBit.withSource(vid(2))).sources, [
        vid(1),
        vid(2),
      ]);
      expect(negated.or(negated), EvidenceBit.absent());
      expect(negated.and(sourced), EvidenceBit.absent());
      final unknown = EvidenceBit.withSources([]);
      expect(unknown.isIndeterminate, isTrue);
      expect(unknown.isDefinite, isTrue);
      expect(unknown.isAbsent, isFalse);
      expect(
        Evidence(
          support: negated,
          refutation: EvidenceBit.absent(),
        ).isTrulyAbsent,
        isFalse,
      );
    },
  );

  test('evidence copies authored lists and does not mutate inputs during composition', () {
    final sources = [vid(2), vid(1)];
    final evidence = Evidence.supported(sources);
    sources.clear();
    evidence.all(Evidence.supported([vid(3)]));
    expect(evidence.support.sources, [vid(2), vid(1)]);
    expect(() => evidence.support.sources.clear(), throwsUnsupportedError);
    expect(() => evidence.allSources.clear(), throwsUnsupportedError);
  });
}
