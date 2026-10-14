@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_app/record_removal_draft.dart';
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
  test('record removal recovers and publishes while retaining history and unrelated records', () async {
    final root = Directory('/tmp')
        .createTempSync('ub-record-removal-workflow-');
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
            name: 'Removal',
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
        universe: Selector('Removal'),
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
      final sourceDraft = await changes().saveContent(
        initial,
        DraftContent(
          baseRevision: initial.content.baseRevision,
          representedContext: scope.representedContext!,
          operations: [
            CreateWorldOperation(
              clientRef: RecordId.generate().value,
              record: WorldRecord(selector: 'Discarded world 記憶 😀'),
            ),
            CreateWorldOperation(
              clientRef: RecordId.generate().value,
              record: WorldRecord(selector: 'Retained world'),
            ),
          ],
          rationale: 'Declare the authored worlds.',
        ),
      );
      final publishedRecords = await publish(sourceDraft);
      final published = publishedRecords.singleWhere(
        (r) => (r.payload as WorldRecord).selector == 'Discarded world 記憶 😀',
      );
      final retainedWorld = publishedRecords.singleWhere(
        (r) => (r.payload as WorldRecord).selector == 'Retained world',
      );
      final removalBase = await changes().rebase(
        (await changes().load())!,
        startNew: true,
      );
      final removalScope = EditorFormScope(
        instance: scope.instance,
        profile: scope.profile,
        universe: scope.universe,
        continuity: scope.continuity,
        representedContext: scope.representedContext,
        typeClientRef: published.identity.recordId.value,
      );
      final removalForm =
          recordRemovalFormFromRecord(
            record: published,
            baseRevision: removalBase.content.baseRevision,
            representedContext: scope.representedContext!,
          ).copyWith(
            rationale: 'Remove the unused world 記憶 😀 from current canon.',
          );
      await session.saveRecordRemovalForm(
        removalScope,
        removalForm,
        BigInt.zero,
      );
      await session.close();
      session = await device.connect();
      final recovered = (await session.loadRecordRemovalForm(removalScope))!
          .form;
      expect(recovered.toWire().toText(), removalForm.toWire().toText());
      final removalDraft = SavedDraft.fromWire(
        await session.call(
          recordRemovalDraftRequest(
            draft: removalBase,
            form: recovered,
            universe: const Selector('Removal'),
            continuity: scope.continuity,
          ),
        ),
      );
      expect(await publish(removalDraft), isEmpty);
      final retained = await readContextRecord(
        session: session,
        universe: LibraryEntry(scope.universe, 'Removal'),
        context: await openDraftChoiceContext(changes(), removalBase),
        record: published.identity.recordId,
      );
      expect(retained.toWire().toText(), published.toWire().toText());
      final after = await changes().rebase(
        (await changes().load())!,
        startNew: true,
      );
      final current = await openDraftChoiceContext(changes(), after);
      final worlds = await searchDraftChoices(
        changes: changes(),
        context: current,
        kind: RecordKind.world,
      );
      expect(worlds.result.hits.map((hit) => hit.recordId), [
        retainedWorld.identity.recordId,
      ]);
      final other = await readContextRecord(
        session: session,
        universe: LibraryEntry(scope.universe, 'Removal'),
        context: current,
        record: retainedWorld.identity.recordId,
      );
      expect(other.toWire().toText(), retainedWorld.toWire().toText());
    } finally {
      await session?.close();
      await server.close();
      root.deleteSync(recursive: true);
    }
  });
}
