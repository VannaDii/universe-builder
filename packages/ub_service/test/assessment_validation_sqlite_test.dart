@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/assessment_validation.dart';
import 'package:ub_service/assessment_resolution.dart';
import 'package:ub_service/proposal_state.dart';
import 'package:ub_service/validation_binding.dart';
import 'package:ub_store/src/database.dart';
import 'package:ub_store/src/workflow_storage.dart';

import 'assessment_validation_test.dart' as a;
import 'operation_compilation_test.dart' as f;
import 'source_verification_test.dart' as sources;
import 'structural_checks_test.dart' as structure;

void main() {
  test('retained external assessment revalidates after SQLite reopen without erasing unresolved accounting', () async {
    final directory = Directory.systemTemp.createTempSync(
      'universe-builder-assessment-',
    );
    final path = '${directory.path}/package.sqlite';
    try {
      final body = a.mapped(kind: CandidateLinkKind.unchangedRecord);
      final envelope = AssessmentEnvelope(
        assessmentId: AssessmentId('asm_${f.suffix(1)}'),
        digest: body.digest(),
        body: body,
      );
      final reference = AssessmentRef(
        assessmentId: envelope.assessmentId,
        digest: envelope.digest,
      );
      final selection = AssessmentSelection(
        proposal: a.proposal.reference,
        generation: BigInt.one,
        selected: reference,
      );
      final original = SqliteDatabase.open(path);
      try {
        WorkflowStorage(original).compareAppend({}, [
          MapEntry(a.proposal.key, a.proposal.toWire()),
          MapEntry(
            '${assessmentSelectionPrefix(a.proposal.reference)}00000000000000000001',
            selection.toWire(),
          ),
          MapEntry(
            'assessment:${envelope.assessmentId.value}',
            envelope.toWire(),
          ),
          for (final entry in sources.staging(sources.source()).entries) entry,
        ]);
      } finally {
        original.close();
      }
      final reopened = SqliteDatabase.open(path, existing: true);
      try {
        final workflow = WorkflowStorage(reopened);
        final retained = AssessmentEnvelope.fromWire(
          workflow.get('assessment:${envelope.assessmentId.value}')!,
        );
        retained.verify();
        final proposal = StoredProposal.fromWire(workflow.get(a.proposal.key)!);
        final version = SourceVersionRecord.fromWire(
          workflow.get('source-version:${f.id(2).value}')!,
        );
        final records = [
          f.row(2, version),
          f.row(10, f.entity()),
          f.row(50, f.entity()),
          structure.context(99),
        ];
        await verifyAssessmentCandidate(
          proposal: proposal,
          universe: f.u,
          body: retained.body,
          readCanon: (_, _) => records,
          readWorkflow: workflow.get,
          readVersion: (_) => throw StateError('Unexpected history read'),
        );
        expect(retained.body.conclusion, DeclaredConclusion.unresolved);
        expect(retained.body.unresolved, hasLength(1));
        expect(retained.toWire().toText(), envelope.toWire().toText());
        final review = await resolveAssessment(
          reference: proposal.reference,
          universe: f.u,
          canObserveMissingMaterial: true,
          readProposal: (_) => proposal,
          checkAccess: (proposal, body) async {
            await checkAssessmentAccess(
              proposal: proposal,
              body: body,
              limits: GrantLimits(),
              worldScope: null,
              readCanon: (_, _) => records,
              readVersion: (_) => throw StateError('Missing history'),
            );
          },
          readLatestKey: workflow.latestKey,
          readWorkflow: workflow.get,
          readHead: (_) => proposal.proposal.baseFrame.revision,
          readCanon: (_, _) => records,
          readVersion: (_) => throw StateError('Unexpected history read'),
        );
        expect(
          (review.state as BoundAssessment).selectionGeneration,
          BigInt.one,
        );
        expect(
          (review.state as BoundAssessment).declaredConclusion,
          DeclaredConclusion.unresolved,
        );
        expect(review.envelope!.toWire().toText(), envelope.toWire().toText());
        final capture = await captureValidationBinding(
          proposal: proposal,
          authorityDigest: 'disposable owner authority',
          authoritySequence: BigInt.parse('9007199254740993'),
          readLatestKey: workflow.latestKey,
          readWorkflow: workflow.get,
          readHead: (_) => proposal.proposal.baseFrame.revision,
          resolveSelected: (_) => review,
        );
        expect(capture.submittedInput, isA<SourceAssessedCandidateInput>());
        expect(
          capture.selection.toWire().toText(),
          selection.toWire().toText(),
        );
        expect(capture.latestProposalKey, proposal.key);
        expect(capture.authoritySequence, BigInt.parse('9007199254740993'));
        expect(workflow.keys('approval:'), isEmpty);
        expect(workflow.keys('validation:'), isEmpty);
      } finally {
        reopened.close();
      }
    } finally {
      directory.deleteSync(recursive: true);
    }
  });
}
