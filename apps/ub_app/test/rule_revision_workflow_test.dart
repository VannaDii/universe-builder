@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_app/rule_draft.dart';
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
  test('rule revision recovers exact chronology and publishes with retained history', () async {
    final root = Directory('/tmp').createTempSync('ub-rule-revision-workflow-');
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
            name: 'Rules',
            realWorld: true,
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
        universe: Selector('Rules'),
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
      final choiceContext = await openDraftChoiceContext(changes(), initial);
      final categories = await searchDraftChoices(
        changes: changes(),
        context: choiceContext,
        kind: RecordKind.domainPack,
      );
      final categoryHit = categories.result.hits.single;
      final categoryRef = RecordRef(
        universe: scope.universe,
        record: categoryHit.recordId,
      );
      final category = await readDraftChoiceVersion(
        changes: changes(),
        context: choiceContext,
        reference: categoryRef,
        kind: RecordKind.domainPack,
      );
      expect(category.payload, isA<DomainPackRecord>());
      expect(category.recordVersionId.value, isNotEmpty);
      await expectLater(
        readDraftChoiceVersion(
          changes: changes(),
          context: choiceContext,
          reference: categoryRef,
          kind: RecordKind.rule,
        ),
        throwsFormatException,
      );
      await expectLater(
        readDraftChoiceVersion(
          changes: changes(),
          context: choiceContext,
          reference: RecordRef(
            universe: UniverseId.generate(),
            record: categoryHit.recordId,
          ),
          kind: RecordKind.domainPack,
        ),
        throwsFormatException,
      );
      final sourceForm = UnfinishedRuleForm(
        baseRevision: initial.content.baseRevision,
        representedContext: scope.representedContext!,
        clientRef: RecordId.generate().value,
        namespace: 'authored',
        key: 'mail-chronology',
        labels: [
          const PropertyLabelInput(
            language: 'en',
            text: 'Mail chronology 記憶 😀',
          ),
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
      final sourceDraft = SavedDraft.fromWire(
        await session.call(
          ruleDraftRequest(
            draft: initial,
            form: sourceForm,
            universe: const Selector('Rules'),
            continuity: scope.continuity,
          ),
        ),
      );
      final published = (await publish(sourceDraft)).single;
      var next = await changes().rebase(
        (await changes().load())!,
        startNew: true,
      );
      final beforeContext = await readContextRecord(
        session: session,
        universe: LibraryEntry(scope.universe, 'Rules'),
        context: await openDraftChoiceContext(changes(), next),
        record: scope.representedContext!,
      );
      final revisionBase = next;
      final revisionScope = EditorFormScope(
        instance: scope.instance,
        profile: scope.profile,
        universe: scope.universe,
        continuity: scope.continuity,
        representedContext: scope.representedContext,
        typeClientRef: published.identity.recordId.value,
      );
      final revisionSourceForm = ruleRevisionFormFromRecord(
        record: published,
        baseRevision: next.content.baseRevision,
        representedContext: scope.representedContext!,
      );
      final revisionForm = UnfinishedRuleForm.fromWire(
        CanonicalObject(
          revisionSourceForm.toWire().fields.map(
            (e) => e.key == 'constraints'
                ? MapEntry(
                    'constraints',
                    revisionSourceForm.constraints!
                        .copyWith(
                          maximumDelay: '9007199254740997',
                          forwardOnly: true,
                        )
                        .toWire(),
                  )
                : e.key == 'rationale'
                ? MapEntry(
                    'rationale',
                    CanonicalString('Correct the authored channel chronology.'),
                  )
                : e,
          ),
        ),
      );
      await session.saveRuleForm(revisionScope, revisionForm, BigInt.zero);
      await session.close();
      session = await device.connect();
      final recovered = (await session.loadRuleForm(revisionScope))!.form;
      expect(recovered.toWire().toText(), revisionForm.toWire().toText());
      final revisionDraft = SavedDraft.fromWire(
        await session.call(
          ruleDraftRequest(
            draft: revisionBase,
            form: recovered,
            universe: const Selector('Rules'),
            continuity: scope.continuity,
          ),
        ),
      );
      final revised = (await publish(revisionDraft)).single;
      expect(revised.identity.recordId, published.identity.recordId);
      expect(
        revised.payload.toWire().toText(),
        ruleRevisionOperation(revisionForm).replacement.toWire().toText(),
      );
      final retained = await readContextRecord(
        session: session,
        universe: LibraryEntry(scope.universe, 'Rules'),
        context: await openDraftChoiceContext(changes(), revisionBase),
        record: published.identity.recordId,
      );
      expect(retained.toWire().toText(), published.toWire().toText());
      next = await changes().rebase((await changes().load())!, startNew: true);
      final afterContext = await readContextRecord(
        session: session,
        universe: LibraryEntry(scope.universe, 'Rules'),
        context: await openDraftChoiceContext(changes(), next),
        record: scope.representedContext!,
      );
      expect(afterContext.toWire().toText(), beforeContext.toWire().toText());
    } finally {
      await session?.close();
      await server.close();
      root.deleteSync(recursive: true);
    }
  });
}
