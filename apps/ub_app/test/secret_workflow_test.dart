@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_app/connection.dart';
import 'package:ub_app/connection_native.dart';
import 'package:ub_app/draft_record_choices.dart';
import 'package:ub_app/record_browser.dart';
import 'package:ub_app/saved_changes.dart';
import 'package:ub_app/secret_draft.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/local_engine.dart';
import 'package:ub_service/local_profiles.dart';
import 'package:ub_store/installation.dart';

void main() {
  test(
    'secret creation and revision recover, publish and retain history and time',
    () async {
      final root = Directory('/tmp').createTempSync('ub-secret-workflow-');
      final catalog = SqliteInstallationStore.create(root.path);
      final instance = catalog.instanceId;
      final profile = InstallationAuthority(catalog).initializeAuthor();
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
              name: 'Secrets',
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
          universe: const Selector('Secrets'),
          scope: scope,
        );
        Future<RecordVersion> publish(SavedDraft draft) async {
          final proposal = await changes().submit(draft);
          final validation =
              await changes().validate(proposal) as EvaluatedValidation;
          await changes().approve(proposal, validation);
          final receipt = await changes().publish(
            proposal,
            validation.execution.runId,
          );
          return (await changes().readPublished(proposal, receipt)).single;
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
        final form = UnfinishedSecretForm(
          baseRevision: initial.content.baseRevision,
          representedContext: scope.representedContext!,
          clientRef: RecordId.generate().value,
          scope: [
            ExpressionReferenceInput(
              record: scope.representedContext!.value,
              universe: scope.universe.value,
            ),
          ],
          readerDisclosed: false,
          hasConcealment: true,
          concealment: 'The heir learns later 記憶\r\n',
          rationale: 'Track the reveal.',
        );
        expect(
          () => secretOperation(
            UnfinishedSecretForm(
              baseRevision: form.baseRevision,
              representedContext: form.representedContext,
              clientRef: form.clientRef,
            ),
          ),
          throwsFormatException,
        );
        final draft = SavedDraft.fromWire(
          await session.call(
            secretDraftRequest(
              draft: initial,
              form: form,
              universe: const Selector('Secrets'),
              continuity: scope.continuity,
            ),
          ),
        );
        expect(
          secretDraftRequest(
            draft: draft,
            form: form,
            universe: const Selector('Secrets'),
            continuity: scope.continuity,
          ).content.toWire().toText(),
          draft.content.toWire().toText(),
        );
        final pendingScope = EditorFormScope(
          instance: instance,
          profile: profile,
          universe: scope.universe,
          continuity: scope.continuity,
          representedContext: scope.representedContext,
          typeClientRef: form.clientRef,
        );
        await session.saveSecretForm(
          pendingScope,
          secretFormFromDraft(draft, 0),
          BigInt.zero,
        );
        final published = await publish(draft);
        expect(
          published.payload.toWire().toText(),
          (secretOperation(form) as CreateSecretOperation).record
              .toWire()
              .toText(),
        );
        final next = await changes().rebase(
          (await changes().load())!,
          startNew: true,
        );
        final beforeContext = await readContextRecord(
          session: session,
          universe: LibraryEntry(scope.universe, 'Secrets'),
          context: await openDraftChoiceContext(changes(), next),
          record: scope.representedContext!,
        );
        final edit =
            secretFormFromRecord(
              record: published,
              baseRevision: next.content.baseRevision,
              representedContext: scope.representedContext!,
            ).copyWith(
              readerDisclosed: true,
              hasConcealment: false,
              rationale: 'Reveal the secret.',
            );
        final editScope = EditorFormScope(
          instance: instance,
          profile: profile,
          universe: scope.universe,
          continuity: scope.continuity,
          representedContext: scope.representedContext,
          typeClientRef: 'secret-revision:${edit.clientRef}',
        );
        await session.saveSecretForm(editScope, edit, BigInt.zero);
        await session.close();
        session = await device.connect();
        final recovered = (await session.loadSecretForm(editScope))!.form;
        expect(recovered.toWire().toText(), edit.toWire().toText());
        expect(
          (await session.loadSecretForm(pendingScope))!.form.revisionTarget,
          isNull,
        );
        final revisedDraft = SavedDraft.fromWire(
          await session.call(
            secretDraftRequest(
              draft: next,
              form: recovered,
              universe: const Selector('Secrets'),
              continuity: scope.continuity,
            ),
          ),
        );
        final reopened = secretFormFromDraft(revisedDraft, 0);
        expect(
          () => secretDraftRequest(
            draft: SavedDraft(
              version: revisedDraft.version + BigInt.one,
              content: revisedDraft.content,
            ),
            form: reopened,
            universe: const Selector('Secrets'),
            continuity: scope.continuity,
            index: 0,
          ),
          throwsFormatException,
        );
        final revised = await publish(revisedDraft);
        expect(revised.identity.recordId, published.identity.recordId);
        expect(
          revised.payload.toWire().toText(),
          (secretOperation(edit) as ReviseSecretOperation).replacement
              .toWire()
              .toText(),
        );
        final retained = await readContextRecord(
          session: session,
          universe: LibraryEntry(scope.universe, 'Secrets'),
          context: await openDraftChoiceContext(changes(), next),
          record: published.identity.recordId,
        );
        expect(retained.toWire().toText(), published.toWire().toText());
        final after = await changes().rebase(
          (await changes().load())!,
          startNew: true,
        );
        final afterContext = await readContextRecord(
          session: session,
          universe: LibraryEntry(scope.universe, 'Secrets'),
          context: await openDraftChoiceContext(changes(), after),
          record: scope.representedContext!,
        );
        expect(afterContext.toWire().toText(), beforeContext.toWire().toText());
      } finally {
        await session?.close();
        await server.close();
        root.deleteSync(recursive: true);
      }
    },
  );
}
