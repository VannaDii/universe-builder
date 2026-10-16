@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/proposal_state.dart';
import 'package:ub_service/proposal_validation.dart';
import 'package:ub_service/validation_binding.dart';
import 'package:ub_store/ub_store.dart';
import 'package:ub_store/src/database.dart';
import 'package:ub_store/src/kernel.dart';
import 'package:ub_store/src/workflow_storage.dart';

import 'candidate_validation_test.dart' as policies;

import 'package:ub_service/src/universe_evidence_policy.dart';

import 'operation_compilation_test.dart' as f;
import 'proposal_state_test.dart' as proposals;
import 'rule_checks_test.dart' as frames;
import 'structural_checks_test.dart' as structure;

void main() {
  test('proposal checks preview the real SQLite candidate without publishing facts or approvals', () async {
    final directory = Directory.systemTemp.createTempSync(
      'universe-builder-proposal-validation-',
    );
    final database = SqliteDatabase.open('${directory.path}/package.sqlite');
    try {
      final kernel = SqliteKernel(database, f.u),
          continuity = frames.frame().continuity;
      final principal = PrincipalId.parse(
        proposals.actor.value.replaceFirst('prf_', 'prn_'),
      );
      database.execute('BEGIN IMMEDIATE');
      final genesis = kernel.journal.initialize(
        'Disposable campaign',
        continuity,
        principal,
      );
      database.execute('COMMIT');
      final context = structure.context(99),
          blocking = f.row(80, policies.rule());
      StoredVersion stored(RecordVersion row) => StoredVersion(
        versionId: row.recordVersionId,
        identity: row.identity,
        payload: row.payload.toWire(),
        digest: row.payloadDigest,
      );
      CommitInput fixtureInput(
        String key,
        RevisionId head,
        List<RecordVersion> rows,
      ) => CommitInput(
        universe: f.u,
        continuity: continuity,
        expectedHead: head,
        principal: principal,
        decision: 'Already admitted test fixture',
        reason: 'Disposable kernel input',
        idempotencyKey: key,
        changes: rows.map(
          (row) =>
              Assignment(recordId: row.identity.recordId, next: stored(row)),
        ),
      );
      final first = kernel.commit(
        fixtureInput('context', genesis, [
          context,
          ...initialUniversePolicyRecords(f.u, false),
        ]),
      );
      Frame frame(RevisionId head) => Frame(
        universe: f.u,
        continuity: continuity,
        revision: head,
        context: f.ref(99),
        time: const TimelessFrameTime(),
        perspective: const AuthorPerspective(),
      );
      List<RecordVersion> readCanon(
        ContinuityId continuity,
        RevisionId revision,
      ) {
        final members =
            kernel.journal.snapshot(continuity, revision).entries.toList()
              ..sort((a, b) => a.key.value.compareTo(b.key.value));
        return [
          for (final entry in members)
            RecordVersion.fromWire(
              kernel.journal.load(entry.value).toCanonical(),
            ),
        ];
      }

      Future<CheckedValidation> check(StoredProposal proposal) =>
          checkProposalCandidate(
            stored: proposal,
            universe: f.u,
            principal: proposals.actor,
            approvalAuthor: proposals.actor,
            scope: null,
            preview: (input) => kernel
                .preview(input)
                .map((r) => RecordVersion.fromWire(r.toCanonical()))
                .toList(),
            readCanon: readCanon,
            readWorkflow: WorkflowStorage(database).get,
            readVersion: (id) =>
                RecordVersion.fromWire(kernel.journal.load(id).toCanonical()),
          );
      final proposal = proposals.prepare(
        frame: frame(first),
        base: readCanon(continuity, first),
      );
      final valid = await check(proposal);
      expect(valid.admissible, isTrue);
      expect(valid.validation.coverage, Coverage.complete);
      expect(valid.validation.inputDigest, proposal.proposal.digest);
      expect(valid.validation.findings, isEmpty);
      expect(valid.report, isNull);
      expect(valid.capture, isNull);
      expect(kernel.journal.head(continuity), first);
      expect(kernel.identityExists(proposal.changes.single.recordId), isFalse);
      expect(WorkflowStorage(database).keys('approval:'), isEmpty);
      expect(WorkflowStorage(database).keys('validation:'), isEmpty);
      final second = kernel.commit(
        fixtureInput('blocking-rule', first, [blocking]),
      );
      await expectLater(check(proposal), throwsFormatException);
      final current = proposals.prepare(
        frame: frame(second),
        base: readCanon(continuity, second),
      );
      final denied = await check(current);
      expect(denied.admissible, isFalse);
      expect(denied.validation.findings, isNotEmpty);
      expect(kernel.journal.head(continuity), second);
      expect(kernel.identityExists(current.changes.single.recordId), isFalse);
      expect(database.autocommit, isTrue);
    } finally {
      database.close();
      directory.deleteSync(recursive: true);
    }
  });
}
