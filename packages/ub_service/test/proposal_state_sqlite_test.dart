@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/proposal_state.dart';
import 'package:ub_store/src/database.dart';
import 'package:ub_store/src/workflow_storage.dart';

import 'proposal_state_test.dart' as proposals;

void main() {
  test('reservations survive withdrawal and reopen; competing drafts roll back atomically', () async {
    final directory = Directory.systemTemp.createTempSync(
      'universe-builder-reservation-',
    );
    final path = '${directory.path}/package.sqlite';
    try {
      final first = proposals.prepare();
      final withdrawn = proposals.prepare(
        request: proposals.transition(first, withdraw: true),
        previous: first,
      );
      final key = proposalReservationKey(first.changes.single.recordId);
      final original = SqliteDatabase.open(path);
      try {
        final workflow = WorkflowStorage(original);
        final reservations = await proposalReservationEntries(
          stored: first,
          readWorkflow: workflow.get,
        );
        workflow.compareAppend({}, [
          MapEntry(first.key, first.toWire()),
          ...reservations,
        ]);
        final retained = await proposalReservationEntries(
          stored: withdrawn,
          readWorkflow: workflow.get,
        );
        expect(retained, isEmpty);
        workflow.compareAppend(
          {'proposal:${first.proposal.proposalId.value}:': first.key},
          [MapEntry(withdrawn.key, withdrawn.toWire()), ...retained],
        );
      } finally {
        original.close();
      }
      final reopened = SqliteDatabase.open(path, existing: true);
      try {
        final workflow = WorkflowStorage(reopened);
        final competing = proposals.prepare();
        expect(
          workflow.get(key)!.toText(),
          CanonicalObject([
            MapEntry(
              'proposal_id',
              CanonicalString(first.proposal.proposalId.value),
            ),
          ]).toText(),
        );
        expect(
          StoredProposal.fromWire(workflow.get(withdrawn.key)!)
              .proposal
              .withdrawn,
          isTrue,
        );
        await checkProposalReservations(
          stored: withdrawn,
          readWorkflow: workflow.get,
          identityExists: (_) => false,
          readVersion: (_) => throw StateError('Unexpected adoption'),
        );
        await expectLater(
          checkProposalReservations(
            stored: competing,
            readWorkflow: workflow.get,
            identityExists: (_) => false,
            readVersion: (_) => throw StateError('Unexpected adoption'),
          ),
          throwsA(
            isA<InvalidArgumentError>().having(
              (e) => e.field,
              'field',
              'client_ref',
            ),
          ),
        );
        // Simulates a reservation append prepared before the winning draft.
        // A conflict must roll back the preceding proposal row as well.
        expect(
          () => workflow.compareAppend({}, [
            MapEntry(competing.key, competing.toWire()),
            MapEntry(
              key,
              CanonicalObject([
                MapEntry(
                  'proposal_id',
                  CanonicalString(competing.proposal.proposalId.value),
                ),
              ]),
            ),
          ]),
          throwsFormatException,
        );
        expect(workflow.get(competing.key), isNull);
        expect(workflow.get(first.key)!.toText(), first.toWire().toText());
      } finally {
        reopened.close();
      }
    } finally {
      directory.deleteSync(recursive: true);
    }
  });

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
