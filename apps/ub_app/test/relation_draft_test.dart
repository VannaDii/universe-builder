@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_app/relation_draft.dart';
import 'package:ub_app/attribute_draft.dart';
import 'package:ub_app/connection.dart';
import 'package:ub_app/connection_native.dart';
import 'package:ub_app/draft_record_choices.dart';
import 'package:ub_app/saved_changes.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/editor_forms.dart';
import 'package:ub_store/installation.dart';
import 'package:ub_service/local_engine.dart';
import 'package:ub_service/local_profiles.dart';

void main() {
  test('relation-definition edits preserve every role, participant type, multiplicity and ordering flag', () {
    final value = RelationRecord(
      namespace: 'authored',
      key: 'account',
      labels: {'en': 'Account', '': 'Authored label 記憶 😀'},
      roles: [
        RoleDefinition(
          name: 'details 記憶 😀',
          participantTypes: [RecordId.generate(), RecordId.generate()],
          multiplicity: Multiplicity.multiple,
          ordered: true,
        ),
        RoleDefinition(
          name: 'note',
          participantTypes: [],
          multiplicity: Multiplicity.single,
          ordered: false,
        ),
      ],
    );
    final operation = DefineRelationOperation(
      clientRef: RecordId.generate().value,
      record: value,
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
        operations: [other, operation],
        rationale: 'Exact rationale',
      ),
    );
    final form = relationFormFromDraft(draft, 1);
    final recovered = UnfinishedRelationForm.fromWire(form.toWire());
    expect(
      relationOperation(recovered).toWire().toText(),
      operation.toWire().toText(),
    );
    final exact = relationDraftRequest(
      draft: draft,
      form: recovered,
      universe: Selector('Universe'),
      continuity: ContinuityId.generate(),
      index: 1,
    );
    expect(exact.content.toWire().toText(), draft.content.toWire().toText());
    final changed = UnfinishedRelationForm(
      baseRevision: form.baseRevision,
      representedContext: form.representedContext,
      clientRef: form.clientRef,
      namespace: form.namespace,
      key: form.key,
      labels: form.labels,
      roles: form.roles.reversed,
      draftVersion: form.draftVersion,
    );
    final replaced = relationDraftRequest(
      draft: draft,
      form: changed,
      universe: Selector('Universe'),
      continuity: ContinuityId.generate(),
      index: 1,
    );
    expect(
      (replaced.content.operations[1] as DefineRelationOperation).record.roles
          .map((f) => f.name),
      ['note', 'details 記憶 😀'],
    );
    expect(
      replaced.content.operations.first.toWire().toText(),
      other.toWire().toText(),
    );
    expect(replaced.content.rationale, draft.content.rationale);
    expect(
      () => relationDraftRequest(
        draft: SavedDraft(version: BigInt.from(3), content: draft.content),
        form: changed,
        universe: Selector('Universe'),
        continuity: ContinuityId.generate(),
        index: 1,
      ),
      throwsFormatException,
    );
  });
  test('incomplete relation-definition rows recover exactly and competing writes cannot overwrite', () {
    final root = Directory('/tmp')
        .createTempSync('ub-relation-definition-cache-');
    final scope = EditorFormScope(
      instance: OperationId.generate(),
      profile: ProfileId.generate(),
      universe: UniverseId.generate(),
      continuity: ContinuityId.generate(),
      representedContext: RecordId.generate(),
    );
    final form = UnfinishedRelationForm(
      baseRevision: RevisionId.generate(),
      representedContext: scope.representedContext!,
      clientRef: RecordId.generate().value,
      namespace: 'authored',
      key: 'incomplete',
      roles: [
        RelationRoleInput(
          name: '記憶 😀',
          participantTypes: ['unfinished type'],
          multiplicity: 'unfinished',
          ordered: true,
        ),
        RelationRoleInput(name: '記憶 😀'),
      ],
      labels: [
        const PropertyLabelInput(language: '', text: 'unfinished label'),
      ],
    );
    var store = RelationFormRecoveryStore.open('${root.path}/forms.sqlite');
    try {
      store.save(scope, form, BigInt.zero);
      store.close();
      store = RelationFormRecoveryStore.open('${root.path}/forms.sqlite');
      expect(store.load(scope)!.form.toWire().toText(), form.toWire().toText());
      expect(store.save(scope, form, BigInt.zero).generation, BigInt.one);
      expect(() => relationOperation(form), throwsFormatException);
      final changed = UnfinishedRelationForm(
        baseRevision: form.baseRevision,
        representedContext: form.representedContext,
        clientRef: form.clientRef,
        namespace: 'competing',
      );
      expect(
        () => store.save(scope, changed, BigInt.zero),
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
  test('relation definition recovers, publishes and is selectable by its display name', () async {
    final root = Directory('/tmp')
        .createTempSync('ub-relation-definition-workflow-');
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
            name: 'Relations',
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
        universe: Selector('Relations'),
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

      final typeDraft = SavedDraft.fromWire(
        await session.call(
          SaveDraftEngineRequest(
            universe: Selector('Relations'),
            continuityId: scope.continuity,
            expectedVersion: BigInt.zero,
            content: DraftContent(
              baseRevision: RevisionId.parse(created.string('revision')),
              representedContext: scope.representedContext!,
              operations: [
                DefineTypeOperation(
                  clientRef: 'person',
                  record: EntityTypeRecord(
                    namespace: 'authored',
                    key: 'person',
                    labels: {'en': 'Person'},
                    name: 'Person',
                    parentResolution: ParentResolution.root,
                    applicability: const UniverseApplicability(),
                    classificationExecutable: true,
                  ),
                ),
              ],
              rationale: 'Declare participant type.',
            ),
          ),
        ),
      );
      final person = (await publish(typeDraft)).single.identity.recordId;
      final initial = await changes().rebase(
        (await changes().load())!,
        startNew: true,
      );
      final typeContext = await openDraftChoiceContext(changes(), initial);
      final typeHits = await searchDraftChoices(
        changes: changes(),
        context: typeContext,
        kind: RecordKind.entityType,
        query: 'Person',
      );
      final selectedType = await selectDraftChoice(
        changes: changes(),
        context: typeContext,
        hit: typeHits.result.hits.single,
        kind: RecordKind.entityType,
      );
      expect(selectedType.record, person);
      final form = UnfinishedRelationForm(
        baseRevision: initial.content.baseRevision,
        representedContext: scope.representedContext!,
        clientRef: RecordId.generate().value,
        namespace: 'authored',
        key: 'account',
        labels: [
          const PropertyLabelInput(language: 'en', text: 'Account 記憶 😀'),
        ],
        roles: [
          RelationRoleInput(
            name: 'speaker',
            participantTypes: [selectedType.record.value],
            multiplicity: 'single',
          ),
          RelationRoleInput(
            name: 'listeners',
            multiplicity: 'multiple',
            ordered: true,
          ),
        ],
        rationale: 'Declare speaker and listener roles.',
      );
      await session.saveRelationForm(scope, form, BigInt.zero);
      await session.close();
      session = await device.connect();
      final recovered = (await session.loadRelationForm(scope))!.form;
      expect(recovered.toWire().toText(), form.toWire().toText());
      final saved = SavedDraft.fromWire(
        await session.call(
          relationDraftRequest(
            draft: initial,
            form: recovered,
            universe: Selector('Relations'),
            continuity: scope.continuity,
          ),
        ),
      );
      expect(
        relationDraftRequest(
          draft: saved,
          form: recovered,
          universe: Selector('Relations'),
          continuity: scope.continuity,
        ).content.toWire().toText(),
        saved.content.toWire().toText(),
      );
      final published = (await publish(saved)).single;
      expect(
        published.payload.toWire().toText(),
        relationOperation(form).record.toWire().toText(),
      );
      final next = await changes().rebase(
        (await changes().load())!,
        startNew: true,
      );
      final context = await openDraftChoiceContext(changes(), next);
      final found = await searchDraftChoices(
        changes: changes(),
        context: context,
        kind: RecordKind.relation,
        query: 'Account',
      );
      expect(found.result.hits.single.label, 'Account 記憶 😀');
      final chosen = await selectDraftChoice(
        changes: changes(),
        context: context,
        hit: found.result.hits.single,
        kind: RecordKind.relation,
      );
      expect(chosen.record, published.identity.recordId);
      expect(chosen.universe, scope.universe);
      final edited = relationFormFromDraft(saved, 0);
      expect(
        relationOperation(edited).toWire().toText(),
        relationOperation(form).toWire().toText(),
      );
      final peopleDraft = await changes().saveContent(
        next,
        DraftContent(
          baseRevision: next.content.baseRevision,
          representedContext: next.content.representedContext,
          operations: [
            for (final name in ['Mara', 'Nia', 'Orr'])
              IntroduceInstanceOperation(
                clientRef: name,
                name: ContextualName(
                  text: name,
                  validity: const UnspecifiedValidity(),
                ),
                classification: person,
                worldAssociations: [],
              ),
          ],
          rationale: 'Introduce participants.',
        ),
      );
      final people = (await publish(peopleDraft))
          .where((r) => r.payload is EntityRecord)
          .toList();
      final claimBase = await changes().rebase(
        (await changes().load())!,
        startNew: true,
      );
      final claimRef = RecordId.generate();
      final evidence = AttributeEvidence(
        attributeMode: AttributeMode.instance,
        polarity: Polarity.support,
        scope: Scope(
          context: RecordRef(
            universe: scope.universe,
            record: scope.representedContext!,
          ),
          applicability: const UniverseApplicability(),
        ),
        validity: const UnknownValidity(),
        persistence: PersistenceSemantics.unspecified,
        precision: Precision.exact,
        basis: const AuthorDecisionBasis('Authored conversation.'),
      );
      RecordRef participant(int index) => RecordRef(
        universe: scope.universe,
        record: people[index].identity.recordId,
      );
      final claim = RecordRelationOperation(
        clientRef: claimRef.value,
        proposition: PropositionRecord(
          predicate: chosen,
          subject: participant(0),
          roles: [
            PropositionRole('speaker', participant(0)),
            PropositionRole('listeners', participant(1)),
          ],
          quantification: Quantification.particular,
          context: evidence.scope.context,
        ),
        assertion: AssertionRecord(
          proposition: RecordRef(universe: scope.universe, record: claimRef),
          attributeMode: evidence.attributeMode,
          polarity: evidence.polarity,
          scope: evidence.scope,
          validity: evidence.validity,
          persistence: evidence.persistence,
          precision: evidence.precision,
          basis: evidence.basis,
        ),
      );
      final claimDraft = await changes().saveContent(
        claimBase,
        DraftContent(
          baseRevision: claimBase.content.baseRevision,
          representedContext: claimBase.content.representedContext,
          operations: [claim],
          rationale: 'Authored conversation.',
        ),
      );
      final pending = attributeFormFromDraft(claimDraft, 0);
      final roleEdit = UnfinishedAttributeForm(
        baseRevision: pending.baseRevision,
        representedContext: pending.representedContext,
        clientRef: pending.clientRef,
        draftVersion: pending.draftVersion,
        value: pending.value,
        roles: [
          PropositionRoleInput(
            role: 'speaker',
            record: participant(0).record.value,
            universe: scope.universe.value,
          ),
          PropositionRoleInput(
            role: 'listeners',
            record: participant(2).record.value,
          ),
          PropositionRoleInput(
            role: 'listeners',
            record: participant(1).record.value,
            universe: scope.universe.value,
          ),
        ],
      );
      final editScope = EditorFormScope(
        instance: scope.instance,
        profile: scope.profile,
        universe: scope.universe,
        continuity: scope.continuity,
        representedContext: scope.representedContext,
        attributeClientRef: pending.clientRef,
      );
      await session.saveAttributeForm(editScope, roleEdit, BigInt.zero);
      await session.close();
      session = await device.connect();
      final restored = (await session.loadAttributeForm(editScope))!.form;
      expect(restored.toWire().toText(), roleEdit.toWire().toText());
      final changedClaim = await changes().saveContent(
        claimDraft,
        replaceDraftAttribute(
          draft: claimDraft,
          index: 0,
          form: UnfinishedAttributeForm(
            baseRevision: restored.baseRevision,
            representedContext: restored.representedContext,
            clientRef: restored.clientRef,
            draftVersion: restored.draftVersion,
            value: restored.value,
            roles: [
              for (final role in restored.roles!)
                PropositionRoleInput(
                  role: role.role,
                  record: role.record,
                  universe: scope.universe.value,
                ),
            ],
          ),
        ),
      );
      final claimRecords = await publish(changedClaim);
      final publishedClaim =
          claimRecords
                  .where((r) => r.payload is PropositionRecord)
                  .single
                  .payload
              as PropositionRecord;
      expect(
        publishedClaim.toWire().toText(),
        (changedClaim.content.operations.single as RecordRelationOperation)
            .proposition
            .toWire()
            .toText(),
      );
      expect(publishedClaim.value, isNull);
      expect(publishedClaim.roles.map((r) => r.participant.record), [
        participant(0).record,
        participant(2).record,
        participant(1).record,
      ]);
    } finally {
      await session?.close();
      await server.close();
      root.deleteSync(recursive: true);
    }
  });
}
