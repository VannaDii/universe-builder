import 'package:ub_domain/ub_domain.dart';

import 'wire.dart';
import 'workflow.dart';
import 'opposing_intersection.dart';

enum EvidenceOutcome {
  supported('supported'),
  refuted('refuted'),
  conflicting('conflicting'),
  notEstablished('not_established');

  const EvidenceOutcome(this.wireName);
  final String wireName;
  static EvidenceOutcome fromName(String name) => values.firstWhere(
    (v) => v.wireName == name,
    orElse: () => throw const FormatException('Unknown EvidenceOutcome'),
  );
}

enum OpposingKind {
  definite('definite'),
  unresolved('unresolved');

  const OpposingKind(this.wireName);
  final String wireName;
  static OpposingKind fromName(String name) => values.firstWhere(
    (v) => v.wireName == name,
    orElse: () => throw const FormatException('Unknown OpposingKind'),
  );
}

enum OpposingReason {
  equality('equality'),
  context('context'),
  realm('realm'),
  worlds('worlds'),
  time('time'),
  precision('precision'),
  persistence('persistence'),
  provenance('provenance'),
  budget('budget');

  const OpposingReason(this.wireName);
  final String wireName;
  static OpposingReason fromName(String name) => values.firstWhere(
    (v) => v.wireName == name,
    orElse: () => throw const FormatException('Unknown OpposingReason'),
  );
}

final class Finding {
  Finding({
    this.message,
    Iterable<RecordRef> records = const [],
    required this.fingerprint,
    required this.ruleId,
    required this.outcome,
    required Iterable<RecordVersionId> evidence,
    required this.coverage,
  }) : records = List.unmodifiable(records),
       evidence = List.unmodifiable(evidence);
  final String? message;
  final List<RecordRef> records;
  final FindingFingerprint fingerprint;
  final RecordId ruleId;
  final EvidenceOutcome outcome;
  final List<RecordVersionId> evidence;
  final Coverage coverage;
  factory Finding.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'message',
      'records',
      'fingerprint',
      'rule_id',
      'outcome',
      'evidence',
      'coverage',
    });
    return Finding(
      message: f.optional('message', (v) => wireString(v)),
      records: f
          .array('records', defaultEmpty: true)
          .map((v) => RecordRef.fromCanonical(v)),
      fingerprint: FindingFingerprint(wireString(f.require('fingerprint'))),
      ruleId: RecordId.parse(wireString(f.require('rule_id'))),
      outcome: EvidenceOutcome.fromName(wireString(f.require('outcome'))),
      evidence: f
          .array('evidence')
          .map((v) => RecordVersionId.parse(wireString(v))),
      coverage: Coverage.fromName(wireString(f.require('coverage'))),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    if (message != null)
      MapEntry(
        'message',
        message == null ? const CanonicalNull() : CanonicalString(message!),
      ),
    if (records.isNotEmpty)
      MapEntry('records', CanonicalArray(records.map((v) => v.toCanonical()))),
    MapEntry('fingerprint', CanonicalString(fingerprint.value)),
    MapEntry('rule_id', CanonicalString(ruleId.value)),
    MapEntry('outcome', CanonicalString(outcome.wireName)),
    MapEntry(
      'evidence',
      CanonicalArray(evidence.map((v) => CanonicalString(v.value))),
    ),
    MapEntry('coverage', CanonicalString(coverage.wireName)),
  ]);
}

final class OpposingChain {
  OpposingChain({
    required this.assertionId,
    required this.propositionId,
    required this.assertion,
    required this.proposition,
    required Iterable<VersionRef> dependencies,
    required this.complete,
  }) : dependencies = List.unmodifiable(dependencies);
  final RecordId assertionId;
  final RecordId propositionId;
  final RecordVersionId assertion;
  final RecordVersionId proposition;
  final List<VersionRef> dependencies;
  final bool complete;
  factory OpposingChain.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'assertion_id',
      'proposition_id',
      'assertion',
      'proposition',
      'dependencies',
      'complete',
    });
    return OpposingChain(
      assertionId: RecordId.parse(wireString(f.require('assertion_id'))),
      propositionId: RecordId.parse(wireString(f.require('proposition_id'))),
      assertion: RecordVersionId.parse(wireString(f.require('assertion'))),
      proposition: RecordVersionId.parse(wireString(f.require('proposition'))),
      dependencies: f
          .array('dependencies')
          .map((v) => VersionRef.fromCanonical(v)),
      complete: f.boolean('complete'),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('assertion_id', CanonicalString(assertionId.value)),
    MapEntry('proposition_id', CanonicalString(propositionId.value)),
    MapEntry('assertion', CanonicalString(assertion.value)),
    MapEntry('proposition', CanonicalString(proposition.value)),
    MapEntry(
      'dependencies',
      CanonicalArray(dependencies.map((v) => v.toCanonical())),
    ),
    MapEntry('complete', CanonicalBool(complete)),
  ]);
}

