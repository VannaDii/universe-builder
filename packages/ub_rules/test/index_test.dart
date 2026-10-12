import 'package:test/test.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_rules/ub_rules.dart';

String suffix(int n) => n.toRadixString(16).padLeft(24, '0');
RecordId id(int n) => RecordId.parse('rec_${suffix(n)}');
UniverseId unv(int n) => UniverseId.parse('unv_${suffix(n)}');
RecordRef ref(int n, {int? universe = 1}) =>
    RecordRef(universe: universe == null ? null : unv(universe), record: id(n));
RecordVersion record(int n, RecordPayload payload) => RecordVersion.build(
  recordVersionId: RecordVersionId.parse('ver_${suffix(n)}'),
  identity: RecordIdentity(
    universeId: unv(1),
    recordId: id(n),
    recordKind: payload.recordKind,
  ),
  payload: payload,
);
final scope = Scope(
  applicability: const UniverseApplicability(),
  context: ref(50),
);
PropertyRecord property() => PropertyRecord(
  namespace: 'author',
  key: 'age',
  labels: {},
  value: const SimpleValueShape(SimpleShapeKind.integer),
  multiplicity: Multiplicity.single,
  persistence: PersistenceSemantics.unspecified,
  exclusive: false,
  symmetric: false,
  transitive: false,
);
PropositionRecord proposition({
  int definition = 1,
  RecordRef? subject,
  RecordRef? context,
}) => PropositionRecord(
  predicate: ref(definition),
  subject: subject ?? ref(20),
  context: context ?? ref(50),
  value: const IntegerValue('10'),
  quantification: Quantification.particular,
);
AssertionRecord assertion(
  int proposition, {
  Polarity polarity = Polarity.support,
}) => AssertionRecord(
  attributeMode: AttributeMode.instance,
  proposition: ref(proposition),
  polarity: polarity,
  scope: scope,
  validity: const UnspecifiedValidity(),
  persistence: PersistenceSemantics.unspecified,
  precision: Precision.exact,
  basis: const AuthorDecisionBasis('claim'),
);
CompletenessRecord completeness({
  String predicate = 'author:age',
  RecordRef? subject,
}) => CompletenessRecord(
  subject: subject ?? ref(20),
  predicate: predicate,
  members: [],
  completeness: const ObjectiveCompleteness(),
  validity: const UnknownValidity(),
  scope: scope,
);

void main() {
  test('claim lookup retains definition order, every assertion and trailing completeness', () {
    final records = [
      record(10, assertion(3, polarity: Polarity.refutation)),
      record(
        2,
        RelationRecord(namespace: 'author', key: 'age', labels: {}, roles: []),
      ),
      record(4, proposition(definition: 2)),
      record(11, assertion(3)),
      record(1, property()),
      record(3, proposition()),
      record(12, assertion(4)),
      record(13, completeness()),
      record(14, completeness()),
    ];
    final index = EvaluationIndex(records);
    expect(
      index
          .claim(ref(20), 'author:age', ref(50))
          .map((r) => r.identity.recordId),
      [id(2), id(4), id(12), id(1), id(3), id(10), id(11), id(13), id(14)],
    );
    expect(index.claim(ref(20), 'author:unknown', ref(50)), isEmpty);
    expect(index.hasPowers, isFalse);
  });

  test(
    'subject and context retain exact reference namespaces without inference',
    () {
      final index = EvaluationIndex([
        record(1, property()),
        record(3, proposition()),
        record(4, proposition(subject: ref(20, universe: 2))),
        record(5, proposition(subject: ref(20, universe: null))),
        record(6, proposition(context: ref(50, universe: 2))),
        record(7, proposition(context: ref(51))),
        record(10, assertion(3)),
      ]);
      List<RecordId> claim(RecordRef subject, RecordRef context) => index
          .claim(subject, 'author:age', context)
          .map((r) => r.identity.recordId)
          .toList();
      expect(claim(ref(20), ref(50)), [id(1), id(3), id(10)]);
      expect(claim(ref(20, universe: 2), ref(50)), [id(1), id(4)]);
      expect(claim(ref(20, universe: null), ref(50)), [id(1), id(5)]);
      expect(claim(ref(20), ref(50, universe: 2)), [id(1), id(6)]);
      expect(claim(ref(20), ref(51)), [id(1), id(7)]);
    },
  );

  test('completeness lookup does not perform scope or context admission', () {
    final index = EvaluationIndex([
      record(1, property()),
      record(13, completeness()),
      record(14, completeness(subject: ref(20, universe: 2))),
      record(15, completeness(predicate: 'author:unknown')),
    ]);
    expect(
      index
          .claim(ref(20), 'author:age', ref(99))
          .map((r) => r.identity.recordId),
      [id(1), id(13)],
    );
    expect(
      index.claim(ref(20), 'author:unknown', ref(99)).single.identity.recordId,
      id(15),
    );
    expect(
      index.claim(ref(20), 'author:age', ref(99)).last.payload,
      isA<CompletenessRecord>().having(
        (c) => c.validity,
        'unresolved validity',
        const UnknownValidity(),
      ),
    );
  });

  test('exceptions stay grouped by exact rule identity and do not authorize a waiver', () {
    ExceptionRecord exception(int target) => ExceptionRecord(
      rule: ref(target),
      scope: scope,
      validity: const UnknownValidity(),
      authorizingDecision: ref(60),
      rationale: 'authored exception',
    );
    final index = EvaluationIndex([
      record(10, exception(1)),
      record(11, exception(2)),
      record(12, exception(1)),
    ]);
    expect(index.exceptions(id(1)).map((r) => r.identity.recordId), [
      id(10),
      id(12),
    ]);
    expect(index.exceptions(id(9)), isEmpty);
    expect(() => index.exceptions(id(1)).clear(), throwsUnsupportedError);
    expect(index.exceptions(id(1)).length, 2);
  });

  test(
    'powers flag and claim results belong to the captured candidate only',
    () {
      final records = [record(1, property())];
      final original = EvaluationIndex(records);
      records.add(
        record(
          2,
          ItemPowerRecord(
            item: ref(20),
            holderPredicate: ref(1),
            powerPredicate: ref(1),
            value: const IntegerValue('1'),
            scope: scope,
            validity: const UnspecifiedValidity(),
          ),
        ),
      );
      records.add(record(3, proposition()));
      final changed = EvaluationIndex(records);
      records.clear();
      expect(original.hasPowers, isFalse);
      expect(changed.hasPowers, isTrue);
      expect(original.claim(ref(20), 'author:age', ref(50)).length, 1);
      expect(changed.claim(ref(20), 'author:age', ref(50)).length, 2);
      expect(
        () => changed.claim(ref(20), 'author:age', ref(50)).clear(),
        throwsUnsupportedError,
      );
    },
  );
}
