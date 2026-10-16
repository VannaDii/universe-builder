@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart' hide Description;
import 'package:ub_app/connection.dart';
import 'package:ub_app/connection_native.dart';
import 'package:ub_app/proposal_impact.dart';
import 'package:ub_app/saved_changes.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

void main() {
  test('proposal impact pages retain proposed names and exact baseline after later publication and restart', () async {
    final root = Directory('/tmp').createTempSync('ub-proposal-impact-');
    final device = DeviceConnection([
      '--installation',
      root.path,
    ], embeddedLocal: true);
    AppSession? session;
    try {
      session = await device.connect();
      final created = WireFields(
        await session.call(
          const CreateUniverseEngineRequest(
            realWorld: false,
            name: 'Impact',
            start: GregorianUniverseStart('2040-01-01T00:00:00Z'),
          ),
        ),
        {'universe_id', 'continuity_id', 'context_id', 'revision', 'name'},
      );
      final status = InstanceLibrary.fromWire(
        await session.call(const StatusEngineRequest()),
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
        universe: const Selector('Impact'),
        scope: scope,
      );
      Future<List<RecordVersion>> publish(SavedDraft draft) async {
        final proposal = await changes().submit(draft);
        final validation =
            await changes().validate(proposal) as EvaluatedValidation;
        await changes().approve(proposal, validation);
        return changes().readPublished(
          proposal,
          await changes().publish(proposal, validation.execution.runId),
        );
      }

      final content = DraftContent(
        baseRevision: RevisionId.parse(created.string('revision')),
        representedContext: scope.representedContext!,
        operations: [
          for (var i = 0; i < 55; i++)
            CreateWorldOperation(
              clientRef: RecordId.generate().value,
              record: WorldRecord(selector: 'Setting $i'),
            ),
        ],
        rationale: 'Worlds for a paged impact review',
      );
      var draft = await changes().saveContent(
        SavedDraft(version: BigInt.zero, content: content),
        content,
      );
      final worlds = await publish(draft);
      RecordVersion world(int n) => worlds.singleWhere(
        (r) => (r.payload as WorldRecord).selector == 'Setting $n',
      );
      Future<SavedDraft> rename(int n, String label) async {
        final base = await changes().rebase(
          (await changes().load())!,
          startNew: true,
        );
        return changes().saveContent(
          base,
          DraftContent(
            baseRevision: base.content.baseRevision,
            representedContext: scope.representedContext!,
            operations: [
              RenameWorldSelectorOperation(
                record: RecordRef(
                  universe: scope.universe,
                  record: world(n).identity.recordId,
                ),
                expectedVersion: world(n).recordVersionId,
                newSelector: label,
              ),
            ],
            rationale: 'Rename one setting',
          ),
        );
      }

      draft = await rename(0, 'Proposed setting 記憶 😀');
      final proposal = await changes().submit(draft);
      await publish(await rename(1, 'Later setting'));
      await session.close();
      session = await device.connect();
      final recovered = await changes().proposal(changes().reference(proposal));
      final snapshot = await readProposalImpact(changes(), recovered);
      expect(snapshot.context.frame, proposal.baseFrame);
      expect(snapshot.impact.coverage, Coverage.complete);
      expect(
        snapshot.impact.records.toSet().length,
        snapshot.impact.records.length,
      );
      expect(
        snapshot.impact.records,
        containsAll(worlds.map((row) => row.identity.recordId)),
      );
      expect(snapshot.impact.records.length, greaterThan(50));
      final rows = <ProposalImpactRecord>[];
      for (
        var offset = 0;
        offset < snapshot.impact.records.length;
        offset += 25
      ) {
        final page = await snapshot.page(changes(), offset: offset);
        expect(page.length, lessThanOrEqualTo(25));
        rows.addAll(page);
      }
      expect(rows.map((row) => row.id), snapshot.impact.records);
      expect(
        rows.singleWhere((row) => row.id == world(0).identity.recordId).label,
        'Proposed setting 記憶 😀',
      );
      final unchanged = rows.singleWhere(
        (row) => row.id == world(1).identity.recordId,
      );
      expect(unchanged.label, 'Setting 1');
      expect(unchanged.change, isNull);
      expect(
        (await snapshot.page(
          changes(),
          offset: snapshot.impact.records.length,
        )),
        isEmpty,
      );
      await expectLater(
        snapshot.page(changes(), offset: -1),
        throwsFormatException,
      );
      await expectLater(
        readProposalImpact(changes(), proposal, byteBudget: 256),
        throwsA(isA<EvaluationLimitReachedError>()),
      );
      // Reading impact leaves publication state and the current revision unchanged.
      final description = Envelope<Description>.fromWire(
        await session.call(
          ToolEngineRequest(
            request: DescribeSummaryRequest(universe: const Selector('Impact')),
          ),
        ),
        Description.fromWire,
      ).result;
      final head = description.continuities.single.revisionId;
      expect(head, isNot(proposal.baseFrame.revision));
      expect(await changes().publication(proposal), isNull);
      final again = await readProposalImpact(changes(), proposal);
      expect(again.impact.toWire().toText(), snapshot.impact.toWire().toText());
      final after = Envelope<Description>.fromWire(
        await session.call(
          ToolEngineRequest(
            request: DescribeSummaryRequest(universe: const Selector('Impact')),
          ),
        ),
        Description.fromWire,
      ).result;
      expect(after.continuities.single.revisionId, head);
    } on ProtocolError catch (error) {
      fail(error.toWire().toText());
    } finally {
      await session?.close();
      root.deleteSync(recursive: true);
    }
  });
}
