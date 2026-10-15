import 'package:test/test.dart';
import 'package:ub_app/initialization_draft.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

void main() {
  final universe = UniverseId.generate();
  final revision = RevisionId.generate();
  final context = RecordId.generate();
  final instance = RecordId.generate();
  final calendar = CalendarId.generate();
  final startId = RecordId.generate();
  final sourceId = RecordId.generate();
  final sourceVersion = RecordVersionId.generate();
  final continuity = ContinuityId.generate();
  final scope = Scope(
    context: RecordRef(record: context),
    applicability: const UniverseApplicability(),
  );
  RecordVersion source({RecordVersionId? version, AttributeMode? mode}) =>
      RecordVersion.build(
        recordVersionId: version ?? sourceVersion,
        identity: RecordIdentity(
          universeId: universe,
          recordId: sourceId,
          recordKind: RecordKind.assertion,
        ),
        payload: AssertionRecord(
          proposition: RecordRef(record: RecordId.generate()),
          attributeMode: mode ?? AttributeMode.initialValue,
          polarity: Polarity.support,
          scope: scope,
          validity: const UnspecifiedValidity(),
          persistence: PersistenceSemantics.explicitInterval,
          precision: Precision.exact,
          alternatives: [],
          basis: const AuthorDecisionBasis('Published initial value'),
        ),
      );
  RecordVersion start({
    OccurrenceKind? occurrence,
    bool participant = true,
    TemporalExpression? time,
  }) => RecordVersion.build(
    recordVersionId: RecordVersionId.generate(),
    identity: RecordIdentity(
      universeId: universe,
      recordId: startId,
      recordKind: RecordKind.event,
    ),
    payload: EventRecord(
      occurrence: SimpleOccurrence(occurrence ?? OccurrenceKind.occurred),
      time: time ?? ExactTime(calendar, '10'),
      participants: [
        if (participant)
          EventParticipant(RecordRef(record: instance), 'starting instance'),
      ],
      worlds: [],
      labels: {},
    ),
  );
  UnfinishedInitializationForm form() => UnfinishedInitializationForm(
    baseRevision: revision,
    representedContext: context,
    clientRef: 'initial stock',
    instance: ExpressionReferenceInput(record: instance.value),
    start: ExpressionReferenceInput(record: startId.value),
    definition: VersionRef(record: sourceId, version: sourceVersion),
    scope: ScopeInput(
      applicability: 'universe_wide',
      contextRecord: context.value,
    ),
    endKind: 'exact',
    endCoordinate: '20',
    rationale: 'Initial stock 記憶 😀',
  );
  InitializeInstanceOperation build(
    UnfinishedInitializationForm value, {
    RecordVersion? event,
    RecordVersion? definition,
  }) => initializationOperation(
    value,
    universe: universe,
    start: event ?? start(),
    definition: definition ?? source(),
  );

  test('unfinished initialization retains pinned sources, incomplete input and exact versions', () {
    final original = UnfinishedInitializationForm(
      baseRevision: revision,
      representedContext: context,
      clientRef: 'pending',
      definition: form().definition,
      endCoordinate: 'unfinished exact time',
      rationale: '\ufeffAccount\r\n記憶 😀',
      draftVersion: BigInt.parse('18446744073709551615'),
    );
    final restored = UnfinishedInitializationForm.fromWire(original.toWire());
    expect(restored.toWire().toText(), original.toWire().toText());
    expect(restored.copyWith(clearDefinition: true).definition, isNull);
    expect(() => build(restored), throwsFormatException);
  });

  test(
    'initialization pins the selected source and begins at the occurred start',
    () {
      final operation = build(form());
      expect(
        operation.definition.toCanonical().toText(),
        form().definition!.toCanonical().toText(),
      );
      expect(operation.instance.record, instance);
      final validity = operation.validity as CalendarIntervalValidity;
      expect(validity.calendar, calendar);
      expect((validity.start as ExactBound).value, '10');
      expect((validity.end as ExactBound).value, '20');
      expect(
        build(form().copyWith(endKind: 'unbounded')).validity,
        isA<CalendarIntervalValidity>().having(
          (v) => v.end,
          'explicit end',
          isA<UnboundedBound>(),
        ),
      );
    },
  );

  test('draft addition and editing preserve other operations and reject stale edits', () {
    final other = AddWorldAliasOperation(
      record: RecordRef(record: RecordId.generate()),
      expectedVersion: RecordVersionId.generate(),
      alias: 'Earlier world',
    );
    final initial = SavedDraft(
      version: BigInt.one,
      content: DraftContent(
        baseRevision: revision,
        representedContext: context,
        operations: [other],
        rationale: 'Earlier rationale',
      ),
    );
    SaveDraftEngineRequest save(
      SavedDraft draft,
      UnfinishedInitializationForm input, {
      int? index,
    }) => initializationDraftRequest(
      draft: draft,
      form: input,
      universe: const Selector('Campaign'),
      universeId: universe,
      continuity: continuity,
      start: start(),
      definition: source(),
      index: index,
    );
    final request = save(initial, form());
    expect(request.expectedVersion, initial.version);
    expect(
      request.content.operations.first.toWire().toText(),
      other.toWire().toText(),
    );
    expect(
      request.content.rationale,
      'Earlier rationale\n\nInitial stock 記憶 😀',
    );
    final saved = SavedDraft(version: BigInt.two, content: request.content);
    expect(
      save(saved, form()).content.toWire().toText(),
      request.content.toWire().toText(),
    );
    final editing = initializationFormFromDraft(saved, 1);
    final edited = save(saved, editing.copyWith(endCoordinate: '30'), index: 1);
    expect(
      edited.content.operations.first.toWire().toText(),
      other.toWire().toText(),
    );
    expect(edited.content.rationale, request.content.rationale);
    expect(
      (edited.content.operations[1] as InitializeInstanceOperation).clientRef,
      editing.clientRef,
    );
    expect(
      () => save(
        SavedDraft(version: BigInt.from(3), content: saved.content),
        editing,
        index: 1,
      ),
      throwsFormatException,
    );
  });

  test('invalid starts, changed source pins and implicit scope/end choices are refused', () {
    expect(
      () => build(form(), event: start(occurrence: OccurrenceKind.planned)),
      throwsFormatException,
    );
    expect(
      () => build(form(), event: start(participant: false)),
      throwsFormatException,
    );
    expect(
      () => build(form(), event: start(time: const UnspecifiedTime())),
      throwsFormatException,
    );
    expect(
      () => build(
        form(),
        definition: source(version: RecordVersionId.generate()),
      ),
      throwsFormatException,
    );
    expect(
      () =>
          build(form(), definition: source(mode: AttributeMode.instance)),
      throwsFormatException,
    );
    for (final invalid in [
      form().copyWith(clearDefinition: true),
      form().copyWith(endKind: ''),
      form().copyWith(endCoordinate: '10'),
      form().copyWith(endCoordinate: '9'),
      form().copyWith(endCoordinate: (BigInt.one << 127).toString()),
      form().copyWith(scope: ScopeInput(contextRecord: context.value)),
      form().copyWith(
        scope: ScopeInput(
          applicability: 'worlds',
          contextRecord: context.value,
        ),
      ),
    ]) {
      expect(() => build(invalid), throwsFormatException);
    }
  });
}