final class OpposingEvidence {
  OpposingEvidence({
    required this.diagnosticVersion,
    required this.fingerprint,
    required this.kind,
    required this.proposition,
    required this.support,
    required this.refutation,
    required this.context,
    this.applicability,
    this.realm,
    required this.intersection,
    required this.coverage,
    required Iterable<OpposingReason> unresolvedReasons,
    required Iterable<RecordVersionId> policyVersions,
    required Iterable<RecordVersionId> exceptionVersions,
  }) : unresolvedReasons = List.unmodifiable(unresolvedReasons),
       policyVersions = List.unmodifiable(policyVersions),
       exceptionVersions = List.unmodifiable(exceptionVersions);
  final String diagnosticVersion;
  final FindingFingerprint fingerprint;
  final OpposingKind kind;
  final PropositionRecord proposition;
  final OpposingChain support;
  final OpposingChain refutation;
  final RecordRef context;
  final Applicability? applicability;
  final RecordRef? realm;
  final OpposingIntersection intersection;
  final Coverage coverage;
  final List<OpposingReason> unresolvedReasons;
  final List<RecordVersionId> policyVersions;
  final List<RecordVersionId> exceptionVersions;
  factory OpposingEvidence.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'diagnostic_version',
      'fingerprint',
      'kind',
      'proposition',
      'support',
      'refutation',
      'context',
      'applicability',
      'realm',
      'intersection',
      'coverage',
      'unresolved_reasons',
      'policy_versions',
      'exception_versions',
    });
    return OpposingEvidence(
      diagnosticVersion: wireString(f.require('diagnostic_version')),
      fingerprint: FindingFingerprint(wireString(f.require('fingerprint'))),
      kind: OpposingKind.fromName(wireString(f.require('kind'))),
      proposition: _propositionInput(f.require('proposition')),
      support: OpposingChain.fromWire(f.require('support')),
      refutation: OpposingChain.fromWire(f.require('refutation')),
      context: RecordRef.fromCanonical(f.require('context')),
      applicability: f.optional(
        'applicability',
        (v) => Applicability.fromWire(v),
      ),
      realm: f.optional('realm', (v) => RecordRef.fromCanonical(v)),
      intersection: OpposingIntersection.fromWire(f.require('intersection')),
      coverage: Coverage.fromName(wireString(f.require('coverage'))),
      unresolvedReasons: f
          .array('unresolved_reasons')
          .map((v) => OpposingReason.fromName(wireString(v))),
      policyVersions: f
          .array('policy_versions')
          .map((v) => RecordVersionId.parse(wireString(v))),
      exceptionVersions: f
          .array('exception_versions')
          .map((v) => RecordVersionId.parse(wireString(v))),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('diagnostic_version', CanonicalString(diagnosticVersion)),
    MapEntry('fingerprint', CanonicalString(fingerprint.value)),
    MapEntry('kind', CanonicalString(kind.wireName)),
    MapEntry('proposition', _propositionOutput(proposition)),
    MapEntry('support', support.toWire()),
    MapEntry('refutation', refutation.toWire()),
    MapEntry('context', context.toCanonical()),
    MapEntry(
      'applicability',
      applicability == null ? const CanonicalNull() : applicability!.toWire(),
    ),
    MapEntry(
      'realm',
      realm == null ? const CanonicalNull() : realm!.toCanonical(),
    ),
    MapEntry('intersection', intersection.toWire()),
    MapEntry('coverage', CanonicalString(coverage.wireName)),
    MapEntry(
      'unresolved_reasons',
      CanonicalArray(unresolvedReasons.map((v) => CanonicalString(v.wireName))),
    ),
    MapEntry(
      'policy_versions',
      CanonicalArray(policyVersions.map((v) => CanonicalString(v.value))),
    ),
    MapEntry(
      'exception_versions',
      CanonicalArray(exceptionVersions.map((v) => CanonicalString(v.value))),
    ),
  ]);
}

