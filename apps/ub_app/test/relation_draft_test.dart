@TestOn('vm')
library;

import 'dart:io';
import 'dart:convert';

import 'package:test/test.dart' hide Description;
import 'package:ub_app/relation_draft.dart';
import 'package:ub_app/event_draft.dart';
import 'package:ub_app/action_draft.dart';
import 'package:ub_app/continuity_draft.dart';
import 'package:ub_app/rule_draft.dart';
import 'package:ub_app/completeness_draft.dart';
import 'package:ub_app/proposition_draft.dart';
import 'package:ub_app/attitude_draft.dart';
import 'package:ub_app/observation_draft.dart';
import 'package:ub_app/communication_draft.dart';
import 'package:ub_app/memory_draft.dart';
import 'package:ub_app/plan_draft.dart';
import 'package:ub_app/commitment_draft.dart';
import 'package:ub_app/item_power_draft.dart';
import 'package:ub_app/represented_context_draft.dart';
import 'package:ub_app/boundary_draft.dart';
import 'package:ub_app/issue_decision_draft.dart';
import 'package:ub_app/exception_draft.dart';
import 'package:ub_app/work_draft.dart';
import 'package:ub_app/scene_draft.dart';
import 'package:ub_app/passage_draft.dart';
import 'package:ub_app/interpretation_draft.dart';
import 'package:crypto/crypto.dart';
import 'package:ub_app/saga_draft.dart';
import 'package:ub_app/work_version_draft.dart';
import 'package:ub_app/record_browser.dart';
import 'package:ub_app/dossier_timeline.dart';
import 'package:ub_app/dossier_appearance.dart';
import 'package:ub_app/image_preview.dart';
import 'package:ub_app/attribute_draft.dart';
import 'package:ub_app/scope_draft.dart';
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
      var claimBase = await changes().rebase(
        (await changes().load())!,
        startNew: true,
      );
      claimBase = await changes().saveContent(
        claimBase,
        DraftContent(
          baseRevision: claimBase.content.baseRevision,
          representedContext: claimBase.content.representedContext,
          operations: [],
          rationale: 'Authored conversation.',
        ),
      );
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
      final blank = newAttributeForm(
        draft: claimBase,
        entity: people[0],
        relationship: true,
      );
      expect(
        blank.clientRef,
        'new-relationship:${people[0].identity.recordId.value}',
      );
      final creationForm = UnfinishedAttributeForm(
        baseRevision: blank.baseRevision,
        representedContext: blank.representedContext,
        clientRef: blank.clientRef,
        draftVersion: blank.draftVersion,
        value: blank.value,
        roles: [
          PropositionRoleInput(
            role: 'speaker',
            record: participant(0).record.value,
            universe: scope.universe.value,
          ),
          PropositionRoleInput(
            role: 'listeners',
            record: participant(1).record.value,
            universe: scope.universe.value,
          ),
        ],
        creationInput: AttributeCreationInput(
          subject: blank.creationInput!.subject,
          operationRef: blank.creationInput!.operationRef,
          relationship: true,
          propertyRecord: chosen.record.value,
          propertyUniverse: scope.universe.value,
        ),
        evidenceInput: AttributeEvidenceInput(
          scope: scopeInput(evidence.scope),
          precision: Precision.exact,
          basis: const EvidenceBasisInput(
            kind: 'author_decision',
            note: 'Authored conversation.',
          ),
        ),
      );
      expect(
        AttributeCreationInput.fromWire(creationForm.creationInput!.toWire())
            .relationship,
        isTrue,
      );
      final content = appendDraftAttribute(
        draft: claimBase,
        form: creationForm,
        entity: people[0],
        property: published,
      );
      expect(content.operations.single, isA<RecordRelationOperation>());
      final claimDraft = await changes().saveContent(claimBase, content);
      expect(
        appendDraftAttribute(
          draft: claimDraft,
          form: creationForm,
          entity: people[0],
          property: published,
        ).toWire().toText(),
        claimDraft.content.toWire().toText(),
      );
      expect(
        () => appendDraftAttribute(
          draft: SavedDraft(
            version: claimBase.version + BigInt.one,
            content: claimBase.content,
          ),
          form: creationForm,
          entity: people[0],
          property: published,
        ),
        throwsFormatException,
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
      final afterPublication = await changes().rebase(
        (await changes().load())!,
        startNew: true,
      );
      final readContext = await openDraftChoiceContext(
        changes(),
        afterPublication,
      );
      for (final person in people) {
        final facts = await readContextEntityState(
          session: session,
          universe: LibraryEntry(scope.universe, 'Relations'),
          context: readContext,
          entity: person.identity.recordId,
        );
        expect(facts.delivery.complete, isTrue);
        expect(facts.result.coverage, Coverage.partial);
        final object = facts.result.objects.single;
        expect(object.identity.identity.recordId, person.identity.recordId);
        if (person.identity.recordId == participant(0).record) {
          expect(object.instanceFacts, hasLength(1));
          expect(object.instanceFacts.single.applicability, isTrue);
          expect(
            (object.instanceFacts.single.record.payload as AssertionRecord)
                .polarity,
            Polarity.support,
          );
          expect(
            object.dependencies.map((r) => r.identity.recordId),
            containsAll([
              published.identity.recordId,
              participant(1).record,
              participant(2).record,
            ]),
          );
        } else {
          expect(object.instanceFacts, isEmpty);
          expect(object.unknowns, contains('instance_state_not_established'));
        }
        final material = Envelope<Records>.fromWire(
          await session.call(
            ToolEngineRequest(
              request: GetRequest(
                universe: Selector('Relations'),
                universeId: scope.universe,
                contextId: readContext.contextId,
                recordIds: [person.identity.recordId],
                fieldGroups: [FieldGroup.evidence],
              ),
            ),
          ),
          Records.fromWire,
        );
        expect(material.delivery.complete, isTrue);
        final relationships = dossierRelationships(
          material.result,
          scope.universe,
          person.identity.recordId,
        );
        expect(relationships, hasLength(1));
        expect(relationships.single.assertions, hasLength(1));
        final original = relationships.single.assertions.single;
        final refutation = RecordVersion.build(
          recordVersionId: RecordVersionId.generate(),
          identity: RecordIdentity(
            universeId: scope.universe,
            recordId: RecordId.generate(),
            recordKind: RecordKind.assertion,
          ),
          payload: AssertionRecord.fromWire(
            CanonicalObject([
              for (final field in original.payload.toWire().fields)
                field.key == 'polarity'
                    ? MapEntry('polarity', Polarity.refutation.toWire())
                    : field,
            ]),
          ),
        );
        final opposed = dossierRelationships(
          Records(
            records: material.result.records,
            evidence: [...material.result.evidence, refutation],
          ),
          scope.universe,
          person.identity.recordId,
        ).single;
        expect(
          opposed.assertions.map(
            (row) => (row.payload as AssertionRecord).polarity,
          ),
          [Polarity.support, Polarity.refutation],
        );
        expect(
          dossierReferenceLabel(
            material.result,
            scope.universe,
            RecordRef(
              universe: UniverseId.generate(),
              record: publishedClaim.predicate.record,
            ),
          ),
          startsWith('Unavailable name'),
        );
        expect(
          relationships.single.proposition.payload.toWire().toText(),
          publishedClaim.toWire().toText(),
        );
        expect(
          dossierReferenceLabel(
            material.result,
            scope.universe,
            publishedClaim.predicate,
          ),
          'Account 記憶 😀',
        );
        expect(
          dossierRelationships(
            material.result,
            scope.universe,
            RecordId.generate(),
          ),
          isEmpty,
        );
        expect(
          dossierRelationships(
            material.result,
            UniverseId.generate(),
            person.identity.recordId,
          ),
          isEmpty,
        );
        expect(
          dossierRelationships(
            Records(records: []),
            scope.universe,
            person.identity.recordId,
          ),
          isEmpty,
        );
      }
      final calendarChoice = await searchDraftChoices(
        changes: changes(),
        context: readContext,
        kind: RecordKind.calendar,
        query: 'Gregorian',
      );
      final calendar = CalendarId.fromRecordId(
        calendarChoice.result.hits.single.recordId,
      );
      final times = <TemporalExpression>[
        ExactTime(calendar, '2208992400'),
        ExactTime(calendar, '2208992300'),
        IntervalTime(
          calendar,
          const ExactBound('2208992000'),
          const UnknownBound(),
        ),
        ApproximateTime(calendar, '2208992200', const TextValue('a few days')),
        RelativeTime(calendar, TemporalRelation.after, participant(0)),
        const UnspecifiedTime(),
      ];
      final actionId = RecordId.generate();
      var eventsDraft = await changes().saveContent(
        afterPublication,
        DraftContent(
          baseRevision: afterPublication.content.baseRevision,
          representedContext: afterPublication.content.representedContext,
          rationale: 'Authored event times.',
          operations: [
            DefineActionOperation(
              clientRef: actionId.value,
              record: ActionDefinitionRecord(
                namespace: 'authored',
                key: 'journey',
                labels: {'en': 'Journey'},
                requirements: [],
                scope: evidence.scope,
                validity: const UnspecifiedValidity(),
                consequenceContract: ConsequenceContract([]),
              ),
            ),
            for (var i = 0; i < times.length; i++)
              RecordEventOperation(
                clientRef: 'event-$i',
                record: EventRecord(
                  action: RecordRef(universe: scope.universe, record: actionId),
                  occurrence: const SimpleOccurrence(OccurrenceKind.planned),
                  time: times[i],
                  participants: [EventParticipant(participant(1), 'traveler')],
                  labels: {'en': 'Journey $i 記憶 😀'},
                ),
              ),
          ],
        ),
      );
      final actionForm = actionFormFromDraft(eventsDraft, 0);
      final actionScope = EditorFormScope(
        instance: scope.instance,
        profile: scope.profile,
        universe: scope.universe,
        continuity: scope.continuity,
        representedContext: scope.representedContext,
        typeClientRef: actionForm.clientRef,
      );
      await session.saveActionForm(actionScope, actionForm, BigInt.zero);
      final recoveredAction = (await session.loadActionForm(actionScope))!.form;
      eventsDraft = await changes().saveContent(
        eventsDraft,
        actionDraftRequest(
          draft: eventsDraft,
          form: recoveredAction,
          universe: const Selector('Relations'),
          continuity: scope.continuity,
          index: 0,
        ).content,
      );
      final eventForm = eventFormFromDraft(eventsDraft, 1);
      final eventScope = EditorFormScope(
        instance: scope.instance,
        profile: scope.profile,
        universe: scope.universe,
        continuity: scope.continuity,
        representedContext: scope.representedContext,
        typeClientRef: eventForm.clientRef,
      );
      final cachedEvent = await session.saveEventForm(
        eventScope,
        eventForm,
        BigInt.zero,
      );
      final recoveredEvent = (await session.loadEventForm(eventScope))!;
      expect(recoveredEvent.generation, cachedEvent.generation);
      expect(
        recoveredEvent.form.toWire().toText(),
        eventForm.toWire().toText(),
      );
      final eventRequest = eventDraftRequest(
        draft: eventsDraft,
        form: recoveredEvent.form,
        universe: const Selector('Relations'),
        continuity: scope.continuity,
        index: 1,
      );
      eventsDraft = await changes().saveContent(
        eventsDraft,
        eventRequest.content,
      );
      try {
        await publish(eventsDraft);
      } on InvalidArgumentError catch (error) {
        fail(error.message);
      }
      final eventsBase = await changes().rebase(
        (await changes().load())!,
        startNew: true,
      );
      final eventsContext = await openDraftChoiceContext(changes(), eventsBase);
      final actionChoices = await searchDraftChoices(
        changes: changes(),
        context: eventsContext,
        kind: RecordKind.actionDefinition,
      );
      expect(actionChoices.result.hits.single.label, 'Journey');
      final eventChoices = await searchDraftChoices(
        changes: changes(),
        context: eventsContext,
        kind: RecordKind.event,
      );
      expect(
        eventChoices.result.hits.map((hit) => hit.label),
        everyElement(startsWith('Journey')),
      );
      final eventMaterial = Envelope<Records>.fromWire(
        await session.call(
          ToolEngineRequest(
            request: GetRequest(
              universe: Selector('Relations'),
              universeId: scope.universe,
              contextId: eventsContext.contextId,
              recordIds: [participant(1).record],
              fieldGroups: [FieldGroup.evidence],
            ),
          ),
        ),
        Records.fromWire,
      );
      expect(eventMaterial.delivery.complete, isTrue);
      final events = dossierEvents(
        eventMaterial.result,
        scope.universe,
        participant(1).record,
      );
      expect(events, hasLength(6));
      final order = dossierEventOrder(events);
      expect(
        order.points[calendar]!
            .map((r) => (r.payload as EventRecord).time)
            .map((t) => (t as ExactTime).value),
        ['2208992300', '2208992400'],
      );
      expect(order.other, hasLength(4));
      expect(
        dossierEvents(
          eventMaterial.result,
          scope.universe,
          participant(0).record,
        ),
        isEmpty,
      );
      expect(
        dossierEvents(
          eventMaterial.result,
          UniverseId.generate(),
          participant(1).record,
        ),
        isEmpty,
      );
      for (final event in events) {
        expect(
          (event.payload as EventRecord).occurrence,
          isA<SimpleOccurrence>(),
        );
        expect(
          (event.payload as EventRecord).time.encode(canonical: true).toText(),
          isIn(times.map((t) => t.encode(canonical: true).toText())),
        );
      }
      final propertyId = RecordId.generate(),
          propositionId = RecordId.generate();
      final propertyDraft = await changes().saveContent(
        eventsBase,
        DraftContent(
          baseRevision: eventsBase.content.baseRevision,
          representedContext: eventsBase.content.representedContext,
          rationale: 'Authored hometown.',
          operations: [
            DefinePropertyOperation(
              clientRef: propertyId.value,
              record: PropertyRecord(
                namespace: 'authored',
                key: 'hometown',
                labels: {'en': 'Hometown'},
                subjectTypes: [person],
                value: const SimpleValueShape(SimpleShapeKind.text),
                multiplicity: Multiplicity.single,
                persistence: PersistenceSemantics.unspecified,
                exclusive: false,
                symmetric: false,
                transitive: false,
              ),
            ),
            AssertPropositionOperation(
              clientRef: propositionId.value,
              proposition: PropositionRecord(
                predicate: RecordRef(
                  universe: scope.universe,
                  record: propertyId,
                ),
                subject: participant(0),
                context: evidence.scope.context,
                quantification: Quantification.particular,
                value: const TextValue('River 記憶 😀'),
              ),
              assertion: AssertionRecord(
                attributeMode: AttributeMode.instance,
                proposition: RecordRef(
                  universe: scope.universe,
                  record: propositionId,
                ),
                polarity: Polarity.support,
                scope: evidence.scope,
                validity: const UnknownValidity(),
                persistence: PersistenceSemantics.unspecified,
                precision: Precision.exact,
                basis: const AuthorDecisionBasis('Authored hometown.'),
              ),
            ),
          ],
        ),
      );
      await publish(propertyDraft);
      final factsBase = await changes().rebase(
        (await changes().load())!,
        startNew: true,
      );
      final factsContext = await openDraftChoiceContext(changes(), factsBase);
      final facts = await readContextEntityState(
        session: session,
        universe: LibraryEntry(scope.universe, 'Relations'),
        context: factsContext,
        entity: participant(0).record,
      );
      expect(facts.result.objects.single.instanceFacts, hasLength(2));
      final fact =
          facts.result.propositions
                  .singleWhere(
                    (r) =>
                        (r.payload as PropositionRecord).predicate.record ==
                        propertyId,
                  )
                  .payload
              as PropositionRecord;
      expect((fact.value as TextValue).text, 'River 記憶 😀');
      expect(
        dossierReferenceLabel(
          Records(records: facts.result.objects.single.dependencies),
          scope.universe,
          fact.predicate,
        ),
        'Hometown',
      );
      final png = base64.decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAADklEQVR4nGP4z8DwHwQBEPgD/U6VwW8AAAAASUVORK5CYII=',
      );
      final source = File('${root.path}/Portrait é.png')..writeAsBytesSync(png);
      final staged = WireFields(
        await session.call(
          StageImageEngineRequest(
            universe: Selector('Relations'),
            source: source.path,
          ),
        ),
        {'canonical', 'asset_id', 'preview', 'metadata', 'operations'},
      );
      final assetId = RecordId.parse(staged.string('asset_id'));
      final assetRef = RecordRef(universe: scope.universe, record: assetId);
      expect(staged.boolean('canonical'), isFalse);
      await expectLater(
        readImagePreview(
          session: session,
          universe: LibraryEntry(scope.universe, 'Relations'),
          context: factsContext,
          reference: assetRef,
        ),
        throwsA(isA<NotFoundOrNotAccessibleError>()),
      );
      final appearanceDraft = await changes().saveContent(
        factsBase,
        DraftContent(
          baseRevision: factsBase.content.baseRevision,
          representedContext: factsBase.content.representedContext,
          rationale: 'Authored travel appearance.',
          operations: [
            DomainOperation.fromWire(staged.array('operations').single),
            CreateAppearanceOperation(
              clientRef: 'travel-appearance',
              record: AppearanceRecord(
                target: EntryAppearance(participant(0)),
                label: 'Travel appearance 記憶 😀',
                physicalDescription: 'A weathered coat.',
                atmosphere: 'Quiet determination.',
                images: [
                  AppearanceImage(
                    asset: assetRef,
                    caption: 'Front portrait',
                    purpose: ImagePurpose.appearance,
                  ),
                  AppearanceImage(
                    asset: assetRef,
                    caption: 'Coat detail',
                    purpose: ImagePurpose.detail,
                  ),
                ],
                links: [
                  AppearanceLink(
                    entry: participant(1),
                    relationship: AppearanceRelationship.complements,
                    note: 'Matching travel palette.',
                  ),
                ],
                validity: CalendarIntervalValidity(
                  calendar,
                  const ExactBound('2208992000'),
                  const ExactBound('2208993000'),
                ),
              ),
            ),
          ],
        ),
      );
      try {
        await publish(appearanceDraft);
      } on InvalidArgumentError catch (error) {
        fail(error.message);
      }
      final appearanceBase = await changes().rebase(
        (await changes().load())!,
        startNew: true,
      );
      final appearanceContext = await openDraftChoiceContext(
        changes(),
        appearanceBase,
      );
      final appearanceMaterial = await readContextRecordMaterial(
        session: session,
        universe: LibraryEntry(scope.universe, 'Relations'),
        context: appearanceContext,
        record: participant(0).record,
        group: FieldGroup.evidence,
        includePayload: true,
      );
      final appearances = dossierAppearances(
        appearanceMaterial.result,
        scope.universe,
        participant(0).record,
      );
      expect(appearances, hasLength(1));
      final appearance = appearances.single.payload as AppearanceRecord;
      expect(appearance.physicalDescription, 'A weathered coat.');
      expect(appearance.images.map((i) => i.caption), [
        'Front portrait',
        'Coat detail',
      ]);
      expect(
        appearance.links.single.relationship,
        AppearanceRelationship.complements,
      );
      expect(
        dossierAppearances(
          appearanceMaterial.result,
          scope.universe,
          participant(1).record,
        ),
        isEmpty,
      );
      expect(
        dossierAppearances(
          appearanceMaterial.result,
          UniverseId.generate(),
          participant(0).record,
        ),
        isEmpty,
      );
      final preview = await readImagePreview(
        session: session,
        universe: LibraryEntry(scope.universe, 'Relations'),
        context: appearanceContext,
        reference: assetRef,
      );
      expect(preview.asset.originalName, 'Portrait é.png');
      expect(preview.asset.width, 2);
      expect(preview.asset.height, 1);
      expect(preview.bytes.take(2), [255, 216]);
      expect(source.readAsBytesSync(), png);
      await expectLater(
        readImagePreview(
          session: session,
          universe: LibraryEntry(scope.universe, 'Relations'),
          context: appearanceContext,
          reference: RecordRef(
            universe: UniverseId.generate(),
            record: assetId,
          ),
        ),
        throwsFormatException,
      );
      final branch = ContinuityId.generate();
      await session.call(
        ForkContinuityEngineRequest(
          universe: const Selector('Relations'),
          name: 'Alternate campaign',
          continuityId: branch,
          source: scope.continuity,
          revision: eventsBase.content.baseRevision,
        ),
      );
      final summary = Envelope<Description>.fromWire(
        await session.call(
          ToolEngineRequest(
            request: DescribeSummaryRequest(
              universe: const Selector('Relations'),
            ),
          ),
        ),
        Description.fromWire,
      ).result;
      final target = summary.continuities.singleWhere((c) => c.id == branch);
      final sourceContinuity = summary.continuities.singleWhere(
        (c) => c.id == scope.continuity,
      );
      final branchChanges = SavedChanges(
        session: session,
        universe: const Selector('Relations'),
        scope: EditorFormScope(
          instance: scope.instance,
          profile: scope.profile,
          universe: scope.universe,
          continuity: branch,
          representedContext: scope.representedContext,
        ),
      );
      final differences = await compareContinuities(
        branchChanges,
        target,
        sourceContinuity,
      );
      final propertyDifference = differences.singleWhere(
        (d) => d.kind == RecordKind.property && d.label == 'Hometown',
      );
      expect(propertyDifference.targetVersion, isNull);
      expect(propertyDifference.sourceVersion, isNotNull);
      final adoption = await stageContinuityAdoption(
        changes: branchChanges,
        target: target,
        source: sourceContinuity,
        selected: [propertyDifference.record],
        rationale: 'Bring the property into this campaign.',
      );
      expect(adoption.content.operations, hasLength(1));
      final retried = await stageContinuityAdoption(
        changes: branchChanges,
        target: target,
        source: sourceContinuity,
        selected: [propertyDifference.record],
        rationale: 'Bring the property into this campaign.',
      );
      expect(retried.version, adoption.version);
      expect(retried.content.rationale, adoption.content.rationale);
      final proposal = await branchChanges.submit(retried);
      final validation = await branchChanges.validate(proposal);
      expect(validation, isA<EvaluatedValidation>());
      await branchChanges.approve(proposal, validation as EvaluatedValidation);
      final adopted = await branchChanges.publish(
        proposal,
        validation.execution.runId,
      );
      expect(adopted.revision, isNot(target.revisionId));
      final ruleBase = await changes().rebase(
        (await changes().load())!,
        startNew: true,
      );
      final ruleForm = UnfinishedRuleForm(
        baseRevision: ruleBase.content.baseRevision,
        representedContext: ruleBase.content.representedContext,
        clientRef: 'ui-rule',
        namespace: 'authored',
        key: 'hometown-continuity',
        rationale: 'Declare a continuity rule.',
        labels: [
          const PropertyLabelInput(language: 'en', text: 'Hometown continuity'),
        ],
        kind: 'physical_constraint',
        commitPolicy: 'block_unless_exception',
        scope: ScopeInput(applicability: 'universe_wide'),
        targetPredicates: ['authored:hometown'],
        expression: ExpressionInput(kind: 'lit', flags: {'value': true}),
        capabilities: ['basic.v1'],
        executable: true,
      );
      await session.saveRuleForm(scope, ruleForm, BigInt.zero);
      final recoveredRule = (await session.loadRuleForm(scope))!.form;
      final ruleDraft = SavedDraft.fromWire(
        await session.call(
          ruleDraftRequest(
            draft: ruleBase,
            form: recoveredRule,
            universe: const Selector('Relations'),
            continuity: scope.continuity,
          ),
        ),
      );
      final List<RecordVersion> rulePublished;
      try {
        rulePublished = await publish(ruleDraft);
      } on InvalidArgumentError catch (error) {
        fail(error.message);
      }
      expect(
        (rulePublished.single.payload as RuleRecord).labels['en'],
        'Hometown continuity',
      );
      final knowledgeBase = await changes().rebase(
        (await changes().load())!,
        startNew: true,
      );
      final knowledgeForm = UnfinishedRuleForm(
        baseRevision: knowledgeBase.content.baseRevision,
        representedContext: knowledgeBase.content.representedContext,
        clientRef: 'knowledge-rule',
        namespace: 'authored',
        key: 'knowledge-acquisition',
        labels: [
          const PropertyLabelInput(
            language: 'en',
            text: 'Knowledge acquisition',
          ),
        ],
        kind: 'physical_constraint',
        commitPolicy: 'always_block',
        scope: const ScopeInput(applicability: 'universe_wide'),
        expression: ExpressionInput(kind: 'lit', flags: {'value': true}),
        capabilities: ['knowledge.acquisition.v1'],
        executable: true,
        knowledge: RuleKnowledgeInput(
          policyEnabled: true,
          mode: 'author_established',
          policyContext: ExpressionReferenceInput(
            record: scope.representedContext!.value,
            universe: scope.universe.value,
          ),
        ),
        rationale: 'Establish the authored knowledge policy.',
      );
      final knowledgeDraft = SavedDraft.fromWire(
        await session.call(
          ruleDraftRequest(
            draft: knowledgeBase,
            form: knowledgeForm,
            universe: const Selector('Relations'),
            continuity: scope.continuity,
          ),
        ),
      );
      final List<RecordVersion> knowledgePublished;
      try {
        knowledgePublished = await publish(knowledgeDraft);
      } on PolicyDeniedError catch (error) {
        fail(error.message);
      }
      expect(
        (knowledgePublished.single.payload as RuleRecord).knowledgePolicy!.mode,
        KnowledgeMode.authorEstablished,
      );
      final chronologyBase = await changes().rebase(
        (await changes().load())!,
        startNew: true,
      );
      final chronologyForm = UnfinishedRuleForm(
        baseRevision: chronologyBase.content.baseRevision,
        representedContext: chronologyBase.content.representedContext,
        clientRef: 'chronology-rule',
        namespace: 'authored',
        key: 'mail-chronology',
        labels: [
          const PropertyLabelInput(language: 'en', text: 'Mail chronology'),
        ],
        kind: 'physical_constraint',
        commitPolicy: 'always_block',
        scope: const ScopeInput(applicability: 'universe_wide'),
        expression: ExpressionInput(kind: 'lit', flags: {'value': true}),
        capabilities: ['communications.chronology.v1'],
        executable: true,
        constraints: const RuleConstraintInput(
          chronologyEnabled: true,
          channel: 'mail',
          forwardOnly: false,
          minimumEnabled: true,
          minimumDelay: '9007199254740993',
          maximumEnabled: true,
          maximumDelay: '9007199254740995',
        ),
        rationale: 'Declare exact mail delay bounds.',
      );
      final chronologyDraft = SavedDraft.fromWire(
        await session.call(
          ruleDraftRequest(
            draft: chronologyBase,
            form: chronologyForm,
            universe: const Selector('Relations'),
            continuity: scope.continuity,
          ),
        ),
      );
      final chronologyPublished = await publish(chronologyDraft);
      expect(
        (chronologyPublished.single.payload as RuleRecord)
            .channelChronology!
            .maximumDelay,
        '9007199254740995',
      );
      final limitedBase = await changes().rebase(
        (await changes().load())!,
        startNew: true,
      );
      final limitedRelation = RelationRecord.fromWire(
        CanonicalObject([
          for (final field in relationOperation(form).record.toWire().fields)
            field.key == 'key'
                ? MapEntry('key', CanonicalString('limited-account'))
                : field,
        ]),
      );
      final limitedDraft = await changes().saveContent(
        limitedBase,
        DraftContent(
          baseRevision: limitedBase.content.baseRevision,
          representedContext: limitedBase.content.representedContext,
          operations: [
            DefineRelationOperation(
              clientRef: 'limited-account',
              record: limitedRelation,
            ),
          ],
          rationale: 'Declare a dedicated bounded relation.',
        ),
      );
      final limitedPublished = (await publish(limitedDraft)).single;
      final cardinalityBase = await changes().rebase(
        (await changes().load())!,
        startNew: true,
      );
      final cardinalityForm = UnfinishedRuleForm(
        baseRevision: cardinalityBase.content.baseRevision,
        representedContext: cardinalityBase.content.representedContext,
        clientRef: 'cardinality-rule',
        namespace: 'authored',
        key: 'limited-account-count',
        labels: [
          const PropertyLabelInput(language: 'en', text: 'Account cardinality'),
        ],
        kind: 'physical_constraint',
        commitPolicy: 'always_block',
        scope: const ScopeInput(applicability: 'universe_wide'),
        expression: ExpressionInput(kind: 'lit', flags: {'value': true}),
        capabilities: ['relations.cardinality.v1'],
        executable: true,
        constraints: RuleConstraintInput(
          cardinalityEnabled: true,
          relation: ExpressionReferenceInput(
            record: limitedPublished.identity.recordId.value,
            universe: scope.universe.value,
          ),
          grouping: 'subject',
          countedRole: 'listeners',
          maximum: '5',
          scope: ScopeInput(
            applicability: 'universe_wide',
            contextRecord: scope.representedContext!.value,
            contextUniverse: scope.universe.value,
          ),
          validity: TemporalValidityInput(
            kind: 'calendar_interval',
            calendar: calendar.value,
            start: const TemporalBoundInput(value: '0'),
            end: const TemporalBoundInput(value: '20'),
          ),
        ),
        rationale: 'Declare a scoped cross-instance maximum.',
      );
      final cardinalityDraft = SavedDraft.fromWire(
        await session.call(
          ruleDraftRequest(
            draft: cardinalityBase,
            form: cardinalityForm,
            universe: const Selector('Relations'),
            continuity: scope.continuity,
          ),
        ),
      );
      final List<RecordVersion> cardinalityPublished;
      try {
        cardinalityPublished = await publish(cardinalityDraft);
      } on InvalidArgumentError catch (error) {
        fail('${error.field}: ${error.message}');
      }
      expect(
        (cardinalityPublished.single.payload as RuleRecord)
            .relationCardinality!
            .maximum,
        5,
      );
      final completenessBase = await changes().rebase(
        (await changes().load())!,
        startNew: true,
      );
      final memberProperty = PropertyRecord(
        namespace: 'authored',
        key: 'party-member',
        labels: {'en': 'Party member'},
        subjectTypes: [person],
        value: EntityRefShape([person]),
        multiplicity: Multiplicity.multiple,
        persistence: PersistenceSemantics.unspecified,
        exclusive: false,
        symmetric: false,
        transitive: false,
      );
      final memberPropertyDraft = await changes().saveContent(
        completenessBase,
        DraftContent(
          baseRevision: completenessBase.content.baseRevision,
          representedContext: completenessBase.content.representedContext,
          operations: [
            DefinePropertyOperation(
              clientRef: 'party-member',
              record: memberProperty,
            ),
          ],
          rationale: 'Declare object-valued party membership.',
        ),
      );
      await publish(memberPropertyDraft);
      final completeBase = await changes().rebase(
        (await changes().load())!,
        startNew: true,
      );
      final completeForm = UnfinishedCompletenessForm(
        baseRevision: completeBase.content.baseRevision,
        representedContext: completeBase.content.representedContext,
        clientRef: 'complete-party',
        subject: ExpressionReferenceInput(
          record: participant(0).record.value,
          universe: scope.universe.value,
        ),
        predicate: 'authored:party-member',
        kind: 'objective_reality',
        members: [],
        scope: ScopeInput(
          applicability: 'universe_wide',
          contextRecord: scope.representedContext!.value,
          contextUniverse: scope.universe.value,
        ),
        rationale: 'Declare an explicitly complete empty party.',
      );
      await session.saveCompletenessForm(scope, completeForm, BigInt.zero);
      final recoveredComplete = (await session.loadCompletenessForm(scope))!
          .form;
      final completeDraft = SavedDraft.fromWire(
        await session.call(
          completenessDraftRequest(
            draft: completeBase,
            form: recoveredComplete,
            universe: const Selector('Relations'),
            continuity: scope.continuity,
          ),
        ),
      );
      final completePublished = await publish(completeDraft);
      expect(
        (completePublished.single.payload as CompletenessRecord).members,
        isEmpty,
      );
      expect(
        (completePublished.single.payload as CompletenessRecord).completeness,
        isA<ObjectiveCompleteness>(),
      );
      final propositionBase = await changes().rebase(
        (await changes().load())!,
        startNew: true,
      );
      final beforeClaimContext = await openDraftChoiceContext(
        changes(),
        propositionBase,
      );
      final beforeAssertions = await searchDraftChoices(
        changes: changes(),
        context: beforeClaimContext,
        kind: RecordKind.assertion,
      );
      expect(beforeAssertions.delivery.complete, isTrue);
      final claimForm = UnfinishedPropositionForm(
        baseRevision: propositionBase.content.baseRevision,
        representedContext: scope.representedContext!,
        clientRef: 'unasserted-account',
        subject: ExpressionReferenceInput(
          record: participant(0).record.value,
          universe: scope.universe.value,
        ),
        predicate: ExpressionReferenceInput(
          record: published.identity.recordId.value,
          universe: scope.universe.value,
        ),
        context: ExpressionReferenceInput(
          record: scope.representedContext!.value,
          universe: scope.universe.value,
        ),
        roles: [
          PropositionRoleInput(
            role: 'speaker',
            record: participant(0).record.value,
            universe: scope.universe.value,
          ),
          PropositionRoleInput(
            role: 'listeners',
            record: participant(1).record.value,
            universe: scope.universe.value,
          ),
          PropositionRoleInput(
            role: 'listeners',
            record: participant(1).record.value,
            universe: scope.universe.value,
          ),
        ],
        quantification: 'particular',
        rationale: 'Define an account that has not been asserted true.',
      );
      await session.savePropositionForm(scope, claimForm, BigInt.zero);
      await session.close();
      session = await device.connect();
      final recoveredClaim = (await session.loadPropositionForm(scope))!.form;
      expect(recoveredClaim.toWire().toText(), claimForm.toWire().toText());
      final propositionDraft = SavedDraft.fromWire(
        await session.call(
          propositionDraftRequest(
            draft: propositionBase,
            form: recoveredClaim,
            universe: const Selector('Relations'),
            continuity: scope.continuity,
          ),
        ),
      );
      final claimPublished = await publish(propositionDraft);
      expect(claimPublished.length, 1);
      expect(
        claimPublished.single.payload.toWire().toText(),
        propositionOperation(claimForm).record.toWire().toText(),
      );
      final afterClaimContext = await openDraftChoiceContext(
        changes(),
        await changes().rebase((await changes().load())!, startNew: true),
      );
      final afterAssertions = await searchDraftChoices(
        changes: changes(),
        context: afterClaimContext,
        kind: RecordKind.assertion,
      );
      expect(afterAssertions.delivery.complete, isTrue);
      expect(
        afterAssertions.result.hits.map((h) => h.recordId).toSet(),
        beforeAssertions.result.hits.map((h) => h.recordId).toSet(),
      );
      final claimChoice = await readDraftChoiceSummary(
        changes: changes(),
        context: afterClaimContext,
        record: claimPublished.single.identity.recordId,
        kind: RecordKind.proposition,
      );
      expect(
        claimChoice.label,
        'Particular: Mara.Account 記憶 😀 — speaker: Mara; listeners: Nia; listeners: Nia [Objective reality]',
      );
      final claimSearch = await searchDraftChoices(
        changes: changes(),
        context: afterClaimContext,
        kind: RecordKind.proposition,
        query: 'Mara.Account',
      );
      expect(
        claimSearch.result.hits.any(
          (h) =>
              h.recordId == claimPublished.single.identity.recordId &&
              h.label == claimChoice.label,
        ),
        isTrue,
      );
      final attitudeBase = await changes().load();
      final attitudeForm = UnfinishedAttitudeForm(
        baseRevision: attitudeBase!.content.baseRevision,
        representedContext: scope.representedContext!,
        clientRef: 'suspected-account',
        holder: ExpressionReferenceInput(
          record: participant(1).record.value,
          universe: scope.universe.value,
        ),
        proposition: ExpressionReferenceInput(
          record: claimPublished.single.identity.recordId.value,
          universe: scope.universe.value,
        ),
        attitude: 'suspects',
        certaintyEnabled: true,
        certainty: 'Unconfirmed 記憶 😀',
        basis: const EvidenceBasisInput(
          kind: 'author_decision',
          note: 'Nia suspects the account.',
        ),
        rationale: 'Record suspicion without asserting objective truth.',
      );
      await session.saveAttitudeForm(scope, attitudeForm, BigInt.zero);
      await session.close();
      session = await device.connect();
      final recoveredAttitude = (await session.loadAttitudeForm(scope))!.form;
      expect(
        recoveredAttitude.toWire().toText(),
        attitudeForm.toWire().toText(),
      );
      final attitudeDraft = SavedDraft.fromWire(
        await session.call(
          attitudeDraftRequest(
            draft: attitudeBase,
            form: recoveredAttitude,
            universe: const Selector('Relations'),
            continuity: scope.continuity,
          ),
        ),
      );
      final attitudePublished = await publish(attitudeDraft);
      final savedAttitude =
          attitudePublished.single.payload as EpistemicAttitudeRecord;
      expect(savedAttitude.attitude, EpistemicAttitudeKind.suspects);
      expect(savedAttitude.acquisition, isNull);
      expect(savedAttitude.certainty, 'Unconfirmed 記憶 😀');
      expect(
        savedAttitude.toWire().toText(),
        attitudeOperation(attitudeForm).record.toWire().toText(),
      );
      final observationBase = await changes().rebase(
        (await changes().load())!,
        startNew: true,
      );
      final observationForm = UnfinishedObservationForm(
        baseRevision: observationBase.content.baseRevision,
        representedContext: scope.representedContext!,
        clientRef: 'account-observation',
        observer: ExpressionReferenceInput(
          record: participant(1).record.value,
          universe: scope.universe.value,
        ),
        observed: ExpressionReferenceInput(
          record: claimPublished.single.identity.recordId.value,
          universe: scope.universe.value,
        ),
        sensoryAccess: false,
        time: TemporalValidityInput(
          kind: 'instant',
          calendar: calendar.value,
          start: const TemporalBoundInput(value: '15'),
        ),
        interpretationEnabled: true,
        interpretation: ExpressionReferenceInput(
          record: claimPublished.single.identity.recordId.value,
          universe: scope.universe.value,
        ),
        basis: const EvidenceBasisInput(
          kind: 'author_decision',
          note: 'Keep Nia’s observation distinct from sensory access.',
        ),
        rationale: 'Record the observation as authored.',
      );
      await session.saveObservationForm(scope, observationForm, BigInt.zero);
      await session.close();
      session = await device.connect();
      final recoveredObservation = (await session.loadObservationForm(scope))!
          .form;
      expect(
        recoveredObservation.toWire().toText(),
        observationForm.toWire().toText(),
      );
      final observationDraft = SavedDraft.fromWire(
        await session.call(
          observationDraftRequest(
            draft: observationBase,
            form: recoveredObservation,
            universe: const Selector('Relations'),
            continuity: scope.continuity,
          ),
        ),
      );
      final observationPublished = await publish(observationDraft);
      expect(
        observationPublished.single.payload.toWire().toText(),
        observationOperation(observationForm).record.toWire().toText(),
      );
      final observationChoices = await changes().rebase(
        (await changes().load())!,
        startNew: true,
      );
      final observationContext = await openDraftChoiceContext(
        changes(),
        observationChoices,
      );
      final observationSummary = await readDraftChoiceSummary(
        changes: changes(),
        context: observationContext,
        record: observationPublished.single.identity.recordId,
        kind: RecordKind.observation,
      );
      expect(
        observationSummary.label,
        'Nia — observation of Mara.Account 記憶 😀',
      );
      final messageBase = await changes().load();
      ExpressionReferenceInput messageParticipant(int i) =>
          ExpressionReferenceInput(
            record: participant(i).record.value,
            universe: scope.universe.value,
          );
      final messageContent = ExpressionReferenceInput(
        record: claimPublished.single.identity.recordId.value,
        universe: scope.universe.value,
      );
      final communicationForm = UnfinishedCommunicationForm(
        baseRevision: messageBase!.content.baseRevision,
        representedContext: scope.representedContext!,
        clientRef: 'recorded-message',
        sender: messageParticipant(0),
        intendedRecipients: [messageParticipant(1), messageParticipant(1)],
        actualRecipients: [messageParticipant(2)],
        content: [messageContent, messageContent],
        channelEnabled: true,
        channel: 'mail',
        distorted: false,
        sentAt: TemporalValidityInput(
          kind: 'instant',
          calendar: calendar.value,
          start: const TemporalBoundInput(value: '20'),
        ),
        receivedEnabled: true,
        receivedAt: TemporalValidityInput(
          kind: 'instant',
          calendar: calendar.value,
          start: const TemporalBoundInput(value: '9007199254741013'),
        ),
        rationale: 'Keep intended listeners distinct from actual receipt.',
      );
      await session.saveCommunicationForm(
        scope,
        communicationForm,
        BigInt.zero,
      );
      await session.close();
      session = await device.connect();
      final recoveredCommunication = (await session.loadCommunicationForm(
        scope,
      ))!.form;
      expect(
        recoveredCommunication.toWire().toText(),
        communicationForm.toWire().toText(),
      );
      final communicationDraft = SavedDraft.fromWire(
        await session.call(
          communicationDraftRequest(
            draft: messageBase,
            form: recoveredCommunication,
            universe: const Selector('Relations'),
            continuity: scope.continuity,
          ),
        ),
      );
      final communicationPublished = await publish(communicationDraft);
      expect(communicationPublished.length, 1);
      expect(
        communicationPublished.single.payload.toWire().toText(),
        communicationOperation(communicationForm).record.toWire().toText(),
      );
      final memoryBase = await changes().rebase(
        (await changes().load())!,
        startNew: true,
      );
      final memoryForm = UnfinishedMemoryForm(
        baseRevision: memoryBase.content.baseRevision,
        representedContext: scope.representedContext!,
        clientRef: 'account-memory',
        holder: messageParticipant(1),
        content: messageContent,
        allegedEnabled: true,
        alleged: ExpressionReferenceInput(
          record: communicationPublished.single.identity.recordId.value,
          universe: scope.universe.value,
        ),
        accessibility: 'Fragmented 記憶 😀',
        altered: true,
        rationale:
            'Record a recollection independently from its alleged message.',
      );
      await session.saveMemoryForm(scope, memoryForm, BigInt.zero);
      await session.close();
      session = await device.connect();
      final recoveredMemory = (await session.loadMemoryForm(scope))!.form;
      expect(recoveredMemory.toWire().toText(), memoryForm.toWire().toText());
      final memoryDraft = SavedDraft.fromWire(
        await session.call(
          memoryDraftRequest(
            draft: memoryBase,
            form: recoveredMemory,
            universe: const Selector('Relations'),
            continuity: scope.continuity,
          ),
        ),
      );
      final memoryPublished = await publish(memoryDraft);
      expect(memoryPublished.length, 1);
      expect(
        memoryPublished.single.payload.toWire().toText(),
        memoryOperation(memoryForm).record.toWire().toText(),
      );
      final memoryChoices = await changes().rebase(
        (await changes().load())!,
        startNew: true,
      );
      final memoryContext = await openDraftChoiceContext(
        changes(),
        memoryChoices,
      );
      final memorySummary = await readDraftChoiceSummary(
        changes: changes(),
        context: memoryContext,
        record: memoryPublished.single.identity.recordId,
        kind: RecordKind.memory,
      );
      expect(memorySummary.label, 'Nia — memory of Mara.Account 記憶 😀');
      final planBase = await changes().load();
      final step = ExpressionReferenceInput(
        record: communicationPublished.single.identity.recordId.value,
        universe: scope.universe.value,
      );
      final planForm = UnfinishedPlanForm(
        baseRevision: planBase!.content.baseRevision,
        representedContext: scope.representedContext!,
        clientRef: 'account-plan',
        actor: messageParticipant(0),
        desiredEnabled: true,
        desired: messageContent,
        prerequisites: [
          ExpressionInput(kind: 'lit', flags: {'value': false}),
        ],
        steps: [step, step],
        status: 'active',
        rationale: 'Record intended steps without executing them or satisfying prerequisites.',
      );
      await session.savePlanForm(scope, planForm, BigInt.zero);
      await session.close();
      session = await device.connect();
      final recoveredPlan = (await session.loadPlanForm(scope))!.form;
      expect(recoveredPlan.toWire().toText(), planForm.toWire().toText());
      final planDraft = SavedDraft.fromWire(
        await session.call(
          planDraftRequest(
            draft: planBase,
            form: recoveredPlan,
            universe: const Selector('Relations'),
            continuity: scope.continuity,
          ),
        ),
      );
      final planPublished = await publish(planDraft);
      expect(planPublished.length, 1);
      expect(
        planPublished.single.payload.toWire().toText(),
        planOperation(planForm).record.toWire().toText(),
      );
      final planChoices = await changes().rebase(
        (await changes().load())!,
        startNew: true,
      );
      final planContext = await openDraftChoiceContext(changes(), planChoices);
      final planSummary = await readDraftChoiceSummary(
        changes: changes(),
        context: planContext,
        record: planPublished.single.identity.recordId,
        kind: RecordKind.goal,
      );
      expect(planSummary.label, 'Mara — Active plan: Mara.Account 記憶 😀');
      final commitmentBase = await changes().load();
      CommitmentPartyInput party(int i, String role) => CommitmentPartyInput(
        record: participant(i).record.value,
        universe: scope.universe.value,
        role: role,
      );
      final commitmentForm = UnfinishedCommitmentForm(
        baseRevision: commitmentBase!.content.baseRevision,
        representedContext: scope.representedContext!,
        clientRef: 'account-commitment',
        parties: [
          party(0, 'promisor'),
          party(1, 'beneficiary'),
          party(1, 'witness'),
        ],
        obligated: messageContent,
        conditions: [
          ExpressionInput(kind: 'lit', flags: {'value': false}),
        ],
        deadlineEnabled: true,
        deadline: TemporalValidityInput(
          kind: 'instant',
          calendar: calendar.value,
          start: const TemporalBoundInput(value: '30'),
        ),
        status: 'unfulfilled',
        rationale:
            'Record a promise without automatic fulfillment or consequences.',
      );
      await session.saveCommitmentForm(scope, commitmentForm, BigInt.zero);
      await session.close();
      session = await device.connect();
      final recoveredCommitment = (await session.loadCommitmentForm(scope))!
          .form;
      expect(
        recoveredCommitment.toWire().toText(),
        commitmentForm.toWire().toText(),
      );
      final commitmentDraft = SavedDraft.fromWire(
        await session.call(
          commitmentDraftRequest(
            draft: commitmentBase,
            form: recoveredCommitment,
            universe: const Selector('Relations'),
            continuity: scope.continuity,
          ),
        ),
      );
      final commitmentPublished = await publish(commitmentDraft);
      expect(commitmentPublished.length, 1);
      expect(
        commitmentPublished.single.payload.toWire().toText(),
        commitmentOperation(commitmentForm).record.toWire().toText(),
      );
      final commitmentChoices = await changes().rebase(
        (await changes().load())!,
        startNew: true,
      );
      final commitmentContext = await openDraftChoiceContext(
        changes(),
        commitmentChoices,
      );
      final commitmentSummary = await readDraftChoiceSummary(
        changes: changes(),
        context: commitmentContext,
        record: commitmentPublished.single.identity.recordId,
        kind: RecordKind.commitment,
      );
      expect(
        commitmentSummary.label,
        'Unfulfilled commitment: promisor: Mara; beneficiary: Nia; witness: Nia — Mara.Account 記憶 😀',
      );
      final powerDefinitionBase = await changes().load();
      final itemId = RecordId.generate(),
          holderPropertyId = RecordId.generate(),
          powerPropertyId = RecordId.generate();
      PropertyRecord powerProperty(
        String key,
        String label,
        ValueShape shape,
      ) => PropertyRecord(
        namespace: 'authored',
        key: key,
        labels: {'en': label},
        subjectTypes: [],
        value: shape,
        multiplicity: Multiplicity.single,
        persistence: PersistenceSemantics.unspecified,
        exclusive: false,
        symmetric: false,
        transitive: false,
      );
      final powerDefinitions = await changes().saveContent(
        powerDefinitionBase!,
        DraftContent(
          baseRevision: powerDefinitionBase.content.baseRevision,
          representedContext: scope.representedContext!,
          operations: [
            CreateEntityOperation(
              clientRef: itemId.value,
              record: EntityRecord(
                names: [],
                classificationResolution: ClassificationResolution.unclassified,
                worldAssociations: [],
                labels: {'en': 'Cedar brooch'},
                metadata: {},
              ),
            ),
            DefinePropertyOperation(
              clientRef: holderPropertyId.value,
              record: powerProperty('held-by', 'Held by', EntityRefShape([])),
            ),
            DefinePropertyOperation(
              clientRef: powerPropertyId.value,
              record: powerProperty(
                'ward-strength',
                'Ward strength',
                const SimpleValueShape(SimpleShapeKind.integer),
              ),
            ),
          ],
          rationale: 'Declare the item and its single-valued holder and power properties.',
        ),
      );
      await publish(powerDefinitions);
      final itemPowerBase = await changes().rebase(
        (await changes().load())!,
        startNew: true,
      );
      final itemPowerForm = UnfinishedItemPowerForm(
        baseRevision: itemPowerBase.content.baseRevision,
        representedContext: scope.representedContext!,
        clientRef: 'brooch-power',
        item: ExpressionReferenceInput(
          record: itemId.value,
          universe: scope.universe.value,
        ),
        holderPredicate: ExpressionReferenceInput(
          record: holderPropertyId.value,
          universe: scope.universe.value,
        ),
        powerPredicate: ExpressionReferenceInput(
          record: powerPropertyId.value,
          universe: scope.universe.value,
        ),
        value: const QualifierInput(kind: 'integer', value: '9007199254740997'),
        scope: ScopeInput(
          applicability: 'universe_wide',
          contextRecord: scope.representedContext!.value,
          contextUniverse: scope.universe.value,
        ),
        rationale:
            'Declare a possession-dependent power without asserting a holder.',
      );
      await session.saveItemPowerForm(scope, itemPowerForm, BigInt.zero);
      await session.close();
      session = await device.connect();
      final recoveredItemPower = (await session.loadItemPowerForm(scope))!.form;
      expect(
        recoveredItemPower.toWire().toText(),
        itemPowerForm.toWire().toText(),
      );
      final itemPowerDraft = SavedDraft.fromWire(
        await session.call(
          itemPowerDraftRequest(
            draft: itemPowerBase,
            form: recoveredItemPower,
            universe: const Selector('Relations'),
            continuity: scope.continuity,
          ),
        ),
      );
      final itemPowerPublished = await publish(itemPowerDraft);
      expect(itemPowerPublished.length, 1);
      expect(
        itemPowerPublished.single.payload.toWire().toText(),
        itemPowerOperation(itemPowerForm).record.toWire().toText(),
      );
      final representedBase = await changes().rebase(
        (await changes().load())!,
        startNew: true,
      );
      final representedForm = UnfinishedRepresentedContextForm(
        baseRevision: representedBase.content.baseRevision,
        representedContext: scope.representedContext!,
        universe: scope.universe,
        clientRef: 'dream-context',
        kind: 'authored',
        authoredLabel: 'Dream 記憶 😀',
        labels: [const PropertyLabelInput(language: 'en', text: 'Dream 記憶 😀')],
        parentEnabled: true,
        parent: ExpressionReferenceInput(
          record: scope.representedContext!.value,
          universe: scope.universe.value,
        ),
        rationale: 'Declare a represented account without inferring its event occurrence.',
      );
      await session.saveRepresentedContextForm(
        scope,
        representedForm,
        BigInt.zero,
      );
      await session.close();
      session = await device.connect();
      final recoveredRepresented = (await session.loadRepresentedContextForm(
        scope,
      ))!.form;
      expect(
        recoveredRepresented.toWire().toText(),
        representedForm.toWire().toText(),
      );
      final representedDraft = SavedDraft.fromWire(
        await session.call(
          representedContextDraftRequest(
            draft: representedBase,
            form: recoveredRepresented,
            universe: const Selector('Relations'),
            continuity: scope.continuity,
          ),
        ),
      );
      final representedPublished = await publish(representedDraft);
      expect(
        representedPublished.single.payload.toWire().toText(),
        representedContextOperation(representedForm).payload.toWire().toText(),
      );
      final selectedRepresented = Envelope<OpenedContext>.fromWire(
        await session.call(
          ToolEngineRequest(
            request: OpenContextRequest(
              universe: const Selector('Relations'),
              universeId: scope.universe,
              continuityId: scope.continuity,
              revision: const HeadRevisionSelector(),
              representedContext: ContextIdSelector(
                representedPublished.single.identity.recordId,
              ),
              temporalQuery: const TimelessFrameTime(),
              temporalSystems: [],
              perspective: const AuthorPerspective(),
            ),
          ),
        ),
        OpenedContext.fromWire,
      ).result;
      expect(
        selectedRepresented.frame.context.record,
        representedPublished.single.identity.recordId,
      );
      final boundaryBase = await changes().rebase(
        (await changes().load())!,
        startNew: true,
      );
      final boundaryForm = UnfinishedBoundaryForm(
        baseRevision: boundaryBase.content.baseRevision,
        representedContext: scope.representedContext!,
        clientRef: 'brooch-origin',
        key: 'Brooch origin',
        areaKind: 'record',
        record: ExpressionReferenceInput(
          record: itemId.value,
          universe: scope.universe.value,
        ),
        mode: 'author_reserved',
        constraints: [
          ExpressionInput(kind: 'lit', flags: {'value': false}),
          ExpressionInput(kind: 'lit', flags: {'value': false}),
        ],
        scope: ScopeInput(
          applicability: 'universe_wide',
          contextRecord: scope.representedContext!.value,
          contextUniverse: scope.universe.value,
        ),
        rationale: 'Reserve the brooch origin to its author.',
      );
      await session.saveBoundaryForm(scope, boundaryForm, BigInt.zero);
      await session.close();
      session = await device.connect();
      final recoveredBoundary = (await session.loadBoundaryForm(scope))!.form;
      expect(
        recoveredBoundary.toWire().toText(),
        boundaryForm.toWire().toText(),
      );
      final boundaryDraft = SavedDraft.fromWire(
        await session.call(
          boundaryDraftRequest(
            draft: boundaryBase,
            form: recoveredBoundary,
            universe: const Selector('Relations'),
            continuity: scope.continuity,
          ),
        ),
      );
      final boundaryPublished = await publish(boundaryDraft);
      expect(
        boundaryPublished.single.payload.toWire().toText(),
        boundaryOperation(boundaryForm).record.toWire().toText(),
      );
      final decisionBase = await changes().rebase(
        (await changes().load())!,
        startNew: true,
      );
      final decisionPrincipal = PrincipalId.parse(
        profile.value.replaceFirst('prf_', 'prn_'),
      );
      final decisionForm = UnfinishedIssueDecisionForm(
        baseRevision: decisionBase.content.baseRevision,
        representedContext: scope.representedContext!,
        clientRef: 'brooch-origin-decision',
        principal: decisionPrincipal,
        mode: 'defer',
        fingerprints: ['authored-finding 記憶 😀', 'authored-finding 記憶 😀'],
        scope: boundaryPublished.single.identity.recordId.value,
        rationale: 'Defer the origin question until research is complete.',
      );
      await session.saveIssueDecisionForm(scope, decisionForm, BigInt.zero);
      await session.close();
      session = await device.connect();
      final recoveredDecision = (await session.loadIssueDecisionForm(scope))!
          .form;
      expect(
        recoveredDecision.toWire().toText(),
        decisionForm.toWire().toText(),
      );
      final decisionDraft = SavedDraft.fromWire(
        await session.call(
          issueDecisionDraftRequest(
            draft: decisionBase,
            form: recoveredDecision,
            universe: const Selector('Relations'),
            continuity: scope.continuity,
            principal: decisionPrincipal,
          ),
        ),
      );
      final decisionPublished = await publish(decisionDraft);
      expect(
        decisionPublished.single.payload.toWire().toText(),
        issueDecisionOperation(
          decisionForm,
          principal: decisionPrincipal,
        ).record.toWire().toText(),
      );
      final acceptanceBase = await changes().rebase(
        (await changes().load())!,
        startNew: true,
      );
      final acceptanceForm = UnfinishedIssueDecisionForm(
        baseRevision: acceptanceBase.content.baseRevision,
        representedContext: scope.representedContext!,
        clientRef: 'origin-departure-acceptance',
        principal: decisionPrincipal,
        mode: 'accept',
        fingerprints: [],
        scope: boundaryPublished.single.identity.recordId.value,
        rationale: 'Accept the specifically scoped departure from the brooch origin boundary.',
      );
      final acceptanceDraft = SavedDraft.fromWire(
        await session.call(
          issueDecisionDraftRequest(
            draft: acceptanceBase,
            form: acceptanceForm,
            universe: const Selector('Relations'),
            continuity: scope.continuity,
            principal: decisionPrincipal,
          ),
        ),
      );
      final acceptancePublished = await publish(acceptanceDraft);
      final exceptionBase = await changes().rebase(
        (await changes().load())!,
        startNew: true,
      );
      final exceptionContext = await openDraftChoiceContext(
        changes(),
        exceptionBase,
      );
      final decisionChoices = await searchDraftChoices(
        changes: changes(),
        context: exceptionContext,
        kind: RecordKind.issueDecision,
        query: 'Accept decision: Brooch origin',
      );
      expect(
        decisionChoices.result.hits.single.recordId,
        acceptancePublished.single.identity.recordId,
      );
      final exceptionForm = UnfinishedExceptionForm(
        baseRevision: exceptionBase.content.baseRevision,
        representedContext: scope.representedContext!,
        clientRef: 'origin-exception',
        rule: ExpressionReferenceInput(
          record: boundaryPublished.single.identity.recordId.value,
          universe: scope.universe.value,
        ),
        ruleVersionEnabled: true,
        ruleVersion: boundaryPublished.single.recordVersionId.value,
        decision: ExpressionReferenceInput(
          record: acceptancePublished.single.identity.recordId.value,
          universe: scope.universe.value,
        ),
        scope: ScopeInput(
          applicability: 'universe_wide',
          contextRecord: scope.representedContext!.value,
          contextUniverse: scope.universe.value,
        ),
        rationale: 'A bounded author-approved departure 記憶 😀.',
      );
      await session.saveExceptionForm(scope, exceptionForm, BigInt.zero);
      await session.close();
      session = await device.connect();
      final recoveredException = (await session.loadExceptionForm(scope))!.form;
      expect(
        recoveredException.toWire().toText(),
        exceptionForm.toWire().toText(),
      );
      final exceptionDraft = SavedDraft.fromWire(
        await session.call(
          exceptionDraftRequest(
            draft: exceptionBase,
            form: recoveredException,
            universe: const Selector('Relations'),
            continuity: scope.continuity,
          ),
        ),
      );
      final exceptionPublished = await publish(exceptionDraft);
      expect(
        exceptionPublished.single.payload.toWire().toText(),
        exceptionOperation(exceptionForm).record.toWire().toText(),
      );
      final workSeedBase = await changes().rebase(
        (await changes().load())!,
        startNew: true,
      );
      final workSeedDraft = SavedDraft.fromWire(
        await session.call(
          SaveDraftEngineRequest(
            universe: const Selector('Relations'),
            continuityId: scope.continuity,
            expectedVersion: workSeedBase.version,
            content: DraftContent(
              baseRevision: workSeedBase.content.baseRevision,
              representedContext: scope.representedContext!,
              operations: [
                CreateWorldOperation(
                  clientRef: 'cedar-setting',
                  record: WorldRecord(selector: 'Cedar setting'),
                ),
                RecordNarrativeReferenceOperation(
                  clientRef: 'campaign-notes',
                  record: RecordKind.source,
                  payload: SourceRecord(
                    label: 'Campaign notes 記憶 😀',
                    origin: const OriginMetadata(
                      originNote: 'Authored source metadata.',
                    ),
                    versions: [],
                  ),
                ),
              ],
              rationale: 'Declare a work’s setting and source metadata.',
            ),
          ),
        ),
      );
      final workSeedPublished = await publish(workSeedDraft);
      final workWorld = workSeedPublished.singleWhere(
        (r) => r.payload is WorldRecord,
      );
      final workSource = workSeedPublished.singleWhere(
        (r) => r.payload is SourceRecord,
      );
      final workBase = await changes().rebase(
        (await changes().load())!,
        startNew: true,
      );
      final workForm = UnfinishedWorkForm(
        baseRevision: workBase.content.baseRevision,
        representedContext: scope.representedContext!,
        clientRef: 'campaign-chronicle',
        kind: 'series_chapter',
        title: 'Campaign chronicle 記憶 😀',
        labels: [const PropertyLabelInput(language: 'en', text: 'Chronicle')],
        sources: [
          ExpressionReferenceInput(
            record: workSource.identity.recordId.value,
            universe: scope.universe.value,
          ),
          ExpressionReferenceInput(
            record: workSource.identity.recordId.value,
            universe: scope.universe.value,
          ),
        ],
        associations: [
          WorkAssociationInput(
            world: worldFromChoice(
              RecordRef(
                universe: scope.universe,
                record: workWorld.identity.recordId,
              ),
            ).value,
            role: 'Setting',
            qualifiers: [
              const QualifierInput(
                key: 'amount',
                kind: 'integer',
                value: '9007199254740997',
              ),
              const QualifierInput(
                key: 'explicit',
                kind: 'boolean',
                value: 'false',
              ),
            ],
          ),
        ],
        rationale:
            'Describe an external chronicle without importing its prose.',
      );
      await session.saveWorkForm(scope, workForm, BigInt.zero);
      await session.close();
      session = await device.connect();
      final recoveredWork = (await session.loadWorkForm(scope))!.form;
      expect(recoveredWork.toWire().toText(), workForm.toWire().toText());
      final workDraft = SavedDraft.fromWire(
        await session.call(
          workDraftRequest(
            draft: workBase,
            form: recoveredWork,
            universe: const Selector('Relations'),
            continuity: scope.continuity,
          ),
        ),
      );
      final workPublished = await publish(workDraft);
      expect(
        workPublished.single.payload.toWire().toText(),
        workOperation(workForm).record.toWire().toText(),
      );
      final workEditionBase = await changes().rebase(
        (await changes().load())!,
        startNew: true,
      );
      final workEditionDraft = SavedDraft.fromWire(
        await session.call(
          SaveDraftEngineRequest(
            universe: const Selector('Relations'),
            continuityId: scope.continuity,
            expectedVersion: workEditionBase.version,
            content: DraftContent(
              baseRevision: workEditionBase.content.baseRevision,
              representedContext: scope.representedContext!,
              operations: [
                RecordNarrativeReferenceOperation(
                  clientRef: 'chronicle-edition',
                  record: RecordKind.workVersion,
                  payload: WorkVersionRecord(
                    work: RecordRef(
                      universe: scope.universe,
                      record: workPublished.single.identity.recordId,
                    ),
                    versionLabel: 'Draft edition 記憶 😀',
                    binding: const UnboundWork(),
                  ),
                ),
              ],
              rationale: 'Declare an explicitly unbound edition reference.',
            ),
          ),
        ),
      );
      final workEditionPublished = await publish(workEditionDraft);
      final workChoiceBase = await changes().rebase(
        (await changes().load())!,
        startNew: true,
      );
      final workChoiceContext = await openDraftChoiceContext(
        changes(),
        workChoiceBase,
      );
      final editionChoices = await searchDraftChoices(
        changes: changes(),
        context: workChoiceContext,
        kind: RecordKind.workVersion,
        query: 'Draft edition 記憶 😀',
      );
      expect(
        editionChoices.result.hits.single.recordId,
        workEditionPublished.single.identity.recordId,
      );
      final sagaBase = (await changes().load())!;
      final memberWork = ExpressionReferenceInput(
        record: workPublished.single.identity.recordId.value,
        universe: scope.universe.value,
      );
      final sagaForm = UnfinishedSagaForm(
        baseRevision: sagaBase.content.baseRevision,
        representedContext: scope.representedContext!,
        clientRef: 'collected-campaign',
        title: 'Collected campaign 記憶 😀',
        labels: [
          const PropertyLabelInput(language: 'en', text: 'Collected campaign'),
        ],
        memberships: [
          SagaMembershipInput(
            work: memberWork,
            role: 'chapter',
            orderEnabled: true,
            order: '9007199254740997',
          ),
          SagaMembershipInput(work: memberWork, role: 'appendix'),
        ],
        rationale: 'Group chapter and appendix roles without merging their continuity bindings.',
      );
      await session.saveSagaForm(scope, sagaForm, BigInt.zero);
      await session.close();
      session = await device.connect();
      final recoveredSaga = (await session.loadSagaForm(scope))!.form;
      expect(recoveredSaga.toWire().toText(), sagaForm.toWire().toText());
      final sagaDraft = SavedDraft.fromWire(
        await session.call(
          sagaDraftRequest(
            draft: sagaBase,
            form: recoveredSaga,
            universe: const Selector('Relations'),
            continuity: scope.continuity,
          ),
        ),
      );
      final sagaPublished = await publish(sagaDraft);
      expect(
        sagaPublished.single.payload.toWire().toText(),
        sagaOperation(sagaForm).record.toWire().toText(),
      );
      final typedEditionBase = await changes().rebase(
        (await changes().load())!,
        startNew: true,
      );
      final editionDescription = Envelope<Description>.fromWire(
        await session.call(
          ToolEngineRequest(
            request: DescribeSummaryRequest(
              universe: const Selector('Relations'),
            ),
          ),
        ),
        Description.fromWire,
      ).result;
      final alternateEdition = editionDescription.continuities.singleWhere(
        (c) => c.name == 'Alternate campaign',
      );
      final typedEditionForm = UnfinishedWorkVersionForm(
        baseRevision: typedEditionBase.content.baseRevision,
        representedContext: scope.representedContext!,
        clientRef: 'researched-edition',
        work: memberWork,
        versionLabel: 'Researched edition 記憶 😀',
        bindingKind: 'segments',
        segments: [
          WorkSegmentInput(
            segment: 'Opening',
            continuity: scope.continuity.value,
            revision: typedEditionBase.content.baseRevision.value,
          ),
          WorkSegmentInput(
            segment: 'Alternative',
            continuity: alternateEdition.id.value,
            revision: alternateEdition.revisionId.value,
          ),
        ],
        rationale: 'Keep each represented segment pinned to its authored continuity revision.',
      );
      await session.saveWorkVersionForm(scope, typedEditionForm, BigInt.zero);
      await session.close();
      session = await device.connect();
      final recoveredEdition = (await session.loadWorkVersionForm(scope))!.form;
      expect(
        recoveredEdition.toWire().toText(),
        typedEditionForm.toWire().toText(),
      );
      final typedEditionDraft = SavedDraft.fromWire(
        await session.call(
          workVersionDraftRequest(
            draft: typedEditionBase,
            form: recoveredEdition,
            universe: const Selector('Relations'),
            continuity: scope.continuity,
          ),
        ),
      );
      final typedEditionPublished = await publish(typedEditionDraft);
      expect(
        typedEditionPublished.single.payload.toWire().toText(),
        workVersionOperation(typedEditionForm).payload.toWire().toText(),
      );
      final afterEditionDescription = Envelope<Description>.fromWire(
        await session.call(
          ToolEngineRequest(
            request: DescribeSummaryRequest(
              universe: const Selector('Relations'),
            ),
          ),
        ),
        Description.fromWire,
      ).result;
      expect(
        afterEditionDescription.continuities
            .singleWhere((c) => c.id == alternateEdition.id)
            .revisionId,
        alternateEdition.revisionId,
      );
      final bindingBase = await changes().rebase(
        (await changes().load())!,
        startNew: true,
      );
      final bindingScope = EditorFormScope(
        instance: scope.instance,
        profile: scope.profile,
        universe: scope.universe,
        continuity: scope.continuity,
        representedContext: scope.representedContext,
        typeClientRef: typedEditionPublished.single.identity.recordId.value,
      );
      final bindingForm =
          workBindingFormFromRecord(
            record: typedEditionPublished.single,
            baseRevision: bindingBase.content.baseRevision,
            representedContext: scope.representedContext!,
          ).copyWith(
            bindingKind: 'unbound',
            rationale: 'Keep the edition explicitly unbound while reviewing its account.',
          );
      await session.saveWorkVersionForm(bindingScope, bindingForm, BigInt.zero);
      await session.close();
      session = await device.connect();
      final recoveredBinding = (await session.loadWorkVersionForm(
        bindingScope,
      ))!.form;
      expect(recoveredBinding.toWire().toText(), bindingForm.toWire().toText());
      final bindingDraft = SavedDraft.fromWire(
        await session.call(
          workVersionDraftRequest(
            draft: bindingBase,
            form: recoveredBinding,
            universe: const Selector('Relations'),
            continuity: scope.continuity,
          ),
        ),
      );
      final bindingPublished = await publish(bindingDraft);
      final beforeBinding =
          typedEditionPublished.single.payload as WorkVersionRecord;
      final afterBinding = bindingPublished.single.payload as WorkVersionRecord;
      expect(
        bindingPublished.single.identity.recordId,
        typedEditionPublished.single.identity.recordId,
      );
      expect(
        bindingPublished.single.recordVersionId,
        isNot(typedEditionPublished.single.recordVersionId),
      );
      expect(afterBinding.work, beforeBinding.work);
      expect(afterBinding.versionLabel, beforeBinding.versionLabel);
      expect(afterBinding.binding, const UnboundWork());
      final bindingHistoryContext = await openDraftChoiceContext(
        changes(),
        bindingBase,
      );
      final retainedEdition = await readContextRecord(
        session: session,
        universe: LibraryEntry(scope.universe, 'Relations'),
        context: bindingHistoryContext,
        record: typedEditionPublished.single.identity.recordId,
      );
      expect(
        retainedEdition.toWire().toText(),
        typedEditionPublished.single.toWire().toText(),
      );
      final membershipBase = await changes().rebase(
        (await changes().load())!,
        startNew: true,
      );
      final membershipScope = EditorFormScope(
        instance: scope.instance,
        profile: scope.profile,
        universe: scope.universe,
        continuity: scope.continuity,
        representedContext: scope.representedContext,
        typeClientRef: sagaPublished.single.identity.recordId.value,
      );
      final membershipForm =
          sagaMembershipFormFromRecord(
            record: sagaPublished.single,
            baseRevision: membershipBase.content.baseRevision,
            representedContext: scope.representedContext!,
          ).copyWith(
            memberships: [
              SagaMembershipInput(
                work: memberWork,
                role: 'chapter',
                orderEnabled: true,
                order: '9007199254740999',
              ),
            ],
            rationale: 'Revise the existing chapter ordering without replacing other roles.',
          );
      await session.saveSagaForm(membershipScope, membershipForm, BigInt.zero);
      await session.close();
      session = await device.connect();
      final recoveredMembership = (await session.loadSagaForm(membershipScope))!
          .form;
      expect(
        recoveredMembership.toWire().toText(),
        membershipForm.toWire().toText(),
      );
      final membershipDraft = SavedDraft.fromWire(
        await session.call(
          sagaDraftRequest(
            draft: membershipBase,
            form: recoveredMembership,
            universe: const Selector('Relations'),
            continuity: scope.continuity,
          ),
        ),
      );
      final membershipPublished = await publish(membershipDraft);
      final beforeMembership = sagaPublished.single.payload as SagaRecord;
      final afterMembership = membershipPublished.single.payload as SagaRecord;
      expect(
        membershipPublished.single.identity.recordId,
        sagaPublished.single.identity.recordId,
      );
      expect(afterMembership.title, beforeMembership.title);
      expect(afterMembership.labels, beforeMembership.labels);
      expect(afterMembership.memberships.length, 2);
      expect(
        afterMembership.memberships.first.order.toString(),
        '9007199254740999',
      );
      expect(
        afterMembership.memberships.last.toWire().toText(),
        beforeMembership.memberships.last.toWire().toText(),
      );
      final membershipHistoryContext = await openDraftChoiceContext(
        changes(),
        membershipBase,
      );
      final retainedSaga = await readContextRecord(
        session: session,
        universe: LibraryEntry(scope.universe, 'Relations'),
        context: membershipHistoryContext,
        record: sagaPublished.single.identity.recordId,
      );
      expect(
        retainedSaga.toWire().toText(),
        sagaPublished.single.toWire().toText(),
      );
      final newRoleBase = await changes().rebase(
        (await changes().load())!,
        startNew: true,
      );
      final newRoleForm =
          sagaMembershipFormFromRecord(
            record: membershipPublished.single,
            baseRevision: newRoleBase.content.baseRevision,
            representedContext: scope.representedContext!,
          ).copyWith(
            memberships: [
              SagaMembershipInput(work: memberWork, role: 'reference'),
            ],
            rationale: 'Add a reference role without removing the existing memberships.',
          );
      final newRoleDraft = SavedDraft.fromWire(
        await session.call(
          sagaDraftRequest(
            draft: newRoleBase,
            form: newRoleForm,
            universe: const Selector('Relations'),
            continuity: scope.continuity,
          ),
        ),
      );
      final newRolePublished = await publish(newRoleDraft);
      final newRolePayload = newRolePublished.single.payload as SagaRecord;
      expect(newRolePayload.memberships.length, 3);
      expect(
        newRolePayload.memberships.take(2).map((m) => m.toWire().toText()),
        afterMembership.memberships.map((m) => m.toWire().toText()),
      );
      expect(newRolePayload.memberships.last.role, 'reference');
      final associationBase = await changes().rebase(
        (await changes().load())!,
        startNew: true,
      );
      final associationScope = EditorFormScope(
        instance: scope.instance,
        profile: scope.profile,
        universe: scope.universe,
        continuity: scope.continuity,
        representedContext: scope.representedContext,
        typeClientRef: workPublished.single.identity.recordId.value,
      );
      final associationForm =
          workAssociationFormFromRecord(
            record: workPublished.single,
            baseRevision: associationBase.content.baseRevision,
            representedContext: scope.representedContext!,
          ).copyWith(
            associations: [
              WorkAssociationInput(
                world: workForm.associations.single.world,
                role: 'Referenced',
                qualifiers: [
                  const QualifierInput(
                    key: 'count',
                    kind: 'integer',
                    value: '9007199254740997',
                  ),
                ],
              ),
            ],
            rationale: 'Add a referenced world role without replacing the setting association.',
          );
      await session.saveWorkForm(
        associationScope,
        associationForm,
        BigInt.zero,
      );
      await session.close();
      session = await device.connect();
      final recoveredAssociation = (await session.loadWorkForm(
        associationScope,
      ))!.form;
      expect(
        recoveredAssociation.toWire().toText(),
        associationForm.toWire().toText(),
      );
      final associationDraft = SavedDraft.fromWire(
        await session.call(
          workDraftRequest(
            draft: associationBase,
            form: recoveredAssociation,
            universe: const Selector('Relations'),
            continuity: scope.continuity,
          ),
        ),
      );
      final associationPublished = await publish(associationDraft);
      final beforeAssociation = workPublished.single.payload as WorkRecord;
      final afterAssociation =
          associationPublished.single.payload as WorkRecord;
      expect(
        associationPublished.single.identity.recordId,
        workPublished.single.identity.recordId,
      );
      expect(afterAssociation.kind, beforeAssociation.kind);
      expect(afterAssociation.title, beforeAssociation.title);
      expect(afterAssociation.labels, beforeAssociation.labels);
      expect(afterAssociation.sourceRefs, beforeAssociation.sourceRefs);
      expect(afterAssociation.versions, beforeAssociation.versions);
      expect(afterAssociation.worldAssociations.length, 2);
      expect(
        afterAssociation.worldAssociations.first.toWire().toText(),
        beforeAssociation.worldAssociations.single.toWire().toText(),
      );
      expect(
        afterAssociation.worldAssociations.last.toWire().toText(),
        workAssociationOperation(associationForm).association.toWire().toText(),
      );
      final associationHistoryContext = await openDraftChoiceContext(
        changes(),
        associationBase,
      );
      final retainedWork = await readContextRecord(
        session: session,
        universe: LibraryEntry(scope.universe, 'Relations'),
        context: associationHistoryContext,
        record: workPublished.single.identity.recordId,
      );
      expect(
        retainedWork.toWire().toText(),
        workPublished.single.toWire().toText(),
      );
      final sceneEditionBase = await changes().rebase(
        (await changes().load())!,
        startNew: true,
      );
      final sceneEditionForm = UnfinishedWorkVersionForm(
        baseRevision: sceneEditionBase.content.baseRevision,
        representedContext: scope.representedContext!,
        clientRef: RecordId.generate().value,
        work: ExpressionReferenceInput(
          record: associationPublished.single.identity.recordId.value,
          universe: scope.universe.value,
        ),
        versionLabel: 'Scene canon edition',
        bindingKind: 'bound',
        continuity: scope.continuity.value,
        revision: sceneEditionBase.content.baseRevision.value,
        rationale: 'Bind the scene edition to its disclosed canon.',
      );
      final sceneEditionDraft = SavedDraft.fromWire(
        await session.call(
          workVersionDraftRequest(
            draft: sceneEditionBase,
            form: sceneEditionForm,
            universe: const Selector('Relations'),
            continuity: scope.continuity,
          ),
        ),
      );
      final sceneEditionPublished = await publish(sceneEditionDraft);
      final sceneBase = await changes().rebase(
        (await changes().load())!,
        startNew: true,
      );
      final sceneScope = EditorFormScope(
        instance: scope.instance,
        profile: scope.profile,
        universe: scope.universe,
        continuity: scope.continuity,
        representedContext: scope.representedContext,
      );
      final sceneForm = UnfinishedSceneForm(
        baseRevision: sceneBase.content.baseRevision,
        representedContext: scope.representedContext!,
        clientRef: RecordId.generate().value,
        sceneId: 'Journey opening 記憶 😀',
        edition: ExpressionReferenceInput(
          record: sceneEditionPublished.single.identity.recordId.value,
          universe: scope.universe.value,
        ),
        editionVersion: sceneEditionPublished.single.recordVersionId.value,
        viewpointEnabled: true,
        viewpoint: ExpressionReferenceInput(
          record: participant(1).record.value,
          universe: scope.universe.value,
        ),
        narrationEnabled: true,
        narration: ExpressionReferenceInput(
          record: scope.representedContext!.value,
          universe: scope.universe.value,
        ),
        positionEnabled: true,
        position: '9007199254740997',
        disclosed: [
          for (var i = 0; i < 2; i++)
            ExpressionReferenceInput(
              record: claimPublished.single.identity.recordId.value,
              universe: scope.universe.value,
            ),
        ],
        depicted: [
          for (var i = 0; i < 2; i++)
            ExpressionReferenceInput(
              record: events.first.identity.recordId.value,
              universe: scope.universe.value,
            ),
        ],
        associations: workForm.associations,
        rationale: 'Declare scene metadata without changing event occurrence or knowledge.',
      );
      await session.saveSceneForm(sceneScope, sceneForm, BigInt.zero);
      await session.close();
      session = await device.connect();
      final recoveredScene = (await session.loadSceneForm(sceneScope))!.form;
      expect(recoveredScene.toWire().toText(), sceneForm.toWire().toText());
      final sceneDraft = SavedDraft.fromWire(
        await session.call(
          sceneDraftRequest(
            draft: sceneBase,
            form: recoveredScene,
            universe: const Selector('Relations'),
            continuity: scope.continuity,
          ),
        ),
      );
      final scenePublished = await publish(sceneDraft);
      expect(
        scenePublished.single.payload.toWire().toText(),
        sceneOperation(sceneForm).payload.toWire().toText(),
      );
      final sceneContext = await openDraftChoiceContext(
        changes(),
        await changes().rebase((await changes().load())!, startNew: true),
      );
      final sceneChoices = await searchDraftChoices(
        changes: changes(),
        context: sceneContext,
        kind: RecordKind.sceneRef,
      );
      expect(sceneChoices.result.hits.single.label, sceneForm.sceneId);
      final unchangedEvent = await readContextRecord(
        session: session,
        universe: LibraryEntry(scope.universe, 'Relations'),
        context: sceneContext,
        record: events.first.identity.recordId,
      );
      expect(unchangedEvent.toWire().toText(), events.first.toWire().toText());
      final correctionBase = await changes().rebase(
        (await changes().load())!,
        startNew: true,
      );
      final correctionScope = EditorFormScope(
        instance: scope.instance,
        profile: scope.profile,
        universe: scope.universe,
        continuity: scope.continuity,
        representedContext: scope.representedContext,
        typeClientRef: scenePublished.single.identity.recordId.value,
      );
      final correctionForm =
          sceneCorrectionFormFromRecord(
            record: scenePublished.single,
            baseRevision: correctionBase.content.baseRevision,
            representedContext: scope.representedContext!,
          ).copyWith(
            position: '9007199254740999',
            narrationEnabled: false,
            rationale:
                'Correct the reader order and remove the narration frame.',
          );
      await session.saveSceneForm(correctionScope, correctionForm, BigInt.zero);
      await session.close();
      session = await device.connect();
      final recoveredCorrection = (await session.loadSceneForm(
        correctionScope,
      ))!.form;
      expect(
        recoveredCorrection.toWire().toText(),
        correctionForm.toWire().toText(),
      );
      final correctionDraft = SavedDraft.fromWire(
        await session.call(
          sceneDraftRequest(
            draft: correctionBase,
            form: recoveredCorrection,
            universe: const Selector('Relations'),
            continuity: scope.continuity,
          ),
        ),
      );
      final correctedScene = await publish(correctionDraft);
      expect(
        correctedScene.single.identity.recordId,
        scenePublished.single.identity.recordId,
      );
      expect(
        correctedScene.single.payload.toWire().toText(),
        sceneCorrectionOperation(correctionForm).replacement.toWire().toText(),
      );
      final historicalScene = await readContextRecord(
        session: session,
        universe: LibraryEntry(scope.universe, 'Relations'),
        context: await openDraftChoiceContext(changes(), correctionBase),
        record: scenePublished.single.identity.recordId,
      );
      expect(
        historicalScene.toWire().toText(),
        scenePublished.single.toWire().toText(),
      );
      const excerpt = 'The journey begins 記憶 😀';
      final passageSourceBase = await changes().rebase(
        (await changes().load())!,
        startNew: true,
      );
      final stagedPassageSource = WireFields(
        await session.call(
          const StageSourceEngineRequest(
            universe: Selector('Relations'),
            label: 'Chapter excerpt',
            text: excerpt,
          ),
        ),
        {'canonical', 'operations'},
      );
      final sourceDraft = await changes().saveContent(
        passageSourceBase,
        DraftContent(
          baseRevision: passageSourceBase.content.baseRevision,
          representedContext: scope.representedContext!,
          operations: stagedPassageSource
              .array('operations')
              .map(DomainOperation.fromWire),
          rationale: 'Retain submitted chapter text.',
        ),
      );
      final passageSourcePublished = await publish(sourceDraft);
      final passageSourceVersion = passageSourcePublished.singleWhere(
        (r) => r.payload is SourceVersionRecord,
      );
      final passageAnchorBase = await changes().rebase(
        (await changes().load())!,
        startNew: true,
      );
      final passageAnchorDraft = await changes().saveContent(
        passageAnchorBase,
        DraftContent(
          baseRevision: passageAnchorBase.content.baseRevision,
          representedContext: scope.representedContext!,
          operations: [
            AddSourceAnchorOperation(
              clientRef: RecordId.generate().value,
              record: AnchorRecord(
                sourceVersion: VersionRef(
                  universe: scope.universe,
                  record: passageSourceVersion.identity.recordId,
                  version: passageSourceVersion.recordVersionId,
                ),
                locator: ByteRangeLocator(
                  BigInt.zero,
                  BigInt.from(utf8.encode(excerpt).length),
                ),
                excerptDigest: sha256.convert(utf8.encode(excerpt)).toString(),
                excerpt: excerpt,
                context: RecordRef(
                  universe: scope.universe,
                  record: scope.representedContext!,
                ),
              ),
            ),
          ],
          rationale: 'Select the complete chapter excerpt.',
        ),
      );
      final passageAnchorPublished = await publish(passageAnchorDraft);
      final passageBase = await changes().rebase(
        (await changes().load())!,
        startNew: true,
      );
      final passageScope = EditorFormScope(
        instance: scope.instance,
        profile: scope.profile,
        universe: scope.universe,
        continuity: scope.continuity,
        representedContext: scope.representedContext,
      );
      final passageForm = UnfinishedPassageForm(
        baseRevision: passageBase.content.baseRevision,
        representedContext: scope.representedContext!,
        clientRef: RecordId.generate().value,
        passageId: 'Journey paragraph 記憶 😀',
        edition: ExpressionReferenceInput(
          record: sceneEditionPublished.single.identity.recordId.value,
          universe: scope.universe.value,
        ),
        editionVersion: sceneEditionPublished.single.recordVersionId.value,
        anchorEnabled: true,
        anchor: ExpressionReferenceInput(
          record: passageAnchorPublished.single.identity.recordId.value,
          universe: scope.universe.value,
        ),
        rationale:
            'Link the passage to its edition and submitted source anchor.',
      );
      await session.savePassageForm(passageScope, passageForm, BigInt.zero);
      await session.close();
      session = await device.connect();
      final recoveredPassage = (await session.loadPassageForm(passageScope))!
          .form;
      expect(recoveredPassage.toWire().toText(), passageForm.toWire().toText());
      final passageDraft = SavedDraft.fromWire(
        await session.call(
          passageDraftRequest(
            draft: passageBase,
            form: recoveredPassage,
            universe: const Selector('Relations'),
            continuity: scope.continuity,
          ),
        ),
      );
      final passagePublished = await publish(passageDraft);
      expect(
        passagePublished.single.payload.toWire().toText(),
        passageOperation(passageForm).payload.toWire().toText(),
      );
      final passageContext = await openDraftChoiceContext(
        changes(),
        await changes().rebase((await changes().load())!, startNew: true),
      );
      final passageChoices = await searchDraftChoices(
        changes: changes(),
        context: passageContext,
        kind: RecordKind.passageRef,
      );
      expect(passageChoices.result.hits.single.label, passageForm.passageId);
      final powerCorrectionBase = await changes().rebase(
        (await changes().load())!,
        startNew: true,
      );
      final powerCorrectionScope = EditorFormScope(
        instance: scope.instance,
        profile: scope.profile,
        universe: scope.universe,
        continuity: scope.continuity,
        representedContext: scope.representedContext,
        typeClientRef: itemPowerPublished.single.identity.recordId.value,
      );
      final powerCorrectionForm =
          itemPowerCorrectionFormFromRecord(
            record: itemPowerPublished.single,
            baseRevision: powerCorrectionBase.content.baseRevision,
            representedContext: scope.representedContext!,
          ).copyWith(
            value: const QualifierInput(
              kind: 'integer',
              value: '9007199254740999',
            ),
            rationale: 'Correct the declared ward strength.',
          );
      await session.saveItemPowerForm(
        powerCorrectionScope,
        powerCorrectionForm,
        BigInt.zero,
      );
      await session.close();
      session = await device.connect();
      final recoveredPowerCorrection = (await session.loadItemPowerForm(
        powerCorrectionScope,
      ))!.form;
      expect(
        recoveredPowerCorrection.toWire().toText(),
        powerCorrectionForm.toWire().toText(),
      );
      final powerCorrectionDraft = SavedDraft.fromWire(
        await session.call(
          itemPowerDraftRequest(
            draft: powerCorrectionBase,
            form: recoveredPowerCorrection,
            universe: const Selector('Relations'),
            continuity: scope.continuity,
          ),
        ),
      );
      final correctedPower = await publish(powerCorrectionDraft);
      expect(
        correctedPower.single.identity.recordId,
        itemPowerPublished.single.identity.recordId,
      );
      expect(
        correctedPower.single.payload.toWire().toText(),
        itemPowerCorrectionOperation(powerCorrectionForm).replacement
            .toWire()
            .toText(),
      );
      final retainedPower = await readContextRecord(
        session: session,
        universe: LibraryEntry(scope.universe, 'Relations'),
        context: await openDraftChoiceContext(changes(), powerCorrectionBase),
        record: itemPowerPublished.single.identity.recordId,
      );
      expect(
        retainedPower.toWire().toText(),
        itemPowerPublished.single.toWire().toText(),
      );
      final communicationCorrectionBase = await changes().rebase(
        (await changes().load())!,
        startNew: true,
      );
      final communicationCorrectionScope = EditorFormScope(
        instance: scope.instance,
        profile: scope.profile,
        universe: scope.universe,
        continuity: scope.continuity,
        representedContext: scope.representedContext,
        typeClientRef: communicationPublished.single.identity.recordId.value,
      );
      final communicationCorrectionForm =
          communicationCorrectionFormFromRecord(
            record: communicationPublished.single,
            baseRevision: communicationCorrectionBase.content.baseRevision,
            representedContext: scope.representedContext!,
          ).copyWith(
            receivedAt: TemporalValidityInput(
              kind: 'instant',
              calendar: calendar.value,
              start: const TemporalBoundInput(value: '9007199254741015'),
            ),
            rationale: 'Correct the historical message receipt time.',
          );
      await session.saveCommunicationForm(
        communicationCorrectionScope,
        communicationCorrectionForm,
        BigInt.zero,
      );
      await session.close();
      session = await device.connect();
      final recoveredCommunicationCorrection =
          (await session.loadCommunicationForm(communicationCorrectionScope))!
              .form;
      expect(
        recoveredCommunicationCorrection.toWire().toText(),
        communicationCorrectionForm.toWire().toText(),
      );
      final communicationCorrectionDraft = SavedDraft.fromWire(
        await session.call(
          communicationDraftRequest(
            draft: communicationCorrectionBase,
            form: recoveredCommunicationCorrection,
            universe: const Selector('Relations'),
            continuity: scope.continuity,
          ),
        ),
      );
      final correctedCommunication = await publish(
        communicationCorrectionDraft,
      );
      expect(
        correctedCommunication.single.identity.recordId,
        communicationPublished.single.identity.recordId,
      );
      expect(
        correctedCommunication.single.payload.toWire().toText(),
        communicationCorrectionOperation(communicationCorrectionForm)
            .replacement
            .toWire()
            .toText(),
      );
      final retainedCommunication = await readContextRecord(
        session: session,
        universe: LibraryEntry(scope.universe, 'Relations'),
        context: await openDraftChoiceContext(
          changes(),
          communicationCorrectionBase,
        ),
        record: communicationPublished.single.identity.recordId,
      );
      expect(
        retainedCommunication.toWire().toText(),
        communicationPublished.single.toWire().toText(),
      );
      final attitudeCorrectionBase = await changes().rebase(
        (await changes().load())!,
        startNew: true,
      );
      final attitudeCorrectionScope = EditorFormScope(
        instance: scope.instance,
        profile: scope.profile,
        universe: scope.universe,
        continuity: scope.continuity,
        representedContext: scope.representedContext,
        typeClientRef: attitudePublished.single.identity.recordId.value,
      );
      final attitudeCorrectionForm =
          attitudeCorrectionFormFromRecord(
            record: attitudePublished.single,
            baseRevision: attitudeCorrectionBase.content.baseRevision,
            representedContext: scope.representedContext!,
          ).copyWith(
            certainty: 'Tentative account 記憶 😀',
            rationale: 'Correct the authored certainty of Nia’s suspicion.',
          );
      await session.saveAttitudeForm(
        attitudeCorrectionScope,
        attitudeCorrectionForm,
        BigInt.zero,
      );
      await session.close();
      session = await device.connect();
      final recoveredAttitudeCorrection = (await session.loadAttitudeForm(
        attitudeCorrectionScope,
      ))!.form;
      expect(
        recoveredAttitudeCorrection.toWire().toText(),
        attitudeCorrectionForm.toWire().toText(),
      );
      final attitudeCorrectionDraft = SavedDraft.fromWire(
        await session.call(
          attitudeDraftRequest(
            draft: attitudeCorrectionBase,
            form: recoveredAttitudeCorrection,
            universe: const Selector('Relations'),
            continuity: scope.continuity,
          ),
        ),
      );
      final correctedAttitude = await publish(attitudeCorrectionDraft);
      expect(
        correctedAttitude.single.identity.recordId,
        attitudePublished.single.identity.recordId,
      );
      expect(
        correctedAttitude.single.payload.toWire().toText(),
        attitudeCorrectionOperation(attitudeCorrectionForm).replacement
            .toWire()
            .toText(),
      );
      final retainedAttitude = await readContextRecord(
        session: session,
        universe: LibraryEntry(scope.universe, 'Relations'),
        context: await openDraftChoiceContext(
          changes(),
          attitudeCorrectionBase,
        ),
        record: attitudePublished.single.identity.recordId,
      );
      expect(
        retainedAttitude.toWire().toText(),
        attitudePublished.single.toWire().toText(),
      );
      final receiptKnowledgeBase = await changes().rebase(
        (await changes().load())!,
        startNew: true,
      );
      final receiptClaimId = RecordId.generate(),
          receiptMessageId = RecordId.generate(),
          receiptPropertyId = RecordId.generate(),
          receiptAlternativeId = RecordId.generate();
      final receiptClaim = PropositionRecord(
        subject: participant(0),
        predicate: RecordRef(
          universe: scope.universe,
          record: receiptPropertyId,
        ),
        context: evidence.scope.context,
        quantification: Quantification.particular,
        value: const BooleanValue(true),
      );
      final receiptKnowledgeDraft = await changes().saveContent(
        receiptKnowledgeBase,
        DraftContent(
          baseRevision: receiptKnowledgeBase.content.baseRevision,
          representedContext: scope.representedContext!,
          rationale: 'Record explicit truthful receipt knowledge.',
          operations: [
            ReviseDefinitionOperation(
              record: RecordRef(
                universe: scope.universe,
                record: knowledgePublished.single.identity.recordId,
              ),
              expectedVersion: knowledgePublished.single.recordVersionId,
              replacement: RuleRecord.fromWire(
                CanonicalObject(
                  (knowledgePublished.single.payload as RuleRecord)
                      .toWire()
                      .fields
                      .map(
                        (e) => e.key == 'knowledgePolicy'
                            ? MapEntry(
                                e.key,
                                KnowledgePolicy(
                                  context: receiptClaim.context,
                                  mode: KnowledgeMode.justified,
                                ).toWire(),
                              )
                            : e,
                      ),
                ),
              ),
            ),
            DefinePropertyOperation(
              clientRef: receiptPropertyId.value,
              record: PropertyRecord(
                namespace: 'authored',
                key: 'receipt-account-established',
                labels: {'en': 'Receipt account established'},
                subjectTypes: [person],
                value: const SimpleValueShape(SimpleShapeKind.boolean),
                multiplicity: Multiplicity.single,
                persistence: PersistenceSemantics.unspecified,
                exclusive: false,
                symmetric: false,
                transitive: false,
              ),
            ),
            for (final claimId in [receiptClaimId, receiptAlternativeId])
              AssertPropositionOperation(
                clientRef: claimId.value,
                proposition: receiptClaim,
                assertion: AssertionRecord(
                  attributeMode: AttributeMode.instance,
                  proposition: RecordRef(
                    universe: scope.universe,
                    record: claimId,
                  ),
                  polarity: Polarity.support,
                  scope: evidence.scope,
                  validity: CalendarIntervalValidity(
                    calendar,
                    const ExactBound('0'),
                    const UnboundedBound(),
                  ),
                  persistence: PersistenceSemantics.unspecified,
                  precision: Precision.exact,
                  basis: const AuthorDecisionBasis(
                    'The account is established.',
                  ),
                ),
              ),
            RecordCommunicationOperation(
              clientRef: receiptMessageId.value,
              record: CommunicationRecord(
                sender: participant(0),
                intendedRecipients: [participant(2)],
                actualRecipients: [participant(2)],
                content: [
                  RecordRef(universe: scope.universe, record: receiptClaimId),
                  RecordRef(
                    universe: scope.universe,
                    record: receiptAlternativeId,
                  ),
                ],
                channel: 'mail',
                distorted: false,
                sentAt: ExactTime(calendar, '20'),
                receivedAt: ExactTime(calendar, '9007199254741015'),
              ),
            ),
            AddBeliefOperation(
              clientRef: RecordId.generate().value,
              record: EpistemicAttitudeRecord(
                holder: participant(2),
                proposition: RecordRef(
                  universe: scope.universe,
                  record: receiptClaimId,
                ),
                attitude: EpistemicAttitudeKind.knows,
                validity: CalendarIntervalValidity(
                  calendar,
                  const ExactBound('9007199254741015'),
                  const UnboundedBound(),
                ),
                basis: const AuthorDecisionBasis('Orr understood the receipt.'),
                acquisition: KnowledgeAcquisition(
                  truthContext: receiptClaim.context,
                  time: ExactTime(calendar, '9007199254741015'),
                  basis: CommunicationKnowledge(
                    communication: RecordRef(
                      universe: scope.universe,
                      record: receiptMessageId,
                    ),
                    interpretation: RecordRef(
                      universe: scope.universe,
                      record: receiptClaimId,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
      final receiptKnowledgePublished = await publish(receiptKnowledgeDraft);
      final receiptKnowledge = receiptKnowledgePublished.singleWhere(
        (r) => r.payload is EpistemicAttitudeRecord,
      );
      final interpretationBase = await changes().rebase(
        (await changes().load())!,
        startNew: true,
      );
      final interpretationScope = EditorFormScope(
        instance: scope.instance,
        profile: scope.profile,
        universe: scope.universe,
        continuity: scope.continuity,
        representedContext: scope.representedContext,
        typeClientRef: receiptKnowledge.identity.recordId.value,
      );
      final interpretationForm =
          interpretationFormFromRecord(
            record: receiptKnowledge,
            baseRevision: interpretationBase.content.baseRevision,
            representedContext: scope.representedContext!,
          ).copyWith(
            interpretation: ExpressionReferenceInput(
              record: receiptAlternativeId.value,
              universe: scope.universe.value,
            ),
            rationale: 'Use the equivalent authored account claim as the receipt interpretation.',
          );
      await session.saveInterpretationForm(
        interpretationScope,
        interpretationForm,
        BigInt.zero,
      );
      await session.close();
      session = await device.connect();
      final recoveredInterpretation = (await session.loadInterpretationForm(
        interpretationScope,
      ))!.form;
      expect(
        recoveredInterpretation.toWire().toText(),
        interpretationForm.toWire().toText(),
      );
      final interpretationDraft = SavedDraft.fromWire(
        await session.call(
          interpretationDraftRequest(
            draft: interpretationBase,
            form: recoveredInterpretation,
            universe: const Selector('Relations'),
            continuity: scope.continuity,
          ),
        ),
      );
      final correctedInterpretation = await publish(interpretationDraft);
      final knowledgeBefore =
          receiptKnowledge.payload as EpistemicAttitudeRecord;
      final knowledgeAfter =
          correctedInterpretation.single.payload as EpistemicAttitudeRecord;
      expect(
        correctedInterpretation.single.identity.recordId,
        receiptKnowledge.identity.recordId,
      );
      expect(
        knowledgeAfter.proposition,
        RecordRef(universe: scope.universe, record: receiptAlternativeId),
      );
      expect(knowledgeAfter.holder, knowledgeBefore.holder);
      expect(knowledgeAfter.basis, knowledgeBefore.basis);
      expect(
        knowledgeAfter.validity.toWire().toText(),
        knowledgeBefore.validity.toWire().toText(),
      );
      expect(
        knowledgeAfter.acquisition!.truthContext,
        knowledgeBefore.acquisition!.truthContext,
      );
      expect(
        knowledgeAfter.acquisition!.time.encode(canonical: true).toText(),
        knowledgeBefore.acquisition!.time.encode(canonical: true).toText(),
      );
      expect(
        (knowledgeAfter.acquisition!.basis as CommunicationKnowledge)
            .communication,
        (knowledgeBefore.acquisition!.basis as CommunicationKnowledge)
            .communication,
      );
      final historicalKnowledge = await readContextRecord(
        session: session,
        universe: LibraryEntry(scope.universe, 'Relations'),
        context: await openDraftChoiceContext(changes(), interpretationBase),
        record: receiptKnowledge.identity.recordId,
      );
      expect(
        historicalKnowledge.toWire().toText(),
        receiptKnowledge.toWire().toText(),
      );
      final relationRevisionBase = await changes().rebase(
        (await changes().load())!,
        startNew: true,
      );
      final relationRevisionScope = EditorFormScope(
        instance: scope.instance,
        profile: scope.profile,
        universe: scope.universe,
        continuity: scope.continuity,
        representedContext: scope.representedContext,
        typeClientRef: published.identity.recordId.value,
      );
      final relationRevisionForm = UnfinishedRelationForm.fromWire(
        CanonicalObject(
          relationRevisionFormFromRecord(
            record: published,
            baseRevision: relationRevisionBase.content.baseRevision,
            representedContext: scope.representedContext!,
          ).toWire().fields.map(
            (e) => e.key == 'labels'
                ? MapEntry(
                    'labels',
                    CanonicalArray([
                      const PropertyLabelInput(
                        language: 'en',
                        text: 'Reviewed account 記憶 😀',
                      ).toWire(),
                    ]),
                  )
                : e.key == 'rationale'
                ? MapEntry(
                    'rationale',
                    CanonicalString('Clarify the account relation label.'),
                  )
                : e,
          ),
        ),
      );
      await session.saveRelationForm(
        relationRevisionScope,
        relationRevisionForm,
        BigInt.zero,
      );
      await session.close();
      session = await device.connect();
      final recoveredRelationRevision = (await session.loadRelationForm(
        relationRevisionScope,
      ))!.form;
      expect(
        recoveredRelationRevision.toWire().toText(),
        relationRevisionForm.toWire().toText(),
      );
      final relationRevisionDraft = SavedDraft.fromWire(
        await session.call(
          relationDraftRequest(
            draft: relationRevisionBase,
            form: recoveredRelationRevision,
            universe: const Selector('Relations'),
            continuity: scope.continuity,
          ),
        ),
      );
      final revisedRelation = await publish(relationRevisionDraft);
      expect(
        revisedRelation.single.identity.recordId,
        published.identity.recordId,
      );
      expect(
        revisedRelation.single.payload.toWire().toText(),
        relationRevisionOperation(relationRevisionForm).replacement
            .toWire()
            .toText(),
      );
      final retainedRelation = await readContextRecord(
        session: session,
        universe: LibraryEntry(scope.universe, 'Relations'),
        context: await openDraftChoiceContext(changes(), relationRevisionBase),
        record: published.identity.recordId,
      );
      expect(retainedRelation.toWire().toText(), published.toWire().toText());
    } finally {
      await session?.close();
      await server.close();
      root.deleteSync(recursive: true);
    }
  });
}
