@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_app/event_withdrawal_draft.dart';
import 'package:ub_app/event_draft.dart';
import 'package:ub_app/connection.dart';
import 'package:ub_app/connection_native.dart';
import 'package:ub_app/draft_record_choices.dart';
import 'package:ub_app/saved_changes.dart';
import 'package:ub_app/record_browser.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/installation.dart';
import 'package:ub_service/local_engine.dart';
import 'package:ub_service/local_profiles.dart';

void main() {
  test('occurrence withdrawal recovers and publishes with retained historical event', () async {
    final root = Directory('/tmp')
        .createTempSync('ub-event-withdrawal-workflow-');
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
            realWorld: false,
            name: 'Events',
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
        universe: Selector('Events'),
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
          rationale: 'Declare the journey resource.',
        ),
      );
      final gregorian = (await searchDraftChoices(
        changes: changes(),
        context: await openDraftChoiceContext(changes(), initial),
        kind: RecordKind.calendar,
        query: 'Gregorian',
      )).result.hits.single;
      final actionId = RecordId.generate();
      final payload = EventRecord(
        action: RecordRef(record: actionId, universe: scope.universe),
        occurrence: const SimpleOccurrence(OccurrenceKind.occurred),
        time: ExactTime(
          CalendarId.fromRecordId(gregorian.recordId),
          '9007199254740997',
        ),
        participants: [],
        labels: {'en': 'Arrival 記憶 😀'},
      );
      final sourceDraft = await changes().saveContent(
        initial,
        DraftContent(
          baseRevision: initial.content.baseRevision,
          representedContext: scope.representedContext!,
          operations: [
            DefineActionOperation(
              clientRef: actionId.value,
              record: ActionDefinitionRecord(
                namespace: 'authored',
                key: 'arrival',
                labels: {'en': 'Arrival action'},
                requirements: [],
                scope: Scope(
                  context: RecordRef(
                    record: scope.representedContext!,
                    universe: scope.universe,
                  ),
                  applicability: const UniverseApplicability(),
                ),
                validity: const UnspecifiedValidity(),
                consequenceContract: ConsequenceContract([]),
              ),
            ),
            RecordEventOperation(
              clientRef: RecordId.generate().value,
              record: payload,
            ),
          ],
          rationale: 'Record the authored occurrence.',
        ),
      );
      var published = (await publish(sourceDraft))
          .singleWhere((r) => r.payload is EventRecord);
      final revisionBase = await changes().rebase(
        (await changes().load())!,
        startNew: true,
      );
      final revisionScope = EditorFormScope(
        instance: scope.instance,
        profile: scope.profile,
        universe: scope.universe,
        continuity: scope.continuity,
        representedContext: scope.representedContext,
        typeClientRef: published.identity.recordId.value,
      );
      final sourceForm = eventRevisionFormFromRecord(
        record: published,
        baseRevision: revisionBase.content.baseRevision,
        representedContext: scope.representedContext!,
      );
      final revisionForm = UnfinishedEventForm.fromWire(
        CanonicalObject(
          sourceForm.toWire().fields.map(
            (e) => e.key == 'time'
                ? MapEntry(
                    'time',
                    sourceForm.time
                        .copyWith(
                          start: const TemporalBoundInput(
                            kind: 'exact',
                            value: '9007199254740999',
                          ),
                        )
                        .toWire(),
                  )
                : e.key == 'label'
                ? MapEntry('label', CanonicalString('Corrected arrival 記憶 😀'))
                : e.key == 'rationale'
                ? MapEntry(
                    'rationale',
                    CanonicalString(
                      'Correct the authored occurrence time and label.',
                    ),
                  )
                : e,
          ),
        ),
      );
      await session.saveEventForm(revisionScope, revisionForm, BigInt.zero);
      await session.close();
      session = await device.connect();
      final recoveredRevision = (await session.loadEventForm(revisionScope))!
          .form;
      expect(
        recoveredRevision.toWire().toText(),
        revisionForm.toWire().toText(),
      );
      final revisionDraft = SavedDraft.fromWire(
        await session.call(
          eventDraftRequest(
            draft: revisionBase,
            form: recoveredRevision,
            universe: const Selector('Events'),
            continuity: scope.continuity,
          ),
        ),
      );
      final revisedEvent = (await publish(revisionDraft)).single;
      expect(revisedEvent.identity.recordId, published.identity.recordId);
      expect(
        revisedEvent.payload.toWire().toText(),
        eventRevisionOperation(revisionForm).replacement.toWire().toText(),
      );
      final retainedEvent = await readContextRecord(
        session: session,
        universe: LibraryEntry(scope.universe, 'Events'),
        context: await openDraftChoiceContext(changes(), revisionBase),
        record: published.identity.recordId,
      );
      expect(retainedEvent.toWire().toText(), published.toWire().toText());
      published = revisedEvent;
      final withdrawalBase = await changes().rebase(
        (await changes().load())!,
        startNew: true,
      );
      final withdrawalScope = EditorFormScope(
        instance: scope.instance,
        profile: scope.profile,
        universe: scope.universe,
        continuity: scope.continuity,
        representedContext: scope.representedContext,
        typeClientRef: published.identity.recordId.value,
      );
      final withdrawalForm = eventWithdrawalFormFromRecord(
        record: published,
        baseRevision: withdrawalBase.content.baseRevision,
        representedContext: scope.representedContext!,
      ).copyWith(rationale: 'Withdraw the mistaken occurrence 記憶 😀.');
      await session.saveEventWithdrawalForm(
        withdrawalScope,
        withdrawalForm,
        BigInt.zero,
      );
      await session.close();
      session = await device.connect();
      final recovered = (await session.loadEventWithdrawalForm(
        withdrawalScope,
      ))!.form;
      expect(recovered.toWire().toText(), withdrawalForm.toWire().toText());
      final withdrawalDraft = SavedDraft.fromWire(
        await session.call(
          eventWithdrawalDraftRequest(
            draft: withdrawalBase,
            form: recovered,
            universe: const Selector('Events'),
            continuity: scope.continuity,
          ),
        ),
      );
      expect(await publish(withdrawalDraft), isEmpty);
      final retained = await readContextRecord(
        session: session,
        universe: LibraryEntry(scope.universe, 'Events'),
        context: await openDraftChoiceContext(changes(), withdrawalBase),
        record: published.identity.recordId,
      );
      expect(retained.toWire().toText(), published.toWire().toText());
      final after = await changes().rebase(
        (await changes().load())!,
        startNew: true,
      );
      final events = await searchDraftChoices(
        changes: changes(),
        context: await openDraftChoiceContext(changes(), after),
        kind: RecordKind.event,
      );
      expect(events.result.hits, isEmpty);
    } finally {
      await session?.close();
      await server.close();
      root.deleteSync(recursive: true);
    }
  });
}
