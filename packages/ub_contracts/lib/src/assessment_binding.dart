import 'dart:convert';

import 'package:ub_domain/ub_domain.dart';

import 'assessment.dart';
import 'validation_scope.dart';

/// Bind declarations to exact proposal/selection inputs. This does not establish
/// factual support or authorize attachment, validation or publication.
extension SourceValidationBindingIntegrity on SourceValidationBindingV1 {
  Sha256Hex digest() {
    Sha256Hex(proposal.digest);
    _ensure(
      proposal.version > BigInt.zero && selection.proposal == proposal,
      'Selection proposal mismatch',
    );
    _ensure(
      _hasRustText(evaluatorVersion) &&
          utf8.encode(evaluatorVersion).length <= 16384,
      'Invalid evaluator version',
    );
    final submittedProposal = switch (submittedInput) {
      QueryInput() => throw const FormatException(
        'Query has no proposal binding',
      ),
      RecordCandidateInput(:final proposal) => proposal,
      SourceAssessedCandidateInput(:final proposal) => proposal,
    };
    _ensure(submittedProposal == proposal, 'Submitted proposal mismatch');
    switch (assessmentState) {
      case BoundAssessment(
        :final assessmentReference,
        :final selectionGeneration,
        :final inventoryDigest,
      ):
        _ensure(
          _sameSelection(selection.selected, assessmentReference) &&
              selectionGeneration == selection.generation,
          'Selected assessment mismatch',
        );
        final input = submittedInput;
        _ensure(
          input is SourceAssessedCandidateInput &&
              input.inventoryDigest == inventoryDigest,
          'Bound assessment scope mismatch',
        );
      case StaleAssessment(:final assessmentReference):
        _ensure(
          _sameSelection(selection.selected, assessmentReference),
          'Stale selection mismatch',
        );
        _ensure(
          submittedInput is RecordCandidateInput,
          'Stale assessment cannot promote scope',
        );
      case AbsentAssessment() || LegacyUnavailableAssessment():
        _ensure(
          selection.selected == null && submittedInput is RecordCandidateInput,
          'Absent assessment selection/scope mismatch',
        );
      case UnavailableAssessment():
        _ensure(
          submittedInput is RecordCandidateInput,
          'Unavailable assessment cannot promote scope',
        );
    }
    return Sha256Hex(payloadDigest('source-validation:v1', toWire()));
  }
}

bool _sameSelection(AssessmentRef? left, AssessmentRef right) =>
    left != null && left.toWire().toText() == right.toWire().toText();

void _ensure(bool condition, String message) {
  if (!condition) throw FormatException(message);
}

// Rust str::trim uses Unicode White_Space, including NEL but excluding FEFF.
bool _hasRustText(String value) => value.runes.any(
  (r) =>
      !((r >= 0x9 && r <= 0xd) ||
          r == 0x20 ||
          r == 0x85 ||
          r == 0xa0 ||
          r == 0x1680 ||
          (r >= 0x2000 && r <= 0x200a) ||
          r == 0x2028 ||
          r == 0x2029 ||
          r == 0x202f ||
          r == 0x205f ||
          r == 0x3000),
);
