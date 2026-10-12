import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_rules/ub_rules.dart';
import 'package:ub_service/event_compilation.dart';
import 'package:ub_store/ub_store.dart';

String suffix(int n) => n.toRadixString(16).padLeft(24, '0');
RecordId id(int n) => RecordId.parse('rec_${suffix(n)}');
RecordVersionId version(int n) => RecordVersionId.parse('ver_${suffix(n)}');
final universe = UniverseId.parse('unv_${suffix(1)}');
final calendar = CalendarId.parse('cal_${suffix(1)}');
RecordRef ref(int n) => RecordRef(universe: universe, record: id(n));
final scope = Scope(
  context: ref(3),
  applicability: const UniverseApplicability(),
);
RecordVersion record(int n, RecordPayload payload, {RecordId? identity}) =>
    RecordVersion.build(
      recordVersionId: version(n),
      identity: RecordIdentity(
        universeId: universe,
        recordId: identity ?? id(n),
        recordKind: payload.recordKind,
      ),
      payload: payload,
    );
StoredVersion stored(RecordVersion r) => StoredVersion(
  versionId: r.recordVersionId,
  identity: r.identity,
  payload: r.payload.toWire(),
  digest: r.payloadDigest,
);
Assignment change(RecordVersion r, {RecordVersionId? expected}) => Assignment(
  recordId: r.identity.recordId,
  expected: expected,
  next: stored(r),
);
final proposition = PropositionRecord(
  subject: ref(1),
  predicate: ref(2),
  value: const BooleanValue(true),
  quantification: Quantification.particular,
  context: ref(3),
);
EventRecord event(
  int time, {
  Polarity polarity = Polarity.support,
  String slot = 'active',
  String? expansion = eventExpansionVersion,
  OccurrenceKind occurrence = OccurrenceKind.occurred,
}) => EventRecord(
  occurrence: SimpleOccurrence(occurrence),
  time: ExactTime(calendar, '$time'),
  participants: [],
  labels: {},
  expansionVersion: expansion,
  effects: [
    EntityEffect(
      slot: slot,
      proposition: ref(4),
      polarity: polarity,
      scope: scope,
      validity: CalendarIntervalValidity(
        calendar,
        ExactBound('$time'),
        const UnboundedBound(),
      ),
      order: BigInt.zero,
    ),
  ],
);
List<RecordVersion> base({bool later = false}) {
  final rows = [
    record(4, proposition),
    record(5, event(10)),
    if (later) record(6, event(20, polarity: Polarity.refutation)),
  ];
  var n = 30;
  return [
    ...rows,
    for (final entry in expandEvents(rows).entries)
      record(n++, entry.value, identity: entry.key),
  ];
}

RecordVersion decode(Assignment a) =>
    RecordVersion.fromWire(a.next!.toCanonical());
List<RecordVersion> apply(List<RecordVersion> rows, List<Assignment> changes) {
  final next = {for (final r in rows) r.identity.recordId: r};
  for (final c in changes) {
    if (c.next == null) {
      next.remove(c.recordId);
    } else {
      c.next!.verify();
      next[c.recordId] = decode(c);
    }
  }
  return next.values.toList();
}

Matcher failure(String text) => throwsA(
  isA<InvalidArgumentError>()
      .having((e) => e.field, 'field', 'event')
      .having((e) => e.message, 'message', contains(text)),
);

