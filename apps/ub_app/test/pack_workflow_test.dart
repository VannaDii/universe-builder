@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_app/pack_draft.dart';
import 'package:ub_app/universe_policies.dart';
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
  test('pack declaration and upgrade recover and publish exact metadata with retained history', () async {
    final root = Directory('/tmp').createTempSync('ub-pack-workflow-');
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
            name: 'Packs',
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
        universe: Selector('Packs'),
        scope: scope,
      );
      Future<List<RecordVersion>> publish(SavedDraft draft) async {
        late Proposal proposal;
        try {
          proposal = await changes().submit(draft);
        } on InvalidArgumentError catch (error) {
          fail('${error.field}: ${error.message}');
        }
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
      final basePack = UnfinishedPackForm(
        baseRevision: initial.content.baseRevision,
        representedContext: scope.representedContext!,
        clientRef: RecordId.generate().value,
        key: 'foundation',
        version: '1',
        capabilities: ['assertion.qualified.v1'],
        rationale: 'Declare the foundation data pack.',
      );
      final baseDraft = SavedDraft.fromWire(
        await session.call(
          packDraftRequest(
            draft: initial,
            form: basePack,
            universe: const Selector('Packs'),
            continuity: scope.continuity,
          ),
        ),
      );
      await publish(baseDraft);
      final next = await changes().rebase(
        (await changes().load())!,
        startNew: true,
      );
      final gregorian = (await searchDraftChoices(
        changes: changes(),
        context: await openDraftChoiceContext(changes(), next),
        kind: RecordKind.calendar,
        query: 'Gregorian',
      )).result.hits.single;
      final groupForm = UnfinishedPackForm(
        baseRevision: next.content.baseRevision,
        representedContext: scope.representedContext!,
        clientRef: RecordId.generate().value,
        key: 'campaign-kit',
        version: '1',
        dependencies: [
          const PackDependencyInput(key: 'foundation', version: '1'),
        ],
        capabilities: ['assertion.qualified.v1'],
        records: [
          scope.representedContext!.value,
          gregorian.recordId.value,
          gregorian.recordId.value,
        ],
        rationale: 'Declare the explicit campaign pack.',
      );
      await session.savePackForm(scope, groupForm, BigInt.zero);
      await session.close();
      session = await device.connect();
      final recoveredGroup = (await session.loadPackForm(scope))!.form;
      expect(recoveredGroup.toWire().toText(), groupForm.toWire().toText());
      final groupDraft = SavedDraft.fromWire(
        await session.call(
          packDraftRequest(
            draft: next,
            form: recoveredGroup,
            universe: const Selector('Packs'),
            continuity: scope.continuity,
          ),
        ),
      );
      final published = (await publish(groupDraft)).single;
      expect(
        published.payload.toWire().toText(),
        packOperation(groupForm).record.toWire().toText(),
      );
      final upgradeBase = await changes().rebase(
        (await changes().load())!,
        startNew: true,
      );
      final upgradeScope = EditorFormScope(
        instance: scope.instance,
        profile: scope.profile,
        universe: scope.universe,
        continuity: scope.continuity,
        representedContext: scope.representedContext,
        typeClientRef: published.identity.recordId.value,
      );
      final upgradeForm =
          packRevisionFormFromRecord(
            record: published,
            baseRevision: upgradeBase.content.baseRevision,
            representedContext: scope.representedContext!,
          ).copyWith(
            version: '2',
            records: groupForm.records.reversed.toList(),
            rationale: 'Upgrade the declared campaign pack.',
          );
      await session.savePackForm(upgradeScope, upgradeForm, BigInt.zero);
      await session.close();
      session = await device.connect();
      final recoveredUpgrade = (await session.loadPackForm(upgradeScope))!.form;
      expect(recoveredUpgrade.toWire().toText(), upgradeForm.toWire().toText());
      final upgradeDraft = SavedDraft.fromWire(
        await session.call(
          packDraftRequest(
            draft: upgradeBase,
            form: recoveredUpgrade,
            universe: const Selector('Packs'),
            continuity: scope.continuity,
          ),
        ),
      );
      final upgraded = (await publish(upgradeDraft)).single;
      expect(upgraded.identity.recordId, published.identity.recordId);
      expect(
        upgraded.payload.toWire().toText(),
        packRevisionOperation(upgradeForm).replacement.toWire().toText(),
      );
      final retained = await readContextRecord(
        session: session,
        universe: LibraryEntry(scope.universe, 'Packs'),
        context: await openDraftChoiceContext(changes(), upgradeBase),
        record: published.identity.recordId,
      );
      expect(retained.toWire().toText(), published.toWire().toText());
      final current = await changes().rebase(
        (await changes().load())!,
        startNew: true,
      );
      final currentContext = await openDraftChoiceContext(changes(), current);
      final foundPack = await searchDraftChoices(
        changes: changes(),
        context: currentContext,
        kind: RecordKind.domainPack,
        query: 'campaign-kit',
      );
      expect(foundPack.result.hits.single.label, 'campaign-kit (2)');
      final contextRecord = await readContextRecord(
        session: session,
        universe: LibraryEntry(scope.universe, 'Packs'),
        context: currentContext,
        record: scope.representedContext!,
      );
      final earlierContext = await readContextRecord(
        session: session,
        universe: LibraryEntry(scope.universe, 'Packs'),
        context: await openDraftChoiceContext(changes(), upgradeBase),
        record: scope.representedContext!,
      );
      expect(contextRecord.toWire().toText(), earlierContext.toWire().toText());
      final policies = await readUniversePolicyChoices(changes(), current);
      final policyScope = EditorFormScope(instance: scope.instance,
        profile: scope.profile, universe: scope.universe, continuity: scope.continuity,
        representedContext: scope.representedContext, typeClientRef: universePolicyEditorKey);
      final unfinished = UnfinishedPackForm(baseRevision: current.content.baseRevision,
        representedContext: scope.representedContext!, clientRef: RecordId.generate().value,
        realWorldPolicy: true, activatePolicy: false,
        expectedRootVersion: policies.selection!.recordVersionId);
      await session.savePackForm(policyScope, unfinished, BigInt.zero);
      await session.close();
      session = await device.connect();
      final recovered = (await session.loadPackForm(policyScope))!.form;
      expect(recovered.toWire().toText(), unfinished.toWire().toText());
      expect(() => universePolicyOperation(recovered), throwsFormatException);
      final named = recovered.copyWith(key: 'Memoir 記憶', rationale: 'Define an independent replacement.');
      final request = packDraftRequest(draft: current, form: named,
        universe: const Selector('Packs'), continuity: scope.continuity);
      final policyDraft = SavedDraft.fromWire(await session.call(request));
      expect(policyDraft.content.operations.single, isA<DefineUniversePolicyOperation>());
      final fields = packFormFromDraft(policyDraft, 0).copyWith(key: 'Memoir 記憶 revised');
      final edited = SavedDraft.fromWire(await session.call(packDraftRequest(
        draft: policyDraft, form: fields, universe: const Selector('Packs'),
        continuity: scope.continuity, index: 0)));
      await publish(edited);
      final selectionBase = await changes().rebase((await changes().load())!, startNew: true);
      final available = await readUniversePolicyChoices(changes(), selectionBase);
      expect(available.definitions, hasLength(2));
      expect(available.selected, policies.selected);
      final definition = available.definitions.singleWhere((row) =>
        row.identity.recordId.value == unfinished.clientRef);
      final visibleRules = await readUniversePolicyRulePage(changes: changes(),
        context: available.context, definition: definition, offset: 0);
      expect(visibleRules.map((r) => r.identity.recordId),
        (definition.payload as DomainPackRecord).records);
      expect(await readUniversePolicyRulePage(changes: changes(),
        context: available.context, definition: definition, offset: 50), isEmpty);
      final selectionRequest = universePolicySelectionDraftRequest(
        draft: selectionBase, universe: const Selector('Packs'), continuity: scope.continuity,
        representedContext: scope.representedContext!, revision: selectionBase.content.baseRevision,
        selection: available.selection!, definition: definition);
      final selectionDraft = SavedDraft.fromWire(await session.call(selectionRequest));
      expect(universePolicyChangeLabel(selectionDraft.content.operations.single),
        'select universe root: Memoir 記憶 revised');
      expect(() => universePolicySelectionDraftRequest(
        draft: selectionDraft, universe: const Selector('Packs'), continuity: scope.continuity,
        representedContext: scope.representedContext!, revision: selectionBase.content.baseRevision,
        selection: available.selection!, definition: definition), throwsFormatException);
      await publish(selectionDraft);
      final selectedBase = await changes().rebase((await changes().load())!, startNew: true);
      expect((await readUniversePolicyChoices(changes(), selectedBase)).selected,
          definition.identity.recordId);
      expect((await readUniversePolicyChoices(changes(), current)).selected, policies.selected);
      final revisionForm = packRevisionFormFromRecord(record: definition,
        baseRevision: selectedBase.content.baseRevision,
        representedContext: scope.representedContext!).copyWith(version: '2',
          rationale: 'Revise the selected policy without breaking its root binding.');
      final revisedDraft = SavedDraft.fromWire(await session.call(packDraftRequest(
        draft: selectedBase, form: revisionForm, universe: const Selector('Packs'),
        continuity: scope.continuity)));
      final revised = await publish(revisedDraft);
      expect(revised, hasLength(2)); // Definition and its selected root dependency.
      final revisedBase = await changes().rebase((await changes().load())!, startNew: true);
      final revisedPolicies = await readUniversePolicyChoices(changes(), revisedBase);
      expect(revisedPolicies.selected, definition.identity.recordId);
      expect((revisedPolicies.selection!.payload as DomainPackRecord).dependencies,
          {(definition.payload as DomainPackRecord).key: '2'});
    } finally {
      await session?.close();
      await server.close();
      root.deleteSync(recursive: true);
    }
  });
}
