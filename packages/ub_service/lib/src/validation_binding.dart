import 'dart:async';

import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/ub_store.dart' show Assignment;

import 'assessment_resolution.dart';
import 'proposal_state.dart';

/// Capture after proposal admission while the owning authority lock and universe
/// read context remain held. Authority values must come from the current owner.
/// Unassessed proposals keep their ordinary write-boundary admission; only an
/// actual selection invokes complete assessment visibility and byte verification.
Future<ValidationCapture> captureValidationBinding({
  required StoredProposal proposal,
  required String authorityDigest,
  required BigInt? authoritySequence,
  required FutureOr<String?> Function(String) readLatestKey,
  required FutureOr<CanonicalValue?> Function(String) readWorkflow,
  required FutureOr<RevisionId> Function(ContinuityId) readHead,
  required FutureOr<AssessmentReview> Function(ProposalRef) resolveSelected,
}) async {
  final reference = proposal.reference;
  var selection = await readAssessmentSelection(
    reference: reference,
    readLatestKey: readLatestKey,
    readWorkflow: readWorkflow,
  );
  AssessmentState assessment = const AbsentAssessment();
  AssessmentEnvelope? envelope;
  if (selection.selected != null) {
    final resolved = await resolveSelected(reference);
    selection = resolved.selection;
    assessment = resolved.state;
    envelope = resolved.envelope;
  }
  final SubmittedInput input;
  if (assessment is BoundAssessment && envelope != null) {
    input = SourceAssessedCandidateInput(
      proposal: reference,
      sources: envelope.body.sources,
      inventoryDigest: assessment.inventoryDigest,
    );
  } else {
    input = recordCandidateInput(reference, proposal.changes);
  }
  return ValidationCapture(
    selection: selection,
    assessment: assessment,
    submittedInput: input,
    head: await readHead(proposal.proposal.baseFrame.continuity),
    latestProposalKey: await readLatestKey(
      'proposal:${reference.proposalId.value}:',
    ),
    authorityDigest: authorityDigest,
    authoritySequence: authoritySequence,
  );
}

BigInt? _sequence(BigInt? value) {
  if (value != null &&
      (value < -(BigInt.one << 63) || value >= BigInt.one << 63)) {
    throw const FormatException('Authority sequence outside i64');
  }
  return value;
}

/// Immutable inputs captured under the owning installation authority lock.
/// Constructing or decoding this value does not authenticate those inputs.
final class ValidationCapture {
  ValidationCapture({
    required this.selection,
    required this.assessment,
    required this.submittedInput,
    required this.head,
    required this.latestProposalKey,
    required this.authorityDigest,
    BigInt? authoritySequence,
  }) : authoritySequence = _sequence(authoritySequence);
  final AssessmentSelection selection;
  final AssessmentState assessment;
  final SubmittedInput submittedInput;
  final RevisionId head;
  final String? latestProposalKey;
  final String authorityDigest;
  final BigInt? authoritySequence;

  factory ValidationCapture.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'selection',
      'assessment',
      'submitted_input',
      'head',
      'latest_proposal_key',
      'authority_digest',
      'authority_sequence',
    });
    f.require('latest_proposal_key');
    BigInt? sequence;
    final raw = f.require('authority_sequence');
    if (raw is! CanonicalNull) {
      if (raw is! CanonicalNumber ||
          RegExp(r'-?(0|[1-9][0-9]*)').stringMatch(raw.digits) != raw.digits) {
        throw const FormatException('Expected authority sequence integer');
      }
      sequence = _sequence(BigInt.parse(raw.digits));
    }
    return ValidationCapture(
      selection: AssessmentSelection.fromWire(f.require('selection')),
      assessment: AssessmentState.fromWire(f.require('assessment')),
      submittedInput: SubmittedInput.fromWire(f.require('submitted_input')),
      head: RevisionId.parse(f.string('head')),
      latestProposalKey: f.optional('latest_proposal_key', wireString),
      authorityDigest: f.string('authority_digest'),
      authoritySequence: sequence,
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('selection', selection.toWire()),
    MapEntry('assessment', assessment.toWire()),
    MapEntry('submitted_input', submittedInput.toWire()),
    MapEntry('head', CanonicalString(head.value)),
    MapEntry(
      'latest_proposal_key',
      latestProposalKey == null
          ? const CanonicalNull()
          : CanonicalString(latestProposalKey!),
    ),
    MapEntry('authority_digest', CanonicalString(authorityDigest)),
    MapEntry(
      'authority_sequence',
      authoritySequence == null
          ? const CanonicalNull()
          : CanonicalNumber(authoritySequence.toString()),
    ),
  ]);

  EvaluatedValidation report({
    required ProposalRef proposal,
    required Frame baseFrame,
    required Validation execution,
    required bool finished,
  }) {
    Sha256Hex? finalDigest;
    if (finished) {
      try {
        finalDigest = SourceValidationBindingV1(
          kind: ValidationBindingKind.sourceValidationBindingV1,
          proposal: proposal,
          baseFrame: baseFrame,
          selection: selection,
          submittedInput: submittedInput,
          assessmentState: assessment,
          executionResultDigest: executionResultDigest(execution),
          evaluatorVersion: execution.evaluatorVersion,
        ).digest();
      } on FormatException catch (e) {
        throw InvalidArgumentError(
          field: 'validation_binding',
          message: e.message,
        );
      }
    }
    return EvaluatedValidation(
      execution: execution,
      submittedInput: submittedInput,
      assessment: assessment,
      finalBindingDigest: finalDigest,
    );
  }

  /// Exact immutable selections to compare inside the same evidence append.
  Map<String, String?> comparisons() {
    final r = selection.proposal;
    final prefix =
        'assessment-selection:${r.proposalId.value}:${r.version.toString().padLeft(20, '0')}:';
    return {
      prefix: selection.generation > BigInt.zero
          ? '$prefix${selection.generation.toString().padLeft(20, '0')}'
          : null,
      'proposal:${r.proposalId.value}:': latestProposalKey,
    };
  }
}

