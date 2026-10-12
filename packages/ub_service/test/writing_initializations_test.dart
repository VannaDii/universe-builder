import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/ub_service.dart';
import 'package:ub_rules/ub_rules.dart' show eventExpansionVersion;

import 'instance_initialization_test.dart' as f;
import 'operation_compilation_test.dart' as op;

final frame = Frame(
  universe: f.universe,
  continuity: ContinuityId.parse('cont_${f.suffix(1)}'),
  revision: f.revision,
  context: f.ref(5),
  time: const TimelessFrameTime(),
  perspective: const AuthorPerspective(),
);
List<RecordVersion> rows() {
  final base = f.fixture();
  f.replace(
    base,
    f.record(
      3,
      op.patch<EntityRecord>(base[2].payload as EntityRecord, {
        'labels': CanonicalObject([MapEntry('en', CanonicalString('Pistol'))]),
      }),
    ),
  );
  f.replace(
    base,
    f.record(
      9,
      op.patch<EventRecord>(base.last.payload as EventRecord, {
        'expansionVersion': CanonicalString(eventExpansionVersion),
      }),
    ),
  );
  final clock = FictionalUniverseStart(
    calendarName: 'Story time',
    initialTick: '10',
    tickLabel: 'ticks',
  ).build(f.calendar);
  f.replace(
    base,
    f.record(
      5,
      RepresentedContextRecord(
        universe: f.universe,
        kind: const ObjectiveContext(),
        chronology: clock.$1,
        labels: {},
      ),
    ),
  );
  return [...base, f.record(6, clock.$2)];
}

WritingInitialization request({
  WritingInstanceStart? start,
  List<String>? handles,
  String scope = 'universe',
  FactLifetime lifetime = const FactUntilChangedLifetime(),
  String instance = 'Pistol',
}) => WritingInitialization(
  instance: instance,
  initialValueHandles: handles ?? [f.version(8).value],
  start: start ?? WritingExistingInstanceStart(handle: f.id(9).value),
  scope: scope,
  lifetime: lifetime,
);
CheckChangesRequest delta(List<WritingInitialization> declarations) =>
    CheckChangesRequest(
      universe: const Selector('Test'),
      contextId: ContextId.generate(),
      initializations: declarations,
    );
