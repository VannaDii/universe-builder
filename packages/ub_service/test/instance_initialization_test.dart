import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/instance_initialization.dart';
import 'package:ub_store/ub_store.dart';

String suffix(int n) => n.toRadixString(16).padLeft(24, '0');
RecordId id(int n) => RecordId.parse('rec_${suffix(n)}');
RecordVersionId version(int n) => RecordVersionId.parse('ver_${suffix(n)}');
final universe = UniverseId.parse('unv_${suffix(1)}'),
    revision = RevisionId.parse('rev_${suffix(1)}');
final calendar = CalendarId.parse('cal_${suffix(6)}');
RecordRef ref(int n) => RecordRef(universe: universe, record: id(n));
RecordVersion record(int n, RecordPayload p) => RecordVersion.build(
  recordVersionId: version(n),
  identity: RecordIdentity(
    universeId: universe,
    recordId: id(n),
    recordKind: p.recordKind,
  ),
  payload: p,
);
Validity interval(int a, int b) =>
    CalendarIntervalValidity(calendar, ExactBound('$a'), ExactBound('$b'));
final scope = Scope(
  context: ref(5),
  applicability: const UniverseApplicability(),
);
EntityTypeRecord type(
  int n, {
  RecordId? parent,
  Applicability applicability = const UniverseApplicability(),
}) => EntityTypeRecord(
  namespace: 'init',
  key: 'type$n',
  name: 'Type$n',
  labels: {},
  parent: parent,
  parentResolution: parent == null
      ? ParentResolution.root
      : ParentResolution.resolved,
  applicability: applicability,
  classificationExecutable: true,
);
RecordVersion prop(
  int n,
  int subject, {
  DomainValue? value = const IntegerValue('7'),
  List<PropositionRole> roles = const [],
}) => record(
  n,
  PropositionRecord(
    subject: ref(subject),
    predicate: ref(4),
    context: ref(5),
    value: value,
    roles: roles,
    quantification: Quantification.universal,
  ),
);
RecordVersion initial(
  int n,
  int target, {
  AttributeMode mode = AttributeMode.initialValue,
  Polarity polarity = Polarity.support,
  Precision precision = Precision.exact,
  Validity? validity,
  Scope? cell,
  List<DomainValue> alternatives = const [],
}) => record(
  n,
  AssertionRecord(
    attributeMode: mode,
    proposition: ref(target),
    polarity: polarity,
    scope: cell ?? scope,
    validity: validity ?? interval(0, 100),
    persistence: PersistenceSemantics.explicitInterval,
    precision: precision,
    alternatives: alternatives,
    basis: const AuthorDecisionBasis('authored initial definition'),
  ),
);
RecordVersion start({
  OccurrenceKind occurrence = OccurrenceKind.occurred,
  TemporalExpression? time,
  List<EventParticipant>? participants,
  List<WorldId> worlds = const [],
}) => record(
  9,
  EventRecord(
    occurrence: SimpleOccurrence(occurrence),
    time: time ?? ExactTime(calendar, '10'),
    participants:
        participants ?? [EventParticipant(ref(3), 'starting_instance')],
    worlds: worlds,
    labels: {},
  ),
);
List<RecordVersion> fixture() => [
  record(1, type(1)),
  record(2, type(2, parent: id(1))),
  record(
    3,
    EntityRecord(
      names: [],
      classification: id(2),
      classificationResolution: ClassificationResolution.resolved,
      worldAssociations: [],
      labels: {},
      metadata: {},
    ),
  ),
  record(
    4,
    PropertyRecord(
      namespace: 'init',
      key: 'rounds',
      labels: {},
      subjectTypes: [id(1)],
      value: const SimpleValueShape(SimpleShapeKind.integer),
      multiplicity: Multiplicity.single,
      persistence: PersistenceSemantics.explicitInterval,
      exclusive: false,
      symmetric: false,
      transitive: false,
    ),
  ),
  record(
    5,
    RepresentedContextRecord(
      universe: universe,
      kind: const ObjectiveContext(),
      labels: {},
    ),
  ),
  prop(7, 1),
  initial(8, 7),
  start(),
];
InitializeInstanceOperation operation({
  String? client,
  RecordRef? instance,
  RecordRef? event,
  VersionRef? definition,
  Validity? validity,
  Scope? cell,
}) => InitializeInstanceOperation(
  clientRef: client ?? id(50).value,
  instance: instance ?? ref(3),
  start: event ?? ref(9),
  definition:
      definition ??
      VersionRef(universe: universe, record: id(8), version: version(8)),
  scope: cell ?? scope,
  validity: validity ?? interval(10, 20),
);
List<Assignment> compile(
  List<RecordVersion> base, {
  InitializeInstanceOperation? op,
  List<DomainOperation>? operations,
  List<Assignment>? changes,
}) {
  final result = changes ?? <Assignment>[];
  compileInitializations(
    universe: universe,
    revision: revision,
    base: base,
    operations: operations ?? [op ?? operation()],
    changes: result,
  );
  return result;
}

