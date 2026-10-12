import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart'
    show InvalidArgumentError, EvaluationLimitReachedError;
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/action_checks.dart';

import 'operation_compilation_test.dart' as fixtures;

final u = fixtures.u, cal = CalendarId.parse('cal_000000000000000000000009');
RecordId id(int n) => fixtures.id(n);
RecordRef ref(int n) => fixtures.ref(n);
RecordVersion row(int n, RecordPayload p) => fixtures.row(n, p);
final scope = Scope(
  context: ref(10),
  applicability: const UniverseApplicability(),
);
final frame = Frame(
  universe: u,
  continuity: ContinuityId.parse('cont_000000000000000000000001'),
  revision: fixtures.revision,
  context: ref(10),
  time: const TimelessFrameTime(),
  perspective: const AuthorPerspective(),
);
List<RecordVersion> fixture() => [
  row(1, fixtures.entity()),
  row(
    2,
    PropertyRecord(
      namespace: 'test',
      key: 'charged',
      labels: {},
      subjectTypes: [],
      value: const SimpleValueShape(SimpleShapeKind.boolean),
      multiplicity: Multiplicity.single,
      persistence: PersistenceSemantics.explicitInterval,
      exclusive: false,
      symmetric: false,
      transitive: false,
    ),
  ),
  row(
    3,
    PropositionRecord(
      subject: ref(1),
      predicate: ref(2),
      value: const BooleanValue(true),
      context: ref(10),
      quantification: Quantification.particular,
    ),
  ),
  row(
    4,
    AssertionRecord(
      attributeMode: AttributeMode.instance,
      proposition: ref(3),
      polarity: Polarity.support,
      scope: scope,
      validity: CalendarIntervalValidity(
        cal,
        const ExactBound('10'),
        const UnboundedBound(),
      ),
      persistence: PersistenceSemantics.explicitInterval,
      precision: Precision.exact,
      basis: const AuthorDecisionBasis('Explicit attribute'),
    ),
  ),
  row(
    5,
    ActionDefinitionRecord(
      namespace: 'test',
      key: 'charged_action',
      labels: {},
      requirements: [
        AttributeRequirement('actor', ref(2), const BooleanValue(true)),
      ],
      scope: scope,
      validity: const UnspecifiedValidity(),
    ),
  ),
  row(
    6,
    EventRecord(
      occurrence: const SimpleOccurrence(OccurrenceKind.occurred),
      action: ref(5),
      time: ExactTime(cal, '11'),
      participants: [EventParticipant(ref(1), 'actor')],
      labels: {},
    ),
  ),
];
void edit(
  List<RecordVersion> rows,
  int n,
  Map<String, CanonicalValue> changes,
) => rows[n - 1] = row(n, fixtures.patch(rows[n - 1].payload, changes));
void validate(List<RecordVersion> rows, {Set<RecordId>? changed}) =>
    validateActionRequirements(
      records: rows,
      changed: changed ?? {id(6)},
      frame: frame,
    );
Matcher fails(String field, [String? text]) => throwsA(
  isA<InvalidArgumentError>()
      .having((e) => e.field, 'field', field)
      .having(
        (e) => e.message,
        'message',
        text == null ? anything : contains(text),
      ),
);