final class Validation {
  Validation({
    this.operationId,
    required this.runId,
    required this.coverage,
    required Iterable<Finding> findings,
    Iterable<OpposingEvidence> opposingEvidence = const [],
    required Iterable<String> unsupportedCapabilities,
    required this.inputDigest,
    required this.evaluatorVersion,
  }) : findings = List.unmodifiable(findings),
       opposingEvidence = List.unmodifiable(opposingEvidence),
       unsupportedCapabilities = List.unmodifiable(unsupportedCapabilities);
  final OperationId? operationId;
  final ValidationRunId runId;
  final Coverage coverage;
  final List<Finding> findings;
  final List<OpposingEvidence> opposingEvidence;
  final List<String> unsupportedCapabilities;
  final String inputDigest;
  final String evaluatorVersion;
  factory Validation.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'operation_id',
      'run_id',
      'coverage',
      'findings',
      'opposing_evidence',
      'unsupported_capabilities',
      'input_digest',
      'evaluator_version',
    });
    return Validation(
      operationId: f.optional(
        'operation_id',
        (v) => OperationId.parse(wireString(v)),
      ),
      runId: ValidationRunId.parse(wireString(f.require('run_id'))),
      coverage: Coverage.fromName(wireString(f.require('coverage'))),
      findings: f.array('findings').map((v) => Finding.fromWire(v)),
      opposingEvidence: f
          .array('opposing_evidence', defaultEmpty: true)
          .map((v) => OpposingEvidence.fromWire(v)),
      unsupportedCapabilities: f
          .array('unsupported_capabilities')
          .map((v) => wireString(v)),
      inputDigest: wireString(f.require('input_digest')),
      evaluatorVersion: wireString(f.require('evaluator_version')),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    if (operationId != null)
      MapEntry(
        'operation_id',
        operationId == null
            ? const CanonicalNull()
            : CanonicalString(operationId!.value),
      ),
    MapEntry('run_id', CanonicalString(runId.value)),
    MapEntry('coverage', CanonicalString(coverage.wireName)),
    MapEntry('findings', CanonicalArray(findings.map((v) => v.toWire()))),
    if (opposingEvidence.isNotEmpty)
      MapEntry(
        'opposing_evidence',
        CanonicalArray(opposingEvidence.map((v) => v.toWire())),
      ),
    MapEntry(
      'unsupported_capabilities',
      CanonicalArray(unsupportedCapabilities.map((v) => CanonicalString(v))),
    ),
    MapEntry('input_digest', CanonicalString(inputDigest)),
    MapEntry('evaluator_version', CanonicalString(evaluatorVersion)),
  ]);
}

final class OperationStatus {
  const OperationStatus({
    this.validation,
    this.failure,
    required this.operationId,
    required this.kind,
    required this.state,
    this.proposal,
    this.receipt,
    required this.cancellationRequested,
  });
  final Validation? validation;
  final String? failure;
  final OperationId operationId;
  final OperationKind kind;
  final OperationState state;
  final Proposal? proposal;
  final CommitReceipt? receipt;
  final bool cancellationRequested;
  factory OperationStatus.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'validation',
      'failure',
      'operation_id',
      'kind',
      'state',
      'proposal',
      'receipt',
      'cancellation_requested',
    });
    return OperationStatus(
      validation: f.optional('validation', (v) => Validation.fromWire(v)),
      failure: f.optional('failure', (v) => wireString(v)),
      operationId: OperationId.parse(wireString(f.require('operation_id'))),
      kind: OperationKind.fromName(wireString(f.require('kind'))),
      state: OperationState.fromName(wireString(f.require('state'))),
      proposal: f.optional('proposal', (v) => Proposal.fromWire(v)),
      receipt: f.optional('receipt', (v) => CommitReceipt.fromWire(v)),
      cancellationRequested: f.boolean('cancellation_requested'),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    if (validation != null)
      MapEntry(
        'validation',
        validation == null ? const CanonicalNull() : validation!.toWire(),
      ),
    if (failure != null)
      MapEntry(
        'failure',
        failure == null ? const CanonicalNull() : CanonicalString(failure!),
      ),
    MapEntry('operation_id', CanonicalString(operationId.value)),
    MapEntry('kind', CanonicalString(kind.wireName)),
    MapEntry('state', CanonicalString(state.wireName)),
    MapEntry(
      'proposal',
      proposal == null ? const CanonicalNull() : proposal!.toWire(),
    ),
    MapEntry(
      'receipt',
      receipt == null ? const CanonicalNull() : receipt!.toWire(),
    ),
    MapEntry('cancellation_requested', CanonicalBool(cancellationRequested)),
  ]);
}

PropositionRecord _propositionInput(CanonicalValue value) {
  if (value is! CanonicalObject ||
      value.fields.any((e) => e.key == 'record_kind')) {
    throw const FormatException('Expected bare proposition DTO');
  }
  return PropositionRecord.fromWire(
    CanonicalObject([
      MapEntry('record_kind', CanonicalString('proposition')),
      ...value.fields,
    ]),
  );
}

CanonicalObject _propositionOutput(PropositionRecord value) =>
    CanonicalObject(value.toWire().fields.where((e) => e.key != 'record_kind'));
