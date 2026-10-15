@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_app/connection.dart';
import 'package:ub_app/connection_native.dart';
import 'package:ub_app/draft_record_choices.dart';
import 'package:ub_app/saved_changes.dart';
import 'package:ub_app/writing_review.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

void main() {
  test('writing passage survives restart and publication recovers the original approval', () async {
    final root = Directory('/tmp').createTempSync('ub-writing-review-');
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
            name: 'Writing',
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
      WritingWorkflow flow() => WritingWorkflow(
        SavedChanges(
          session: session!,
          universe: const Selector('Writing'),
          scope: scope,
        ),
      );
      final opened = await openDraftChoiceContext(
        flow().changes,
        SavedDraft(
          version: BigInt.zero,
          content: DraftContent(
            baseRevision: RevisionId.parse(created.string('revision')),
            representedContext: scope.representedContext!,
            operations: [],
            rationale: '',
          ),
        ),
      );
      await session.call(
        ToolEngineRequest(
          request: CheckChangesRequest(
            universe: const Selector('Writing'),
            contextId: opened.contextId,
            changes: [ObjectChange(name: 'Mara', introduce: true)],
          ),
        ),
      );
      final row = (await flow().choices()).proposals.single;
      expect(row.label, contains('Mara'));
      final draft = await flow().exact(row.candidate);
      const text = '\ufeffMara arrives.\r\n記憶 😀\u0000';
      final form = flow().passage(draft, label: 'Opening', text: text);
      final saved = await session.saveSourceForm(
        flow().passageScope(draft),
        form,
        BigInt.zero,
      );
      await session.close();
      session = await device.connect();
      final retained = await session.loadSourceForm(flow().passageScope(draft));
      expect(retained!.generation, saved.generation);
      expect(retained.form.text, text);
      expect(retained.form.label, 'Opening');
      final prepared = await flow().review(
        PrepareWritingAction(
          candidate: row.candidate.proposalId,
          label: retained.form.label,
          text: retained.form.text,
        ),
      );
      expect(prepared.publishable, isTrue);
      expect(
        prepared.proposal.operations
            .whereType<AddSourceAnchorOperation>()
            .single
            .record
            .excerpt,
        text,
      );
      expect((await flow().choices()).approved, isEmpty);
      // Publication must not implicitly approve even a publishable review.
      await expectLater(
        flow().publish(
          WritingApproval(
            CanonicalObject([
              MapEntry('candidate', prepared.candidate.toWire()),
              MapEntry(
                'validation_run',
                CanonicalString(prepared.validation.execution!.runId.value),
              ),
              MapEntry('label', CanonicalString('Not approved')),
            ]),
          ),
        ),
        throwsA(isA<ProtocolError>()),
      );
      expect((await flow().choices()).approved, isEmpty);
      final inspected = await flow().review(
        InspectWritingAction(candidate: prepared.candidate),
      );
      expect(inspected.candidate, prepared.candidate);
      expect(
        inspected.proposal.operations
            .whereType<AddSourceAnchorOperation>()
            .single
            .record
            .excerpt,
        text,
      );
      final approval = await flow().approve(inspected);
      expect(approval.publicationKey, startsWith('native-writing-commit-'));
      final approvals = (await flow().choices()).approved;
      expect(approvals.single.candidate, inspected.candidate);
      expect(approvals.single.run, approval.run);
      final receipt = await flow().publish(approval);
      await session.close();
      session = await device.connect();
      final recovered = await flow().publish(
        (await flow().choices()).approved.single,
      );
      expect(recovered.operationId, receipt.operationId);
      expect(recovered.revision, receipt.revision);
      expect(recovered.proposalId, receipt.proposalId);
      expect((await flow().choices()).proposals, isEmpty);
    } on ProtocolError catch (error) {
      fail(error.toWire().toText());
    } finally {
      await session?.close();
      root.deleteSync(recursive: true);
    }
  });
}
