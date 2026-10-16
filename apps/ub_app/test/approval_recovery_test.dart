@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart' hide Description;
import 'package:ub_app/connection.dart';
import 'package:ub_app/connection_native.dart';
import 'package:ub_app/saved_changes.dart';
import 'package:ub_app/world_draft.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

void main() {
  test('embedded app restarts retain saved approval before publication and recover its exact receipt', () async {
    final root = Directory.systemTemp.createTempSync('ub-approval-recovery-');
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
            name: 'Campaign',
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
        universe: const Selector('Campaign'),
        scope: scope,
      );
      final base = RevisionId.parse(created.string('revision'));
      await session.call(
        worldDraftRequest(
          universe: const Selector('Campaign'),
          continuity: scope.continuity,
          previous: null,
          form: UnfinishedWorldForm(
            baseRevision: base,
            representedContext: scope.representedContext!,
            record: RecordId.generate(),
            selector: 'River world',
            settingType: '',
            rationale: 'Add the campaign setting.',
          ),
        ),
      );
      Future<void> restart() async {
        await session!.close();
        session = null;
        session = await device.connect();
      }

      await restart();
      var draft = (await changes().load())!;
      expect(await changes().recover(draft), isNull);
      final proposal = await changes().submit(draft);
      final validation =
          await changes().validate(proposal) as EvaluatedValidation;
      await restart();
      draft = (await changes().load())!;
      final recovered = (await changes().recover(draft))!;
      expect(changes().reference(recovered), changes().reference(proposal));
      expect(await changes().publication(recovered), isNull);
      await changes().approve(recovered, validation);
      await restart();
      final approval = (await changes().publication(recovered))!;
      expect(approval.run, validation.execution.runId);
      expect(approval.status, isNull);
      final before = Envelope<Description>.fromWire(
        await session!.call(
          ToolEngineRequest(
            request: DescribeSummaryRequest(
              universe: const Selector('Campaign'),
            ),
          ),
        ),
        Description.fromWire,
      ).result;
      expect(before.worlds, isEmpty);
      expect(before.continuities.single.revisionId, base);
      final receipt = await changes().publish(recovered, approval.run);
      await restart();
      final published = (await changes().publication(recovered))!;
      expect(
        published.status!.receipt!.toWire().toText(),
        receipt.toWire().toText(),
      );
      expect(
        (await changes().publish(recovered, published.run)).toWire().toText(),
        receipt.toWire().toText(),
      );
      final records = await changes().readPublished(recovered, receipt);
      expect(records.where((r) => r.payload is WorldRecord), hasLength(1));
    } finally {
      await session?.close();
      root.deleteSync(recursive: true);
    }
  });
}
