import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

final sha = Sha256Hex('a' * 64);
final otherSha = Sha256Hex('b' * 64);
final max = BigInt.parse('18446744073709551615');
final proposal = ProposalRef(
  proposalId: ProposalId.parse('prp_000000000000000000000001'),
  version: BigInt.one,
  digest: sha.value,
);
final exact = AssessmentVersionRef(
  universe: UniverseId.parse('unv_000000000000000000000001'),
  record: RecordId.parse('rec_000000000000000000000001'),
  version: RecordVersionId.parse('ver_000000000000000000000001'),
);
final frame = Frame(
  universe: exact.universe,
  continuity: ContinuityId.parse('cont_000000000000000000000001'),
  revision: RevisionId.parse('rev_000000000000000000000001'),
  context: RecordRef(record: exact.record),
  time: const TimelessFrameTime(),
  perspective: const AuthorPerspective(),
);
final assessment = AssessmentRef(
  assessmentId: AssessmentId('asm_000000000000000000000001'),
  digest: sha,
);
final absentSelection = AssessmentSelection(
  proposal: proposal,
  generation: BigInt.zero,
  selected: null,
);
final selected = AssessmentSelection(
  proposal: proposal,
  generation: max,
  selected: assessment,
);
final recordInput = RecordCandidateInput(
  proposal: proposal,
  includesSources: true,
);
final sourceInput = SourceAssessedCandidateInput(
  proposal: proposal,
  sources: [],
  inventoryDigest: sha,
);
BoundAssessment bound({BigInt? generation, Sha256Hex? inventory}) =>
    BoundAssessment(
      assessmentReference: assessment,
      selectionGeneration: generation ?? max,
      byteVerification: ByteVerification.verified,
      declaredConclusion: DeclaredConclusion.unresolved,
      inventoryCount: max,
      mappingCount: max,
      unresolvedCount: max,
      inventoryDigest: inventory ?? sha,
    );
SourceValidationBindingV1 binding({
  AssessmentState state = const AbsentAssessment(),
  AssessmentSelection? selection,
  SubmittedInput? input,
  ProposalRef? ref,
  String evaluator = 'v1',
  Sha256Hex? execution,
}) => SourceValidationBindingV1(
  kind: ValidationBindingKind.sourceValidationBindingV1,
  proposal: ref ?? proposal,
  baseFrame: frame,
  selection: selection ?? absentSelection,
  submittedInput: input ?? recordInput,
  assessmentState: state,
  executionResultDigest: execution ?? sha,
  evaluatorVersion: evaluator,
);