void main() {
  test('declared owner attributes validate without changing the candidate', () {
    final rows = fixture(),
        before = fixture().map((r) => r.toWire().toText()).toList();
    validate(rows);
    expect(rows.map((r) => r.toWire().toText()).toList(), before);
  });

  test(
    'historical actionless occurrences remain readable but changed ones fail',
    () {
      final rows = fixture();
      edit(rows, 6, {'action': const CanonicalNull()});
      validate(rows, changed: {});
      expect(() => validate(rows), fails('event.action', 'new or revised'));
      edit(rows, 6, {
        'occurrence': const SimpleOccurrence(OccurrenceKind.planned).toWire(),
      });
      expect(() => validate(rows), fails('event.action', 'declared action'));
    },
  );

  test('action identity requires a local declared action definition', () {
    for (final reference in [
      ref(1),
      ref(99),
      RecordRef(record: id(5)),
      RecordRef(
        universe: UniverseId.parse('unv_000000000000000000000002'),
        record: id(5),
      ),
    ]) {
      final rows = fixture();
      edit(rows, 6, {'action': reference.toCanonical()});
      expect(
        () => validate(rows),
        fails('event.action', 'declared action definition'),
      );
    }
  });

  test('mandatory roles require exactly one owning entity', () {
    for (final participants in [
      <EventParticipant>[],
      [EventParticipant(ref(1), 'actor'), EventParticipant(ref(1), 'actor')],
      [EventParticipant(ref(2), 'actor')],
      [EventParticipant(ref(99), 'actor')],
      [EventParticipant(ref(1), 'patient')],
    ]) {
      final rows = fixture();
      edit(rows, 6, {
        'participants': CanonicalArray(participants.map((p) => p.toWire())),
      });
      expect(
        () => validate(rows),
        fails('event.action.requirements', 'exactly one owning entity'),
      );
    }
    final rows = fixture()..add(row(7, fixtures.entity()));
    edit(rows, 6, {
      'participants': CanonicalArray([
        EventParticipant(ref(1), 'actor').toWire(),
        EventParticipant(ref(7), 'patient').toWire(),
      ]),
    });
    validate(rows);
  });

  test('missing, uncertain, expired and opposing evidence do not establish requirements', () {
    for (final alterations in [
      <String, CanonicalValue>{'validity': const UnknownValidity().toWire()},
      {
        'alternatives': CanonicalArray([const BooleanValue(false).toWire()]),
      },
      {'precision': CanonicalString('unresolved')},
      {
        'scope': Scope(
          context: ref(11),
          applicability: const UniverseApplicability(),
        ).toWire(),
      },
      {'polarity': Polarity.refutation.toWire()},
    ]) {
      final rows = fixture();
      edit(rows, 4, alterations);
      expect(
        () => validate(rows),
        fails('event.action.requirements', 'required attribute test:charged'),
      );
    }
    final missing = fixture()..removeAt(3);
    expect(
      () => validate(missing),
      fails(
        'event.action.requirements',
        'on entity ${id(1).value} in event ${id(6).value}',
      ),
    );
    final noProperty = fixture()..removeAt(1);
    expect(
      () => validate(noProperty),
      fails('event.action.requirements', 'property is unavailable'),
    );
    final conflicting = fixture();
    conflicting.add(
      row(
        7,
        fixtures.patch(conflicting[3].payload as AssertionRecord, {
          'polarity': Polarity.refutation.toWire(),
        }),
      ),
    );
    expect(
      () => validate(conflicting),
      fails('event.action.requirements', 'outcome: Conflicting'),
    );
  });

  test('exact pre-event boundaries prevent self-granted capability', () {
    for (final (tick, allowed) in [
      (10, false),
      (11, true),
      (20, true),
      (21, false),
    ]) {
      final rows = fixture();
      edit(rows, 4, {
        'validity': CalendarIntervalValidity(
          cal,
          const ExactBound('10'),
          const ExactBound('20'),
        ).toWire(),
      });
      edit(rows, 6, {'time': ExactTime(cal, '$tick').encode(canonical: false)});
      if (allowed) {
        validate(rows);
      } else {
        expect(() => validate(rows), fails('event.action.requirements'));
      }
    }
    final sameEvent = fixture();
    edit(sameEvent, 4, {
      'validity': CalendarIntervalValidity(
        cal,
        const ExactBound('11'),
        const UnboundedBound(),
      ).toWire(),
    });
    expect(() => validate(sameEvent), fails('event.action.requirements'));
  });

  test('changed evidence revalidates unchanged dependent events', () {
    final rows = fixture();
    validate(rows, changed: {});
    edit(rows, 4, {
      'validity': CalendarIntervalValidity(
        cal,
        const ExactBound('0'),
        const ExactBound('10'),
      ).toWire(),
    });
    expect(
      () => validate(rows, changed: {id(4)}),
      fails('event.action.requirements'),
    );
  });

  test('action scope cannot widen across contexts, worlds or unsupported applicability', () {
    for (final applicability in [
      WorldsApplicability([WorldId.parse('wld_000000000000000000000020')]),
      const ConditionalApplicability(),
      const UnspecifiedApplicability(),
    ]) {
      final rows = fixture();
      edit(rows, 5, {
        'scope': Scope(context: ref(10), applicability: applicability).toWire(),
      });
      expect(
        () => validate(rows),
        fails('event.action', 'context/world scope'),
      );
    }
    final rows = fixture();
    final effect = EntityEffect(
      slot: 'result',
      proposition: ref(3),
      polarity: Polarity.support,
      scope: Scope(
        context: ref(11),
        applicability: const UniverseApplicability(),
      ),
      validity: const UnspecifiedValidity(),
      order: BigInt.zero,
    );
    edit(rows, 6, {
      'effects': CanonicalArray([effect.toWire()]),
    });
    expect(() => validate(rows), fails('event.action', 'context/world scope'));
  });

  test(
    'every event world must independently establish the owner attribute',
    () {
      final w1 = WorldId.parse('wld_000000000000000000000020'),
          w2 = WorldId.parse('wld_000000000000000000000021');
      final rows = fixture();
      edit(rows, 5, {
        'scope': Scope(
          context: ref(10),
          applicability: WorldsApplicability([w1, w2]),
        ).toWire(),
      });
      edit(rows, 6, {
        'worlds': CanonicalArray([
          CanonicalString(w1.value),
          CanonicalString(w2.value),
        ]),
      });
      validate(rows);
      edit(rows, 4, {
        'scope': Scope(
          context: ref(10),
          applicability: WorldsApplicability([w1]),
        ).toWire(),
      });
      expect(() => validate(rows), fails('event.action.requirements'));
      edit(rows, 6, {
        'worlds': CanonicalArray([CanonicalString(w1.value)]),
      });
      validate(rows);
    },
  );

  test('action active interval must be proven before occurrence', () {
    final rows = fixture();
    edit(rows, 5, {'validity': const UnknownValidity().toWire()});
    expect(
      () => validate(rows),
      fails('event.action', 'not explicitly active'),
    );
    edit(rows, 5, {
      'validity': CalendarIntervalValidity(
        cal,
        const ExactBound('11'),
        const UnboundedBound(),
      ).toWire(),
    });
    expect(
      () => validate(rows),
      fails('event.action', 'not explicitly active'),
    );
    edit(rows, 5, {
      'validity': CalendarIntervalValidity(
        cal,
        const ExactBound('0'),
        const ExactBound('11'),
      ).toWire(),
    });
    validate(rows);
  });

  test('plans and reports retain role structure without asserting factual execution', () {
    for (final mode in [
      OccurrenceKind.planned,
      OccurrenceKind.reported,
      OccurrenceKind.predicted,
      OccurrenceKind.hypothetical,
    ]) {
      final rows = fixture();
      edit(rows, 6, {'occurrence': SimpleOccurrence(mode).toWire()});
      edit(rows, 4, {'validity': const UnknownValidity().toWire()});
      edit(rows, 5, {'validity': const UnknownValidity().toWire()});
      validate(rows);
      edit(rows, 6, {'participants': CanonicalArray([])});
      expect(() => validate(rows), fails('event.action.requirements'));
    }
  });

  test('candidate ancestry can establish inherited shared attributes for the owner', () {
    final rows = fixture()..add(row(7, fixtures.type(7)));
    edit(rows, 1, {
      'classification': CanonicalString(id(7).value),
      'classificationResolution': CanonicalString('resolved'),
    });
    edit(rows, 3, {
      'subject': ref(7).toCanonical(),
      'quantification': CanonicalString('universal'),
    });
    edit(rows, 4, {'attributeMode': CanonicalString('shared')});
    validate(rows);
    edit(rows, 1, {'classificationResolution': CanonicalString('ambiguous')});
    expect(() => validate(rows), fails('event.action.requirements'));
  });

  test(
    'the existing work budget fails explicitly before partial validation',
    () {
      final r = row(1, fixtures.entity());
      expect(
        () => validateActionRequirements(
          records: List.filled(1000001, r),
          changed: {},
          frame: frame,
        ),
        throwsA(isA<EvaluationLimitReachedError>()),
      );
    },
  );
}
