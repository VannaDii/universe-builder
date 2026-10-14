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
    } finally {
      await session?.close();
      await server.close();
      root.deleteSync(recursive: true);
    }
  });
}
