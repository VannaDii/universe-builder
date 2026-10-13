@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_app/connection.dart';
import 'package:ub_app/connection_native.dart';
import 'package:ub_app/saved_changes.dart';
import 'package:ub_app/world_draft.dart';
import 'package:ub_app/record_browser.dart';
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