RecordCandidateInput recordCandidateInput(
  ProposalRef proposal,
  List<Assignment> changes,
) => RecordCandidateInput(
  proposal: proposal,
  includesSources: changes.any((c) {
    final kind = c.next?.identity.recordKind;
    return kind == RecordKind.source ||
        kind == RecordKind.sourceVersion ||
        kind == RecordKind.anchor ||
        kind == RecordKind.workVersion;
  }),
);

String validationAuthorityDigest({
  required ProfileId principal,
  required bool author,
  required ProfileId approvalAuthor,
  required String scopeHash,
}) => canonicalDigest(
  CanonicalArray([
    CanonicalString(principal.value),
    CanonicalBool(author),
    CanonicalString(approvalAuthor.value),
    CanonicalString(scopeHash),
  ]),
);

/// The current capture must be resolved again under trusted workflow authority.
void verifyValidationCapture({
  required ProposalRef proposal,
  required ValidationCapture captured,
  required ValidationCapture current,
}) {
  if (captured.selection.proposal != proposal ||
      captured.authorityDigest != current.authorityDigest ||
      captured.head != current.head ||
      captured.latestProposalKey != current.latestProposalKey ||
      canonicalDigest(captured.selection.toWire()) !=
          canonicalDigest(current.selection.toWire()) ||
      canonicalDigest(captured.assessment.toWire()) !=
          canonicalDigest(current.assessment.toWire())) {
    throw const ApprovalStaleError();
  }
}

void verifyValidationAuthority(ValidationCapture capture, BigInt? current) {
  if (capture.authoritySequence != current) throw const ApprovalStaleError();
}

/// Publication privately re-resolves assessment state before comparing the exact
/// completed report. This does not disclose it or expand a committer's grants.
void verifyPublicationReport({
  required ValidationV3? report,
  required ValidationCapture current,
  required ProposalRef proposal,
  required Frame baseFrame,
  required Validation execution,
}) {
  if (report is! EvaluatedValidation ||
      report.finalBindingDigest == null ||
      canonicalDigest(report.toWire()) !=
          canonicalDigest(
            current
                .report(
                  proposal: proposal,
                  baseFrame: baseFrame,
                  execution: execution,
                  finished: true,
                )
                .toWire(),
          )) {
    throw const ApprovalStaleError();
  }
}

/// Retained validation evidence in the existing closed Checked storage family.
/// Admission and report integrity are rechecked before approval/publication.
final class CheckedValidation {
  const CheckedValidation({
    required this.proposalDigest,
    required this.validation,
    required this.admissible,
    this.report,
    this.capture,
  });
  final String proposalDigest;
  final Validation validation;
  final bool admissible;
  final ValidationV3? report;
  final ValidationCapture? capture;
  factory CheckedValidation.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'proposal_digest',
      'validation',
      'admissible',
      'report',
      'capture',
    });
    return CheckedValidation(
      proposalDigest: f.string('proposal_digest'),
      validation: Validation.fromWire(f.require('validation')),
      admissible: f.boolean('admissible'),
      report: f.optional('report', ValidationV3.fromWire),
      capture: f.optional('capture', ValidationCapture.fromWire),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('proposal_digest', CanonicalString(proposalDigest)),
    MapEntry('validation', validation.toWire()),
    MapEntry('admissible', CanonicalBool(admissible)),
    MapEntry('report', report?.toWire() ?? const CanonicalNull()),
    if (capture != null) MapEntry('capture', capture!.toWire()),
  ]);
}
