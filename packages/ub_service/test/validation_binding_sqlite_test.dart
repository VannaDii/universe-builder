@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_service/validation_binding.dart';
import 'package:ub_store/src/database.dart';
import 'package:ub_store/src/workflow_storage.dart';

import 'rule_checks_test.dart' as frames;
import 'validation_binding_test.dart' as bindings;

void main() {
  test('retained Checked binding survives reopen and rejects a competing selection atomically', () {
    final directory = Directory.systemTemp.createTempSync(
      'universe-builder-validation-',
    );
    final path = '${directory.path}/package.sqlite';
    try {
      final capture = bindings.capture(
        latest: null,
        sequence: BigInt.parse('9007199254740993'),
      );
      final execution = bindings.execution();
      final checked = CheckedValidation(
        proposalDigest: bindings.proposal.digest,
        validation: execution,
        admissible: true,
        capture: capture,
        report: capture.report(
          proposal: bindings.proposal,
          baseFrame: frames.frame(),
          execution: execution,
          finished: true,
        ),
      );
      final key = 'validation:${execution.runId.value}';
      final original = SqliteDatabase.open(path);
      try {
        WorkflowStorage(original).compareAppend(capture.comparisons(), [
          MapEntry(key, checked.toWire()),
        ]);
      } finally {
        original.close();
      }
      final reopened = SqliteDatabase.open(path, existing: true);
      try {
        final workflow = WorkflowStorage(reopened);
        final retained = CheckedValidation.fromWire(workflow.get(key)!);
        expect(retained.toWire().toText(), checked.toWire().toText());
        expect(
          retained.capture!.authoritySequence,
          BigInt.parse('9007199254740993'),
        );
        bindings.publication(retained.capture!, retained.report);
        final prefix = capture.comparisons().keys.first;
        final selected = AssessmentSelection(
          proposal: bindings.proposal,
          generation: BigInt.one,
          selected: null,
        );
        workflow.compareAppend({}, [
          MapEntry('${prefix}00000000000000000001', selected.toWire()),
        ]);
        const staleKey = 'validation:stale-result';
        expect(
          () => workflow.compareAppend(capture.comparisons(), [
            MapEntry(staleKey, checked.toWire()),
          ]),
          throwsFormatException,
        );
        expect(workflow.get(staleKey), isNull);
        expect(workflow.get(key)!.toText(), checked.toWire().toText());
      } finally {
        reopened.close();
      }
    } finally {
      directory.deleteSync(recursive: true);
    }
  });
}
