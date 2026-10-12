import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/ub_service.dart';

import 'operation_compilation_test.dart' as f;
import 'rule_checks_test.dart' as facts;
import 'writing_binding_test.dart' as binding;

PropertyRecord property(
  String key,
  ValueShape shape, {
  Multiplicity multiplicity = Multiplicity.single,
}) => PropertyRecord(
  namespace: 'test',
  key: key,
  labels: {},
  value: shape,
  multiplicity: multiplicity,
  persistence: PersistenceSemantics.persistentUntilChanged,
  exclusive: false,
  symmetric: false,
  transitive: false,
);
List<RecordVersion> rows() => [
  f.row(1, binding.entity(labels: {'en': 'Wand'})),
  f.row(2, binding.entity(labels: {'en': 'Mara'})),
  f.row(3, property('holder', EntityRefShape([]))),
  f.row(4, property('able', const SimpleValueShape(SimpleShapeKind.boolean))),
  f.row(
    5,
    property('owners', EntityRefShape([]), multiplicity: Multiplicity.multiple),
  ),
];
final frame = facts.frame(time: AtFrameTime(ExactTime(facts.calendar, '10')));
WritingItemPower power({String holder = 'holder', String scope = 'universe'}) =>
    WritingItemPower(
      item: 'Wand',
      holderProperty: holder,
      abilityProperty: 'able',
      value: const FactBooleanValue(true),
      scope: scope,
      atTick: '10',
      lifetime: const FactUntilLifetime(endTick: '30'),
    );
WritingExhaustiveSet boundary({
  String property = 'owners',
  List<String> members = const ['Mara'],
  String scope = 'universe',
}) => WritingExhaustiveSet(
  subject: 'Wand',
  property: property,
  members: members,
  scope: scope,
  atTick: '10',
  lifetime: const FactUntilChangedLifetime(),
);

