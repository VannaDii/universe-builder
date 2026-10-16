@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_app/connection.dart';
import 'package:ub_app/connection_native.dart';
import 'package:ub_app/saved_changes.dart';
import 'package:ub_app/type_draft.dart';
import 'package:ub_app/draft_record_choices.dart';
import 'package:ub_app/record_browser.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/local_engine.dart';
import 'package:ub_service/local_profiles.dart';
import 'package:ub_store/installation.dart';

void main() {
  test('type completion requires explicit choices and retains unresolved or empty applicability', () {
    final revision = RevisionId.generate(), context = RecordId.generate();
    final continuity = ContinuityId.generate();
    UnfinishedTypeForm form({
      String parent = '',
      String applicability = '',
      bool? executable,
    }) => UnfinishedTypeForm(
      baseRevision: revision,
      representedContext: context,
      clientRef: 'person',
      namespace: 'authored',
      key: 'person',
      name: '人物',
      parentChoice: parent,
      applicabilityChoice: applicability,
      classificationExecutable: executable,
      rationale: '',
    );
    SaveDraftEngineRequest request(UnfinishedTypeForm value) =>
        typeDraftRequest(
          universe: Selector('World'),
          continuity: continuity,
          form: value,
          previous: null,
        );
    expect(() => request(form()), throwsFormatException);
    expect(() => request(form(parent: 'none')), throwsFormatException);
    expect(
      () => request(form(parent: 'none', applicability: 'universe_wide')),
      throwsFormatException,
    );
    final unresolved =
        request(
              form(
                parent: 'none',
                applicability: 'unspecified',
                executable: false,
              ),
            ).content.operations.single
            as IntroduceDefinitionOperation;
    expect(unresolved.parent, isNull);
    expect(unresolved.applicability, isA<UnspecifiedApplicability>());
    expect(unresolved.classificationExecutable, isFalse);
    final nowhere =
        request(form(parent: 'none', applicability: 'worlds', executable: true))
                .content
                .operations
                .single
            as IntroduceDefinitionOperation;
    expect((nowhere.applicability as WorldsApplicability).worldIds, isEmpty);
  });

  test(
    'editing a conditional definition retains unresolved scope and references',
    () {
      final original = IntroduceDefinitionOperation(
        clientRef: 'writer-conditional',
        namespace: 'authored',
        key: 'traveler',
        name: 'Traveler',
        parent: RecordId.generate(),
        applicability: const ConditionalApplicability(),
        classificationExecutable: false,
      );
      final draft = SavedDraft(
        version: BigInt.from(3),
        content: DraftContent(
          baseRevision: RevisionId.generate(),
          representedContext: RecordId.generate(),
          operations: [original],
          rationale: 'Keep the authored scope unresolved.',
        ),
      );
      final initial = typeFormFromDraft(draft, 0);
      expect(initial.applicabilityChoice, 'conditional');
      final edit = UnfinishedTypeForm(
        baseRevision: initial.baseRevision,
        representedContext: initial.representedContext,
        clientRef: initial.clientRef,
        namespace: initial.namespace,
        key: initial.key,
        name: 'Traveler revised',
        parentChoice: initial.parentChoice,
        applicabilityChoice: initial.applicabilityChoice,
        classificationExecutable: initial.classificationExecutable,
        draftVersion: initial.draftVersion,
        rationale: '',
      );
      final updated = replaceDraftType(draft: draft, index: 0, form: edit);
      final operation =
          updated.operations.single as IntroduceDefinitionOperation;
      expect(operation.name, 'Traveler revised');
      expect(
        operation.applicability.toWire().toText(),
        original.applicability.toWire().toText(),
      );
      expect(operation.parent, original.parent);
      expect(operation.clientRef, original.clientRef);
      expect(operation.classificationExecutable, isFalse);
      expect(updated.rationale, draft.content.rationale);
    },
  );

  test('recovered type input appends to other Changes and publishes exact definition semantics', () async {
    final root = Directory('/tmp').createTempSync('ub-type-workflow-');
    final store = SqliteInstallationStore.create(root.path);
    final instance = store.instanceId;
    final author = InstallationAuthority(store).initializeAuthor();
    store.close();
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
        author.value,
        '--engine=/nonexistent/universe-engine',
      ]);
      session = await device.connect();
      final created = WireFields(
        await session.call(
          const CreateUniverseEngineRequest(
            realWorld: false,
            name: 'Type history',
            start: GregorianUniverseStart('2040-01-01T00:00:00Z'),
          ),
        ),
        {'universe_id', 'continuity_id', 'context_id', 'revision', 'name'},
      );
      final scope = EditorFormScope(
        instance: instance,
        profile: author,
        universe: UniverseId.parse(created.string('universe_id')),
        continuity: ContinuityId.parse(created.string('continuity_id')),
        representedContext: RecordId.parse(created.string('context_id')),
      );
      final form = UnfinishedTypeForm(
        baseRevision: RevisionId.parse(created.string('revision')),
        representedContext: scope.representedContext!,
        clientRef: 'writer-person',
        namespace: 'authored',
        key: 'person',
        name: '人物',
        parentChoice: 'none',
        applicabilityChoice: 'universe_wide',
        classificationExecutable: true,
        rationale: 'Declare the person type.',
      );
      final existing = SavedDraft.fromWire(
        await session.call(
          SaveDraftEngineRequest(
            universe: Selector('Type history'),
            continuityId: scope.continuity,
            expectedVersion: BigInt.zero,
            content: DraftContent(
              baseRevision: form.baseRevision,
              representedContext: form.representedContext,
              operations: [
                CreateWorldOperation(
                  clientRef: 'setting',
                  record: WorldRecord(selector: 'River'),
                ),
              ],
              rationale: 'Create the setting.',
            ),
          ),
        ),
      );
      await session.close();
      // Incomplete/pending input remains writable when the service link closes.
      await session.saveTypeForm(scope, form, BigInt.zero);
      session = await device.connect();
      final recovered = (await session.loadTypeForm(scope))!.form;
      final request = typeDraftRequest(
        universe: Selector('Type history'),
        continuity: scope.continuity,
        form: recovered,
        previous: existing,
      );
      final saved = SavedDraft.fromWire(await session.call(request));
      expect(saved.content.operations.length, 2);
      expect(
        saved.content.operations.first.toWire().toText(),
        existing.content.operations.single.toWire().toText(),
      );
      expect(
        saved.content.rationale,
        'Create the setting.\n\nDeclare the person type.',
      );
      expect(
        typeDraftRequest(
          universe: Selector('Type history'),
          continuity: scope.continuity,
          form: recovered,
          previous: saved,
        ).content.toWire().toText(),
        saved.content.toWire().toText(),
      );
      final editScope = EditorFormScope(
        instance: scope.instance,
        profile: scope.profile,
        universe: scope.universe,
        continuity: scope.continuity,
        representedContext: scope.representedContext,
        typeClientRef: 'writer-person',
      );
      final initial = typeFormFromDraft(saved, 1);
      final edited = UnfinishedTypeForm(
        baseRevision: initial.baseRevision,
        representedContext: initial.representedContext,
        clientRef: initial.clientRef,
        namespace: initial.namespace,
        key: initial.key,
        name: 'Person revised',
        parentChoice: initial.parentChoice,
        applicabilityChoice: initial.applicabilityChoice,
        classificationExecutable: initial.classificationExecutable,
        rationale: '',
        draftVersion: initial.draftVersion,
      );
      await session.close();
      await session.saveTypeForm(editScope, edited, BigInt.zero);
      session = await device.connect();
      final pendingEdit = (await session.loadTypeForm(editScope))!.form;
      expect(
        (await session.loadTypeForm(scope))!.form.toWire().toText(),
        recovered.toWire().toText(),
      );
      final currentChanges = SavedChanges(
        session: session,
        universe: Selector('Type history'),
        scope: scope,
      );
      final updated = await currentChanges.saveContent(
        saved,
        replaceDraftType(draft: saved, index: 1, form: pendingEdit),
      );
      expect(
        (updated.content.operations[1] as IntroduceDefinitionOperation)
            .clientRef,
        'writer-person',
      );
      expect(
        updated.content.operations.first.toWire().toText(),
        saved.content.operations.first.toWire().toText(),
      );
      expect(updated.content.rationale, saved.content.rationale);
      expect(
        () => replaceDraftType(draft: updated, index: 1, form: pendingEdit),
        throwsFormatException,
      );
      final proposal = await currentChanges.submit(updated);
      final definition = proposal.compiledChanges
          .map((change) => change.next?.payload)
          .whereType<EntityTypeRecord>()
          .single;
      expect(definition.namespace, 'authored');
      expect(definition.key, 'person');
      expect(definition.name, 'Person revised');
      expect(definition.parent, isNull);
      expect(definition.parentResolution, ParentResolution.root);
      expect(definition.applicability, isA<UniverseApplicability>());
      expect(definition.classificationExecutable, isTrue);
      final validation =
          await currentChanges.validate(proposal) as EvaluatedValidation;
      await currentChanges.approve(proposal, validation);
      final receipt = await currentChanges.publish(
        proposal,
        validation.execution.runId,
      );
      expect(
        (await currentChanges.readPublished(proposal, receipt))
            .map((record) => record.payload)
            .whereType<EntityTypeRecord>()
            .single
            .name,
        'Person revised',
      );
      expect(
        (await currentChanges.publish(
          proposal,
          validation.execution.runId,
        )).revision,
        receipt.revision,
      );
      final typeSource = (await currentChanges.readPublished(
        proposal,
        receipt,
      )).singleWhere((r) => r.payload is EntityTypeRecord);
      final revisionBase = await currentChanges.rebase(
        (await currentChanges.load())!,
        startNew: true,
      );
      final revisionScope = EditorFormScope(
        instance: scope.instance,
        profile: scope.profile,
        universe: scope.universe,
        continuity: scope.continuity,
        representedContext: scope.representedContext,
        typeClientRef: typeSource.identity.recordId.value,
      );
      final initialRevision = typeRevisionFormFromRecord(
        record: typeSource,
        baseRevision: revisionBase.content.baseRevision,
        representedContext: scope.representedContext!,
      );
      final revisionForm = UnfinishedTypeForm(
        baseRevision: initialRevision.baseRevision,
        representedContext: initialRevision.representedContext,
        clientRef: initialRevision.clientRef,
        revisionTarget: initialRevision.revisionTarget,
        expectedRecordVersion: initialRevision.expectedRecordVersion,
        original: initialRevision.original,
        namespace: initialRevision.namespace,
        key: initialRevision.key,
        name: 'Person clarified',
        parentChoice: 'none',
        parentResolution: 'ambiguous',
        applicabilityChoice: 'universe_wide',
        classificationExecutable: false,
        labels: [
          const PropertyLabelInput(language: 'ja', text: '人物 記憶 😀'),
          const PropertyLabelInput(language: 'en', text: 'Reviewed person'),
        ],
        rationale: 'Clarify unresolved parent and authored labels.',
      );
      await session.saveTypeForm(revisionScope, revisionForm, BigInt.zero);
      await session.close();
      session = await device.connect();
      final recoveredRevision = (await session.loadTypeForm(revisionScope))!
          .form;
      expect(
        recoveredRevision.toWire().toText(),
        revisionForm.toWire().toText(),
      );
      final revisionChanges = SavedChanges(
        session: session,
        universe: const Selector('Type history'),
        scope: scope,
      );
      final revisionDraft = SavedDraft.fromWire(
        await session.call(
          typeDraftRequest(
            universe: const Selector('Type history'),
            continuity: scope.continuity,
            form: recoveredRevision,
            previous: revisionBase,
          ),
        ),
      );
      final revisedProposal = await revisionChanges.submit(revisionDraft);
      final revisedValidation = await revisionChanges.validate(
        revisedProposal,
      ) as EvaluatedValidation;
      await revisionChanges.approve(revisedProposal, revisedValidation);
      final revisedReceipt = await revisionChanges.publish(
        revisedProposal,
        revisedValidation.execution.runId,
      );
      final revisedType = (await revisionChanges.readPublished(
        revisedProposal,
        revisedReceipt,
      )).single;
      expect(revisedType.identity.recordId, typeSource.identity.recordId);
      expect(
        revisedType.payload.toWire().toText(),
        typeRevisionOperation(revisionForm).replacement.toWire().toText(),
      );
      final retainedType = await readContextRecord(
        session: session,
        universe: LibraryEntry(scope.universe, 'Type history'),
        context: await openDraftChoiceContext(revisionChanges, revisionBase),
        record: typeSource.identity.recordId,
      );
      expect(retainedType.toWire().toText(), typeSource.toWire().toText());
    } finally {
      try {
        await session?.close();
      } finally {
        try {
          await server.close();
        } finally {
          root.deleteSync(recursive: true);
        }
      }
    }
  });
}
