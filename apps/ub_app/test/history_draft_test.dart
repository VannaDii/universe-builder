@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_app/connection.dart';
import 'package:ub_app/connection_native.dart';
import 'package:ub_app/draft_record_choices.dart';
import 'package:ub_app/history_draft.dart';
import 'package:ub_app/record_browser.dart';
import 'package:ub_app/saved_changes.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

void main() {
  test('history restoration recovers a compensating draft and preserves prior revisions', () async {
    final root = Directory('/tmp').createTempSync('ub-history-restoration-');
    final device = DeviceConnection([
      '--installation',
      root.path,
    ], embeddedLocal: true);
    AppSession? session;
    try {
      session = await device.connect();
      final status = InstanceLibrary.fromWire(
        await session.call(const StatusEngineRequest()),
      );
      final created = WireFields(
        await session.call(
          const CreateUniverseEngineRequest(
            realWorld: false,
            name: 'History',
            start: GregorianUniverseStart('2040-01-01T00:00:00Z'),
          ),
        ),
        {'universe_id', 'continuity_id', 'context_id', 'revision', 'name'},
      );
      final scope = EditorFormScope(
        instance: status.instance,
        profile: session.principal,
        universe: UniverseId.parse(created.string('universe_id')),
        continuity: ContinuityId.parse(created.string('continuity_id')),
        representedContext: RecordId.parse(created.string('context_id')),
      );
      SavedChanges changes() => SavedChanges(
        session: session!,
        universe: const Selector('History'),
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

      final empty = SavedDraft(
        version: BigInt.zero,
        content: DraftContent(
          baseRevision: RevisionId.parse(created.string('revision')),
          representedContext: scope.representedContext!,
          operations: [],
          rationale: '',
        ),
      );
      var draft = await changes().saveContent(
        empty,
        DraftContent(
          baseRevision: empty.content.baseRevision,
          representedContext: scope.representedContext!,
          operations: [
            CreateWorldOperation(
              clientRef: RecordId.generate().value,
              record: WorldRecord(selector: 'Original 記憶 😀'),
            ),
          ],
          rationale: 'Original world name.',
        ),
      );
      final original = (await publish(draft)).single;
      draft = await changes().rebase((await changes().load())!, startNew: true);
      final firstContext = await openDraftChoiceContext(changes(), draft);
      draft = await changes().saveContent(
        draft,
        DraftContent(
          baseRevision: draft.content.baseRevision,
          representedContext: scope.representedContext!,
          operations: [
            RenameWorldSelectorOperation(
              record: RecordRef(
                universe: scope.universe,
                record: original.identity.recordId,
              ),
              expectedVersion: original.recordVersionId,
              newSelector: 'Later name',
            ),
          ],
          rationale: 'Rename the world.',
        ),
      );
      final renamed = (await publish(draft)).single;
      draft = await changes().rebase((await changes().load())!, startNew: true);
      final opened = await openDraftChoiceContext(changes(), draft);
      final material = await readContextRecordMaterial(
        session: session,
        universe: LibraryEntry(scope.universe, 'History'),
        context: opened,
        record: original.identity.recordId,
        group: FieldGroup.history,
        includePayload: true,
      );
      final historical = material.result.history
          .singleWhere(
            (entry) =>
                entry.record?.recordVersionId == original.recordVersionId,
          )
          .record!;
      expect(canRestoreRecordVersion(renamed, historical), isTrue);
      expect(canRestoreRecordVersion(renamed, renamed), isFalse);
      final other = CreateWorldOperation(
        clientRef: RecordId.generate().value,
        record: WorldRecord(selector: 'Unrelated draft world'),
      );
      draft = await changes().saveContent(
        draft,
        DraftContent(
          baseRevision: draft.content.baseRevision,
          representedContext: scope.representedContext!,
          operations: [other],
          rationale: 'Keep this other draft work.',
        ),
      );
      await expectLater(
        stageHistoryRestoration(
          changes: changes(),
          context: firstContext,
          current: renamed,
          source: historical,
          rationale: 'Wrong revision',
        ),
        throwsFormatException,
      );
      final restored = await stageHistoryRestoration(
        changes: changes(),
        context: opened,
        current: renamed,
        source: historical,
        rationale: 'Restore the earlier authored name.',
      );
      final again = await stageHistoryRestoration(
        changes: changes(),
        context: opened,
        current: renamed,
        source: historical,
        rationale: 'Restore the earlier authored name.',
      );
      expect(again.version, restored.version);
      expect(again.content.operations, hasLength(2));
      expect(
        again.content.operations.first.toWire().toText(),
        other.toWire().toText(),
      );
      expect(again.content.rationale, contains('Keep this other draft work.'));
      expect(
        (again.content.operations.last as AdoptRecordVersionOperation)
            .expectedVersion,
        renamed.recordVersionId,
      );
      expect(
        (await readContextRecord(
          session: session,
          universe: LibraryEntry(scope.universe, 'History'),
          context: opened,
          record: original.identity.recordId,
        )).recordVersionId,
        renamed.recordVersionId,
      );
      await session.close();
      session = await device.connect();
      final recovered = (await changes().load())!;
      expect(recovered.toWire().toText(), restored.toWire().toText());
      final published = await publish(recovered);
      final finalRecord = published.singleWhere(
        (row) => row.identity.recordId == original.identity.recordId,
      );
      expect(
        published.where(
          (row) =>
              (row.payload as WorldRecord).selector == 'Unrelated draft world',
        ),
        hasLength(1),
      );
      expect(finalRecord.identity.recordId, original.identity.recordId);
      expect(finalRecord.recordVersionId, isNot(original.recordVersionId));
      expect(finalRecord.recordVersionId, isNot(renamed.recordVersionId));
      expect(
        finalRecord.payload.toWire().toText(),
        original.payload.toWire().toText(),
      );
      final fresh = await changes().rebase(
        (await changes().load())!,
        startNew: true,
      );
      final freshContext = await openDraftChoiceContext(changes(), fresh);
      final history = await readContextRecordMaterial(
        session: session,
        universe: LibraryEntry(scope.universe, 'History'),
        context: freshContext,
        record: original.identity.recordId,
        group: FieldGroup.history,
        includePayload: true,
      );
      expect(
        history.result.history.map((entry) => entry.record?.recordVersionId),
        containsAll([
          original.recordVersionId,
          renamed.recordVersionId,
          finalRecord.recordVersionId,
        ]),
      );
    } on ProtocolError catch (error) {
      fail(error.toWire().toText());
    } finally {
      await session?.close();
      root.deleteSync(recursive: true);
    }
  });
}
