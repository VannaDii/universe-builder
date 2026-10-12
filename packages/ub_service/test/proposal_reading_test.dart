import 'dart:convert';

import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/ub_service.dart';

import 'operation_compilation_test.dart' as f;
import 'proposal_state_test.dart' as proposals;
import 'assessment_resolution_test.dart' as assessments;
import '../../ub_contracts/test/assessment_integrity_test.dart' as accounting;

void main() {
  test('frozen proposal pages preserve exact metadata and compile all changes without altering retained state', () {
    final stored = proposals.prepare(
      request: proposals.create(
        operations: [
          for (var n = 20; n < 45; n++)
            CreateEntityOperation(clientRef: f.id(n).value, record: f.entity()),
        ],
      ),
    );
    final before = stored.toWire().toText();
    final first = pageFrozenProposal(stored, 0),
        last = pageFrozenProposal(stored, 20);
    expect(first.proposal.operations.length, 20);
    expect(first.proposal.compiledChanges.length, 20);
    expect(first.complete, isFalse);
    expect(last.proposal.operations.length, 5);
    expect(last.complete, isTrue);
    expect(first.proposal.digest, stored.proposal.digest);
    expect(last.proposal.proposalId, stored.proposal.proposalId);
    expect(stored.toWire().toText(), before);
    expect(
      () => pageFrozenProposal(stored, 26),
      throwsA(isA<NotFoundOrNotAccessibleError>()),
    );
  });
  test('assessment fragments reassemble canonical UTF-8 without splitting characters', () {
    CanonicalValue wire = assessments.selected.body.toWire();
    final text = List.filled(2300, '漢🙂').join();
    wire = accounting.replace(
      wire,
      ['assessor', 'tool'],
      ToolIdentity(
        name: text,
        version: 'fixture',
        modelRevision: 'fixture',
        procedureDigest: Sha256Hex('a' * 64),
      ).toWire(),
    );
    wire = accounting.replace(wire, [
      'assessor',
      'method',
    ], CanonicalString(Method.externalModelReview.wireName));
    wire = accounting.replace(wire, [
      'inventory_declaration',
      'rationale',
    ], CanonicalString(text));
    final envelope = assessments.envelope(
      20,
      SourceAssessmentV1.fromWire(wire),
    );
    final review = AssessmentReview(
      selection: assessments.selection,
      state: const AbsentAssessment(),
      envelope: envelope,
    );
    final chunks = <String>[];
    var offset = 0;
    while (true) {
      final page = pageAssessmentReview(review, offset);
      final fragment = page.page.fragment!;
      expect(fragment.offset, BigInt.from(offset));
      expect(
        utf8.encode(fragment.canonicalEnvelopeUtf8).length,
        lessThanOrEqualTo(32768),
      );
      chunks.add(fragment.canonicalEnvelopeUtf8);
      if (page.complete) break;
      offset = page.next;
    }
    expect(chunks.join(), envelope.toWire().toText());
    expect(
      () => pageAssessmentReview(review, envelope.toWire().toBytes().length),
      throwsA(isA<NotFoundOrNotAccessibleError>()),
    );
    final bytes = envelope.toWire().toBytes();
    final continuation = bytes.indexWhere((byte) => byte & 0xc0 == 0x80);
    expect(
      () => pageAssessmentReview(review, continuation),
      throwsA(isA<NotFoundOrNotAccessibleError>()),
    );
  });
  test('assessment pages preserve absence and pin selection changes independently of envelope content', () {
    final review = AssessmentReview(
      selection: assessments.selection,
      state: const AbsentAssessment(),
      envelope: null,
    );
    expect(pageAssessmentReview(review, 0).page.fragment, isNull);
    expect(pageAssessmentReview(review, 0).complete, isTrue);
    expect(
      () => pageAssessmentReview(review, 1),
      throwsA(isA<NotFoundOrNotAccessibleError>()),
    );
    final changed = AssessmentReview(
      selection: AssessmentSelection(
        proposal: review.selection.proposal,
        generation: review.selection.generation + BigInt.one,
        selected: null,
      ),
      state: const AbsentAssessment(),
      envelope: null,
    );
    expect(
      assessmentPageBinding(
        CanonicalObject([]),
        review.selection.proposal,
        review,
      ).toText(),
      isNot(
        assessmentPageBinding(
          CanonicalObject([]),
          review.selection.proposal,
          changed,
        ).toText(),
      ),
    );
  });
}
