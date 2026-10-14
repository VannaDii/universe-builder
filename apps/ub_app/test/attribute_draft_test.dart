@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_app/attribute_draft.dart';
import 'package:ub_app/assertion_retraction_draft.dart';
import 'package:ub_app/record_browser.dart';
import 'package:ub_app/evidence_basis_draft.dart';
import 'package:ub_app/draft_record_choices.dart';
import 'package:ub_app/connection.dart';
import 'package:ub_app/connection_native.dart';
import 'package:ub_app/saved_changes.dart';
import 'package:ub_app/scope_draft.dart';
import 'package:ub_app/dossier_sources.dart';
import 'package:ub_app/source_draft.dart';
import 'package:ub_app/source_anchor.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/local_engine.dart';
import 'package:ub_service/local_profiles.dart';
import 'package:ub_store/installation.dart';

void main() {
  test(
    'source basis edits preserve exact provenance and evaluator-owned bases',
    () {
      final universe = UniverseId.generate(), record = RecordId.generate();
      final version = VersionRef(
        universe: universe,
        record: record,
        version: RecordVersionId.generate(),
      );
      final original = const AuthorDecisionBasis('Original decision.');
      final authored = const EvidenceBasisInput(
        kind: 'author_decision',
        note: '記憶 😀\nAn attributed account.',
      );
      expect(
        buildEvidenceBasis(
          EvidenceBasisInput.fromWire(authored.toWire()),
          original,
        ),
        const AuthorDecisionBasis('記憶 😀\nAn attributed account.'),
      );
      for (final namespace in [null, universe]) {
        for (final verified in [false, true]) {
          final basis = SourceAnchorBasis(
            RecordRef(universe: namespace, record: record),
            verified,
          );
          expect(
            buildEvidenceBasis(
              EvidenceBasisInput.fromWire(evidenceBasisInput(basis).toWire()),
              original,
            ),
            basis,
          );
        }
      }
      for (final basis in <EvidenceBasis>[
        const ImportedClaimBasis(),
        EventEffectBasis(RecordRef(record: record), 'effect 記憶 😀'),
        InstanceInitializationBasis(version, version, RevisionId.generate()),
        DerivationBasis([version, version], 'evaluator 記憶 😀'),
        DerivationBasis([], null),
      ]) {
        final input = EvidenceBasisInput.fromWire(
          evidenceBasisInput(basis).toWire(),
        );
        expect(
          buildEvidenceBasis(input, basis).toWire().toText(),
          basis.toWire().toText(),
        );
        expect(
          buildEvidenceBasis(const EvidenceBasisInput(), basis),
          same(basis),
        );
      }
      expect(
        () => buildEvidenceBasis(
          const EvidenceBasisInput(
            kind: 'source_anchor',
            anchorRecord: 'unfinished anchor',
          ),
          original,
        ),
        throwsFormatException,
      );
      expect(
        () => buildEvidenceBasis(
          const EvidenceBasisInput(kind: 'event_effect'),
          original,
        ),
        throwsFormatException,
      );
      expect(
        buildEvidenceBasis(
          const EvidenceBasisInput(
            kind: 'imported_claim',
            anchorRecord: 'hidden unfinished reference',
          ),
          original,
        ),
        const ImportedClaimBasis(),
      );
    },
  );

  test('assertion edits retain scope, alternatives and basis while changed validity is exact', () {
    final calendar = CalendarId.generate();
    final evidence = AttributeEvidence(
      attributeMode: AttributeMode.shared,
      polarity: Polarity.support,
      scope: Scope(
        context: RecordRef(record: RecordId.generate()),
        applicability: const ConditionalApplicability(),
      ),
      validity: InstantValidity(
        DurationTime(calendar, const TextValue('one lifetime')),
      ),
      persistence: PersistenceSemantics.persistentUntilChanged,
      precision: Precision.oneOf,
      alternatives: [
        const TextValue('alternative'),
        SequenceValue([const TextValue('original second')]),
      ],
      basis: const AuthorDecisionBasis('Authored source.'),
    );
    final op = AddNamedAttributeOperation(
      clientRef: 'attribute',
      subject: RecordRef(record: RecordId.generate()),
      namespace: 'authored',
      key: 'account',
      valueShape: const SimpleValueShape(SimpleShapeKind.text),
      subjectTypes: [RecordId.generate()],
      multiplicity: Multiplicity.multiple,
      value: const TextValue('account'),
      evidence: evidence,
    );
    final draft = SavedDraft(
      version: BigInt.two,
      content: DraftContent(
        baseRevision: RevisionId.generate(),
        representedContext: RecordId.generate(),
        operations: [op],
        rationale: 'Authored rationale.',
      ),
    );
    final fields = attributeFormFromDraft(draft, 0);
    UnfinishedAttributeForm form(AttributeEvidenceInput input) =>
        UnfinishedAttributeForm(
          baseRevision: fields.baseRevision,
          representedContext: fields.representedContext,
          clientRef: fields.clientRef,
          draftVersion: fields.draftVersion,
          value: fields.value,
          evidenceInput: input,
        );
    final retained =
        (replaceDraftAttribute(
                  draft: draft,
                  index: 0,
                  form: fields,
                ).operations.single
                as AddNamedAttributeOperation)
            .evidence;
    expect(retained.toWire().toText(), evidence.toWire().toText());
    final input = AttributeEvidenceInput(
      polarity: Polarity.refutation,
      precision: Precision.approximate,
      persistence: PersistenceSemantics.instantaneousObservation,
      temporalValidity: TemporalValidityInput(
        kind: 'instant_duration',
        calendar: calendar.value,
        start: const TemporalBoundInput(
          uncertaintyKind: 'text',
          uncertainty: 'two lifetimes 記憶 😀',
        ),
      ),
    );
    final parsed = AttributeEvidenceInput.fromWire(input.toWire());
    final edited =
        (replaceDraftAttribute(
                  draft: draft,
                  index: 0,
                  form: form(parsed),
                ).operations.single
                as AddNamedAttributeOperation)
            .evidence;
    expect(edited.polarity, Polarity.refutation);
    expect(edited.precision, Precision.approximate);
    expect(edited.persistence, PersistenceSemantics.instantaneousObservation);
    expect(
      edited.validity,
      InstantValidity(
        DurationTime(calendar, const TextValue('two lifetimes 記憶 😀')),
      ),
    );
    expect(edited.attributeMode, evidence.attributeMode);
    expect(edited.scope, evidence.scope);
    expect(edited.alternatives, evidence.alternatives);
    expect(edited.basis.toWire().toText(), evidence.basis.toWire().toText());
    final worldA = WorldId.generate(), worldB = WorldId.generate();
    final context = RecordId.generate(), realm = RecordId.generate();
    final otherUniverse = UniverseId.generate();
    final changedScope = Scope(
      context: RecordRef(record: context),
      realm: RecordRef(universe: otherUniverse, record: realm),
      applicability: WorldsApplicability([worldB, worldA, worldB]),
    );
    for (final mode in AttributeMode.values) {
      final changedEvidence =
          (replaceDraftAttribute(
                    draft: draft,
                    index: 0,
                    form: form(
                      AttributeEvidenceInput.fromWire(
                        AttributeEvidenceInput(
                          attributeMode: mode,
                          scope: scopeInput(changedScope),
                        ).toWire(),
                      ),
                    ),
                  ).operations.single
                  as AddNamedAttributeOperation)
              .evidence;
      expect(changedEvidence.attributeMode, mode);
      expect(changedEvidence.scope, changedScope);
      expect(changedEvidence.scope.context.universe, isNull);
      expect(changedEvidence.scope.realm!.universe, otherUniverse);
      expect(changedEvidence.basis, evidence.basis);
      expect(changedEvidence.alternatives, evidence.alternatives);
    }
    for (final applicability in <Applicability>[
      const UniverseApplicability(),
      const ConditionalApplicability(),
      const UnspecifiedApplicability(),
      WorldsApplicability([]),
    ]) {
      final scope = Scope(
        context: changedScope.context,
        applicability: applicability,
      );
      expect(buildScope(scopeInput(scope)), scope);
      expect(buildScope(scopeInput(scope)).realm, isNull);
    }
    expect(
      () => buildScope(const ScopeInput(contextRecord: 'unfinished 記憶 😀')),
      throwsFormatException,
    );
    final hidden = ScopeInput(
      contextRecord: context.value,
      realmRecord: 'unfinished realm',
      worlds: ['unfinished world'],
    );
    expect(buildScope(hidden).realm, isNull);
    expect(buildScope(hidden).applicability, const UnspecifiedApplicability());
    final changedAlternatives = AttributeEvidenceInput(
      alternatives: [
        const QualifierInput(
          kind: 'sequence',
          children: [
            QualifierInput(kind: 'text', value: '記憶 😀\nsecond account'),
          ],
        ),
        const QualifierInput(kind: 'retain', originalKey: '1'),
        const QualifierInput(kind: 'retain', originalKey: '0'),
      ],
    );
    final changed =
        (replaceDraftAttribute(
                  draft: draft,
                  index: 0,
                  form: form(
                    AttributeEvidenceInput.fromWire(
                      changedAlternatives.toWire(),
                    ),
                  ),
                ).operations.single
                as AddNamedAttributeOperation)
            .evidence;
    expect(changed.alternatives, [
      SequenceValue([const TextValue('記憶 😀\nsecond account')]),
      SequenceValue([const TextValue('original second')]),
      const TextValue('alternative'),
    ]);
    expect(changed.precision, evidence.precision);
    expect(changed.basis.toWire().toText(), evidence.basis.toWire().toText());
    expect(
      (replaceDraftAttribute(
                draft: draft,
                index: 0,
                form: form(const AttributeEvidenceInput(alternatives: [])),
              ).operations.single
              as AddNamedAttributeOperation)
          .evidence
          .alternatives,
      isEmpty,
    );
    expect(
      () => replaceDraftAttribute(
        draft: draft,
        index: 0,
        form: form(
          const AttributeEvidenceInput(
            alternatives: [
              QualifierInput(kind: 'retain', originalKey: 'missing'),
            ],
          ),
        ),
      ),
      throwsFormatException,
    );
    for (final marker in [
      const UnspecifiedValidity(),
      const UnknownValidity(),
      const ConditionalValidity(),
    ]) {
      expect(
        (replaceDraftAttribute(
                  draft: draft,
                  index: 0,
                  form: form(AttributeEvidenceInput(validity: marker)),
                ).operations.single
                as AddNamedAttributeOperation)
            .evidence
            .validity,
        marker,
      );
    }
  });

  test('existing-property edits preserve proposition and event identities', () {
    final universe = UniverseId.generate();
    RecordRef ref() =>
        RecordRef(universe: universe, record: RecordId.generate());
    final context = ref();
    final proposition = PropositionRecord(
      predicate: ref(),
      subject: ref(),
      context: context,
      quantification: Quantification.particular,
      roles: [PropositionRole('witness 記憶 😀', ref())],
      value: const TextValue('Earlier account'),
    );
    final assertion = AssertionRecord(
      attributeMode: AttributeMode.instance,
      proposition: ref(),
      polarity: Polarity.support,
      scope: Scope(
        context: context,
        applicability: const UniverseApplicability(),
      ),
      validity: const UnknownValidity(),
      persistence: PersistenceSemantics.unspecified,
      precision: Precision.exact,
      alternatives: [const TextValue('Other account')],
      basis: const AuthorDecisionBasis('Original note'),
      establishedBy: EventEffectRef(ref(), 'authored effect'),
    );
    final op = AssertPropositionOperation(
      clientRef: RecordId.generate().value,
      proposition: proposition,
      assertion: assertion,
    );
    final draft = SavedDraft(
      version: BigInt.one,
      content: DraftContent(
        baseRevision: RevisionId.generate(),
        representedContext: context.record,
        operations: [op],
        rationale: 'Exact rationale',
      ),
    );
    final original = attributeFormFromDraft(draft, 0);
    expect(isEditableAttribute(op), isTrue);
    expect(
      replaceDraftAttribute(
        draft: draft,
        index: 0,
        form: original,
      ).operations.single.toWire().toText(),
      op.toWire().toText(),
    );
    final changedContext = ref();
    final edited = replaceDraftAttribute(
      draft: draft,
      index: 0,
      form: UnfinishedAttributeForm(
        baseRevision: original.baseRevision,
        representedContext: original.representedContext,
        clientRef: original.clientRef,
        draftVersion: original.draftVersion,
        value: const QualifierInput(kind: 'text', value: '記憶 😀 new account'),
        evidenceInput: AttributeEvidenceInput(
          scope: scopeInput(
            Scope(
              context: changedContext,
              applicability: const ConditionalApplicability(),
            ),
          ),
          basis: const EvidenceBasisInput(
            kind: 'author_decision',
            note: 'New note',
          ),
        ),
      ),
    );
    final changed = edited.operations.single as AssertPropositionOperation;
    expect(changed.clientRef, op.clientRef);
    expect(changed.proposition.predicate, proposition.predicate);
    expect(changed.proposition.subject, proposition.subject);
    expect(changed.proposition.roles, proposition.roles);
    expect(changed.proposition.quantification, proposition.quantification);
    expect(changed.proposition.context, changedContext);
    expect(changed.proposition.value, const TextValue('記憶 😀 new account'));
    expect(changed.assertion.proposition, assertion.proposition);
    expect(changed.assertion.establishedBy, assertion.establishedBy);
    expect(changed.assertion.alternatives, assertion.alternatives);
    expect(changed.assertion.validity, assertion.validity);
    expect(changed.assertion.scope.context, changedContext);
    expect(changed.assertion.basis, const AuthorDecisionBasis('New note'));
    expect(edited.rationale, draft.content.rationale);
    final relation = AssertPropositionOperation(
      clientRef: op.clientRef,
      proposition: PropositionRecord(
        predicate: ref(),
        subject: ref(),
        context: context,
        quantification: Quantification.particular,
      ),
      assertion: assertion,
    );
    expect(isEditableAttribute(relation), isTrue);
    final relationDraft = SavedDraft(
      version: draft.version,
      content: DraftContent(
        baseRevision: draft.content.baseRevision,
        representedContext: context.record,
        operations: [op, relation],
        rationale: 'Relationship rationale',
      ),
    );
    final relationForm = attributeFormFromDraft(relationDraft, 1);
    expect(
      replaceDraftAttribute(
        draft: relationDraft,
        index: 1,
        form: relationForm,
      ).toWire().toText(),
      relationDraft.content.toWire().toText(),
    );
    final dedicated = RecordRelationOperation(
      clientRef: relation.clientRef,
      proposition: relation.proposition,
      assertion: relation.assertion,
    );
    final dedicatedDraft = SavedDraft(
      version: relationDraft.version,
      content: DraftContent(
        baseRevision: relationDraft.content.baseRevision,
        representedContext: relationDraft.content.representedContext,
        operations: [dedicated],
        rationale: 'Dedicated relationship.',
      ),
    );
    expect(isEditableAttribute(dedicated), isTrue);
    expect(
      replaceDraftAttribute(
        draft: dedicatedDraft,
        index: 0,
        form: attributeFormFromDraft(dedicatedDraft, 0),
      ).toWire().toText(),
      dedicatedDraft.content.toWire().toText(),
    );
    final participant = ref();
    final roleInputs = [
      PropositionRoleInput(
        role: 'listener 記憶 😀',
        record: participant.record.value,
        universe: participant.universe!.value,
      ),
      PropositionRoleInput(
        role: 'listener 記憶 😀',
        record: participant.record.value,
      ),
    ];
    UnfinishedAttributeForm relationEdit({
      List<PropositionRoleInput>? roles,
      AttributeEvidenceInput? evidence,
    }) => UnfinishedAttributeForm(
      baseRevision: relationForm.baseRevision,
      representedContext: relationForm.representedContext,
      clientRef: relationForm.clientRef,
      draftVersion: relationForm.draftVersion,
      value: relationForm.value,
      roles: roles,
      evidenceInput: evidence,
    );
    final result = replaceDraftAttribute(
      draft: relationDraft,
      index: 1,
      form: relationEdit(
        roles: roleInputs,
        evidence: const AttributeEvidenceInput(polarity: Polarity.refutation),
      ),
    );
    final editedRelation = result.operations[1] as AssertPropositionOperation;
    expect(editedRelation.proposition.value, isNull);
    expect(editedRelation.proposition.roles, [
      PropositionRole(roleInputs[0].role, participant),
      PropositionRole(
        roleInputs[1].role,
        RecordRef(record: participant.record),
      ),
    ]);
    expect(
      editedRelation.proposition.predicate,
      relation.proposition.predicate,
    );
    expect(editedRelation.proposition.subject, relation.proposition.subject);
    expect(
      editedRelation.proposition.quantification,
      relation.proposition.quantification,
    );
    expect(editedRelation.assertion.proposition, assertion.proposition);
    expect(editedRelation.assertion.establishedBy, assertion.establishedBy);
    expect(editedRelation.assertion.polarity, Polarity.refutation);
    expect(result.operations.first.toWire().toText(), op.toWire().toText());
    expect(result.rationale, relationDraft.content.rationale);
    expect(
      (replaceDraftAttribute(
                draft: relationDraft,
                index: 1,
                form: relationEdit(roles: []),
              ).operations[1]
              as AssertPropositionOperation)
          .proposition
          .roles,
      isEmpty,
    );
    expect(
      () => replaceDraftAttribute(
        draft: SavedDraft(
          version: draft.version + BigInt.one,
          content: relationDraft.content,
        ),
        index: 1,
        form: relationEdit(roles: roleInputs),
      ),
      throwsFormatException,
    );
  });

  test('attribute values recover and publish with their exact definition and evidence', () async {
    final root = Directory('/tmp').createTempSync('ub-attribute-workflow-');
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
            name: 'Attributes',
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
      SavedChanges changes() => SavedChanges(
        session: session!,
        universe: Selector('Attributes'),
        scope: scope,
      );
      const sourceText = 'An exact sourced account.';
      final stagedSource = WireFields(
        await session.call(
          const StageSourceEngineRequest(
            universe: Selector('Attributes'),
            label: 'Diary source',
            text: sourceText,
          ),
        ),
        {'canonical', 'operations'},
      );
      final sourceOperations = stagedSource
          .array('operations')
          .map(DomainOperation.fromWire)
          .toList();
      final sourceForm = UnfinishedSourceForm(
        baseRevision: RevisionId.parse(created.string('revision')),
        representedContext: scope.representedContext!,
        clientRef: RecordId.generate().value,
        label: 'Diary source',
        text: sourceText,
        rationale: 'Retain the submitted diary.',
        staged: sourceOperations,
      );
      final savedSourceForm = await session.saveSourceForm(
        scope,
        sourceForm,
        BigInt.zero,
      );
      final recoveredSourceForm = (await session.loadSourceForm(scope))!;
      expect(recoveredSourceForm.generation, savedSourceForm.generation);
      expect(
        recoveredSourceForm.form.toWire().toText(),
        sourceForm.toWire().toText(),
      );
      final emptySourceDraft = SavedDraft(
        version: BigInt.zero,
        content: DraftContent(
          baseRevision: sourceForm.baseRevision,
          representedContext: sourceForm.representedContext,
          operations: [],
          rationale: '',
        ),
      );
      final sourceRequest = sourceDraftRequest(
        draft: emptySourceDraft,
        form: recoveredSourceForm.form,
        universe: const Selector('Attributes'),
        continuity: scope.continuity,
      );
      expect(
        sourceRequest.content.operations.map((op) => op.toWire().toText()),
        sourceOperations.map((op) => op.toWire().toText()),
      );
      final alreadyAdded = SavedDraft(
        version: BigInt.one,
        content: sourceRequest.content,
      );
      expect(
        sourceDraftRequest(
          draft: alreadyAdded,
          form: recoveredSourceForm.form,
          universe: const Selector('Attributes'),
          continuity: scope.continuity,
        ).content.toWire().toText(),
        alreadyAdded.content.toWire().toText(),
      );
      final initial = SavedDraft.fromWire(
        await session.call(
          SaveDraftEngineRequest(
            universe: Selector('Attributes'),
            continuityId: scope.continuity,
            expectedVersion: BigInt.zero,
            content: DraftContent(
              baseRevision: RevisionId.parse(created.string('revision')),
              representedContext: scope.representedContext!,
              operations: [
                IntroduceInstanceOperation(
                  clientRef: 'person',
                  name: const ContextualName(
                    text: 'Mara',
                    validity: UnspecifiedValidity(),
                  ),
                  worldAssociations: [],
                ),
                ...sourceOperations,
                CreateWorldOperation(
                  clientRef: 'first-world',
                  record: WorldRecord(selector: 'Early world 記憶 😀'),
                ),
                CreateWorldOperation(
                  clientRef: 'second-world',
                  record: WorldRecord(selector: 'Other early world'),
                ),
              ],
              rationale: 'Introduce Mara.',
            ),
          ),
        ),
      );
      final proposal = await changes().submit(initial);
      final validation =
          await changes().validate(proposal) as EvaluatedValidation;
      await changes().approve(proposal, validation);
      final receipt = await changes().publish(
        proposal,
        validation.execution.runId,
      );
      final foundations = await changes().readPublished(proposal, receipt);
      final entity = foundations.where((r) => r.payload is EntityRecord).single;
      final sourceVersion = foundations
          .where((r) => r.payload is SourceVersionRecord)
          .single;
      var fresh = await changes().rebase(
        (await changes().load())!,
        startNew: true,
      );
      final anchorReference = VersionRef(
        universe: scope.universe,
        record: sourceVersion.identity.recordId,
        version: sourceVersion.recordVersionId,
      );
      final anchorSelection = sourceExcerptMatch(
        text: sourceText,
        excerpt: sourceText,
        source: anchorReference,
        context: RecordRef(
          universe: scope.universe,
          record: scope.representedContext!,
        ),
      );
      final anchorForm = UnfinishedSourceForm(
        baseRevision: fresh.content.baseRevision,
        representedContext: fresh.content.representedContext,
        clientRef: RecordId.generate().value,
        text: sourceText,
        rationale: 'Retain the exact diary excerpt.',
        anchorSource: anchorReference,
        staged: [
          AddSourceAnchorOperation(
            clientRef: 'diary-anchor',
            record: anchorSelection.selected!,
          ),
        ],
      );
      final anchorScope = EditorFormScope(
        instance: scope.instance,
        profile: scope.profile,
        universe: scope.universe,
        continuity: scope.continuity,
        representedContext: scope.representedContext,
        typeClientRef: sourceVersion.recordVersionId.value,
      );
      await session.saveSourceForm(anchorScope, anchorForm, BigInt.zero);
      final recoveredAnchor = (await session.loadSourceForm(anchorScope))!.form;
      expect(recoveredAnchor.toWire().toText(), anchorForm.toWire().toText());
      expect(
        (await session.loadSourceForm(scope))!.form.toWire().toText(),
        sourceForm.toWire().toText(),
      );
      final anchorRequest = sourceDraftRequest(
        draft: fresh,
        form: recoveredAnchor,
        universe: const Selector('Attributes'),
        continuity: scope.continuity,
      );
      final anchorDraft = await changes().saveContent(
        fresh,
        anchorRequest.content,
      );
      final anchorProposal = await changes().submit(anchorDraft);
      final anchorValidation =
          await changes().validate(anchorProposal) as EvaluatedValidation;
      await changes().approve(anchorProposal, anchorValidation);
      await changes().publish(anchorProposal, anchorValidation.execution.runId);
      fresh = await changes().rebase((await changes().load())!, startNew: true);
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
        alternatives: [
          SequenceValue([const TextValue('alternative')]),
        ],
        basis: const AuthorDecisionBasis('Authored continuity fact.'),
      );
      final operation = AddNamedAttributeOperation(
        clientRef: 'writer-attribute',
        subject: RecordRef(
          universe: scope.universe,
          record: entity.identity.recordId,
        ),
        namespace: 'authored',
        key: 'account',
        valueShape: const SequenceShape(SimpleValueShape(SimpleShapeKind.text)),
        subjectTypes: [],
        multiplicity: Multiplicity.multiple,
        value: SequenceValue([
          const TextValue('first'),
          const TextValue('second'),
        ]),
        evidence: evidence,
      );
      final saved = await changes().saveContent(
        fresh,
        DraftContent(
          baseRevision: fresh.content.baseRevision,
          representedContext: fresh.content.representedContext,
          operations: [
            operation,
            CreateWorldOperation(
              clientRef: 'world',
              record: WorldRecord(selector: 'River'),
            ),
          ],
          rationale: 'An attributed account.',
        ),
      );
      final choiceContext = await openDraftChoiceContext(changes(), saved);
      expect(choiceContext.frame.revision, saved.content.baseRevision);
      final firstPage = await searchDraftChoices(
        changes: changes(),
        context: choiceContext,
        kind: RecordKind.world,
        limit: 1,
      );
      expect(firstPage.result.hits.length, 1);
      expect(firstPage.delivery.complete, isFalse);
      final secondPage = await searchDraftChoices(
        changes: changes(),
        context: choiceContext,
        kind: RecordKind.world,
        limit: 1,
        cursor: firstPage.delivery.cursor,
      );
      expect(secondPage.delivery.complete, isTrue);
      final worlds = [...firstPage.result.hits, ...secondPage.result.hits];
      expect(worlds.map((h) => h.label).toSet(), {
        'Early world 記憶 😀',
        'Other early world',
      });
      final selectedWorld = await selectDraftChoice(
        changes: changes(),
        context: choiceContext,
        hit: worlds.first,
        kind: RecordKind.world,
      );
      expect(selectedWorld.universe, scope.universe);
      expect(
        worldChoiceRecord(worldFromChoice(selectedWorld).value),
        selectedWorld.record,
      );
      expect(
        (await readDraftChoiceSummary(
          changes: changes(),
          context: choiceContext,
          record: selectedWorld.record,
          kind: RecordKind.world,
        )).label,
        worlds.first.label,
      );
      await expectLater(
        selectDraftChoice(
          changes: changes(),
          context: choiceContext,
          hit: worlds.first,
          kind: RecordKind.realm,
        ),
        throwsFormatException,
      );
      final contexts = await searchDraftChoices(
        changes: changes(),
        context: choiceContext,
        kind: RecordKind.representedContext,
      );
      expect(contexts.result.hits.single.recordId, scope.representedContext);
      expect(
        (await selectDraftChoice(
          changes: changes(),
          context: choiceContext,
          hit: contexts.result.hits.single,
          kind: RecordKind.representedContext,
        )).record,
        scope.representedContext,
      );
      final anchors = await searchDraftChoices(
        changes: changes(),
        context: choiceContext,
        kind: RecordKind.anchor,
        query: 'sourced',
      );
      expect(anchors.result.hits.single.label, sourceText);
      final sourceMaterial = Envelope<Records>.fromWire(
        await session.call(
          ToolEngineRequest(
            request: GetRequest(
              universe: const Selector('Attributes'),
              universeId: scope.universe,
              contextId: choiceContext.contextId,
              recordIds: [anchors.result.hits.single.recordId],
              fieldGroups: [FieldGroup.payload, FieldGroup.evidence],
            ),
          ),
        ),
        Records.fromWire,
      );
      final sourceRows = dossierSourceRecords(
        sourceMaterial.result,
        scope.universe,
      );
      final sourceAnchor =
          sourceRows.singleWhere((row) => row.payload is AnchorRecord).payload
              as AnchorRecord;
      expect(sourceAnchor.excerpt, sourceText);
      expect(
        await readSourceText(
          session: session,
          universe: const Selector('Attributes'),
          context: choiceContext.contextId,
          source: sourceAnchor.sourceVersion,
        ),
        sourceText,
      );
      final textRequest = ReadSourceEngineRequest(
        universe: const Selector('Attributes'),
        contextId: choiceContext.contextId,
        sourceVersion: sourceAnchor.sourceVersion,
        after: BigInt.zero,
      );
      final textPage = WireFields(await session.call(textRequest), {
        'text',
        'after',
        'next',
      });
      expect(textPage.string('text'), sourceText);
      expect(textPage.require('next'), isA<CanonicalNull>());
      expect(
        EngineRequest.fromWire(textRequest.toWire()),
        isA<ReadSourceEngineRequest>(),
      );
      await expectLater(
        session.call(
          ReadSourceEngineRequest(
            universe: const Selector('Attributes'),
            contextId: choiceContext.contextId,
            sourceVersion: VersionRef(
              universe: scope.universe,
              record: sourceVersion.identity.recordId,
              version: RecordVersionId.generate(),
            ),
            after: BigInt.zero,
          ),
        ),
        throwsA(isA<NotFoundOrNotAccessibleError>()),
      );
      expect(
        dossierAnchorSource(
          sourceRows,
          scope.universe,
          sourceAnchor,
        )?.recordVersionId,
        sourceVersion.recordVersionId,
      );
      final anchor = await selectDraftChoice(
        changes: changes(),
        context: choiceContext,
        hit: anchors.result.hits.single,
        kind: RecordKind.anchor,
      );
      expect(anchor.universe, scope.universe);
      expect(
        (await readDraftChoiceSummary(
          changes: changes(),
          context: choiceContext,
          record: anchor.record,
          kind: RecordKind.anchor,
        )).label,
        sourceText,
      );
      await expectLater(
        readDraftChoiceSummary(
          changes: changes(),
          context: choiceContext,
          record: anchor.record,
          kind: RecordKind.realm,
        ),
        throwsFormatException,
      );
      final mislabeledAnchor = SearchHit(
        recordId: anchor.record,
        kind: RecordKind.world,
        label: 'Wrong type',
        worldIds: [],
        scopeCategory: anchors.result.hits.single.scopeCategory,
      );
      await expectLater(
        selectDraftChoice(
          changes: changes(),
          context: choiceContext,
          hit: mislabeledAnchor,
          kind: RecordKind.world,
        ),
        throwsFormatException,
      );
      final formScope = EditorFormScope(
        instance: instance,
        profile: author,
        universe: scope.universe,
        continuity: scope.continuity,
        representedContext: scope.representedContext,
        attributeClientRef: operation.clientRef,
      );
      final fields = attributeFormFromDraft(saved, 0);
      UnfinishedAttributeForm form(String text) => UnfinishedAttributeForm(
        baseRevision: fields.baseRevision,
        representedContext: fields.representedContext,
        clientRef: fields.clientRef,
        draftVersion: fields.draftVersion,
        value: QualifierInput(
          kind: 'sequence',
          children: [
            QualifierInput(kind: 'text', value: text),
            const QualifierInput(kind: 'retain', originalKey: '1'),
          ],
        ),
      );
      final entered = form('記憶 😀\naccount');
      await session.saveAttributeForm(formScope, entered, BigInt.zero);
      await session.close();
      session = await device.connect();
      final recovered = (await session.loadAttributeForm(formScope))!;
      expect(recovered.form.toWire().toText(), entered.toWire().toText());
      expect(
        (await session.saveAttributeForm(
          formScope,
          entered,
          BigInt.zero,
        )).generation,
        BigInt.one,
      );
      await expectLater(
        session.saveAttributeForm(formScope, form('competing'), BigInt.zero),
        throwsA(isA<EditorRecoveryException>()),
      );
      final replacement = replaceDraftAttribute(
        draft: saved,
        index: 0,
        form: recovered.form,
      );
      final exact = replacement.operations.first as AddNamedAttributeOperation;
      expect(exact.clientRef, operation.clientRef);
      expect(exact.subject, operation.subject);
      expect(exact.valueShape, operation.valueShape);
      expect(exact.subjectTypes, operation.subjectTypes);
      expect(exact.evidence.toWire().toText(), evidence.toWire().toText());
      expect(
        replacement.operations.last.toWire().toText(),
        saved.content.operations.last.toWire().toText(),
      );
      expect(replacement.rationale, saved.content.rationale);
      final detailsForm = UnfinishedAttributeForm(
        baseRevision: recovered.form.baseRevision,
        representedContext: recovered.form.representedContext,
        clientRef: recovered.form.clientRef,
        draftVersion: recovered.form.draftVersion,
        value: recovered.form.value,
        evidenceInput: AttributeEvidenceInput(
          basis: const EvidenceBasisInput(
            kind: 'author_decision',
            note: '記憶 😀 revised author decision.',
          ),
          attributeMode: AttributeMode.instance,
          scope: ScopeInput(
            applicability: 'worlds',
            contextRecord: scope.representedContext!.value,
            contextUniverse: scope.universe.value,
          ),
          polarity: Polarity.refutation,
          validity: const UnspecifiedValidity(),
          alternatives: [
            QualifierInput(
              kind: 'sequence',
              children: [
                QualifierInput(kind: 'text', value: '記憶 😀 alternative'),
              ],
            ),
            QualifierInput(kind: 'retain', originalKey: '0'),
          ],
        ),
      );
      await session.saveAttributeForm(
        formScope,
        detailsForm,
        recovered.generation,
      );
      await session.close();
      session = await device.connect();
      final detailsRecovered = (await session.loadAttributeForm(formScope))!
          .form;
      expect(detailsRecovered.toWire().toText(), detailsForm.toWire().toText());
      final updated = await changes().saveContent(
        saved,
        replaceDraftAttribute(draft: saved, index: 0, form: detailsRecovered),
      );
      expect(
        () => replaceDraftAttribute(
          draft: updated,
          index: 0,
          form: recovered.form,
        ),
        throwsFormatException,
      );
      final authored = await changes().submit(updated);
      final checked = await changes().validate(authored) as EvaluatedValidation;
      await changes().approve(authored, checked);
      final published = await changes().publish(
        authored,
        checked.execution.runId,
      );
      final pinnedWorlds = await searchDraftChoices(
        changes: changes(),
        context: choiceContext,
        kind: RecordKind.world,
      );
      expect(
        pinnedWorlds.result.hits.map((h) => h.label),
        isNot(contains('River')),
      );
      final nextDraft = await changes().rebase(
        (await changes().load())!,
        startNew: true,
      );
      final nextContext = await openDraftChoiceContext(changes(), nextDraft);
      final currentWorlds = await searchDraftChoices(
        changes: changes(),
        context: nextContext,
        kind: RecordKind.world,
      );
      expect(currentWorlds.result.hits.map((h) => h.label), contains('River'));
      final result = await changes().readPublished(authored, published);
      final fact = result
          .map((r) => r.payload)
          .whereType<PropositionRecord>()
          .single;
      expect(fact.subject, operation.subject);
      expect(
        fact.value,
        SequenceValue([TextValue('記憶 😀\naccount'), const TextValue('second')]),
      );
      final assertion = result
          .map((r) => r.payload)
          .whereType<AssertionRecord>()
          .single;
      expect(
        assertion.basis.toWire().toText(),
        const AuthorDecisionBasis('記憶 😀 revised author decision.')
            .toWire()
            .toText(),
      );
      expect(assertion.validity, const UnspecifiedValidity());
      expect(assertion.polarity, Polarity.refutation);
      expect(assertion.attributeMode, AttributeMode.instance);
      expect(
        assertion.scope,
        Scope(
          context: RecordRef(
            universe: scope.universe,
            record: scope.representedContext!,
          ),
          applicability: WorldsApplicability([]),
        ),
      );
      expect(assertion.alternatives, [
        SequenceValue([const TextValue('記憶 😀 alternative')]),
        SequenceValue([const TextValue('alternative')]),
      ]);
      final property = result.where((r) => r.payload is PropertyRecord).single;
      final newFields = newAttributeForm(draft: nextDraft, entity: entity);
      expect(
        newAttributeEvidence(
          scope.universe,
          scope.representedContext!,
        ).scope.applicability,
        const UnspecifiedApplicability(),
      );
      final creation = newFields.creationInput!;
      final factId = RecordId.parse(creation.operationRef);
      final newScope = EditorFormScope(
        instance: instance,
        profile: author,
        universe: scope.universe,
        continuity: scope.continuity,
        representedContext: scope.representedContext,
        attributeClientRef: newFields.clientRef,
      );
      final enteredFact = UnfinishedAttributeForm(
        baseRevision: newFields.baseRevision,
        representedContext: newFields.representedContext,
        clientRef: newFields.clientRef,
        draftVersion: newFields.draftVersion,
        value: const QualifierInput(
          kind: 'sequence',
          children: [
            QualifierInput(kind: 'text', value: '記憶 😀 another account'),
          ],
        ),
        evidenceInput: AttributeEvidenceInput(
          scope: ScopeInput(
            applicability: 'universe_wide',
            contextRecord: newFields.representedContext.value,
            contextUniverse: scope.universe.value,
          ),
          basis: const EvidenceBasisInput(
            kind: 'author_decision',
            note: 'Another account.',
          ),
          precision: Precision.exact,
        ),
        creationInput: AttributeCreationInput(
          subject: creation.subject,
          operationRef: creation.operationRef,
          propertyRecord: property.identity.recordId.value,
          propertyUniverse: property.identity.universeId.value,
        ),
      );
      await session.saveAttributeForm(newScope, enteredFact, BigInt.zero);
      await session.close();
      session = await device.connect();
      final recoveredFact = (await session.loadAttributeForm(newScope))!.form;
      expect(recoveredFact.toWire().toText(), enteredFact.toWire().toText());
      final newContent = appendDraftAttribute(
        draft: nextDraft,
        form: recoveredFact,
        entity: entity,
        property: property,
      );
      final existingPropertyOp =
          newContent.operations.single as AssertPropositionOperation;
      expect(existingPropertyOp.clientRef, creation.operationRef);
      expect(
        existingPropertyOp.proposition.predicate,
        RecordRef(universe: scope.universe, record: property.identity.recordId),
      );
      expect(existingPropertyOp.proposition.subject, operation.subject);
      expect(existingPropertyOp.assertion.precision, Precision.exact);
      expect(existingPropertyOp.assertion.validity, const UnknownValidity());
      expect(existingPropertyOp.assertion.proposition.record, factId);
      expect(
        () => appendDraftAttribute(
          draft: nextDraft,
          form: newFields,
          entity: entity,
          property: property,
        ),
        throwsFormatException,
      );
      final competing = SavedDraft(
        version: nextDraft.version + BigInt.one,
        content: nextDraft.content,
      );
      expect(
        () => appendDraftAttribute(
          draft: competing,
          form: recoveredFact,
          entity: entity,
          property: property,
        ),
        throwsFormatException,
      );
      final existingDraft = await changes().saveContent(nextDraft, newContent);
      expect(
        appendDraftAttribute(
          draft: existingDraft,
          form: recoveredFact,
          entity: entity,
          property: property,
        ).toWire().toText(),
        newContent.toWire().toText(),
      );
      expect(newContent.rationale, nextDraft.content.rationale);
      final changedEntry = UnfinishedAttributeForm(
        baseRevision: recoveredFact.baseRevision,
        representedContext: recoveredFact.representedContext,
        clientRef: recoveredFact.clientRef,
        draftVersion: recoveredFact.draftVersion,
        value: const QualifierInput(
          kind: 'text',
          value: 'Changed after adding',
        ),
        evidenceInput: recoveredFact.evidenceInput,
        creationInput: recoveredFact.creationInput,
      );
      expect(
        () => appendDraftAttribute(
          draft: existingDraft,
          form: changedEntry,
          entity: entity,
          property: property,
        ),
        throwsFormatException,
      );
      final existingFields = attributeFormFromDraft(existingDraft, 0);
      final existingScope = EditorFormScope(
        instance: instance,
        profile: author,
        universe: scope.universe,
        continuity: scope.continuity,
        representedContext: scope.representedContext,
        attributeClientRef: factId.value,
      );
      final revised = UnfinishedAttributeForm(
        baseRevision: existingFields.baseRevision,
        representedContext: existingFields.representedContext,
        clientRef: existingFields.clientRef,
        draftVersion: existingFields.draftVersion,
        value: const QualifierInput(
          kind: 'sequence',
          children: [
            QualifierInput(kind: 'text', value: '記憶 😀 another account'),
          ],
        ),
      );
      await session.saveAttributeForm(existingScope, revised, BigInt.zero);
      await session.close();
      session = await device.connect();
      final recoveredExisting = (await session.loadAttributeForm(
        existingScope,
      ))!.form;
      expect(recoveredExisting.toWire().toText(), revised.toWire().toText());
      final revisedDraft = await changes().saveContent(
        existingDraft,
        replaceDraftAttribute(
          draft: existingDraft,
          index: 0,
          form: recoveredExisting,
        ),
      );
      final ready = await changes().saveRationale(
        revisedDraft,
        'Another attributed account.',
      );
      final existingProposal = await changes().submit(ready);
      final existingValidation =
          await changes().validate(existingProposal) as EvaluatedValidation;
      await changes().approve(existingProposal, existingValidation);
      final existingReceipt = await changes().publish(
        existingProposal,
        existingValidation.execution.runId,
      );
      final existingRecords = await changes().readPublished(
        existingProposal,
        existingReceipt,
      );
      expect(
        existingRecords.where((r) => r.payload is PropertyRecord),
        isEmpty,
      );
      final existingFact = existingRecords
          .map((r) => r.payload)
          .whereType<PropositionRecord>()
          .single;
      expect(existingFact.predicate, existingPropertyOp.proposition.predicate);
      expect(
        existingFact.value,
        SequenceValue([const TextValue('記憶 😀 another account')]),
      );
      final existingAssertion = existingRecords
          .map((r) => r.payload)
          .whereType<AssertionRecord>()
          .single;
      expect(
        existingAssertion.basis.toWire().toText(),
        const AuthorDecisionBasis('Another account.').toWire().toText(),
      );
      final retractionBase = await changes().rebase(
        (await changes().load())!,
        startNew: true,
      );
      final assertionSource = existingRecords.singleWhere(
        (r) => r.payload is AssertionRecord,
      );
      final retractionScope = EditorFormScope(
        instance: scope.instance,
        profile: scope.profile,
        universe: scope.universe,
        continuity: scope.continuity,
        representedContext: scope.representedContext,
        typeClientRef: assertionSource.identity.recordId.value,
      );
      final retractionForm = assertionRetractionFormFromRecord(
        record: assertionSource,
        baseRevision: retractionBase.content.baseRevision,
        representedContext: scope.representedContext!,
      ).copyWith(rationale: 'Withdraw the incorrect attributed account 記憶 😀.');
      await session.saveAssertionRetractionForm(
        retractionScope,
        retractionForm,
        BigInt.zero,
      );
      await session.close();
      session = await device.connect();
      final recoveredRetraction = (await session.loadAssertionRetractionForm(
        retractionScope,
      ))!.form;
      expect(
        recoveredRetraction.toWire().toText(),
        retractionForm.toWire().toText(),
      );
      final retractionDraft = SavedDraft.fromWire(
        await session.call(
          assertionRetractionDraftRequest(
            draft: retractionBase,
            form: recoveredRetraction,
            universe: const Selector('Attributes'),
            continuity: scope.continuity,
          ),
        ),
      );
      final retractionProposal = await changes().submit(retractionDraft);
      final retractionValidation =
          await changes().validate(retractionProposal) as EvaluatedValidation;
      await changes().approve(retractionProposal, retractionValidation);
      final retractionReceipt = await changes().publish(
        retractionProposal,
        retractionValidation.execution.runId,
      );
      expect(
        await changes().readPublished(retractionProposal, retractionReceipt),
        isEmpty,
      );
      final retainedAssertion = await readContextRecord(
        session: session,
        universe: LibraryEntry(scope.universe, 'Attributes'),
        context: await openDraftChoiceContext(changes(), retractionBase),
        record: assertionSource.identity.recordId,
      );
      expect(
        retainedAssertion.toWire().toText(),
        assertionSource.toWire().toText(),
      );
      final afterRetraction = await changes().rebase(
        (await changes().load())!,
        startNew: true,
      );
      final currentContext = await openDraftChoiceContext(
        changes(),
        afterRetraction,
      );
      final currentAssertions = await searchDraftChoices(
        changes: changes(),
        context: currentContext,
        kind: RecordKind.assertion,
      );
      expect(
        currentAssertions.result.hits.map((hit) => hit.recordId),
        isNot(contains(assertionSource.identity.recordId)),
      );
      final retainedProposition = await readContextRecord(
        session: session,
        universe: LibraryEntry(scope.universe, 'Attributes'),
        context: currentContext,
        record: existingAssertion.proposition.record,
      );
      expect(
        retainedProposition.payload.toWire().toText(),
        existingFact.toWire().toText(),
      );
    } finally {
      await session?.close();
      await server.close();
      root.deleteSync(recursive: true);
    }
  });
}