void main() {
  test('power and exhaustive declarations compile without inferring holder facts or knowledge', () {
    final base = rows();
    final result = compileWritingPowersAndSets(
      universe: f.u,
      frame: frame,
      rows: base,
      powers: [power()],
      corrections: [],
      exhaustiveSets: [boundary()],
    );
    expect(result.clarifications, isEmpty);
    expect(result.operations, hasLength(2));
    final candidate = compileWritingCandidate(
      universe: f.u,
      revision: f.revision,
      base: base,
      operations: result.operations,
    );
    expect(candidate, hasLength(base.length + 2));
    final grant =
        candidate.singleWhere((r) => r.payload is ItemPowerRecord).payload
            as ItemPowerRecord;
    expect(grant.item, f.ref(1));
    expect(grant.holderPredicate, f.ref(3));
    expect(grant.powerPredicate, f.ref(4));
    expect(grant.value, const BooleanValue(true));
    expect(
      grant.validity,
      CalendarIntervalValidity(
        facts.calendar,
        const ExactBound('10'),
        const ExactBound('30'),
      ),
    );
    final set =
        candidate.singleWhere((r) => r.payload is CompletenessRecord).payload
            as CompletenessRecord;
    expect(set.predicate, 'test:owners');
    expect(set.members, [f.ref(2)]);
    expect(set.completeness, isA<ObjectiveCompleteness>());
    expect(set.scope.context, frame.context);
    expect(
      candidate.where(
        (r) =>
            r.payload is AssertionRecord ||
            r.payload is EpistemicAttitudeRecord,
      ),
      isEmpty,
    );
    final denied = compileWritingPowersAndSets(
      universe: f.u,
      frame: frame,
      rows: base,
      powers: [
        power(holder: 'owners'),
        power(holder: 'able'),
        power(scope: 'unspecified'),
      ],
      corrections: [],
      exhaustiveSets: [
        boundary(property: 'able'),
        boundary(scope: 'unspecified'),
        boundary(members: ['Hidden']),
      ],
    );
    expect(denied.operations, isEmpty);
    expect(denied.clarifications, hasLength(6));
  });

  test('grant corrections pin versions preserve omitted fields and retain rationales', () {
    final base = rows();
    final created = compileWritingPowersAndSets(
      universe: f.u,
      frame: frame,
      rows: base,
      powers: [power()],
      corrections: [],
      exhaustiveSets: [],
    );
    final candidate = compileWritingCandidate(
      universe: f.u,
      revision: f.revision,
      base: base,
      operations: created.operations,
    );
    final original = candidate.singleWhere((r) => r.payload is ItemPowerRecord);
    final old = original.payload as ItemPowerRecord;
    final result = compileWritingPowersAndSets(
      universe: f.u,
      frame: frame,
      rows: candidate,
      powers: [],
      exhaustiveSets: [],
      corrections: [
        WritingItemPowerCorrection(
          grantHandle: original.recordVersionId.value,
          reason: 'Limit the grant',
          value: const FactBooleanValue(false),
          endTick: '20',
        ),
      ],
    );
    expect(result.clarifications, isEmpty);
    final op = result.operations.single as ReviseItemPowerOperation;
    expect(op.expectedVersion, original.recordVersionId);
    expect(op.rationale, 'Limit the grant');
    expect(op.replacement.item, old.item);
    expect(op.replacement.scope, old.scope);
    expect(op.replacement.holderPredicate, old.holderPredicate);
    expect(op.replacement.value, const BooleanValue(false));
    expect(
      op.replacement.validity,
      CalendarIntervalValidity(
        facts.calendar,
        const ExactBound('10'),
        const ExactBound('20'),
      ),
    );
    final revised = compileWritingCandidate(
      universe: f.u,
      revision: f.revision,
      base: candidate,
      operations: result.operations,
    );
    final current = revised.singleWhere(
      (r) => r.identity.recordId == original.identity.recordId,
    );
    expect(current.recordVersionId, isNot(original.recordVersionId));
    expect(
      () => compileWritingCandidate(
        universe: f.u,
        revision: f.revision,
        base: revised,
        operations: result.operations,
      ),
      throwsA(isA<InvalidArgumentError>()),
    );
    final wrongContext = facts.frame(time: frame.time);
    final foreign = f.row(
      70,
      ItemPowerRecord(
        item: old.item,
        holderPredicate: old.holderPredicate,
        powerPredicate: old.powerPredicate,
        value: old.value,
        scope: Scope(
          context: f.ref(98),
          applicability: old.scope.applicability,
        ),
        validity: old.validity,
      ),
    );
    final hidden = compileWritingPowersAndSets(
      universe: f.u,
      frame: wrongContext,
      rows: [foreign],
      powers: [],
      exhaustiveSets: [],
      corrections: [
        WritingItemPowerCorrection(
          grantHandle: foreign.recordVersionId.value,
          reason: 'Wrong context',
          value: const FactBooleanValue(false),
        ),
      ],
    );
    expect(hidden.operations, isEmpty);
    expect(
      hidden.clarifications.single,
      contains('current pinned author-visible grant handle'),
    );
  });

  test('grant endings enforce exact bounds and once-only edits per delta', () {
    final original = f.row(
      20,
      ItemPowerRecord(
        item: f.ref(1),
        holderPredicate: f.ref(3),
        powerPredicate: f.ref(4),
        value: const BooleanValue(true),
        scope: Scope(
          context: frame.context,
          applicability: const UniverseApplicability(),
        ),
        validity: CalendarIntervalValidity(
          facts.calendar,
          const ExactBound('9007199254740993'),
          const ExactBound('9007199254741000'),
        ),
      ),
    );
    WritingItemPowerCorrection patch(String end) => WritingItemPowerCorrection(
      grantHandle: original.recordVersionId.value,
      reason: 'End grant',
      endTick: end,
    );
    final valid = compileWritingPowersAndSets(
      universe: f.u,
      frame: frame,
      rows: [...rows(), original],
      powers: [],
      exhaustiveSets: [],
      corrections: [patch('9007199254740994'), patch('9007199254740995')],
    );
    expect(valid.operations, hasLength(1));
    expect(valid.clarifications, ['Correct each grant once in a delta']);
    expect(
      ((valid.operations.single as ReviseItemPowerOperation)
                  .replacement
                  .validity
              as CalendarIntervalValidity)
          .end,
      const ExactBound('9007199254740994'),
    );
    for (final end in [
      '9007199254740993',
      '9007199254741001',
      '${BigInt.one << 127}',
      'tomorrow',
    ]) {
      final denied = compileWritingPowersAndSets(
        universe: f.u,
        frame: frame,
        rows: [original],
        powers: [],
        exhaustiveSets: [],
        corrections: [patch(end)],
      );
      expect(denied.operations, isEmpty);
      expect(denied.clarifications, hasLength(1));
    }
    final mixed = compileWritingPowersAndSets(
      universe: f.u,
      frame: frame,
      rows: [original],
      powers: [],
      exhaustiveSets: [],
      corrections: [
        WritingItemPowerCorrection(
          grantHandle: original.recordVersionId.value,
          reason: 'Mixed',
          endTick: '9007199254740994',
          atTick: '1',
        ),
      ],
    );
    expect(mixed.clarifications.single, contains('not both'));
  });

  test('validity corrections retain original calendars and support exact instants or unresolved starts', () {
    ItemPowerRecord grant(Validity validity) => ItemPowerRecord(
      item: f.ref(1),
      holderPredicate: f.ref(3),
      powerPredicate: f.ref(4),
      value: const BooleanValue(true),
      scope: Scope(
        context: frame.context,
        applicability: const UniverseApplicability(),
      ),
      validity: validity,
    );
    final other = CalendarId.parse('cal_${f.suffix(80)}');
    final original = f.row(20, grant(InstantValidity(ExactTime(other, '10'))));
    final result = compileWritingPowersAndSets(
      universe: f.u,
      frame: frame,
      rows: [original],
      powers: [],
      exhaustiveSets: [],
      corrections: [
        WritingItemPowerCorrection(
          grantHandle: original.recordVersionId.value,
          reason: 'Expand period',
          lifetime: const FactUntilLifetime(endTick: '25'),
        ),
      ],
    );
    expect(result.clarifications, isEmpty);
    expect(
      (result.operations.single as ReviseItemPowerOperation)
          .replacement
          .validity,
      CalendarIntervalValidity(
        other,
        const ExactBound('10'),
        const ExactBound('25'),
      ),
    );
    final unresolved = f.row(
      21,
      grant(
        CalendarIntervalValidity(
          other,
          const UnboundedBound(),
          const UnboundedBound(),
        ),
      ),
    );
    final denied = compileWritingPowersAndSets(
      universe: f.u,
      frame: frame,
      rows: [unresolved],
      powers: [],
      exhaustiveSets: [],
      corrections: [
        WritingItemPowerCorrection(
          grantHandle: unresolved.recordVersionId.value,
          reason: 'No start',
          lifetime: const FactUntilChangedLifetime(),
        ),
      ],
    );
    expect(denied.clarifications.single, contains('explicit start'));
    final started = compileWritingPowersAndSets(
      universe: f.u,
      frame: frame,
      rows: [unresolved],
      powers: [],
      exhaustiveSets: [],
      corrections: [
        WritingItemPowerCorrection(
          grantHandle: unresolved.recordVersionId.value,
          reason: 'Start specified',
          atTick: '12',
          lifetime: const FactUntilChangedLifetime(),
        ),
      ],
    );
    expect(started.clarifications, isEmpty);
    expect(
      (started.operations.single as ReviseItemPowerOperation)
          .replacement
          .validity,
      CalendarIntervalValidity(
        other,
        const ExactBound('12'),
        const UnboundedBound(),
      ),
    );
    final endingInstant = compileWritingPowersAndSets(
      universe: f.u,
      frame: frame,
      rows: [original],
      powers: [],
      exhaustiveSets: [],
      corrections: [
        WritingItemPowerCorrection(
          grantHandle: original.recordVersionId.value,
          reason: 'End instant',
          endTick: '20',
        ),
      ],
    );
    expect(
      endingInstant.clarifications.single,
      contains('existing authored calendar interval'),
    );
  });
}
