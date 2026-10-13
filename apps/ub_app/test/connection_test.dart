@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart' hide Description;
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/local_engine.dart';
import 'package:ub_service/local_profiles.dart';
import 'package:ub_store/installation.dart';
import 'package:ub_store/profile_credentials.dart';

import 'package:ub_app/connection.dart';
import 'package:ub_app/connection_native.dart';
import 'package:ub_app/universe_creation.dart';
import 'package:ub_app/world_draft.dart';
import 'package:ub_app/saved_changes.dart';

void main() {
  test('app connects to the existing engine and reads only its accessible library', () async {
    final root = Directory('/tmp').createTempSync('ub-app-');
    final store = SqliteInstallationStore.create(root.path);
    final authority = InstallationAuthority(store);
    final author = authority.initializeAuthor();
    final writer = authority.enroll(
      authority.authenticateHello(
        EngineHello(
          protocolVersion: protocolVersion,
          profileId: author,
          credential: Credential(
            ProfileCredentialStore.read(root: root.path, profile: author),
          ),
          clientName: 'Disposable app setup',
        ),
      ),
    );
    store.close();
    final server = await LocalSqliteEngineServer.start(
      root.path,
      compatibilitySocket: false,
    );
    AppSession? owner, contributor;
    DeviceConnection connection(ProfileId profile) => DeviceConnection([
      '--installation=${root.path}',
      '--profile',
      profile.value,
      '--engine=/nonexistent/universe-engine',
    ]);
    try {
      expect(DeviceConnection(['--installation=']).available, isFalse);
      owner = await connection(author).connect();
      expect(owner.author, isTrue);
      expect(
        InstanceLibrary.fromWire(await owner.call(const StatusEngineRequest()))
            .universes,
        isEmpty,
      );
      await owner.call(
        const UniverseCreationForm(
          name: 'A shared history',
          calendar: CreationCalendar.gregorian,
          date: '2040-01-01',
          time: '00:00:00',
          offset: '+05:30',
        ).request(),
      );
      final catalog = InstanceLibrary.fromWire(
        await owner.call(const StatusEngineRequest()),
      );
      expect(catalog.universes.single.name, 'A shared history');
      final description = Envelope<Description>.fromWire(
        await owner.call(
          ToolEngineRequest(
            request: DescribeSummaryRequest(
              universe: Selector('A shared history'),
            ),
          ),
        ),
        Description.fromWire,
      );
      expect(description.result.continuities, isNotEmpty);
      final continuity = description.result.continuities.single;
      final scope = EditorFormScope(
        instance: catalog.instance,
        profile: owner.principal,
        universe: catalog.universes.single.id,
        continuity: continuity.id,
      );
      final unfinished = UnfinishedWorldForm(
        baseRevision: continuity.revisionId,
        representedContext: continuity.representedContexts.single.id,
        record: RecordId.generate(),
        selector: '',
        settingType: 'Still deciding',
        rationale: 'Source notes 😀\r\n',
      );
      final saved = await owner.saveWorldForm(scope, unfinished, BigInt.zero);
      expect(saved.generation, BigInt.one);
      await owner.close();
      owner = await connection(author).connect();
      final recovered = await owner.loadWorldForm(scope);
      expect(recovered!.form.toWire().toText(), unfinished.toWire().toText());
      expect(
        (await owner.saveWorldForm(scope, unfinished, BigInt.zero)).generation,
        BigInt.one,
      );
      await owner.close();
      expect(
        (await owner.saveWorldForm(scope, unfinished, BigInt.one)).generation,
        BigInt.two,
      );
      owner = await connection(author).connect();
      expect((await owner.loadWorldForm(scope))!.generation, BigInt.two);
      final afterRecovery = Envelope<Description>.fromWire(
        await owner.call(
          ToolEngineRequest(
            request: DescribeSummaryRequest(
              universe: Selector('A shared history'),
            ),
          ),
        ),
        Description.fromWire,
      );
      expect(afterRecovery.result.worlds, isEmpty);
      expect(
        afterRecovery.result.continuities.single.revisionId,
        continuity.revisionId,
      );
      final completed = UnfinishedWorldForm(
        baseRevision: unfinished.baseRevision,
        representedContext: unfinished.representedContext,
        record: unfinished.record,
        selector: 'A river world',
        settingType: unfinished.settingType,
        rationale: unfinished.rationale,
      );
      final draftRequest = worldDraftRequest(
        universe: Selector('A shared history'),
        continuity: continuity.id,
        form: completed,
        previous: null,
      );
      final added = SavedDraft.fromWire(await owner.call(draftRequest));
      expect(added.version, BigInt.one);
      final loadedDraft = SavedDraft.fromWire(
        await owner.call(
          LoadDraftEngineRequest(
            universe: Selector('A shared history'),
            continuityId: continuity.id,
          ),
        ),
      );
      final retry = worldDraftRequest(
        universe: Selector('A shared history'),
        continuity: continuity.id,
        form: completed,
        previous: loadedDraft,
      );
      expect(retry.content.toWire().toText(), added.content.toWire().toText());
      expect(retry.content.operations, hasLength(1));
      final afterAdding = Envelope<Description>.fromWire(
        await owner.call(
          ToolEngineRequest(
            request: DescribeSummaryRequest(
              universe: Selector('A shared history'),
            ),
          ),
        ),
        Description.fromWire,
      );
      expect(afterAdding.result.worlds, isEmpty);
      expect(
        afterAdding.result.continuities.single.revisionId,
        continuity.revisionId,
      );
      // More than one frozen review page, with an interrupted draft-link save.
      var largerDraft = SavedDraft.fromWire(
        await owner.call(
          SaveDraftEngineRequest(
            universe: Selector('A shared history'),
            continuityId: continuity.id,
            expectedVersion: added.version,
            content: DraftContent(
              baseRevision: added.content.baseRevision,
              representedContext: added.content.representedContext,
              operations: [
                ...added.content.operations,
                for (var n = 0; n < 24; n++)
                  CreateWorldOperation(
                    clientRef: RecordId.generate().value,
                    record: WorldRecord(selector: 'World $n'),
                  ),
              ],
              rationale: '',
            ),
          ),
        ),
      );
      final rationaleChanges = SavedChanges(
        session: owner,
        universe: Selector('A shared history'),
        scope: scope,
      );
      await expectLater(
        rationaleChanges.submit(largerDraft),
        throwsA(
          isA<InvalidArgumentError>().having(
            (error) => error.field,
            'required rationale',
            contains('rationale'),
          ),
        ),
      );
      final withoutRationale = largerDraft;
      largerDraft = await rationaleChanges.saveRationale(
        largerDraft,
        'Explain all worlds.\nPreserve authored notes.',
      );
      expect(largerDraft.content.operations, hasLength(25));
      expect(
        largerDraft.content.rationale,
        'Explain all worlds.\nPreserve authored notes.',
      );
      await expectLater(
        rationaleChanges.saveRationale(withoutRationale, 'Stale notes'),
        throwsA(isA<BaseRevisionConflictError>()),
      );
      final active = owner;
      final interrupted = AppSession(
        call: (request) {
          if (request is SaveDraftEngineRequest) {
            throw const FormatException('Disposable interrupted link save');
          }
          return active.call(request);
        },
        close: active.close,
        author: active.author,
        principal: active.principal,
        loadWorldForm: active.loadWorldForm,
        saveWorldForm: active.saveWorldForm,
      );
      await expectLater(
        SavedChanges(
          session: interrupted,
          universe: Selector('A shared history'),
          scope: scope,
        ).submit(largerDraft),
        throwsFormatException,
      );
      await owner.close();
      owner = await connection(author).connect();
      final changes = SavedChanges(
        session: owner,
        universe: Selector('A shared history'),
        scope: scope,
      );
      final recoveredProposal = (await changes.recover(largerDraft))!;
      expect(recoveredProposal.submission, Submission.submitted);
      expect(recoveredProposal.operations, hasLength(25));
      expect(recoveredProposal.compiledChanges, hasLength(25));
      expect((await changes.load())!.content.proposal, isNull);
      final relinked = await changes.submit(largerDraft);
      expect(relinked.proposalId, recoveredProposal.proposalId);
      final linked = (await changes.load())!;
      expect(linked.version, largerDraft.version + BigInt.one);
      expect(linked.content.proposal!.digest, recoveredProposal.digest);
      expect((await changes.recover(linked))!.compiledChanges, hasLength(25));
      final afterSubmitting = Envelope<Description>.fromWire(
        await owner.call(
          ToolEngineRequest(
            request: DescribeSummaryRequest(
              universe: Selector('A shared history'),
            ),
          ),
        ),
        Description.fromWire,
      );
      expect(afterSubmitting.result.worlds, isEmpty);
      expect(
        afterSubmitting.result.continuities.single.revisionId,
        continuity.revisionId,
      );
      final openedForChecks = Envelope<OpenedContext>.fromWire(
        await owner.call(
          ToolEngineRequest(
            request: OpenContextRequest(
              universe: Selector('A shared history'),
              continuityId: continuity.id,
              revision: ExactRevisionSelector(
                revisionId: continuity.revisionId,
              ),
              representedContext: ContextIdSelector(
                completed.representedContext,
              ),
              temporalQuery: const TimelessFrameTime(),
              temporalSystems: [],
              perspective: const AuthorPerspective(),
            ),
          ),
        ),
        OpenedContext.fromWire,
      ).result;
      final ref = linked.content.proposal!;
      final validation =
          Envelope<ValidationV3>.fromWire(
                await owner.call(
                  ToolEngineRequest(
                    request: ProposalValidationRequest(
                      universe: Selector('A shared history'),
                      contextId: openedForChecks.contextId,
                      proposalReference: ref,
                      checkScope: CheckScope.universe,
                    ),
                  ),
                ),
                ValidationV3.fromWire,
              ).result
              as EvaluatedValidation;
      await owner.call(
        ApproveEngineRequest(
          universe: Selector('A shared history'),
          proposalReference: ref,
          validationRun: validation.execution.runId,
        ),
      );
      final receipt = Envelope<CommitReceipt>.fromWire(
        await owner.call(
          ToolEngineRequest(
            request: CommitRequest(
              universe: Selector('A shared history'),
              proposalReference: ref,
              expectedBaseRevision: continuity.revisionId,
              validationRun: validation.execution.runId,
              idempotencyKey: 'disposable-app-publish',
            ),
          ),
        ),
        CommitReceipt.fromWire,
      ).result;
      final original = recoveredProposal.compiledChanges.first.next!;
      final changedDraft = SavedDraft.fromWire(
        await owner.call(
          SaveDraftEngineRequest(
            universe: Selector('A shared history'),
            continuityId: continuity.id,
            expectedVersion: linked.version,
            content: DraftContent(
              baseRevision: receipt.revision,
              representedContext: completed.representedContext,
              operations: [
                RenameWorldSelectorOperation(
                  record: RecordRef(
                    universe: scope.universe,
                    record: original.identity.recordId,
                  ),
                  expectedVersion: original.recordVersionId,
                  newSelector: 'Renamed world',
                ),
              ],
              rationale: 'Explicit name change',
            ),
          ),
        ),
      );
      final renamed = await changes.submit(changedDraft);
      final oldRecords = await changes.before(renamed);
      expect(
        oldRecords.values.single.recordVersionId,
        original.recordVersionId,
      );
      expect(
        (oldRecords.values.single.payload as WorldRecord).selector,
        (original.payload as WorldRecord).selector,
      );
      expect(
        (renamed.compiledChanges.single.next!.payload as WorldRecord).selector,
        'Renamed world',
      );
      final fictional = createdUniverse(
        await owner.call(
          const UniverseCreationForm(
            name: 'Before the first age',
            calendar: CreationCalendar.fictional,
            calendarName: 'Ages',
            initialTick: '-123456789012345678901234567890',
            tickLabel: 'beat',
          ).request(),
        ),
      );
      expect(fictional.name, 'Before the first age');
      expect(
        InstanceLibrary.fromWire(await owner.call(const StatusEngineRequest()))
            .universes
            .map((row) => row.id),
        contains(fictional.id),
      );
      contributor = await connection(writer).connect();
      expect(contributor.author, isFalse);
      await expectLater(
        contributor.loadWorldForm(scope),
        throwsA(isA<NotFoundOrNotAccessibleError>()),
      );
      await expectLater(
        contributor.loadWorldForm(
          EditorFormScope(
            instance: scope.instance,
            profile: contributor.principal,
            universe: scope.universe,
            continuity: scope.continuity,
          ),
        ),
        throwsA(isA<NotFoundOrNotAccessibleError>()),
      );
      await expectLater(
        owner.loadWorldForm(
          EditorFormScope(
            instance: OperationId.generate(),
            profile: scope.profile,
            universe: scope.universe,
            continuity: scope.continuity,
          ),
        ),
        throwsA(isA<NotFoundOrNotAccessibleError>()),
      );
      await expectLater(
        contributor.call(
          const UniverseCreationForm(
            name: 'Not permitted',
            calendar: CreationCalendar.gregorian,
            date: '2040-01-01',
            time: '00:00:00',
            offset: 'Z',
          ).request(),
        ),
        throwsA(isA<ProtocolError>()),
      );
      expect(
        InstanceLibrary.fromWire(
          await contributor.call(const StatusEngineRequest()),
        ).universes,
        isEmpty,
      );
    } finally {
      await contributor?.close();
      await owner?.close();
      await server.close();
      root.deleteSync(recursive: true);
    }
  });
}
