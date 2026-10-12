import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/validation_binding.dart';

import 'assessment_resolution_test.dart' as assessments;
import 'assessment_validation_test.dart' as a;
import 'operation_compilation_test.dart' as f;
import 'validation_binding_test.dart' as binding;

Future<ValidationCapture> capture({
  Map<String, CanonicalValue>? stored,
  RevisionId? head,
  BigInt? sequence,
  String authority = 'trusted authority',
  void Function()? onResolve,
}) {
  final entries = stored ?? assessments.entries();
  return captureValidationBinding(
    proposal: a.proposal,
    authorityDigest: authority,
    authoritySequence: sequence,
    readLatestKey: (prefix) {
      final keys = entries.keys.where((k) => k.startsWith(prefix)).toList()
        ..sort();
      return keys.isEmpty ? null : keys.last;
    },
    readWorkflow: (key) => entries[key],
    readHead: (_) => head ?? a.proposal.proposal.baseFrame.revision,
    resolveSelected: (reference) {
      expect(reference, a.proposal.reference);
      onResolve?.call();
      return assessments.resolve(stored: entries, head: head);
    },
  );
}

void main() {
  test('an explicit cleared selection retains its generation without resolving evidence', () async {
    final entries = assessments.entries()
      ..removeWhere((key, _) => key.startsWith('assessment-selection:'));
    final prefix =
        'assessment-selection:${a.proposal.reference.proposalId.value}:${a.proposal.reference.version.toString().padLeft(20, '0')}:';
    final key = '${prefix}00000000000000000004';
    entries[key] = AssessmentSelection(
      proposal: a.proposal.reference,
      generation: BigInt.from(4),
      selected: null,
    ).toWire();
    final result = await capture(
      stored: entries,
      onResolve: () => fail('Cleared selection resolved evidence'),
    );
    expect(result.assessment, isA<AbsentAssessment>());
    expect(result.selection.generation, BigInt.from(4));
    expect(result.comparisons()[prefix], key);
  });
  test('unassessed proposals retain record input without assessment visibility reads', () async {
    final entries = assessments.entries()
      ..removeWhere((key, _) => key.startsWith('assessment-selection:'));
    final result = await capture(
      stored: entries,
      onResolve: () => fail('Unassessed proposal entered assessment admission'),
    );
    expect(result.assessment, isA<AbsentAssessment>());
    expect(result.selection.generation, BigInt.zero);
    expect(
      (result.submittedInput as RecordCandidateInput).includesSources,
      isFalse,
    );
    expect(result.head, a.proposal.proposal.baseFrame.revision);
    expect(result.latestProposalKey, a.proposal.key);
    expect(result.authoritySequence, isNull);
  });

  test('byte-verified selected evidence binds exact submitted sources and inventory', () async {
    final result = await capture(sequence: BigInt.from(7));
    final input = result.submittedInput as SourceAssessedCandidateInput;
    expect(input.proposal, a.proposal.reference);
    expect(input.inventoryDigest, assessments.selected.body.inventoryDigest());
    expect(
      input.sources.single.toWire().toText(),
      assessments.selected.body.sources.single.toWire().toText(),
    );
    expect(
      (result.assessment as BoundAssessment).declaredConclusion,
      DeclaredConclusion.unresolved,
    );
    expect(result.authoritySequence, BigInt.from(7));
    expect(result.authorityDigest, 'trusted authority');
    expect(
      ValidationCapture.fromWire(result.toWire()).toWire().toText(),
      result.toWire().toText(),
    );
    expect(result.comparisons().values, contains(a.proposal.key));
    final report = result.report(
      proposal: a.proposal.reference,
      baseFrame: a.proposal.proposal.baseFrame,
      execution: binding.execution(),
      finished: true,
    );
    expect(report.finalBindingDigest, isNotNull);
    verifyPublicationReport(
      report: report,
      current: result,
      proposal: a.proposal.reference,
      baseFrame: a.proposal.proposal.baseFrame,
      execution: binding.execution(),
    );
  });

  test('stale or unavailable selections retain state but cannot claim source-assessed input', () async {
    final stale = await capture(head: RevisionId.parse('rev_${f.suffix(80)}'));
    expect(stale.assessment, isA<StaleAssessment>());
    expect(stale.submittedInput, isA<RecordCandidateInput>());
    final entries = assessments.entries()
      ..remove(
        'source:${assessments.selected.body.sources.single.blobDigest.value}',
      );
    final unavailable = await capture(stored: entries);
    expect(unavailable.assessment, isA<UnavailableAssessment>());
    expect(unavailable.submittedInput, isA<RecordCandidateInput>());
    expect(unavailable.selection.generation, BigInt.from(3));
  });

  test(
    'changed authority sequence and selection invalidate earlier captures',
    () async {
      final original = await capture(sequence: BigInt.one);
      expect(
        () => verifyValidationAuthority(original, BigInt.two),
        throwsA(isA<ApprovalStaleError>()),
      );
      final entries = assessments.entries()
        ..removeWhere((key, _) => key.startsWith('assessment-selection:'));
      final current = await capture(stored: entries, sequence: BigInt.one);
      expect(
        () => verifyValidationCapture(
          proposal: a.proposal.reference,
          captured: original,
          current: current,
        ),
        throwsA(isA<ApprovalStaleError>()),
      );
      final changed = await capture(
        sequence: BigInt.one,
        authority: 'revoked grant',
      );
      expect(
        () => verifyValidationCapture(
          proposal: a.proposal.reference,
          captured: original,
          current: changed,
        ),
        throwsA(isA<ApprovalStaleError>()),
      );
    },
  );
}
