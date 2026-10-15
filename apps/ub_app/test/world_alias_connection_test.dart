@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart' hide Description;
import 'package:ub_app/connection.dart';
import 'package:ub_app/connection_native.dart';
import 'package:ub_app/saved_changes.dart';
import 'package:ub_app/world_draft.dart';
import 'package:ub_app/record_browser.dart';
import 'package:ub_app/world_browser.dart';
import 'package:ub_app/world_evidence_policies.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/local_engine.dart';
import 'package:ub_service/local_profiles.dart';
import 'package:ub_store/installation.dart';

void main() {
  test('world alias enters exact Changes and preserves other world fields through publication', () async {
    final root = Directory('/tmp').createTempSync('ub-world-alias-');
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
            name: 'Alias history',
            realWorld: true,
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
      );
      final context = RecordId.parse(created.string('context_id'));
      final typeScope = EditorFormScope(
        instance: instance,
        profile: author,
        universe: scope.universe,
        continuity: scope.continuity,
        representedContext: context,
      );
      final pendingType = UnfinishedTypeForm(
        baseRevision: RevisionId.parse(created.string('revision')),
        representedContext: context,
        clientRef: 'pending-person-type',
        namespace: '',
        key: '',
        name: '人物',
        parentChoice: '',
        applicabilityChoice: '',
        rationale: 'Still choosing scope.',
      );
      await session.saveTypeForm(typeScope, pendingType, BigInt.zero);
      final changes = SavedChanges(
        session: session,
        universe: Selector('Alias history'),
        scope: scope,
      );
      final original = WorldRecord(
        selector: 'River',
        aliases: ['Old river'],
        settingType: 'Historical',
        labels: {'en': 'River', 'fr': 'Rivière'},
        metadata: {'source note': const TextValue('Keep\r\nexact')},
      );
      final draft = SavedDraft.fromWire(
        await session.call(
          SaveDraftEngineRequest(
            universe: Selector('Alias history'),
            continuityId: scope.continuity,
            expectedVersion: BigInt.zero,
            content: DraftContent(
              baseRevision: RevisionId.parse(created.string('revision')),
              representedContext: context,
              operations: [
                CreateWorldOperation(clientRef: 'river', record: original),
              ],
              rationale: 'Create the setting.',
            ),
          ),
        ),
      );
      final proposal = await changes.submit(draft);
      final checks = await changes.validate(proposal) as EvaluatedValidation;
      await changes.approve(proposal, checks);
      final receipt = await changes.publish(proposal, checks.execution.runId);
      final record = proposal.compiledChanges.single.next!;
      final entry = LibraryEntry(scope.universe, 'Alias history');
      final opened = Envelope<OpenedContext>.fromWire(
        await session.call(
          ToolEngineRequest(
            request: OpenContextRequest(
              universe: Selector(entry.name),
              universeId: entry.id,
              continuityId: scope.continuity,
              revision: ExactRevisionSelector(revisionId: receipt.revision),
              representedContext: ContextIdSelector(context),
              temporalQuery: const TimelessFrameTime(),
              temporalSystems: [],
              perspective: const AuthorPerspective(),
            ),
          ),
        ),
        OpenedContext.fromWire,
      ).result;
      final firstPage = await searchContextRecords(
        session: session,
        universe: entry,
        context: opened,
        query: '',
        limit: 1,
      );
      expect(firstPage.delivery.complete, isFalse);
      final nextPage = await searchContextRecords(
        session: session,
        universe: entry,
        context: opened,
        query: '',
        limit: 1,
        cursor: firstPage.delivery.cursor,
      );
      expect(
        nextPage.result.hits.single.recordId,
        isNot(firstPage.result.hits.single.recordId),
      );
      final worldSearch = await searchContextRecords(
        session: session,
        universe: entry,
        context: opened,
        query: 'Old river',
        kind: RecordKind.world,
      );
      expect(worldSearch.delivery.complete, isTrue);
      expect(worldSearch.result.hits.single.recordId, record.identity.recordId);
      expect(
        (await readContextRecord(
          session: session,
          universe: entry,
          context: opened,
          record: record.identity.recordId,
        )).payload.toWire().toText(),
        original.toWire().toText(),
      );
      final latest = SavedDraft.fromWire(
        await session.call(
          LoadDraftEngineRequest(
            universe: Selector('Alias history'),
            continuityId: scope.continuity,
          ),
        ),
      );
      final empty = await changes.rebase(latest, startNew: true);
      final aliasScope = EditorFormScope(
        instance: instance,
        profile: author,
        universe: scope.universe,
        continuity: scope.continuity,
        representedContext: context,
        worldRecord: record.identity.recordId,
        worldClientRef: 'alias',
      );
      final renameScope = EditorFormScope(
        instance: instance,
        profile: author,
        universe: scope.universe,
        continuity: scope.continuity,
        representedContext: context,
        worldRecord: record.identity.recordId,
      );
      final form = UnfinishedWorldForm(
        baseRevision: receipt.revision,
        representedContext: context,
        record: record.identity.recordId,
        expectedRecordVersion: record.recordVersionId,
        selector: '古河',
        settingType: '',
        rationale: 'Retain the historical name.',
      );
      await session.saveWorldForm(aliasScope, form, BigInt.zero);
      expect(await session.loadWorldForm(renameScope), isNull);
      await session.close();
      session = await device.connect();
      expect(
        (await session.loadTypeForm(typeScope))!.form.toWire().toText(),
        pendingType.toWire().toText(),
      );
      final recovered = (await session.loadWorldForm(aliasScope))!.form;
      expect(recovered.toWire().toText(), form.toWire().toText());
      final resumed = SavedChanges(
        session: session,
        universe: Selector('Alias history'),
        scope: scope,
      );
      final request = worldAliasDraftRequest(
        universe: Selector('Alias history'),
        universeId: scope.universe,
        continuity: scope.continuity,
        form: recovered,
        previous: empty,
      );
      final saved = SavedDraft.fromWire(await session.call(request));
      expect(
        worldAliasDraftRequest(
          universe: Selector('Alias history'),
          universeId: scope.universe,
          continuity: scope.continuity,
          form: recovered,
          previous: saved,
        ).content.toWire().toText(),
        saved.content.toWire().toText(),
      );
      final aliased = await resumed.submit(saved);
      final payload =
          aliased.compiledChanges.single.next!.payload as WorldRecord;
      expect(payload.selector, original.selector);
      expect(payload.aliases, ['Old river', '古河']);
      expect(payload.labels, original.labels);
      expect(payload.settingType, original.settingType);
      expect(
        payload.metadata['source note']!.toWire().toText(),
        original.metadata['source note']!.toWire().toText(),
      );
      final validation = await resumed.validate(aliased) as EvaluatedValidation;
      await resumed.approve(aliased, validation);
      final published = await resumed.publish(
        aliased,
        validation.execution.runId,
      );
      expect(published.revision, isNot(receipt.revision));
      final latestDescription = Envelope<Description>.fromWire(
        await session.call(
          ToolEngineRequest(
            request: DescribeSummaryRequest(universe: Selector(entry.name)),
          ),
        ),
        Description.fromWire,
      ).result;
      final latestContinuity = latestDescription.continuities.single;
      expect(latestContinuity.revisionId, published.revision);
      final reopened = await openAuthorReadContext(
        session,
        entry,
        latestContinuity,
        latestContinuity.representedContexts.single,
        revision: receipt.revision,
      );
      expect(reopened.frame.revision, receipt.revision);
      expect(
        (await readContextRecord(
          session: session,
          universe: entry,
          context: reopened,
          record: record.identity.recordId,
        )).payload.toWire().toText(),
        original.toWire().toText(),
      );
      final historical = await readContextRecordMaterial(
        session: session,
        universe: entry,
        context: opened,
        record: record.identity.recordId,
        group: FieldGroup.history,
      );
      expect(historical.delivery.complete, isTrue);
      expect(historical.result.records, isEmpty);
      expect(historical.result.historyCoverage, Coverage.complete);
      expect(historical.result.history.single.reason, 'Create the setting.');
      expect(
        historical.result.history.single.record!.payload.toWire().toText(),
        original.toWire().toText(),
      );
      final current = Envelope<OpenedContext>.fromWire(
        await session.call(
          ToolEngineRequest(
            request: OpenContextRequest(
              universe: Selector(entry.name),
              universeId: entry.id,
              continuityId: scope.continuity,
              revision: ExactRevisionSelector(revisionId: published.revision),
              representedContext: ContextIdSelector(context),
              temporalQuery: const TimelessFrameTime(),
              temporalSystems: [],
              perspective: const AuthorPerspective(),
            ),
          ),
        ),
        OpenedContext.fromWire,
      ).result;
      final currentHistory = await readContextRecordMaterial(
        session: session,
        universe: entry,
        context: current,
        record: record.identity.recordId,
        group: FieldGroup.history,
      );
      expect(currentHistory.result.history.length, 2);
      expect(
        currentHistory.result.history.first.reason,
        'Retain the historical name.',
      );
      expect(
        currentHistory.result.history.first.record!.payload.toWire().toText(),
        payload.toWire().toText(),
      );
      final support = await readContextRecordMaterial(
        session: session,
        universe: entry,
        context: current,
        record: record.identity.recordId,
        group: FieldGroup.evidence,
      );
      expect(support.result.records, isEmpty);
      expect(support.result.history, isEmpty);
      // The browser keeps its opened revision even after later publication.
      expect(
        (await readContextRecord(
          session: session,
          universe: entry,
          context: opened,
          record: record.identity.recordId,
        )).payload.toWire().toText(),
        original.toWire().toText(),
      );
      expect(
        (await resumed.publish(aliased, validation.execution.runId)).revision,
        published.revision,
      );
      final worldId = WorldId.parse(
        'wld_${record.identity.recordId.value.substring(4)}',
      );
      final inherited = await readWorldEvidencePolicies(
        session: session,
        universe: entry,
        context: opened,
        world: worldId,
      );
      expect(inherited.complete, isTrue);
      expect(inherited.policies.single.origin, WorldPolicyOrigin.universe);
      expect(inherited.categories, hasLength(1));
      final defaultRule = inherited.policies.single.rule;
      final otherWorldRecord = RecordId.generate();
      final otherWorld = WorldId.parse(
        'wld_${otherWorldRecord.value.substring(4)}',
      );
      RuleRecord scopedRule(
        String key,
        Applicability applicability, {
        bool evidence = true,
      }) => RuleRecord.fromWire(
        CanonicalObject([
          for (final field in defaultRule.toWire().fields)
            if (evidence || field.key != 'requiredEvidence')
              MapEntry(field.key, switch (field.key) {
                'key' => CanonicalString(key),
                'applicability' => applicability.toWire(),
                _ => field.value,
              }),
        ]),
      );
      final fresh = await resumed.rebase(
        (await resumed.load())!,
        startNew: true,
      );
      final policyDraft = SavedDraft.fromWire(
        await session.call(
          SaveDraftEngineRequest(
            universe: Selector(entry.name),
            continuityId: scope.continuity,
            expectedVersion: fresh.version,
            content: DraftContent(
              baseRevision: fresh.content.baseRevision,
              representedContext: context,
              operations: [
                CreateWorldOperation(
                  clientRef: otherWorldRecord.value,
                  record: WorldRecord(selector: 'Mountain'),
                ),
                for (var i = 0; i < 51; i++)
                  DefineRuleOperation(
                    clientRef: RecordId.generate().value,
                    record: scopedRule(
                      'ordinary-$i',
                      const UniverseApplicability(),
                      evidence: false,
                    ),
                  ),
                DefineRuleOperation(
                  clientRef: RecordId.generate().value,
                  record: scopedRule(
                    'river-sources',
                    WorldsApplicability([worldId]),
                  ),
                ),
                DefineRuleOperation(
                  clientRef: RecordId.generate().value,
                  record: scopedRule(
                    'mountain-sources',
                    WorldsApplicability([otherWorld]),
                  ),
                ),
              ],
              rationale: 'Add explicit scoped policies and ordinary rules.',
            ),
          ),
        ),
      );
      final policyProposal = await resumed.submit(policyDraft);
      final policyChecks =
          await resumed.validate(policyProposal) as EvaluatedValidation;
      await resumed.approve(policyProposal, policyChecks);
      final policyReceipt = await resumed.publish(
        policyProposal,
        policyChecks.execution.runId,
      );
      final policyContext = await openAuthorReadContext(
        session,
        entry,
        latestContinuity,
        latestContinuity.representedContexts.single,
        revision: policyReceipt.revision,
      );
      final policies = await readWorldEvidencePolicies(
        session: session,
        universe: entry,
        context: policyContext,
        world: worldId,
      );
      expect(policies.complete, isTrue);
      expect(policies.policies, hasLength(2));
      expect(
        policies.policies.map((p) => p.origin),
        containsAll([
          WorldPolicyOrigin.universe,
          WorldPolicyOrigin.selectedWorld,
        ]),
      );
      expect(
        policies.policies.map((p) => p.rule.key),
        isNot(contains('mountain-sources')),
      );
      final oldPolicies = await readWorldEvidencePolicies(
        session: session,
        universe: entry,
        context: opened,
        world: worldId,
      );
      expect(oldPolicies.complete, isTrue);
      expect(
        oldPolicies.policies.single.record.recordVersionId,
        inherited.policies.single.record.recordVersionId,
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
