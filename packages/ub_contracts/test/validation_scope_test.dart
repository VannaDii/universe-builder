import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

final max = BigInt.parse('18446744073709551615');
final digest = Sha256Hex('a' * 64);
final universe = UniverseId.parse('unv_000000000000000000000001');
final record = RecordId.parse('rec_000000000000000000000001');
final version = RecordVersionId.parse('ver_000000000000000000000001');
final proposal = ProposalRef(
  proposalId: ProposalId.parse('prp_000000000000000000000001'),
  version: BigInt.one,
  digest: digest.value,
);
final assessment = AssessmentRef(
  assessmentId: AssessmentId('asm_000000000000000000000001'),
  digest: digest,
);
final sourceVersion = AssessmentVersionRef(
  universe: universe,
  record: record,
  version: version,
);
final execution = Validation(
  runId: ValidationRunId.parse('val_000000000000000000000001'),
  coverage: Coverage.complete,
  findings: [],
  unsupportedCapabilities: [],
  inputDigest: digest.value,
  evaluatorVersion: 'v1',
);
final frame = Frame(
  universe: universe,
  continuity: ContinuityId.parse('cont_000000000000000000000001'),
  revision: RevisionId.parse('rev_000000000000000000000001'),
  context: RecordRef(record: record),
  time: const TimelessFrameTime(),
  perspective: const AuthorPerspective(),
);

void main() {
  test(
    'assessment identities and SHA digests enforce exact declared grammar',
    () {
      for (final text in ['A' * 64, 'a' * 63, '${'a' * 64}\n', 'z' * 64]) {
        expect(() => Sha256Hex(text), throwsFormatException);
      }
      expect(() => AssessmentId('asm_${'A' * 24}'), throwsFormatException);
      expect(() => AssessmentId('rec_${'0' * 24}'), throwsFormatException);
      expect(AssessmentRef.fromWire(assessment.toWire()).digest, digest);
    },
  );
  test(
    'source bindings require nullable edition and passage and exact namespace',
    () {
      final binding = SourceBinding(
        key: 'source',
        sourceVersion: sourceVersion,
        blobDigest: digest,
        byteSize: max,
        representation: SourceRepresentation.exactUtf8V1,
        ranges: [ByteRange(start: BigInt.zero, end: max)],
        workEdition: null,
        passageId: null,
      );
      final back = SourceBinding.fromWire(binding.toWire());
      expect(back.byteSize, max);
      expect(back.ranges.single.end, max);
      expect(back.toWire().toText(), contains('"work_edition":null'));
      for (final key in ['work_edition', 'passage_id']) {
        expect(
          () => SourceBinding.fromWire(
            CanonicalObject(binding.toWire().fields.where((e) => e.key != key)),
          ),
          throwsFormatException,
        );
      }
      expect(
        () => AssessmentVersionRef.fromWire(
          CanonicalObject(
            sourceVersion.toWire().fields.where((e) => e.key != 'universe'),
          ),
        ),
        throwsFormatException,
      );
      expect(() => back.ranges.clear(), throwsUnsupportedError);
    },
  );
  test(
    'submitted query record and source inputs remain distinct declarations',
    () {
      for (final input in [
        QueryInput(frame: frame, checkScope: CheckScope.dependencies),
        RecordCandidateInput(proposal: proposal, includesSources: false),
        RecordCandidateInput(proposal: proposal, includesSources: true),
        SourceAssessedCandidateInput(
          proposal: proposal,
          sources: [],
          inventoryDigest: digest,
        ),
      ]) {
        expect(
          SubmittedInput.fromWire(input.toWire()).toWire().toText(),
          input.toWire().toText(),
        );
      }
      expect(
        () => SubmittedInput.fromWire(
          CanonicalValue.parseJson('{"kind":"record_candidate"}'),
        ),
        throwsFormatException,
      );
    },
  );
  test('assessment absence unqualified unavailability staleness and bound counts stay distinct', () {
    for (final state in [
      const AbsentAssessment(),
      const AbsentAssessment(),
      const UnavailableAssessment(
        reason: UnavailableReason.failedOrCancelledCheck,
      ),
      StaleAssessment(
        assessmentReference: assessment,
        reasons: StaleReason.values,
      ),
      BoundAssessment(
        assessmentReference: assessment,
        selectionGeneration: max,
        byteVerification: ByteVerification.verified,
        declaredConclusion: DeclaredConclusion.unresolved,
        inventoryCount: max,
        mappingCount: max,
        unresolvedCount: max,
        inventoryDigest: digest,
      ),
    ]) {
      expect(
        AssessmentState.fromWire(state.toWire()).toWire().toText(),
        state.toWire().toText(),
      );
    }
    expect(
      () => AssessmentState.fromWire(
        CanonicalValue.parseJson('{"kind":"bound"}'),
      ),
      throwsFormatException,
    );
  });
  test('evaluated report requires an explicit nullable final binding', () {
    final report = EvaluatedValidation(
      execution: execution,
      submittedInput: RecordCandidateInput(
        proposal: proposal,
        includesSources: false,
      ),
      assessment: const AbsentAssessment(),
      finalBindingDigest: null,
    );
    final back = ValidationV3.fromWire(report.toWire()) as EvaluatedValidation;
    expect(back.execution.coverage, Coverage.complete);
    expect(back.assessment, isA<AbsentAssessment>());
    expect(back.finalBindingDigest, isNull);
    expect(
      () => ValidationV3.fromWire(
        CanonicalObject(
          report.toWire().fields.where((e) => e.key != 'final_binding_digest'),
        ),
      ),
      throwsFormatException,
    );
    final bound = EvaluatedValidation(
      execution: execution,
      submittedInput: report.submittedInput,
      assessment: report.assessment,
      finalBindingDigest: digest,
    );
    expect(
      (ValidationV3.fromWire(
        bound.toWire(),
      ) as EvaluatedValidation).finalBindingDigest,
      digest,
    );
  });
  test('restricted reports contain only fixed restricted reporting axes', () {
    const report = RestrictedValidation(
      executionCoverage: RestrictedCoverage.restricted,
      submittedInput: RestrictedInputValue(),
      assessment: RestrictedAssessmentValue(),
    );
    expect(
      report.toWire().toText(),
      '{"assessment":{"kind":"restricted"},"execution_coverage":"restricted","kind":"restricted","submitted_input":{"kind":"restricted"}}',
    );
    expect(ValidationV3.fromWire(report.toWire()), isA<RestrictedValidation>());
    expect(ValidationV3.restricted().execution, isNull);
    expect(
      () => ValidationV3.fromWire(
        CanonicalObject([
          ...report.toWire().fields,
          MapEntry('execution', execution.toWire()),
        ]),
      ),
      throwsFormatException,
    );
  });
  test('public operation view preserves nullable v3 report independently of completion', () {
    final s = OperationStatusV3(
      operationId: OperationId.parse('op_000000000000000000000001'),
      kind: OperationKind.validate,
      state: OperationState.running,
      cancellationRequested: false,
    );
    final back = OperationStatusV3.fromWire(s.toWire());
    expect(back.validation, isNull);
    expect(back.receipt, isNull);
    expect(back.state, OperationState.running);
    expect(back.toWire().toText(), contains('"validation":null'));
    final stored = OperationStatus(
      operationId: s.operationId,
      kind: s.kind,
      state: s.state,
      validation: execution,
      cancellationRequested: false,
    );
    final public = OperationStatusV3.fromStored(
      stored,
      ValidationV3.restricted(),
    );
    expect(public.validation!.execution, isNull);
    expect(public.state, OperationState.running);
  });
}
