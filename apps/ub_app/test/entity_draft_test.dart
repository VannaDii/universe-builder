@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_app/connection.dart';
import 'package:ub_app/connection_native.dart';
import 'package:ub_app/entity_draft.dart';
import 'package:ub_app/saved_changes.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/local_engine.dart';
import 'package:ub_service/local_profiles.dart';
import 'package:ub_store/installation.dart';

void main() {
  test('a name alone is enough; world associations need an explicit role', () {
    final base = RevisionId.generate(), context = RecordId.generate();
    final worlds = [WorldId.generate(), WorldId.generate()];
    UnfinishedEntityForm form({
      String name = '人物',
      String role = '',
      List<WorldId> selected = const [],
    }) => UnfinishedEntityForm(
      baseRevision: base,
      representedContext: context,
      clientRef: 'person',
      name: name,
      classification: '',
      worldRole: role,
      rationale: '',
      worlds: selected,
    );
    IntroduceInstanceOperation operation(UnfinishedEntityForm value) =>
        entityDraftRequest(
              universe: Selector('World'),
              continuity: ContinuityId.generate(),
              form: value,
              previous: null,
            ).content.operations.single
            as IntroduceInstanceOperation;
    expect(() => operation(form(name: ' ')), throwsFormatException);
    final minimal = operation(form());
    expect(minimal.name.text, '人物');
    expect(minimal.classification, isNull);
    expect(minimal.worldAssociations, isEmpty);
    expect(minimal.name.validity, isA<UnspecifiedValidity>());
    expect(() => operation(form(selected: worlds)), throwsFormatException);
    final associated = operation(
      form(selected: worlds, role: 'shared setting'),
    );
    expect(associated.worldAssociations.map((a) => a.world), worlds);
    expect(
      associated.worldAssociations.every(
        (a) =>
            a.role == 'shared setting' &&
            a.validity is UnspecifiedValidity &&
            a.qualifiers.isEmpty,
      ),
      isTrue,
    );
  });
  test('entity name/classification edits retain authored metadata and associations', () {
    final original = IntroduceInstanceOperation(
      clientRef: 'writer-person',
      name: const ContextualName(
        text: 'Mara',
        language: 'en',
        community: 'River',
        role: 'pseudonym',
        validity: ConditionalValidity(),
      ),
      classification: RecordId.generate(),
      worldAssociations: [
        WorldAssociation(
          world: WorldId.generate(),
          role: 'home',
          validity: const UnknownValidity(),
          qualifiers: {'account': const TextValue('Firsthand')},
        ),
        WorldAssociation(
          world: WorldId.generate(),
          role: 'shared setting',
          validity: const UnspecifiedValidity(),
          qualifiers: {},
        ),
      ],
    );
    final draft = SavedDraft(
      version: BigInt.two,
      content: DraftContent(
        baseRevision: RevisionId.generate(),
        representedContext: RecordId.generate(),
        operations: [
          CreateWorldOperation(
            clientRef: 'setting',
            record: WorldRecord(selector: 'River'),
          ),
          original,
        ],
        rationale: 'Authored details',
      ),
    );
    final initial = entityFormFromDraft(draft, 1);
    final form = UnfinishedEntityForm(
      baseRevision: initial.baseRevision,
      representedContext: initial.representedContext,
      clientRef: initial.clientRef,
      name: 'Mara revised',
      classification: '',
      worldRole: '',
      rationale: '',
      draftVersion: initial.draftVersion,
    );
    final edited = replaceDraftEntity(draft: draft, index: 1, form: form);
    final operation = edited.operations[1] as IntroduceInstanceOperation;
    expect(operation.name.text, form.name);
    expect(operation.classification, isNull);
    expect(operation.clientRef, original.clientRef);
    expect(operation.name.language, original.name.language);
    expect(operation.name.community, original.name.community);
    expect(operation.name.role, original.name.role);
    expect(
      operation.name.validity.toWire().toText(),
      original.name.validity.toWire().toText(),
    );
    expect(
      operation.worldAssociations.map((a) => a.toWire().toText()),
      original.worldAssociations.map((a) => a.toWire().toText()),
    );
    expect(
      edited.operations.first.toWire().toText(),
      draft.content.operations.first.toWire().toText(),
    );
    expect(edited.rationale, draft.content.rationale);
    expect(
      () => replaceDraftEntity(
        draft: SavedDraft(version: BigInt.from(3), content: draft.content),
        index: 1,
        form: form,
      ),
      throwsFormatException,
    );
  });
  test('association edits retain row-specific details while addition and removal are explicit', () {
    final world = WorldId.generate(), other = WorldId.generate();
    final original = IntroduceInstanceOperation(
      clientRef: 'shared-person',
      name: const ContextualName(text: 'Mara', validity: UnspecifiedValidity()),
      worldAssociations: [
        WorldAssociation(
          world: world,
          role: 'home',
          validity: const ConditionalValidity(),
          qualifiers: {'account': const TextValue('Firsthand')},
        ),
        WorldAssociation(
          world: world,
          role: 'journey',
          validity: const UnknownValidity(),
          qualifiers: {},
        ),
      ],
    );
    final draft = SavedDraft(
      version: BigInt.two,
      content: DraftContent(
        baseRevision: RevisionId.generate(),
        representedContext: RecordId.generate(),
        operations: [original],
        rationale: 'Associations are not location.',
      ),
    );
    final initial = entityFormFromDraft(draft, 0);
    expect(initial.associations!.map((a) => a.originalOrdinal), [0, 1]);
    UnfinishedEntityForm form(List<EntityAssociationForm> rows) =>
        UnfinishedEntityForm(
          baseRevision: initial.baseRevision,
          representedContext: initial.representedContext,
          clientRef: initial.clientRef,
          name: initial.name,
          classification: initial.classification,
          worldRole: '',
          rationale: '',
          draftVersion: initial.draftVersion,
          associations: rows,
        );
    final updated = replaceDraftEntity(
      draft: draft,
      index: 0,
      form: form([
        EntityAssociationForm(
          world: other.value,
          role: 'past home',
          originalOrdinal: 0,
        ),
        EntityAssociationForm(world: world.value, role: 'setting'),
      ]),
    );
    final result = (updated.operations.single as IntroduceInstanceOperation)
        .worldAssociations;
    expect(result.map((a) => a.world), [other, world]);
    expect(result.map((a) => a.role), ['past home', 'setting']);
    expect(
      result.first.validity.toWire().toText(),
      original.worldAssociations.first.validity.toWire().toText(),
    );
    expect(
      result.first.qualifiers['account'],
      original.worldAssociations.first.qualifiers['account'],
    );
    expect(result.last.validity, isA<UnspecifiedValidity>());
    expect(result.last.qualifiers, isEmpty);
    expect(
      (replaceDraftEntity(
                draft: draft,
                index: 0,
                form: form([]),
              ).operations.single
              as IntroduceInstanceOperation)
          .worldAssociations,
      isEmpty,
    );
    expect(
      () => replaceDraftEntity(
        draft: draft,
        index: 0,
        form: form([EntityAssociationForm(world: world.value, role: '')]),
      ),
      throwsFormatException,
    );
    expect(
      () => replaceDraftEntity(
        draft: draft,
        index: 0,
        form: form([
          EntityAssociationForm(
            world: world.value,
            role: 'home',
            originalOrdinal: 2,
          ),
        ]),
      ),
      throwsFormatException,
    );
  });
  test('entity input recovers after disconnect and publishes once with other Changes intact', () async {
    final root = Directory('/tmp').createTempSync('ub-entity-workflow-');
    final store = SqliteInstallationStore.create(root.path);
    final instance = store.instanceId,
        author = InstallationAuthority(store).initializeAuthor();
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
            name: 'Entity history',
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
      final form = UnfinishedEntityForm(
        baseRevision: RevisionId.parse(created.string('revision')),
        representedContext: scope.representedContext!,
        clientRef: 'writer-person',
        name: '人物 😀',
        classification: '',
        worldRole: '',
        rationale: 'Introduce a person.',
      );
      final prior = SavedDraft.fromWire(
        await session.call(
          SaveDraftEngineRequest(
            universe: Selector('Entity history'),
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
      await session.saveEntityForm(scope, form, BigInt.zero);
      session = await device.connect();
      final recovered = (await session.loadEntityForm(scope))!.form;
      expect(recovered.toWire().toText(), form.toWire().toText());
      final saved = SavedDraft.fromWire(
        await session.call(
          entityDraftRequest(
            universe: Selector('Entity history'),
            continuity: scope.continuity,
            form: recovered,
            previous: prior,
          ),
        ),
      );
      expect(saved.content.operations.length, 2);
      expect(
        saved.content.operations.first.toWire().toText(),
        prior.content.operations.single.toWire().toText(),
      );
      expect(
        saved.content.rationale,
        'Create the setting.\n\nIntroduce a person.',
      );
      expect(
        entityDraftRequest(
          universe: Selector('Entity history'),
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
        entityClientRef: 'writer-person',
      );
      final initial = entityFormFromDraft(saved, 1);
      final edit = UnfinishedEntityForm(
        baseRevision: initial.baseRevision,
        representedContext: initial.representedContext,
        clientRef: initial.clientRef,
        name: '人物 revised',
        classification: '',
        worldRole: '',
        rationale: '',
        draftVersion: initial.draftVersion,
      );
      await session.close();
      await session.saveEntityForm(editScope, edit, BigInt.zero);
      session = await device.connect();
      expect(
        (await session.loadEntityForm(scope))!.form.toWire().toText(),
        recovered.toWire().toText(),
      );
      final pending = (await session.loadEntityForm(editScope))!.form;
      final currentChanges = SavedChanges(
        session: session,
        universe: Selector('Entity history'),
        scope: scope,
      );
      final updated = await currentChanges.saveContent(
        saved,
        replaceDraftEntity(draft: saved, index: 1, form: pending),
      );
      expect(
        (updated.content.operations[1] as IntroduceInstanceOperation).clientRef,
        'writer-person',
      );
      final proposal = await currentChanges.submit(updated);
      final entity = proposal.compiledChanges
          .map((c) => c.next?.payload)
          .whereType<EntityRecord>()
          .single;
      expect(entity.names.single.text, edit.name);
      expect(
        entity.classificationResolution,
        ClassificationResolution.unclassified,
      );
      expect(entity.classification, isNull);
      expect(entity.worldAssociations, isEmpty);
      final validation =
          await currentChanges.validate(proposal) as EvaluatedValidation;
      await currentChanges.approve(proposal, validation);
      final receipt = await currentChanges.publish(
        proposal,
        validation.execution.runId,
      );
      expect(
        (await currentChanges.readPublished(proposal, receipt))
            .map((r) => r.payload)
            .whereType<EntityRecord>()
            .single
            .names
            .single
            .text,
        edit.name,
      );
      expect(
        (await currentChanges.publish(
          proposal,
          validation.execution.runId,
        )).revision,
        receipt.revision,
      );
      final worldRecord = proposal.compiledChanges
          .map((c) => c.next)
          .whereType<RecordVersion>()
          .singleWhere((r) => r.payload is WorldRecord);
      final world = WorldId.parse(
        'wld_${worldRecord.identity.recordId.value.substring(RecordId.prefix.length)}',
      );
      final fresh = await currentChanges.rebase(
        (await currentChanges.load())!,
        startNew: true,
      );
      final newEntity = SavedDraft.fromWire(
        await session.call(
          entityDraftRequest(
            universe: Selector('Entity history'),
            continuity: scope.continuity,
            form: UnfinishedEntityForm(
              baseRevision: fresh.content.baseRevision,
              representedContext: fresh.content.representedContext,
              clientRef: 'associated-person',
              name: 'Mara',
              classification: '',
              worldRole: '',
              rationale: '',
            ),
            previous: fresh,
          ),
        ),
      );
      final fields = entityFormFromDraft(newEntity, 0);
      final associated = await currentChanges.saveContent(
        newEntity,
        replaceDraftEntity(
          draft: newEntity,
          index: 0,
          form: UnfinishedEntityForm(
            baseRevision: fields.baseRevision,
            representedContext: fields.representedContext,
            clientRef: fields.clientRef,
            name: fields.name,
            classification: '',
            worldRole: '',
            rationale: '',
            draftVersion: fields.draftVersion,
            associations: [
              EntityAssociationForm(world: world.value, role: 'home'),
            ],
          ),
        ),
      );
      await expectLater(
        currentChanges.submit(associated),
        throwsA(
          isA<InvalidArgumentError>().having(
            (e) => e.field,
            'field',
            'rationale',
          ),
        ),
      );
      final ready = await currentChanges.saveRationale(
        associated,
        'Associate Mara with River.',
      );
      final associatedProposal = await currentChanges.submit(ready);
      final associatedValidation = await currentChanges.validate(
        associatedProposal,
      ) as EvaluatedValidation;
      await currentChanges.approve(associatedProposal, associatedValidation);
      final associatedReceipt = await currentChanges.publish(
        associatedProposal,
        associatedValidation.execution.runId,
      );
      final published = (await currentChanges.readPublished(
        associatedProposal,
        associatedReceipt,
      )).map((r) => r.payload).whereType<EntityRecord>().single;
      expect(published.worldAssociations.single.world, world);
      expect(published.worldAssociations.single.role, 'home');
      expect(
        published.worldAssociations.single.validity,
        isA<UnspecifiedValidity>(),
      );
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
