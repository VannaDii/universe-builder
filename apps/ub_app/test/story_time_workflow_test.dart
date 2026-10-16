@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_app/connection.dart';
import 'package:ub_app/connection_native.dart';
import 'package:ub_app/draft_record_choices.dart';
import 'package:ub_app/record_browser.dart';
import 'package:ub_app/saved_changes.dart';
import 'package:ub_app/story_time_draft.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/local_engine.dart';
import 'package:ub_service/local_profiles.dart';
import 'package:ub_store/installation.dart';

void main() {
  test('story-time fields recover, require explicit transitions and preserve clock history', () async {
    final root = Directory.systemTemp.createTempSync('ub-story-time-');
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
          CreateUniverseEngineRequest(
            realWorld: false,
            name: 'Clock',
            start: FictionalUniverseStart(
              calendarName: 'Campaign days',
              initialTick: '9007199254740993',
              tickLabel: 'days',
              ticksPerMonth: 30,
            ),
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
        universe: const Selector('Clock'),
        scope: scope,
      );
      final initial = SavedDraft(
        version: BigInt.zero,
        content: DraftContent(
          baseRevision: RevisionId.parse(created.string('revision')),
          representedContext: scope.representedContext!,
          operations: [],
          rationale: '',
        ),
      );
      Future<RecordVersion> read(SavedDraft draft) async => readContextRecord(
        session: session!,
        universe: LibraryEntry(scope.universe, 'Clock'),
        context: await openDraftChoiceContext(changes(), draft),
        record: scope.representedContext!,
      );
      final before = await read(initial);
      final fresh = storyTimeFormFromRecord(
        record: before,
        baseRevision: initial.content.baseRevision,
        representedContext: scope.representedContext!,
      );
      final partial = fresh.copyWith(
        value: '9007199254740',
        reason: '記憶 😀\r\n',
        rationale: 'Waiting for the exact date',
      );
      await session.saveStoryTimeForm(scope, partial, BigInt.zero);
      expect(() => storyTimeOperation(partial), throwsFormatException);
      await session.close();
      session = await device.connect();
      final recovered = (await session.loadStoryTimeForm(scope))!;
      expect(recovered.form.toWire().toText(), partial.toWire().toText());
      await expectLater(
        session.saveStoryTimeForm(
          scope,
          partial.copyWith(reason: 'Competing edit'),
          BigInt.zero,
        ),
        throwsA(isA<EditorRecoveryException>()),
      );
      final form = recovered.form.copyWith(
        value: '9007199254741023',
        mode: 'elapsed',
        reason: 'Thirty days passed. 記憶',
        rationale: 'Advance the authored campaign clock.',
      );
      expect(
        form.original.monthsAgo(form.original.current, 1),
        '9007199254740963',
      );
      expect(
        () => storyTimeOperation(form.copyWith(value: '9007199254740992')),
        throwsFormatException,
      );
      expect(
        () => storyTimeOperation(form.copyWith(reason: '')),
        throwsFormatException,
      );
      final saved = SavedDraft.fromWire(
        await session.call(
          storyTimeDraftRequest(
            draft: initial,
            form: form,
            universe: const Selector('Clock'),
            continuity: scope.continuity,
          ),
        ),
      );
      expect((await read(initial)).toWire().toText(), before.toWire().toText());
      final edited = storyTimeFormFromDraft(saved, 0, before);
      expect(
        storyTimeDraftRequest(
          draft: saved,
          form: form,
          universe: const Selector('Clock'),
          continuity: scope.continuity,
        ).content.toWire().toText(),
        saved.content.toWire().toText(),
      );
      expect(
        () => storyTimeDraftRequest(
          draft: saved,
          form: form.copyWith(value: '9007199254741053'),
          universe: const Selector('Clock'),
          continuity: scope.continuity,
        ),
        throwsFormatException,
      );
      expect(
        () => storyTimeDraftRequest(
          draft: saved,
          form: form,
          universe: const Selector('Clock'),
          continuity: scope.continuity,
          index: 0,
        ),
        throwsFormatException,
      );
      final changed = edited.copyWith(value: '9007199254741053');
      final updated = SavedDraft.fromWire(
        await session.call(
          storyTimeDraftRequest(
            draft: saved,
            form: changed,
            universe: const Selector('Clock'),
            continuity: scope.continuity,
            index: 0,
          ),
        ),
      );
      Future<void> publish(SavedDraft draft) async {
        final proposal = await changes().submit(draft);
        final validation =
            await changes().validate(proposal) as EvaluatedValidation;
        await changes().approve(proposal, validation);
        await changes().publish(proposal, validation.execution.runId);
      }

      await publish(updated);
      final next = await changes().rebase(
        (await changes().load())!,
        startNew: true,
      );
      final after = await read(next);
      final clock = (after.payload as RepresentedContextRecord).chronology!;
      expect(clock.current, '9007199254741053');
      expect(clock.firstInteraction, '9007199254740993');
      expect(after.identity.recordId, before.identity.recordId);
      expect((await read(initial)).toWire().toText(), before.toWire().toText());
      final travel =
          storyTimeFormFromRecord(
            record: after,
            baseRevision: next.content.baseRevision,
            representedContext: scope.representedContext!,
          ).copyWith(
            mode: 'time_travel',
            value: '-9007199254740993',
            reason: 'The party travels back explicitly.',
            rationale: 'Record the authored time jump.',
          );
      final jump = SavedDraft.fromWire(
        await session.call(
          storyTimeDraftRequest(
            draft: next,
            form: travel,
            universe: const Selector('Clock'),
            continuity: scope.continuity,
          ),
        ),
      );
      await publish(jump);
      final latest = await changes().rebase(
        (await changes().load())!,
        startNew: true,
      );
      expect(
        ((await read(latest)).payload as RepresentedContextRecord)
            .chronology!
            .current,
        '-9007199254740993',
      );
      expect((await read(next)).toWire().toText(), after.toWire().toText());
      final gregorian = const GregorianUniverseStart(
        '2042-01-31T12:00:00+05:30',
      ).build(CalendarId.generate()).$1;
      expect(
        () => gregorian.change(
          '2042-02-01T12:00:00',
          TimeChangeKind.elapsed,
          'Next day',
        ),
        throwsFormatException,
      );
      expect(
        gregorian
            .change(
              '2042-02-01T12:00:00+05:30',
              TimeChangeKind.elapsed,
              'Next day',
            )
            .display(gregorian.coordinate('2042-02-01T12:00:00+05:30')),
        '2042-02-01T12:00:00+05:30',
      );
    } finally {
      await session?.close();
      await server.close();
      root.deleteSync(recursive: true);
    }
  });
}