void main() {
  test(
    'new effects freeze deterministic identities and valid versioned bodies',
    () {
      final rows = [record(4, proposition)];
      final changes = [change(record(5, event(10)))];
      freezeEventEffects(universe: universe, base: rows, changes: changes);
      expect(changes, hasLength(2));
      final derived = changes.last;
      expect(derived.recordId, eventEffectId(id(5), 'active'));
      expect(derived.expected, isNull);
      expect(decode(derived).identity.universeId, universe);
      final assertion = decode(derived).payload as AssertionRecord;
      expect(assertion.establishedBy, EventEffectRef(ref(5), 'active'));
      expect(
        assertion.basis,
        AuthorDecisionBasis('Compiled event ${id(5).value} slot active'),
      );
      verifyEventEffects(apply(rows, changes));
      expect(rows, hasLength(1));
    },
  );

  test('unchanged effects do not churn versions or assignments', () {
    final rows = base(later: true), changes = <Assignment>[];
    freezeEventEffects(universe: universe, base: rows, changes: changes);
    expect(changes, isEmpty);
    verifyEventEffects(rows);
  });

  test(
    'later occurrence truncates the earlier fact with its expected version',
    () {
      final rows = base();
      final old = rows.last;
      final changes = [
        change(record(6, event(20, polarity: Polarity.refutation))),
      ];
      freezeEventEffects(universe: universe, base: rows, changes: changes);
      expect(changes, hasLength(3));
      final revised = changes.singleWhere(
        (c) => c.recordId == old.identity.recordId,
      );
      expect(revised.expected, old.recordVersionId);
      expect(revised.next!.versionId, isNot(old.recordVersionId));
      expect(
        (decode(revised).payload as AssertionRecord).validity,
        CalendarIntervalValidity(
          calendar,
          const ExactBound('10'),
          const ExactBound('20'),
        ),
      );
      verifyEventEffects(apply(rows, changes));
    },
  );

  test('withdrawal removes generated facts and reopens earlier intervals', () {
    final rows = base(later: true);
    final changes = [Assignment(recordId: id(6), expected: version(6))];
    freezeEventEffects(universe: universe, base: rows, changes: changes);
    final removedId = eventEffectId(id(6), 'active');
    final old = rows.singleWhere((r) => r.identity.recordId == removedId);
    final removed = changes.singleWhere((c) => c.recordId == removedId);
    expect(removed.expected, old.recordVersionId);
    expect(removed.next, isNull);
    final earlier = changes.singleWhere(
      (c) => c.recordId == eventEffectId(id(5), 'active'),
    );
    expect(
      (decode(earlier).payload as AssertionRecord).validity,
      CalendarIntervalValidity(
        calendar,
        const ExactBound('10'),
        const UnboundedBound(),
      ),
    );
    verifyEventEffects(apply(rows, changes));
  });

  test(
    'event revision preserves effect identity and freezes replacement facts',
    () {
      final rows = base();
      final changes = [
        change(
          record(50, event(12, polarity: Polarity.refutation), identity: id(5)),
          expected: version(5),
        ),
      ];
      freezeEventEffects(universe: universe, base: rows, changes: changes);
      expect(changes, hasLength(2));
      expect(changes.last.recordId, rows.last.identity.recordId);
      expect(changes.last.expected, rows.last.recordVersionId);
      final a = decode(changes.last).payload as AssertionRecord;
      expect(a.polarity, Polarity.refutation);
      expect(
        a.validity,
        CalendarIntervalValidity(
          calendar,
          const ExactBound('12'),
          const UnboundedBound(),
        ),
      );
      verifyEventEffects(apply(rows, changes));
    },
  );

  test(
    'changed slot withdraws the old effect and creates the new identity',
    () {
      final rows = base();
      final changes = [
        change(
          record(50, event(10, slot: 'replacement'), identity: id(5)),
          expected: version(5),
        ),
      ];
      freezeEventEffects(universe: universe, base: rows, changes: changes);
      expect(changes, hasLength(3));
      expect(
        changes
            .singleWhere((c) => c.recordId == rows.last.identity.recordId)
            .next,
        isNull,
      );
      expect(
        changes
            .singleWhere(
              (c) => c.recordId == eventEffectId(id(5), 'replacement'),
            )
            .expected,
        isNull,
      );
      verifyEventEffects(apply(rows, changes));
    },
  );

  test('direct generated edits, removal and injection are rejected', () {
    final rows = base(), generated = rows.last;
    for (final edit in [
      change(
        record(99, generated.payload, identity: generated.identity.recordId),
        expected: generated.recordVersionId,
      ),
      Assignment(
        recordId: generated.identity.recordId,
        expected: generated.recordVersionId,
      ),
      change(
        record(99, proposition, identity: generated.identity.recordId),
        expected: generated.recordVersionId,
      ),
    ]) {
      expect(
        () =>
            freezeEventEffects(universe: universe, base: rows, changes: [edit]),
        failure('only change through their event'),
      );
    }
    expect(
      () => freezeEventEffects(
        universe: universe,
        base: [record(4, proposition)],
        changes: [change(generated)],
      ),
      failure('only change through their event'),
    );
  });

  test('effect identity cannot overwrite an ordinary record', () {
    final rows = [
      record(4, proposition),
      record(20, proposition, identity: eventEffectId(id(5), 'active')),
    ];
    expect(
      () => freezeEventEffects(
        universe: universe,
        base: rows,
        changes: [change(record(5, event(10)))],
      ),
      failure('identity collides'),
    );
  });

  test('expansion errors remain event argument failures', () {
    for (final e in [event(10, expansion: 'future'), event(10, slot: '')]) {
      expect(
        () => freezeEventEffects(
          universe: universe,
          base: [record(4, proposition)],
          changes: [change(record(5, e))],
        ),
        throwsA(
          isA<InvalidArgumentError>().having((e) => e.field, 'field', 'event'),
        ),
      );
    }
  });

  test('non-occurrences never generate objective facts', () {
    for (final mode in [
      OccurrenceKind.planned,
      OccurrenceKind.reported,
      OccurrenceKind.predicted,
      OccurrenceKind.hypothetical,
    ]) {
      final rows = [record(4, proposition)],
          changes = [
            change(record(5, event(10, occurrence: mode, expansion: null))),
          ];
      freezeEventEffects(universe: universe, base: rows, changes: changes);
      expect(changes, hasLength(1));
      verifyEventEffects(apply(rows, changes));
    }
  });

  test(
    'surviving initialization blocks start removal; removing both is allowed',
    () {
      final rows = base();
      final generated = rows.last.payload as AssertionRecord;
      rows.add(
        record(
          80,
          AssertionRecord(
            attributeMode: generated.attributeMode,
            proposition: generated.proposition,
            polarity: generated.polarity,
            scope: generated.scope,
            validity: generated.validity,
            persistence: generated.persistence,
            precision: generated.precision,
            basis: InstanceInitializationBasis(
              VersionRef(
                universe: universe,
                record: id(5),
                version: version(5),
              ),
              VersionRef(
                universe: universe,
                record: id(90),
                version: version(90),
              ),
              RevisionId.parse('rev_${suffix(1)}'),
            ),
          ),
        ),
      );
      final changes = [Assignment(recordId: id(5), expected: version(5))];
      expect(
        () => freezeEventEffects(
          universe: universe,
          base: rows,
          changes: changes,
        ),
        failure('surviving initialization'),
      );
      changes.add(Assignment(recordId: id(80), expected: version(80)));
      freezeEventEffects(universe: universe, base: rows, changes: changes);
      expect(changes.last.recordId, eventEffectId(id(5), 'active'));
      expect(changes.last.next, isNull);
      verifyEventEffects(apply(rows, changes));
    },
  );
}