Assignment change(RecordVersion next) => Assignment(
  recordId: next.identity.recordId,
  expected: next.recordVersionId,
  next: StoredVersion(
    versionId: next.recordVersionId,
    identity: next.identity,
    payload: next.payload.toWire(),
    digest: next.payloadDigest,
  ),
);
void replace(List<RecordVersion> rows, RecordVersion next) =>
    rows[rows.indexWhere(
          (r) => r.identity.recordId == next.identity.recordId,
        )] =
        next;
final denied = throwsA(
  isA<InvalidArgumentError>().having(
    (e) => e.field,
    'field',
    'initialize_instance',
  ),
);
void main() {
  test('an explicit selected source produces separate frozen instance state and exact provenance', () {
    final rows = fixture(),
        before = fixture().map((r) => r.toWire().toText()).toList();
    final changes = compile(rows);
    expect(changes.length, 2);
    expect(changes.every((c) => c.expected == null), isTrue);
    for (final c in changes) {
      c.next!.verify();
    }
    final generated = changes
        .map((c) => RecordVersion.fromWire(c.next!.toCanonical()))
        .toList();
    final p =
        generated.firstWhere((r) => r.payload is PropositionRecord).payload
            as PropositionRecord;
    final a =
        generated.firstWhere((r) => r.payload is AssertionRecord).payload
            as AssertionRecord;
    expect(p.subject, ref(3));
    expect(p.value, const IntegerValue('7'));
    expect(p.quantification, Quantification.particular);
    expect(a.attributeMode, AttributeMode.instance);
    expect(a.validity, interval(10, 20));
    expect(a.proposition.record, id(50));
    final basis = a.basis as InstanceInitializationBasis;
    expect(basis.start.version, version(9));
    expect(basis.start.record, id(9));
    expect(basis.definition.version, version(8));
    expect(basis.sourceRevision, revision);
    expect(rows.map((r) => r.toWire().toText()), before);
    expect(() => compile([...rows, ...generated]), denied);
    final again = compile(rows, op: operation(client: id(51).value));
    expect(
      again
          .map((c) => c.next!.versionId)
          .toSet()
          .intersection(changes.map((c) => c.next!.versionId).toSet()),
      isEmpty,
    );
  });
  test('classification and a source definition alone do not initialize instance state', () {
    final rows = fixture();
    final changes = <Assignment>[];
    compileInitializations(
      universe: universe,
      revision: revision,
      base: rows,
      operations: [],
      changes: changes,
    );
    expect(changes, isEmpty);
    expect(
      rows.where(
        (r) =>
            r.payload is AssertionRecord &&
            (r.payload as AssertionRecord).attributeMode ==
                AttributeMode.instance,
      ),
      isEmpty,
    );
  });
  test(
    'conflicting, uncertain and opposed ancestor candidates remain unresolved',
    () {
      for (final other in [
        initial(11, 10),
        initial(11, 10, validity: const UnknownValidity()),
        initial(11, 10, polarity: Polarity.refutation),
        initial(11, 10, precision: Precision.approximate),
        initial(11, 10, alternatives: [const IntegerValue('7')]),
      ]) {
        final rows = fixture()
          ..addAll([
            prop(
              10,
              2,
              value:
                  other.payload is AssertionRecord &&
                      (other.payload as AssertionRecord).validity
                          is UnknownValidity
                  ? const IntegerValue('7')
                  : const IntegerValue('3'),
            ),
            other,
          ]);
        final before = rows.map((r) => r.toWire().toText()).toList();
        if ((other.payload as AssertionRecord).polarity ==
            Polarity.refutation) {
          replace(rows, prop(10, 2));
        }
        expect(() => compile(rows), denied);
        expect(rows.length, before.length);
        expect(rows.last.recordVersionId, version(11));
      }
      final equal = fixture()
        ..addAll([
          prop(10, 2, value: const RationalValue('14', '2')),
          initial(11, 10),
        ]);
      expect(compile(equal).length, 2);
      final disprovenOther = fixture()
        ..addAll([
          prop(10, 2, value: const IntegerValue('3')),
          initial(11, 10, polarity: Polarity.refutation),
        ]);
      expect(compile(disprovenOther).length, 2);
    },
  );
  test('same-proposal source and proposition changes cannot alter an approved initial value', () {
    final rows = fixture();
    expect(
      () => compile(
        rows,
        changes: [change(initial(8, 7, precision: Precision.unresolved))],
      ),
      denied,
    );
    expect(
      () => compile(
        rows,
        changes: [change(prop(7, 1, value: const IntegerValue('9')))],
      ),
      denied,
    );
    expect(
      () => compile(
        rows,
        changes: [Assignment(recordId: id(8), expected: version(8))],
      ),
      denied,
    );
    expect(
      () => compile(
        rows,
        op: operation(
          definition: VersionRef(
            universe: universe,
            record: id(8),
            version: version(99),
          ),
        ),
      ),
      denied,
    );
    final newlyProposed = initial(12, 7);
    expect(
      () => compile(
        rows,
        changes: [change(newlyProposed)],
        op: operation(
          definition: VersionRef(
            universe: universe,
            record: id(12),
            version: version(12),
          ),
        ),
      ),
      denied,
    );
  });
  test('initialization requires an exact occurred start and full interval containment', () {
    for (final event in [
      start(occurrence: OccurrenceKind.planned),
      start(occurrence: OccurrenceKind.hypothetical),
      start(participants: []),
      start(time: const UnspecifiedTime()),
    ]) {
      final rows = fixture();
      replace(rows, event);
      expect(() => compile(rows), denied);
    }
    for (final validity in [
      interval(9, 20),
      interval(10, 10),
      interval(11, 20),
      const UnknownValidity(),
      CalendarIntervalValidity(
        CalendarId.parse('cal_${suffix(99)}'),
        const ExactBound('10'),
        const ExactBound('20'),
      ),
      CalendarIntervalValidity(
        calendar,
        const ExactBound('10'),
        const UnknownBound(),
      ),
    ]) {
      expect(
        () => compile(fixture(), op: operation(validity: validity)),
        denied,
      );
    }
  });
  test('explicit local references, instance classification and source modes are required', () {
    expect(
      () => compile(
        fixture(),
        op: operation(instance: RecordRef(record: id(3))),
      ),
      denied,
    );
    expect(() => compile(fixture(), op: operation(instance: ref(1))), denied);
    for (final source in [
      initial(8, 7, mode: AttributeMode.shared),
      initial(8, 7, polarity: Polarity.refutation),
      initial(8, 7, precision: Precision.approximate),
      initial(
        8,
        7,
        cell: Scope(
          context: ref(5),
          applicability: const UniverseApplicability(),
          realm: ref(30),
        ),
      ),
    ]) {
      final rows = fixture();
      replace(rows, source);
      expect(() => compile(rows), denied);
    }
    final ambiguous = fixture();
    replace(
      ambiguous,
      record(
        3,
        EntityRecord(
          names: [],
          classification: id(2),
          classificationResolution: ClassificationResolution.ambiguous,
          worldAssociations: [],
          labels: {},
          metadata: {},
        ),
      ),
    );
    expect(() => compile(ambiguous), denied);
    final noValue = fixture();
    replace(noValue, prop(7, 1, value: null));
    expect(() => compile(noValue), denied);
  });
  test('every requested world must be established at start with applicable ancestry and evidence', () {
    final a = WorldId.parse('wld_${suffix(30)}'),
        b = WorldId.parse('wld_${suffix(31)}');
    final rows = fixture()
      ..addAll([
        record(30, WorldRecord(selector: 'a')),
        record(31, WorldRecord(selector: 'b')),
      ]);
    replace(rows, start(worlds: [a]));
    expect(() => compile(rows), denied);
    replace(rows, start(worlds: [a, b]));
    expect(compile(rows).length, 2);
    replace(
      rows,
      initial(
        8,
        7,
        cell: Scope(context: ref(5), applicability: WorldsApplicability([a])),
      ),
    );
    expect(() => compile(rows), denied);
    expect(
      compile(
        rows,
        op: operation(
          cell: Scope(context: ref(5), applicability: WorldsApplicability([a])),
        ),
      ).length,
      2,
    );
    replace(rows, record(1, type(1, applicability: WorldsApplicability([b]))));
    expect(
      () => compile(
        rows,
        op: operation(
          cell: Scope(context: ref(5), applicability: WorldsApplicability([a])),
        ),
      ),
      denied,
    );
    expect(
      () => compile(
        rows,
        op: operation(
          cell: Scope(context: ref(5), applicability: WorldsApplicability([])),
        ),
      ),
      denied,
    );
  });
  test('disjoint source timing ignores another dimension but never selects an inapplicable source', () {
    final rows = fixture()
      ..addAll([
        prop(10, 2, value: const IntegerValue('3')),
        initial(
          11,
          10,
          validity: interval(20, 30),
          precision: Precision.approximate,
        ),
      ]);
    expect(compile(rows).length, 2);
    replace(rows, initial(8, 7, validity: interval(20, 30)));
    expect(() => compile(rows), denied);
  });
  test('client identity collisions and duplicate instance/property requests are rejected', () {
    expect(
      () => compile(fixture(), op: operation(client: '\u0085\u3000')),
      denied,
    );
    expect(
      () => compile(fixture(), op: operation(client: id(7).value)),
      denied,
    );
    expect(
      () => compile(fixture(), changes: [Assignment(recordId: id(50))]),
      denied,
    );
    expect(
      () => compile(
        fixture(),
        operations: [
          operation(),
          operation(client: id(51).value),
        ],
      ),
      denied,
    );
    final random = compile(fixture(), op: operation(client: 'starting-value'));
    expect(random.length, 2);
    expect(random.first.recordId.value, startsWith('rec_'));
  });
}
