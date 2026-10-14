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
import 'package:ub_app/access_management.dart';
import 'package:ub_app/connection_native.dart';
import 'package:ub_app/universe_creation.dart';
import 'package:ub_app/world_draft.dart';
import 'package:ub_app/saved_changes.dart';
import 'package:ub_app/world_browser.dart';

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
      expect(catalog.backend, ConnectedBackend.sqlite);
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
      expect(
        selectedRepresentedContext(continuity, null)!.id,
        continuity.representedContexts.single.id,
      );
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
        loadTypeForm: active.loadTypeForm,
        saveTypeForm: active.saveTypeForm,
        loadPropertyForm: active.loadPropertyForm,
        savePropertyForm: active.savePropertyForm,
        loadUnitForm: active.loadUnitForm,
        saveUnitForm: active.saveUnitForm,
        loadValueDefinitionForm: active.loadValueDefinitionForm,
        saveValueDefinitionForm: active.saveValueDefinitionForm,
        loadRelationForm: active.loadRelationForm,
        saveRelationForm: active.saveRelationForm,
        loadRuleForm: active.loadRuleForm,
        saveRuleForm: active.saveRuleForm,
        loadActionForm: active.loadActionForm,
        saveActionForm: active.saveActionForm,
        loadEventForm: active.loadEventForm,
        saveEventForm: active.saveEventForm,
        loadSourceForm: active.loadSourceForm,
        saveSourceForm: active.saveSourceForm,
        loadCalendarForm: active.loadCalendarForm,
        saveCalendarForm: active.saveCalendarForm,
        loadEntityForm: active.loadEntityForm,
        saveEntityForm: active.saveEntityForm,
        loadAttributeForm: active.loadAttributeForm,
        saveAttributeForm: active.saveAttributeForm,
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
      final validation =
          await changes.validate(recoveredProposal) as EvaluatedValidation;
      expect(validation.execution.coverage, Coverage.complete);
      await expectLater(
        changes.publish(recoveredProposal, validation.execution.runId),
        throwsA(isA<ApprovalRequiredError>()),
      );
      await changes.approve(recoveredProposal, validation);
      final afterApproval = Envelope<Description>.fromWire(
        await owner.call(
          ToolEngineRequest(
            request: DescribeSummaryRequest(
              universe: Selector('A shared history'),
            ),
          ),
        ),
        Description.fromWire,
      );
      expect(afterApproval.result.worlds, isEmpty);
      final publishingSession = owner;
      final interruptedPublication = AppSession(
        call: (request) async {
          final response = await publishingSession.call(request);
          if (request is ToolEngineRequest &&
              request.request is CommitRequest) {
            throw const FormatException('Disposable lost publication response');
          }
          return response;
        },
        close: publishingSession.close,
        author: publishingSession.author,
        principal: publishingSession.principal,
        loadWorldForm: publishingSession.loadWorldForm,
        saveWorldForm: publishingSession.saveWorldForm,
        loadTypeForm: publishingSession.loadTypeForm,
        saveTypeForm: publishingSession.saveTypeForm,
        loadPropertyForm: publishingSession.loadPropertyForm,
        savePropertyForm: publishingSession.savePropertyForm,
        loadUnitForm: publishingSession.loadUnitForm,
        saveUnitForm: publishingSession.saveUnitForm,
        loadValueDefinitionForm: publishingSession.loadValueDefinitionForm,
        saveValueDefinitionForm: publishingSession.saveValueDefinitionForm,
        loadRelationForm: publishingSession.loadRelationForm,
        saveRelationForm: publishingSession.saveRelationForm,
        loadRuleForm: publishingSession.loadRuleForm,
        saveRuleForm: publishingSession.saveRuleForm,
        loadActionForm: publishingSession.loadActionForm,
        saveActionForm: publishingSession.saveActionForm,
        loadEventForm: publishingSession.loadEventForm,
        saveEventForm: publishingSession.saveEventForm,
        loadSourceForm: publishingSession.loadSourceForm,
        saveSourceForm: publishingSession.saveSourceForm,
        loadCalendarForm: publishingSession.loadCalendarForm,
        saveCalendarForm: publishingSession.saveCalendarForm,
        loadEntityForm: publishingSession.loadEntityForm,
        saveEntityForm: publishingSession.saveEntityForm,
        loadAttributeForm: publishingSession.loadAttributeForm,
        saveAttributeForm: publishingSession.saveAttributeForm,
      );
      await expectLater(
        SavedChanges(
          session: interruptedPublication,
          universe: Selector('A shared history'),
          scope: scope,
        ).publish(recoveredProposal, validation.execution.runId),
        throwsFormatException,
      );
      await owner.close();
      owner = await connection(author).connect();
      final resumedChanges = SavedChanges(
        session: owner,
        universe: Selector('A shared history'),
        scope: scope,
      );
      final publication = (await resumedChanges.publication(
        recoveredProposal,
      ))!;
      final receipt = publication.status.receipt!;
      expect(publication.run, validation.execution.runId);
      expect(receipt.revision, isNot(continuity.revisionId));
      expect(
        (await resumedChanges.publish(
          recoveredProposal,
          publication.run,
        )).toWire().toText(),
        receipt.toWire().toText(),
      );
      final publishedRecords = await resumedChanges.readPublished(
        recoveredProposal,
        receipt,
      );
      expect(publishedRecords, hasLength(25));
      expect(
        publishedRecords.map(
          (record) => (record.payload as WorldRecord).selector,
        ),
        contains('A river world'),
      );
      final original = recoveredProposal.compiledChanges.first.next!;
      final publishedContinuity = ContinuitySummary(
        id: continuity.id,
        revisionId: receipt.revision,
        name: continuity.name,
        representedContexts: continuity.representedContexts,
      );
      final detail = await readPublishedWorld(
        session: owner,
        universe: LibraryEntry(scope.universe, 'A shared history'),
        continuity: publishedContinuity,
        representedContext: continuity.representedContexts.single,
        world: WorldSummary(
          id: WorldId.parse(
            'wld_${original.identity.recordId.value.substring(RecordId.prefix.length)}',
          ),
          name: Selector((original.payload as WorldRecord).selector),
        ),
      );
      expect(detail.recordVersionId, original.recordVersionId);
      final renameScope = EditorFormScope(
        instance: scope.instance,
        profile: scope.profile,
        universe: scope.universe,
        continuity: scope.continuity,
        representedContext: completed.representedContext,
        worldRecord: original.identity.recordId,
      );
      final renameForm = UnfinishedWorldForm(
        baseRevision: receipt.revision,
        representedContext: completed.representedContext,
        record: original.identity.recordId,
        expectedRecordVersion: original.recordVersionId,
        selector: 'Renamed world',
        settingType: '',
        rationale: 'Explicit name change',
      );
      expect(await owner.loadWorldForm(renameScope), isNull);
      await owner.saveWorldForm(renameScope, renameForm, BigInt.zero);
      expect(
        (await owner.loadWorldForm(renameScope))!.form.toWire().toText(),
        renameForm.toWire().toText(),
      );
      final emptyRenameDraft = await resumedChanges.saveContent(
        linked,
        DraftContent(
          baseRevision: receipt.revision,
          representedContext: completed.representedContext,
          operations: [],
          rationale: '',
        ),
      );
      final renameRequest = renameWorldDraftRequest(
        universe: Selector('A shared history'),
        universeId: scope.universe,
        continuity: continuity.id,
        form: renameForm,
        previous: emptyRenameDraft,
      );
      final changedDraft = SavedDraft.fromWire(await owner.call(renameRequest));
      expect(
        renameWorldDraftRequest(
          universe: Selector('A shared history'),
          universeId: scope.universe,
          continuity: continuity.id,
          form: renameForm,
          previous: changedDraft,
        ).content.toWire().toText(),
        changedDraft.content.toWire().toText(),
      );
      final renamed = await resumedChanges.submit(changedDraft);
      final oldRecords = await resumedChanges.before(renamed);
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
      expect(
        (renamed.compiledChanges.single.next!.payload as WorldRecord).aliases,
        contains((original.payload as WorldRecord).selector),
      );
      final linkedRename = (await resumedChanges.load())!;
      final renameValidation =
          await resumedChanges.validate(renamed) as EvaluatedValidation;
      await resumedChanges.approve(renamed, renameValidation);
      final secondReceipt = await resumedChanges.publish(
        renamed,
        renameValidation.execution.runId,
      );
      final editable = await resumedChanges.continueEditing(linkedRename);
      expect(editable.content.proposal, isNull);
      expect(editable.content.operations, hasLength(1));
      final removed = await resumedChanges.removeOperation(editable, 0);
      expect(removed.content.operations, isEmpty);
      expect(removed.content.rationale, editable.content.rationale);
      expect(
        (await resumedChanges.removeOperation(editable, 0)).version,
        removed.version,
      );
      await expectLater(
        resumedChanges.saveRationale(editable, 'Competing rationale'),
        throwsA(isA<BaseRevisionConflictError>()),
      );
      final restored = await resumedChanges.saveContent(
        removed,
        editable.content,
      );
      expect(
        restored.content.toWire().toText(),
        editable.content.toWire().toText(),
      );
      final redone = await resumedChanges.saveContent(
        restored,
        removed.content,
      );
      expect(redone.content.operations, isEmpty);
      final undoneAgain = await resumedChanges.saveContent(
        redone,
        editable.content,
      );
      final rebased = await resumedChanges.rebase(undoneAgain);
      expect(rebased.content.baseRevision, secondReceipt.revision);
      expect(
        rebased.content.operations.single.toWire().toText(),
        editable.content.operations.single.toWire().toText(),
      );
      // The original expected record version is not silently changed by rebase.
      await expectLater(
        resumedChanges.submit(rebased),
        throwsA(isA<InvalidArgumentError>()),
      );
      final oldProposal = await resumedChanges.proposal(
        resumedChanges.reference(renamed),
      );
      expect(oldProposal.digest, renamed.digest);
      expect(
        oldProposal.operations.single.toWire().toText(),
        renamed.operations.single.toWire().toText(),
      );
      final emptyDraft = await resumedChanges.rebase(rebased, startNew: true);
      expect(emptyDraft.content.operations, isEmpty);
      expect(emptyDraft.content.baseRevision, secondReceipt.revision);
      expect(emptyDraft.content.rationale, isEmpty);
      final worldToEdit = await resumedChanges.saveContent(
        emptyDraft,
        DraftContent(
          baseRevision: emptyDraft.content.baseRevision,
          representedContext: emptyDraft.content.representedContext,
          operations: [
            CreateWorldOperation(
              clientRef: 'external-writer/new-world',
              record: WorldRecord(
                selector: 'Local draft world',
                aliases: ['Earlier name'],
                labels: {'fr': 'Monde'},
                metadata: {'notes': const TextValue('Author supplied')},
              ),
            ),
          ],
          rationale: 'Edit the draft, preserving its identity.',
        ),
      );
      final editScope = EditorFormScope(
        instance: scope.instance,
        profile: scope.profile,
        universe: scope.universe,
        continuity: scope.continuity,
        worldClientRef: 'external-writer/new-world',
      );
      final unfinishedEdit = UnfinishedWorldForm(
        baseRevision: worldToEdit.content.baseRevision,
        representedContext: worldToEdit.content.representedContext,
        record: RecordId.generate(),
        selector: '',
        settingType: 'Still entering the edit',
        rationale: '',
        draftVersion: worldToEdit.version,
      );
      expect(await owner.loadWorldForm(editScope), isNull);
      await owner.saveWorldForm(editScope, unfinishedEdit, BigInt.zero);
      expect(
        (await owner.loadWorldForm(editScope))!.form.toWire().toText(),
        unfinishedEdit.toWire().toText(),
      );
      expect((await resumedChanges.load())!.version, worldToEdit.version);
      expect((await owner.loadWorldForm(scope))!.form.draftVersion, isNull);
      final editedWorld = await resumedChanges.editWorldFields(
        worldToEdit,
        0,
        selector: 'Edited local world',
        settingType: 'Historical',
        englishLabel: 'Edited world',
      );
      final savedWorld =
          (await resumedChanges.load())!.content.operations.single
              as CreateWorldOperation;
      expect(savedWorld.clientRef, 'external-writer/new-world');
      expect(savedWorld.record.selector, 'Edited local world');
      expect(savedWorld.record.aliases, ['Earlier name']);
      expect(savedWorld.record.labels, {'fr': 'Monde', 'en': 'Edited world'});
      expect(savedWorld.record.metadata['notes'], isA<TextValue>());
      expect(editedWorld.content.rationale, worldToEdit.content.rationale);
      await expectLater(
        resumedChanges.editWorldFields(
          worldToEdit,
          0,
          selector: 'Competing edit',
          settingType: '',
          englishLabel: '',
        ),
        throwsA(isA<BaseRevisionConflictError>()),
      );
      expect(
        (await resumedChanges.editWorldFields(
          worldToEdit,
          0,
          selector: 'Edited local world',
          settingType: 'Historical',
          englishLabel: 'Edited world',
        )).version,
        editedWorld.version,
      );
      expect(
        () => resumedChanges.editWorldFields(
          linked,
          0,
          selector: 'Cannot edit submitted world',
          settingType: '',
          englishLabel: '',
        ),
        throwsFormatException,
      );
      final unchangedHead = Envelope<Description>.fromWire(
        await owner.call(
          ToolEngineRequest(
            request: DescribeSummaryRequest(
              universe: Selector('A shared history'),
            ),
          ),
        ),
        Description.fromWire,
      );
      expect(
        unchangedHead.result.continuities.single.revisionId,
        secondReceipt.revision,
      );
      final contextDraft = await resumedChanges.saveContent(
        editedWorld,
        DraftContent(
          baseRevision: secondReceipt.revision,
          representedContext: scopeContext(continuity),
          operations: [
            RecordNarrativeReferenceOperation(
              clientRef: RecordId.generate().value,
              record: RecordKind.representedContext,
              payload: RepresentedContextRecord(
                universe: scope.universe,
                kind: const AuthoredContext('Dream'),
                parent: RecordRef(
                  universe: scope.universe,
                  record: scopeContext(continuity),
                ),
                labels: {'en': 'Dream'},
              ),
            ),
          ],
          rationale: 'Keep the dream separate from objective history.',
        ),
      );
      final contextProposal = await resumedChanges.submit(contextDraft);
      final contextChecks =
          await resumedChanges.validate(contextProposal) as EvaluatedValidation;
      await resumedChanges.approve(contextProposal, contextChecks);
      final contextReceipt = await resumedChanges.publish(
        contextProposal,
        contextChecks.execution.runId,
      );
      final contextSummary = Envelope<Description>.fromWire(
        await owner.call(
          ToolEngineRequest(
            request: DescribeSummaryRequest(
              universe: Selector('A shared history'),
              universeId: scope.universe,
            ),
          ),
        ),
        Description.fromWire,
      ).result.continuities.single;
      expect(contextSummary.representedContexts, hasLength(2));
      expect(selectedRepresentedContext(contextSummary, null), isNull);
      expect(
        selectedRepresentedContext(contextSummary, RecordId.generate()),
        isNull,
      );
      for (final represented in contextSummary.representedContexts) {
        expect(
          selectedRepresentedContext(contextSummary, represented.id)!.id,
          represented.id,
        );
        final view = await readContextWorlds(
          session: owner,
          universe: LibraryEntry(scope.universe, 'A shared history'),
          continuity: contextSummary,
          representedContext: represented,
        );
        expect(view.frame!.context.record, represented.id);
        expect(view.frame!.revision, contextReceipt.revision);
        final contextScope = EditorFormScope(
          instance: scope.instance,
          profile: scope.profile,
          universe: scope.universe,
          continuity: scope.continuity,
          representedContext: represented.id,
        );
        final pending = await owner.loadWorldForm(contextScope);
        if (represented.id == scopeContext(continuity)) {
          expect(
            pending!.form.toWire().toText(),
            (await owner.loadWorldForm(scope))!.form.toWire().toText(),
          );
          expect(pending.generation, BigInt.zero);
        } else {
          expect(pending, isNull);
        }
        final entered = UnfinishedWorldForm(
          baseRevision: contextReceipt.revision,
          representedContext: represented.id,
          record: RecordId.generate(),
          selector: 'Pending in ${representedContextName(represented)}',
          settingType: '',
          rationale: '',
        );
        await owner.saveWorldForm(contextScope, entered, BigInt.zero);
        expect(
          (await owner.loadWorldForm(contextScope))!.form.toWire().toText(),
          entered.toWire().toText(),
        );
      }
      expect(
        (await owner.loadWorldForm(scope))!.form.representedContext,
        scopeContext(continuity),
      );
      for (final represented in contextSummary.representedContexts) {
        final stored = await owner.loadWorldForm(
          EditorFormScope(
            instance: scope.instance,
            profile: scope.profile,
            universe: scope.universe,
            continuity: scope.continuity,
            representedContext: represented.id,
          ),
        );
        expect(
          stored!.form.selector,
          'Pending in ${representedContextName(represented)}',
        );
      }
      await expectLater(
        owner.loadWorldForm(
          EditorFormScope(
            instance: scope.instance,
            profile: scope.profile,
            universe: scope.universe,
            continuity: scope.continuity,
            representedContext: RecordId.generate(),
          ),
        ),
        throwsA(isA<NotFoundOrNotAccessibleError>()),
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
      final access = await readAccessDirectory(owner);
      expect(access.profiles.map((p) => p.id), contains(writer));
      expect(access.grant(writer, scope.universe), isNull);
      final restrictedGrant = GrantSpec(
        profileId: writer,
        universeId: scope.universe,
        worlds: null,
        propose: true,
        edit: false,
        protected: false,
        limits: GrantLimits(
          entities: [RecordId.generate()],
          predicates: [RecordId.generate()],
          continuities: [scope.continuity],
          expiresAt: (BigInt.one << 64) - BigInt.one,
          delegatedCommit: false,
          allowShared: true,
        ),
      );
      await saveAccessGrant(owner, restrictedGrant);
      final grantedAccess = await readAccessDirectory(owner);
      expect(
        grantedAccess.grant(writer, scope.universe)!.toWire().toText(),
        restrictedGrant.toWire().toText(),
      );
      expect(
        InstanceLibrary.fromWire(
          await contributor.call(const StatusEngineRequest()),
        ).universes.map((u) => u.id),
        contains(scope.universe),
      );
      await expectLater(
        readAccessDirectory(contributor),
        throwsA(isA<NotFoundOrNotAccessibleError>()),
      );
      await withdrawAccessGrant(owner, writer, scope.universe);
      expect(
        (await readAccessDirectory(owner)).grant(writer, scope.universe),
        isNull,
      );
      expect(
        InstanceLibrary.fromWire(
          await contributor.call(const StatusEngineRequest()),
        ).universes,
        isEmpty,
      );

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

RecordId scopeContext(ContinuitySummary continuity) =>
    continuity.representedContexts.single.id;