List<RecordVersion> compiled(
  List<RecordVersion> base,
  List<DomainOperation> operations,
) => compileWritingCandidate(
  universe: f.universe,
  revision: f.revision,
  base: base,
  operations: operations,
);
void main() {
  test('explicit existing starts freeze selected approved sources with exact provenance', () {
    final base = rows();
    final result = compileWritingInitializations(
      frame: frame,
      base: base,
      input: delta([
        request(lifetime: FactUntilLifetime(endTick: '9007199254740993')),
      ]),
    );
    expect(result.clarifications, isEmpty);
    final operation = result.operations.single as InitializeInstanceOperation;
    expect(operation.instance, f.ref(3));
    expect(operation.start, f.ref(9));
    expect(
      operation.definition,
      VersionRef(universe: f.universe, record: f.id(8), version: f.version(8)),
    );
    expect(
      operation.validity,
      CalendarIntervalValidity(
        f.calendar,
        const ExactBound('10'),
        const ExactBound('9007199254740993'),
      ),
    );
    final candidate = compiled(base, result.operations);
    final initialized =
        candidate
                .where(
                  (r) =>
                      r.payload is AssertionRecord &&
                      (r.payload as AssertionRecord).basis
                          is InstanceInitializationBasis,
                )
                .single
                .payload
            as AssertionRecord;
    expect(initialized.attributeMode, AttributeMode.instance);
    final basis = initialized.basis as InstanceInitializationBasis;
    expect(
      basis.start,
      VersionRef(universe: f.universe, record: f.id(9), version: f.version(9)),
    );
    expect(basis.definition, operation.definition);
    expect(
      candidate
          .singleWhere((r) => r.identity.recordId == f.id(8))
          .toWire()
          .toText(),
      base.singleWhere((r) => r.identity.recordId == f.id(8)).toWire().toText(),
    );
    expect(basis.sourceRevision, frame.revision);
  });

  test('nested occurred starts reuse the connected action compiler and remain atomic with initialization', () {
    final base = rows();
    final action = ActionDefinitionRecord(
      namespace: 'init',
      key: 'created',
      labels: {},
      requirements: [],
      scope: f.scope,
      validity: const UnspecifiedValidity(),
      consequenceContract: ConsequenceContract([]),
    );
    final full = [...base, f.record(20, action)];
    final result = compileWritingInitializations(
      frame: frame,
      base: full,
      input: delta([
        request(
          start: WritingOccurredInstanceStart(
            event: WritingEvent(
              action: 'created',
              participants: {'starting_instance': 'Pistol'},
              atTick: '12',
            ),
          ),
        ),
      ]),
    );
    expect(result.clarifications, isEmpty);
    final occurred = result.operations.whereType<RecordEventOperation>().single;
    final initialization = result.operations
        .whereType<InitializeInstanceOperation>()
        .single;
    expect(initialization.start.record.value, occurred.clientRef);
    final candidate = compiled(full, result.operations);
    expect(candidate.where((r) => r.payload is EventRecord), hasLength(2));
    expect(
      candidate.where(
        (r) =>
            r.payload is AssertionRecord &&
            (r.payload as AssertionRecord).basis is InstanceInitializationBasis,
      ),
      hasLength(1),
    );
    final invalid = compileWritingInitializations(
      frame: frame,
      base: full,
      input: delta([
        request(
          start: WritingOccurredInstanceStart(
            event: WritingEvent(
              action: 'created',
              participants: {'starting_instance': 'Pistol'},
              atTick: '12',
            ),
          ),
          handles: [f.version(808).value],
        ),
      ]),
    );
    expect(invalid.operations, isEmpty);
    expect(invalid.clarifications.single, contains('approved initial-value'));
  });

  test('unpublished sources and starts cannot substitute for pinned approved records', () {
    final base = rows();
    final stale = compileWritingInitializations(
      frame: frame,
      base: base,
      input: delta([
        request(handles: [f.id(8).value]),
        request(
          start: WritingExistingInstanceStart(handle: f.version(9).value),
        ),
        request(handles: [f.version(7).value]),
        request(handles: []),
        request(instance: 'Absent'),
        request(scope: 'unspecified'),
        request(lifetime: const FactUnspecifiedLifetime()),
      ]),
    );
    expect(stale.operations, isEmpty);
    expect(stale.clarifications, hasLength(7));
    final revisedSource = op.patch<AssertionRecord>(
      base.singleWhere((row) => row.identity.recordId == f.id(8)).payload
          as AssertionRecord,
      {'basis': const ImportedClaimBasis().toWire()},
    );
    final changed = compileWritingInitializations(
      frame: frame,
      base: base,
      priorOperations: [
        SupersedeAssertionOperation(
          record: f.ref(8),
          expectedVersion: f.version(8),
          replacement: revisedSource,
          rationale: 'Unpublished source revision',
        ),
      ],
      input: delta([request()]),
    );
    expect(changed.operations, isEmpty);
    expect(
      changed.clarifications.single,
      contains('source definition changed'),
    );
  });

  test('canonical initialization refusals remain clarifications without partial operations', () {
    final base = rows();
    final planned = [
      for (final row in base)
        row.identity.recordId == f.id(9)
            ? f.record(
                9,
                op.patch<EventRecord>(row.payload as EventRecord, {
                  'occurrence': const SimpleOccurrence(OccurrenceKind.planned)
                      .toWire(),
                }),
              )
            : row,
    ];
    final result = compileWritingInitializations(
      frame: frame,
      base: planned,
      input: delta([request()]),
    );
    expect(result.operations, isEmpty);
    expect(result.clarifications.single, contains('occurred instance start'));
    final duplicate = compileWritingInitializations(
      frame: frame,
      base: base,
      input: delta([request(), request()]),
    );
    expect(duplicate.operations, hasLength(1));
    expect(duplicate.clarifications, hasLength(1));
    final invalid = compileWritingInitializations(
      frame: frame,
      base: base,
      input: delta([request(lifetime: FactUntilLifetime(endTick: '9'))]),
    );
    expect(invalid.operations, isEmpty);
    expect(invalid.clarifications, hasLength(1));
  });
}
