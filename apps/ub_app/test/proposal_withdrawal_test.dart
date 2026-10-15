@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart' hide Description;
import 'package:ub_app/connection.dart';
import 'package:ub_app/connection_native.dart';
import 'package:ub_app/saved_changes.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

void main() {
  test('withdrawal recovers the original operation, preserves history and requires fresh approval for later changes', () async {
    final root = Directory('/tmp').createTempSync('ub-proposal-withdrawal-');
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
            name: 'Withdrawal',
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
        universe: const Selector('Withdrawal'),
        scope: scope,
      );
      final content = DraftContent(
        baseRevision: RevisionId.parse(created.string('revision')),
        representedContext: scope.representedContext!,
        operations: [
          CreateWorldOperation(
            clientRef: RecordId.generate().value,
            record: WorldRecord(selector: 'Original'),
          ),
        ],
        rationale: 'Create the world.',
      );
      var draft = await changes().saveContent(
        SavedDraft(version: BigInt.zero, content: content),
        content,
      );
      final first = await changes().submit(draft);
      final firstChecks =
          await changes().validate(first) as EvaluatedValidation;
      await changes().approve(first, firstChecks);
      final firstReceipt = await changes().publish(
        first,
        firstChecks.execution.runId,
      );
      final world = (await changes().readPublished(first, firstReceipt)).single;
      draft = await changes().rebase((await changes().load())!, startNew: true);
      draft = await changes().saveContent(
        draft,
        DraftContent(
          baseRevision: draft.content.baseRevision,
          representedContext: scope.representedContext!,
          operations: [
            RenameWorldSelectorOperation(
              record: RecordRef(
                universe: scope.universe,
                record: world.identity.recordId,
              ),
              expectedVersion: world.recordVersionId,
              newSelector: 'Later 記憶 😀',
            ),
          ],
          rationale: 'An exact proposed rename.',
        ),
      );
      final proposed = await changes().submit(draft);
      final submitted = (await changes().load())!;
      final validation =
          await changes().validate(proposed) as EvaluatedValidation;
      await changes().approve(proposed, validation);
      // Ignore this response, as if the connection disappeared after the write.
      await changes().withdraw(proposed);
      await session.close();
      session = await device.connect();
      final retained = (await changes().load())!;
      expect(retained.toWire().toText(), submitted.toWire().toText());
      final withdrawn = (await changes().recover(retained))!;
      expect(withdrawn.withdrawn, isTrue);
      expect(withdrawn.proposalId, proposed.proposalId);
      expect(withdrawn.version, proposed.version + BigInt.one);
      expect(
        withdrawn.operations.map((op) => op.toWire().toText()),
        proposed.operations.map((op) => op.toWire().toText()),
      );
      final retry = await changes().withdraw(proposed);
      expect(retry.operationId, withdrawn.operationId);
      expect(retry.version, withdrawn.version);
      expect(
        (await changes().proposal(changes().reference(proposed))).withdrawn,
        isFalse,
      );
      await expectLater(
        changes().publish(proposed, validation.execution.runId),
        throwsA(isA<ProtocolError>()),
      );
      final description = Envelope<Description>.fromWire(
        await session.call(
          ToolEngineRequest(
            request: DescribeSummaryRequest(
              universe: const Selector('Withdrawal'),
            ),
          ),
        ),
        Description.fromWire,
      );
      expect(
        description.result.continuities.single.revisionId,
        firstReceipt.revision,
      );
      final editing = await changes().continueEditing(retained);
      expect(editing.content.proposal, isNull);
      expect(
        editing.content.operations.map((op) => op.toWire().toText()),
        retained.content.operations.map((op) => op.toWire().toText()),
      );
      final replacement = await changes().submit(editing);
      expect(replacement.proposalId, isNot(proposed.proposalId));
      await expectLater(
        changes().publish(replacement, validation.execution.runId),
        throwsA(isA<ProtocolError>()),
      );
      final fresh =
          await changes().validate(replacement) as EvaluatedValidation;
      await changes().approve(replacement, fresh);
      final receipt = await changes().publish(
        replacement,
        fresh.execution.runId,
      );
      final result = (await changes().readPublished(
        replacement,
        receipt,
      )).single;
      expect((result.payload as WorldRecord).selector, 'Later 記憶 😀');
    } on ProtocolError catch (error) {
      fail(error.toWire().toText());
    } finally {
      await session?.close();
      root.deleteSync(recursive: true);
    }
  });
}
