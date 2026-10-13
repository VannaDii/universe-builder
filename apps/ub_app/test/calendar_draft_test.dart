@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_app/calendar_draft.dart';
import 'package:ub_app/connection.dart';
import 'package:ub_app/connection_native.dart';
import 'package:ub_app/draft_record_choices.dart';
import 'package:ub_app/record_browser.dart';
import 'package:ub_app/saved_changes.dart';
import 'package:ub_app/temporal_validity_draft.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/editor_forms.dart';
import 'package:ub_store/installation.dart';
import 'package:ub_service/local_engine.dart';
import 'package:ub_service/local_profiles.dart';

void main() {
  test('calendar edits preserve empty versus absent values and exact conversion order', () {
    final target = CalendarId.generate();
    for (final epoch in [null, '', 'Origin 記憶 😀']) {
      final calendar = CalendarRecord(
        namespace: 'authored',
        key: 'calendar',
        labels: {'en': 'Calendar', '': 'Authored label'},
        epoch: epoch,
        unitStructure: {
          '': 'Authored unnamed unit',
          'month': '30 days',
          'year': '12 months 記憶 😀',
        },
        conversions: [
          CalendarConversion(target: target, valid: false),
          CalendarConversion(target: target, expression: '', valid: true),
          CalendarConversion(
            target: target,
            expression: '記憶 😀 mapping',
            valid: false,
          ),
        ],
      );
      final op = DefineCalendarOperation(
        clientRef: RecordId.generate().value,
        record: calendar,
      );
      final other = CreateWorldOperation(
        clientRef: 'river',
        record: WorldRecord(selector: 'River'),
      );
      final draft = SavedDraft(
        version: BigInt.two,
        content: DraftContent(
          baseRevision: RevisionId.generate(),
          representedContext: RecordId.generate(),
          operations: [other, op],
          rationale: 'Exact rationale',
        ),
      );
      final form = calendarFormFromDraft(draft, 1);
      final recovered = UnfinishedCalendarForm.fromWire(form.toWire());
      expect(
        calendarOperation(recovered).toWire().toText(),
        op.toWire().toText(),
      );
      final exact = calendarDraftRequest(
        draft: draft,
        form: recovered,
        universe: Selector('Universe'),
        continuity: ContinuityId.generate(),
        index: 1,
      );
      expect(exact.content.toWire().toText(), draft.content.toWire().toText());
      final changed = UnfinishedCalendarForm(
        baseRevision: form.baseRevision,
        representedContext: form.representedContext,
        clientRef: form.clientRef,
        namespace: form.namespace,
        key: form.key,
        labels: form.labels,
        hasEpoch: form.hasEpoch,
        epoch: form.epoch,
        units: form.units,
        conversions: form.conversions.reversed,
        draftVersion: form.draftVersion,
      );
      final replaced = calendarDraftRequest(
        draft: draft,
        form: changed,
        universe: Selector('Universe'),
        continuity: ContinuityId.generate(),
        index: 1,
      );
      final edited =
          (replaced.content.operations[1] as DefineCalendarOperation).record;
      expect(
        edited.conversions.map((c) => c.toWire().toText()),
        calendar.conversions.reversed.map((c) => c.toWire().toText()),
      );
      expect(edited.epoch, epoch);
      expect(
        replaced.content.operations.first.toWire().toText(),
        other.toWire().toText(),
      );
      expect(replaced.content.rationale, draft.content.rationale);
      expect(
        () => calendarDraftRequest(
          draft: SavedDraft(version: BigInt.from(3), content: draft.content),
          form: changed,
          universe: Selector('Universe'),
          continuity: ContinuityId.generate(),
          index: 1,
        ),
        throwsFormatException,
      );
    }
  });
  test('unfinished calendar unit entries and conversion references recover exactly', () {
    final root = Directory('/tmp').createTempSync('ub-calendar-cache-');
    final scope = EditorFormScope(
      instance: OperationId.generate(),
      profile: ProfileId.generate(),
      universe: UniverseId.generate(),
      continuity: ContinuityId.generate(),
      representedContext: RecordId.generate(),
    );
    final form = UnfinishedCalendarForm(
      baseRevision: RevisionId.generate(),
      representedContext: scope.representedContext!,
      clientRef: RecordId.generate().value,
      namespace: 'authored',
      key: 'incomplete',
      hasEpoch: true,
      epoch: 'unfinished epoch 記憶 😀',
      units: [
        const CalendarUnitInput(
          name: 'month',
          structure: 'unfinished structure',
        ),
        const CalendarUnitInput(
          name: 'month',
          structure: 'another unfinished structure',
        ),
      ],
      conversions: [
        const CalendarConversionInput(
          target: 'unfinished calendar',
          hasExpression: true,
          expression: 'unfinished expression 記憶 😀',
          valid: true,
        ),
      ],
    );
    var store = CalendarFormRecoveryStore.open('${root.path}/forms.sqlite');
    try {
      store.save(scope, form, BigInt.zero);
      store.close();
      store = CalendarFormRecoveryStore.open('${root.path}/forms.sqlite');
      expect(store.load(scope)!.form.toWire().toText(), form.toWire().toText());
      expect(store.save(scope, form, BigInt.zero).generation, BigInt.one);
      expect(() => calendarOperation(form), throwsFormatException);
      final competing = UnfinishedCalendarForm(
        baseRevision: form.baseRevision,
        representedContext: form.representedContext,
        clientRef: form.clientRef,
        namespace: 'competing',
      );
      expect(
        () => store.save(scope, competing, BigInt.zero),
        throwsA(isA<EditorRecoveryException>()),
      );
      final editScope = EditorFormScope(
        instance: scope.instance,
        profile: scope.profile,
        universe: scope.universe,
        continuity: scope.continuity,
        representedContext: scope.representedContext,
        typeClientRef: form.clientRef,
      );
      expect(store.load(editScope), isNull);
    } finally {
      store.close();
      root.deleteSync(recursive: true);
    }
  });
  test('calendar form recovers and publishes explicit metadata without changing the represented story clock', () async {
    final root = Directory('/tmp').createTempSync('ub-calendar-workflow-');
    final catalog = SqliteInstallationStore.create(root.path);
    final instance = catalog.instanceId,
        profile = InstallationAuthority(catalog).initializeAuthor();
    catalog.close();
    final server = await LocalSqliteEngineServer.start(
      root.path,
      compatibilitySocket: false,
    );
    AppSession? session;
    try {
      final device = DeviceConnection([
        '--installation',
        root.path,
        '--profile',
        profile.value,
        '--engine=/nonexistent/universe-engine',
      ]);
      session = await device.connect();
      final created = WireFields(
        await session.call(
          const CreateUniverseEngineRequest(
            name: 'Calendars',
            start: GregorianUniverseStart('2040-01-01T00:00:00Z'),
          ),
        ),
        {'universe_id', 'continuity_id', 'context_id', 'revision', 'name'},
      );
      final scope = EditorFormScope(
        instance: instance,
        profile: profile,
        universe: UniverseId.parse(created.string('universe_id')),
        continuity: ContinuityId.parse(created.string('continuity_id')),
        representedContext: RecordId.parse(created.string('context_id')),
      );
      SavedChanges changes() => SavedChanges(
        session: session!,
        universe: Selector('Calendars'),
        scope: scope,
      );
      Future<List<RecordVersion>> publish(SavedDraft draft) async {
        final proposal = await changes().submit(draft);
        final validation =
            await changes().validate(proposal) as EvaluatedValidation;
        await changes().approve(proposal, validation);
        final receipt = await changes().publish(
          proposal,
          validation.execution.runId,
        );
        return changes().readPublished(proposal, receipt);
      }

      final initial = SavedDraft(
        version: BigInt.zero,
        content: DraftContent(
          baseRevision: RevisionId.parse(created.string('revision')),
          representedContext: scope.representedContext!,
          operations: [],
          rationale: '',
        ),
      );
      Future<RecordVersion> storyContext(SavedDraft draft) async =>
          readContextRecord(
            session: session!,
            universe: LibraryEntry(scope.universe, 'Calendars'),
            context: await openDraftChoiceContext(changes(), draft),
            record: scope.representedContext!,
          );
      final before = await storyContext(initial);
      final base = UnfinishedCalendarForm(
        baseRevision: initial.content.baseRevision,
        representedContext: scope.representedContext!,
        clientRef: RecordId.generate().value,
        namespace: 'authored',
        key: 'campaign-calendar',
        labels: [
          const PropertyLabelInput(
            language: 'en',
            text: 'Campaign calendar 記憶 😀',
          ),
        ],
        rationale: 'Declare an independent campaign calendar.',
      );
      await session.saveCalendarForm(scope, base, BigInt.zero);
      await session.close();
      session = await device.connect();
      final recovered = (await session.loadCalendarForm(scope))!.form;
      expect(recovered.toWire().toText(), base.toWire().toText());
      final saved = SavedDraft.fromWire(
        await session.call(
          calendarDraftRequest(
            draft: initial,
            form: recovered,
            universe: Selector('Calendars'),
            continuity: scope.continuity,
          ),
        ),
      );
      expect(
        calendarDraftRequest(
          draft: saved,
          form: recovered,
          universe: Selector('Calendars'),
          continuity: scope.continuity,
        ).content.toWire().toText(),
        saved.content.toWire().toText(),
      );
      final published = (await publish(saved)).single;
      expect(
        published.payload.toWire().toText(),
        calendarOperation(base).record.toWire().toText(),
      );
      var next = await changes().rebase(
        (await changes().load())!,
        startNew: true,
      );
      final found = await searchDraftChoices(
        changes: changes(),
        context: await openDraftChoiceContext(changes(), next),
        kind: RecordKind.calendar,
        query: 'Campaign',
      );
      expect(found.result.hits.single.label, 'Campaign calendar 記憶 😀');
      final chosen = await selectDraftChoice(
        changes: changes(),
        context: await openDraftChoiceContext(changes(), next),
        hit: found.result.hits.single,
        kind: RecordKind.calendar,
      );
      final target = calendarFromChoice(chosen);
      expect(calendarChoiceRecord(target.value), published.identity.recordId);
      expect(
        () => calendarChoiceRecord('unfinished calendar'),
        throwsFormatException,
      );
      // Selecting a calendar changes only its reference, not authored coordinates,
      // bounds, exact amounts or relative targets.
      final oldCalendar = CalendarId.generate();
      for (final validity in <Validity>[
        InstantValidity(ExactTime(oldCalendar, 'Year 4 / 記憶 😀')),
        InstantValidity(
          IntervalTime(
            oldCalendar,
            const UnknownBound(),
            const ExactBound('Harvest'),
          ),
        ),
        InstantValidity(
          ApproximateTime(oldCalendar, 'Harvest', RationalValue('3', '2')),
        ),
        InstantValidity(DurationTime(oldCalendar, DecimalValue('1.500'))),
        InstantValidity(
          RelativeTime(
            oldCalendar,
            TemporalRelation.after,
            RecordRef(record: published.identity.recordId),
          ),
        ),
        CalendarIntervalValidity(
          oldCalendar,
          const UnboundedBound(),
          const ExactBound('Year 5'),
        ),
      ]) {
        final input = temporalValidityInput(validity);
        final changed = input.copyWith(calendar: target.value);
        final restored = TemporalValidityInput.fromWire(changed.toWire());
        expect(restored.start.toWire().toText(), input.start.toWire().toText());
        expect(restored.end.toWire().toText(), input.end.toWire().toText());
        expect(restored.targetRecord, input.targetRecord);
        expect(restored.targetUniverse, input.targetUniverse);
        expect(restored.relation, input.relation);
        final built = buildTemporalValidity(restored, validity);
        expect(temporalValidityInput(built).calendar, target.value);
        expect(
          buildTemporalValidity(
            restored.copyWith(calendar: oldCalendar.value),
            validity,
          ).toWire().toText(),
          validity.toWire().toText(),
        );
      }

      final derived = UnfinishedCalendarForm(
        baseRevision: next.content.baseRevision,
        representedContext: base.representedContext,
        clientRef: RecordId.generate().value,
        namespace: 'authored',
        key: 'regional-calendar',
        labels: [
          const PropertyLabelInput(language: 'en', text: 'Regional calendar'),
        ],
        hasEpoch: true,
        epoch: '',
        units: [
          const CalendarUnitInput(name: 'month', structure: '30 days'),
          const CalendarUnitInput(name: 'year', structure: '12 months 記憶 😀'),
        ],
        conversions: [
          CalendarConversionInput(target: target.value),
          CalendarConversionInput(
            target: target.value,
            hasExpression: true,
            expression: '',
            valid: true,
          ),
        ],
        rationale: 'Declare authored calendar metadata.',
      );
      final derivedDraft = SavedDraft.fromWire(
        await session.call(
          calendarDraftRequest(
            draft: next,
            form: derived,
            universe: Selector('Calendars'),
            continuity: scope.continuity,
          ),
        ),
      );
      final derivedRecord =
          (await publish(derivedDraft)).single.payload as CalendarRecord;
      expect(
        derivedRecord.toWire().toText(),
        calendarOperation(derived).record.toWire().toText(),
      );
      expect(derivedRecord.conversions.map((c) => c.target), [target, target]);
      expect(derivedRecord.conversions.map((c) => c.expression), [null, '']);
      next = await changes().rebase((await changes().load())!, startNew: true);
      final after = await storyContext(next);
      expect(after.recordVersionId, before.recordVersionId);
      expect(after.payload.toWire().toText(), before.payload.toWire().toText());
    } finally {
      await session?.close();
      await server.close();
      root.deleteSync(recursive: true);
    }
  });
}
