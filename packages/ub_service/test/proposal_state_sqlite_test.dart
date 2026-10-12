@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_service/proposal_state.dart';
import 'package:ub_store/src/database.dart';
import 'package:ub_store/src/workflow_storage.dart';

import 'proposal_state_test.dart' as proposals;

void main() {
  test('immutable frozen proposal versions survive SQLite reopen and remain independently readable', () {
    final directory = Directory.systemTemp.createTempSync(
      'universe-builder-proposal-',
    );
    final path = '${directory.path}/package.sqlite';
    try {
      final old = proposals.prepare();
      final submitted = proposals.prepare(
        request: proposals.transition(old),
        previous: old,
      );
      final original = SqliteDatabase.open(path);
      try {
        WorkflowStorage(original).compareAppend({}, [
          MapEntry(old.key, old.toWire()),
          MapEntry(submitted.key, submitted.toWire()),
        ]);
      } finally {
        original.close();
      }
      final reopened = SqliteDatabase.open(path, existing: true);
      try {
        final workflow = WorkflowStorage(reopened);
        final readOld = StoredProposal.fromWire(workflow.get(old.key)!);
        final readSubmitted = StoredProposal.fromWire(
          workflow.get(submitted.key)!,
        );
        expect(readOld.toWire().toText(), old.toWire().toText());
        expect(readSubmitted.toWire().toText(), submitted.toWire().toText());
        final prefix = 'proposal:${old.proposal.proposalId.value}:';
        expect(isLatestProposal(readOld, workflow.keys(prefix)), isFalse);
        expect(isLatestProposal(readSubmitted, workflow.keys(prefix)), isTrue);
        expect(
          () => workflow.compareAppend({}, [
            MapEntry(old.key, submitted.toWire()),
          ]),
          throwsFormatException,
        );
        expect(workflow.get(old.key)!.toText(), old.toWire().toText());
        final withdrawn = proposals.prepare(
          request: proposals.transition(submitted, withdraw: true),
          previous: submitted,
        );
        workflow.compareAppend(
          {prefix: submitted.key},
          [MapEntry(withdrawn.key, withdrawn.toWire())],
        );
        final revised = proposals.prepare(
          request: proposals.revise(submitted),
          previous: submitted,
        );
        expect(
          () => workflow.compareAppend(
            {prefix: submitted.key},
            [MapEntry(revised.key, revised.toWire())],
          ),
          throwsFormatException,
        );
        expect(
          StoredProposal.fromWire(workflow.get(withdrawn.key)!)
              .proposal
              .withdrawn,
          isTrue,
        );
      } finally {
        reopened.close();
      }
    } finally {
      directory.deleteSync(recursive: true);
    }
  });
}
