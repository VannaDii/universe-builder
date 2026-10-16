import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/validation_binding.dart';
import 'package:ub_store/ub_store.dart' show Assignment;

import 'event_compilation_test.dart' as events;
import 'operation_compilation_test.dart' as f;
import 'rule_checks_test.dart' as frames;
import 'source_verification_test.dart' as sources;

final proposal = ProposalRef(
  proposalId: ProposalId.parse('prp_${f.suffix(1)}'),
  version: BigInt.one,
  digest: 'a' * 64,
);
final principal = ProfileId.parse('prf_${f.suffix(1)}');
Validation execution({int run = 1, String? evaluator}) => Validation(
  runId: ValidationRunId.parse('val_${f.suffix(run)}'),
  coverage: Coverage.complete,
  findings: [],
  unsupportedCapabilities: [],
  inputDigest: proposal.digest,
  evaluatorVersion:
      evaluator ?? 'finite-policy-v15-writer-constraint-diagnostics',
);
ValidationCapture capture({
  ProposalRef? reference,
  AssessmentState assessment = const AbsentAssessment(),
  int generation = 0,
  String? authority,
  int head = 1,
  String? latest = 'proposal:exact-latest-key',
  BigInt? sequence,
  SubmittedInput? input,
}) {
  final r = reference ?? proposal;
  return ValidationCapture(
    selection: AssessmentSelection(
      proposal: r,
      generation: BigInt.from(generation),
      selected: null,
    ),
    assessment: assessment,
    submittedInput:
        input ?? RecordCandidateInput(proposal: r, includesSources: false),
    head: RevisionId.parse('rev_${f.suffix(head)}'),
    latestProposalKey: latest,
    authorityDigest: authority ?? 'authority-digest',
    authoritySequence: sequence,
  );
}