void main() {
  test('proposal reference equality compares every exact field', () {
    final same = ProposalRef.fromWire(proposal.toWire());
    expect(same, proposal);
    expect(same.hashCode, proposal.hashCode);
    expect(
      ProposalRef(
        proposalId: proposal.proposalId,
        version: BigInt.two,
        digest: sha.value,
      ),
      isNot(proposal),
    );
    expect(
      ProposalRef(
        proposalId: proposal.proposalId,
        version: BigInt.one,
        digest: otherSha.value,
      ),
      isNot(proposal),
    );
  });
  test('selection distinguishes explicit absence and retained generation on VM and web', () {
    final back = AssessmentSelection.fromWire(selected.toWire());
    expect(back.generation, max);
    expect(back.selected!.digest, sha);
    expect(
      () => AssessmentSelection.fromWire(
        CanonicalObject(
          absentSelection.toWire().fields.where((e) => e.key != 'selected'),
        ),
      ),
      throwsFormatException,
    );
    expect(
      AssessmentSelection.fromWire(absentSelection.toWire()).selected,
      isNull,
    );
  });
  test('position variants preserve unknowns and exact authored work order', () {
    for (final p in [
      const NotApplicablePosition(),
      const UnknownPosition(reason: 'uncertain order'),
      WorkPosition(workEdition: exact, sceneId: 'scene', ordinal: max),
    ]) {
      expect(
        Position.fromWire(p.toWire()).toWire().toText(),
        p.toWire().toText(),
      );
    }
    expect(
      () => Position.fromWire(CanonicalValue.parseJson('{"kind":"unknown"}')),
      throwsFormatException,
    );
  });
  test('semantic variants preserve typed values and copied evidence lists', () {
    final participants = [RoleParticipant(role: 'holder', participant: exact)];
    final variants = <SemanticMapping>[
      ClaimSemanticMapping(
        predicate: exact,
        subject: exact,
        value: const DecimalValue('1.00'),
        roles: participants,
        polarity: Polarity.refutation,
      ),
      ActionSemanticMapping(
        action: exact,
        participants: participants,
        prerequisites: [exact],
        effects: [exact],
      ),
      KnowledgeSemanticMapping(
        holder: exact,
        content: exact,
        acquisition: [exact],
      ),
      SourceDescriptionSemanticMapping(
        subject: exact,
        depiction: Depiction.subjective,
        impliedClaims: [exact],
      ),
    ];
    participants.clear();
    for (final m in variants) {
      expect(
        SemanticMapping.fromWire(m.toWire()).toWire().toText(),
        m.toWire().toText(),
      );
    }
    expect((variants.first as ClaimSemanticMapping).roles, hasLength(1));
    expect(
      () => (variants.first as ClaimSemanticMapping).roles.clear(),
      throwsUnsupportedError,
    );
    expect(variants.first.toWire().toText(), contains('"digits":"1.00"'));
  });
  test('assessor and review nullable members must be explicitly supplied', () {
    final assessor = Assessor(
      principal: PrincipalId.parse('prn_000000000000000000000001'),
      method: Method.humanReview,
      tool: null,
      assessedAt: '2026-10-02T20:00:00Z',
    );
    expect(
      () => Assessor.fromWire(
        CanonicalObject(assessor.toWire().fields.where((e) => e.key != 'tool')),
      ),
      throwsFormatException,
    );
    final page = AssessmentReviewPage(
      selection: absentSelection,
      state: const AbsentAssessment(),
      envelope: null,
      fragment: null,
    );
    expect(AssessmentReviewPage.fromWire(page.toWire()).envelope, isNull);
    expect(
      () => AssessmentReviewPage.fromWire(
        CanonicalObject(page.toWire().fields.where((e) => e.key != 'fragment')),
      ),
      throwsFormatException,
    );
  });
  test(
    'fragment is exact envelope bytes rather than a partial assessment body',
    () {
      final fragment = AssessmentFragment(
        assessmentReference: assessment,
        offset: max,
        totalBytes: max,
        canonicalEnvelopeUtf8: 'é🌲 chunk',
      );
      final back = AssessmentFragment.fromWire(fragment.toWire());
      expect(back.offset, max);
      expect(back.canonicalEnvelopeUtf8, 'é🌲 chunk');
      expect(back.toWire().toText(), isNot(contains('claim_mappings')));
    },
  );
  test('final bindings preserve distinct absent stale unavailable and bound states', () {
    for (final b in [
      binding(),
      binding(
        state: const UnavailableAssessment(
          reason: UnavailableReason.missingRetainedMaterial,
        ),
        selection: selected,
      ),
      binding(
        state: StaleAssessment(
          assessmentReference: assessment,
          reasons: [StaleReason.sourceChanged],
        ),
        selection: selected,
      ),
      binding(state: bound(), selection: selected, input: sourceInput),
    ]) {
      expect(
        SourceValidationBindingV1.fromWire(b.toWire()).digest(),
        b.digest(),
      );
    }
    expect(binding(execution: otherSha).digest(), isNot(binding().digest()));
  });
  test('binding rejects stale generations inventory mismatches and promoted source scope', () {
    for (final b in [
      binding(
        state: bound(generation: BigInt.one),
        selection: selected,
        input: sourceInput,
      ),
      binding(
        state: bound(inventory: otherSha),
        selection: selected,
        input: sourceInput,
      ),
      binding(state: bound(), selection: selected),
      binding(
        state: StaleAssessment(assessmentReference: assessment, reasons: []),
        selection: selected,
        input: sourceInput,
      ),
      binding(
        state: StaleAssessment(assessmentReference: assessment, reasons: []),
      ),
      binding(selection: selected),
      binding(
        state: const UnavailableAssessment(
          reason: UnavailableReason.failedOrCancelledCheck,
        ),
        input: sourceInput,
      ),
    ]) {
      expect(b.digest, throwsFormatException);
    }
  });
  test('binding rejects nonpositive mismatched proposal and query inputs', () {
    final wrong = ProposalRef(
      proposalId: proposal.proposalId,
      version: BigInt.two,
      digest: sha.value,
    );
    expect(binding(ref: wrong).digest, throwsFormatException);
    expect(
      binding(
        input: RecordCandidateInput(proposal: wrong, includesSources: true),
      ).digest,
      throwsFormatException,
    );
    expect(
      binding(
        ref: ProposalRef(
          proposalId: proposal.proposalId,
          version: BigInt.zero,
          digest: sha.value,
        ),
      ).digest,
      throwsFormatException,
    );
    expect(
      binding(
        input: QueryInput(frame: frame, checkScope: CheckScope.universe),
      ).digest,
      throwsFormatException,
    );
    expect(
      binding(
        ref: ProposalRef(
          proposalId: proposal.proposalId,
          version: BigInt.one,
          digest: 'invalid',
        ),
      ).digest,
      throwsFormatException,
    );
  });
  test('binding evaluator text uses UTF-8 byte limits and Rust whitespace semantics', () {
    expect(binding(evaluator: ' \u0085\u3000').digest, throwsFormatException);
    expect(binding(evaluator: '\ufeff').digest().value, hasLength(64));
    expect(binding(evaluator: 'é' * 8193).digest, throwsFormatException);
    expect(binding(evaluator: 'é' * 8192).digest().value, hasLength(64));
  });
}