void publication(
  ValidationCapture current,
  ValidationV3? report, {
  Validation? result,
}) => verifyPublicationReport(
  report: report,
  current: current,
  proposal: proposal,
  baseFrame: frames.frame(),
  execution: result ?? execution(),
);
void main() {
  test('only a finished exact report is eligible for publication binding', () {
    final c = capture(), result = execution();
    final finished = c.report(
      proposal: proposal,
      baseFrame: frames.frame(),
      execution: result,
      finished: true,
    );
    expect(finished.finalBindingDigest!.value, hasLength(64));
    publication(c, finished);
    publication(c, ValidationV3.fromWire(finished.toWire()));
    final unfinished = c.report(
      proposal: proposal,
      baseFrame: frames.frame(),
      execution: result,
      finished: false,
    );
    expect(unfinished.finalBindingDigest, isNull);
    for (final report in [null, unfinished, ValidationV3.restricted()]) {
      expect(() => publication(c, report), throwsA(isA<ApprovalStaleError>()));
    }
    expect(
      () => publication(c, finished, result: execution(run: 2)),
      throwsA(isA<ApprovalStaleError>()),
    );
    expect(
      () => publication(
        c,
        finished,
        result: execution(evaluator: 'new-evaluator'),
      ),
      throwsA(isA<ApprovalStaleError>()),
    );
  });
  test('head proposal selection assessment and authority changes make capture stale', () {
    final c = capture();
    final nextProposal = ProposalRef(
      proposalId: proposal.proposalId,
      version: BigInt.two,
      digest: 'b' * 64,
    );
    for (final current in [
      capture(head: 2),
      capture(latest: null),
      capture(reference: nextProposal),
      capture(generation: 1),
      capture(authority: 'changed-rights'),
    ]) {
      expect(
        () => verifyValidationCapture(
          proposal: proposal,
          captured: c,
          current: current,
        ),
        throwsA(isA<ApprovalStaleError>()),
      );
    }
    verifyValidationCapture(
      proposal: proposal,
      captured: c,
      current: ValidationCapture.fromWire(c.toWire()),
    );
    expect(
      () => verifyValidationCapture(
        proposal: nextProposal,
        captured: c,
        current: c,
      ),
      throwsA(isA<ApprovalStaleError>()),
    );
  });
  test(
    'assessment availability and input scope cannot reuse an earlier report',
    () {
      final c = capture();
      final report = c.report(
        proposal: proposal,
        baseFrame: frames.frame(),
        execution: execution(),
        finished: true,
      );
      for (final current in [
        capture(
          input: RecordCandidateInput(
            proposal: proposal,
            includesSources: true,
          ),
        ),
      ]) {
        expect(
          () => publication(current, report),
          throwsA(isA<ApprovalStaleError>()),
        );
      }
    },
  );
  test('comparison keys bind exact proposal and selection generations', () {
    final prefix =
        'assessment-selection:${proposal.proposalId.value}:00000000000000000001:';
    expect(capture().comparisons(), {
      prefix: null,
      'proposal:${proposal.proposalId.value}:': 'proposal:exact-latest-key',
    });
    expect(
      capture(generation: 7).comparisons()[prefix],
      '${prefix}00000000000000000007',
    );
  });
  test(
    'authority sequence remains an exact optional signed i64 on every target',
    () {
      for (final sequence in [
        null,
        -(BigInt.one << 63),
        BigInt.parse('9007199254740993'),
        (BigInt.one << 63) - BigInt.one,
      ]) {
        final c = capture(sequence: sequence),
            roundtrip = ValidationCapture.fromWire(
              capture(sequence: sequence).toWire(),
            );
        expect(roundtrip.authoritySequence, sequence);
        verifyValidationAuthority(roundtrip, sequence);
        expect(
          () => verifyValidationAuthority(
            c,
            sequence == null ? BigInt.zero : null,
          ),
          throwsA(isA<ApprovalStaleError>()),
        );
      }
      for (final sequence in [
        -(BigInt.one << 63) - BigInt.one,
        BigInt.one << 63,
      ]) {
        expect(() => capture(sequence: sequence), throwsFormatException);
      }
      final wire = capture().toWire();
      expect(
        () => ValidationCapture.fromWire(
          CanonicalObject(
            wire.fields.where((e) => e.key != 'authority_sequence'),
          ),
        ),
        throwsFormatException,
      );
      final malformed = CanonicalObject(
        wire.fields.map(
          (e) => MapEntry(
            e.key,
            e.key == 'authority_sequence'
                ? const CanonicalNumber('1.0')
                : e.value,
          ),
        ),
      );
      expect(
        () => ValidationCapture.fromWire(malformed),
        throwsFormatException,
      );
    },
  );
  test('authority digest binds principal author status approval owner and grant scope', () {
    String digest({
      ProfileId? actor,
      bool author = true,
      ProfileId? owner,
      String scope = 'grant-scope',
    }) => validationAuthorityDigest(
      principal: actor ?? principal,
      author: author,
      approvalAuthor: owner ?? principal,
      scopeHash: scope,
    );
    final other = ProfileId.parse('prf_${f.suffix(2)}');
    expect({
      digest(),
      digest(actor: other),
      digest(author: false),
      digest(owner: other),
      digest(scope: 'changed-grant'),
    }, hasLength(5));
    expect(digest(), digest());
  });
  test(
    'record scope includes sources and editions only for proposed versions',
    () {
      final payloads = <RecordPayload>[
        SourceRecord(
          label: 'Research',
          origin: const OriginMetadata(),
          versions: [],
        ),
        sources.source(),
        sources.anchor(),
        WorkVersionRecord(
          work: f.ref(10),
          versionLabel: '1',
          binding: const UnboundWork(),
        ),
      ];
      for (final p in payloads) {
        expect(
          recordCandidateInput(proposal, [
            events.change(f.row(2, p)),
          ]).includesSources,
          isTrue,
        );
      }
      expect(
        recordCandidateInput(proposal, [
          events.change(f.row(1, f.entity())),
        ]).includesSources,
        isFalse,
      );
      expect(
        recordCandidateInput(proposal, [
          Assignment(recordId: f.id(2), expected: f.ver(2)),
        ]).includesSources,
        isFalse,
      );
    },
  );
  test('unfinished checks cannot supply a publication binding', () {
    final checked = CheckedValidation(
      proposalDigest: proposal.digest,
      validation: execution(),
      admissible: true,
    );
    final wire = checked.toWire();
    expect(wire.fields.any((e) => e.key == 'capture'), isFalse);
    final read = CheckedValidation.fromWire(wire);
    expect(read.capture, isNull);
    expect(read.report, isNull);
    expect(read.admissible, isTrue);
    expect(
      () => publication(capture(), read.report),
      throwsA(isA<ApprovalStaleError>()),
    );
  });
  test('mismatched binding inputs reject a finished report with the existing protocol error', () {
    final next = ProposalRef(
      proposalId: proposal.proposalId,
      version: BigInt.two,
      digest: 'b' * 64,
    );
    expect(
      () => capture(reference: next).report(
        proposal: proposal,
        baseFrame: frames.frame(),
        execution: execution(),
        finished: true,
      ),
      throwsA(
        isA<InvalidArgumentError>().having(
          (e) => e.field,
          'field',
          'validation_binding',
        ),
      ),
    );
  });
}
