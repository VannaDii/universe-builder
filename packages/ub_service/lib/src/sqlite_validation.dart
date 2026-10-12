import 'dart:convert';

import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/sqlite.dart';

import 'assessment_resolution.dart';
import 'assessment_validation.dart';
import 'installation_authority.dart';
import 'operation_state.dart';
import 'proposal_authorization.dart';
import 'proposal_state.dart';
import 'validation_binding.dart';

/// Internal native workflow for an already recovered, writer-owned package.
/// It retains assessments and checked results, never approvals or canonical
/// facts. The caller must produce the checked result through the factual
/// evaluator, not client IO.
final class SqliteValidationWorkflow {
  SqliteValidationWorkflow({
    required this.package,
    required this.authority,
    required this.principal,
  });
  final OwnedSqliteDatabase package;
  final InstallationAuthority authority;
  final InstallationPrincipal principal;
  UniverseId get universe => package.universeId;
  SqliteJournal get _journal => SqliteJournal(package.database, universe);
  WorkflowStorage get _workflow => WorkflowStorage(package.database);

  RecordVersion _version(RecordVersionId id) =>
      RecordVersion.fromWire(_journal.load(id).toCanonical());
  List<RecordVersion> _canon(ContinuityId continuity, RevisionId revision) {
    final rows =
        [
          for (final version in _journal.snapshot(continuity, revision).values)
            _version(version),
        ]..sort(
          (a, b) =>
              a.identity.recordId.value.compareTo(b.identity.recordId.value),
        );
    return rows;
  }

  StoredProposal _proposal(
    ProposalRef reference,
    CurrentUniverseAuthority current,
  ) {
    final value = _workflow.get(proposalKey(reference));
    if (value == null) {
      throw const NotFoundOrNotAccessibleError(message: 'resource');
    }
    final proposal = StoredProposal.fromWire(value);
    if (proposal.proposal.baseFrame.universe != universe) {
      throw const NotFoundOrNotAccessibleError(message: 'resource');
    }
    authorizeStoredProposal(
      stored: proposal,
      reference: reference,
      principal: current.principal.id,
      author: current.principal.author,
      scope: current.worldScope,
    );
    authority.authorizeWrite(
      principal,
      universe: universe,
      worlds: proposal.footprint.worlds,
      shared: proposal.footprint.shared,
      protected: proposal.footprint.protected,
      commit: false,
    );
    try {
      if (current.limits.continuities != null &&
          !current.limits.continuities!.contains(
            proposal.proposal.baseFrame.continuity,
          )) {
        throw const NotFoundOrNotAccessibleError(message: 'resource');
      }
      checkWriteBoundaries(
        base:
            current.limits.entities != null || current.limits.predicates != null
            ? _canon(
                proposal.proposal.baseFrame.continuity,
                proposal.proposal.baseFrame.revision,
              )
            : const [],
        changes: proposal.changes,
        continuity: proposal.proposal.baseFrame.continuity,
        limits: current.limits,
      );
    } on Object {
      throw const NotFoundOrNotAccessibleError(message: 'resource');
    }
    return proposal;
  }

  Future<ValidationCapture> _capture(
    StoredProposal proposal,
    CurrentUniverseAuthority current,
  ) => captureValidationBinding(
    proposal: proposal,
    authorityDigest: current.validationDigest,
    authoritySequence: current.sequence,
    readLatestKey: _workflow.latestKey,
    readWorkflow: _workflow.get,
    readHead: _journal.head,
    resolveSelected: (reference) => resolveAssessment(
      reference: reference,
      universe: universe,
      canObserveMissingMaterial:
          current.principal.author && current.worldScope == null,
      readProposal: (reference) => _proposal(reference, current),
      checkAccess: (proposal, body) async {
        await checkAssessmentAccess(
          proposal: proposal,
          body: body,
          limits: current.limits,
          worldScope: current.worldScope,
          readCanon: _canon,
          readVersion: _version,
        );
      },
      readLatestKey: _workflow.latestKey,
      readWorkflow: _workflow.get,
      readHead: _journal.head,
      readCanon: _canon,
      readVersion: _version,
    ),
  );

  Future<ValidationCapture> capture(ProposalRef reference) =>
      authority.withUniverseAuthority(
        principal,
        universe,
        (current) => _capture(_proposal(reference, current), current),
      );

  Future<StoredOperation> operation(
    OperationId id, {
    required bool Function(OperationId) isValidationActive,
  }) => authority.withUniverseAuthority(
    principal,
    universe,
    (current) => loadStoredOperation(
      key: 'operation:${id.value}',
      principal: current.principal.id,
      worldScope: current.worldScope,
      readWorkflow: _workflow.get,
      readReceipt: _journal.receipt,
      isValidationActive: isValidationActive,
    ),
  );

  Future<AssessmentSelection> attachAssessment(
    ProposalRef reference, {
    required BigInt expectedGeneration,
    required SourceAssessmentV1 body,
    required String idempotencyKey,
  }) => _changeAssessment(
    reference,
    expectedGeneration,
    body,
    null,
    idempotencyKey,
  );

  Future<AssessmentSelection> selectAssessment(
    ProposalRef reference, {
    required BigInt expectedGeneration,
    required AssessmentRef? selected,
    required String idempotencyKey,
  }) => _changeAssessment(
    reference,
    expectedGeneration,
    null,
    selected,
    idempotencyKey,
  );

  Future<AssessmentSelection> _changeAssessment(
    ProposalRef reference,
    BigInt expected,
    SourceAssessmentV1? body,
    AssessmentRef? selected,
    String key,
  ) => authority.withUniverseAuthority(principal, universe, (current) async {
    const denied = NotFoundOrNotAccessibleError(message: 'resource');
    InvalidArgumentError invalid(String message) =>
        InvalidArgumentError(field: 'assessment', message: message);
    final entries = <MapEntry<String, CanonicalValue>>[];
    late AssessmentSelection result;
    await _workflow.compareAppendWithVerification(
      entries: entries,
      verify: () async {
        StoredProposal proposal;
        try {
          proposal = _proposal(reference, current);
        } on Object {
          throw denied;
        }
        Future<void> access(SourceAssessmentV1? body) async {
          await checkAssessmentAccess(
            proposal: proposal,
            body: body,
            limits: current.limits,
            worldScope: current.worldScope,
            readCanon: _canon,
            readVersion: _version,
          );
        }

        Future<void> verify(SourceAssessmentV1 body) =>
            verifyAssessmentCandidate(
              proposal: proposal,
              universe: universe,
              body: body,
              readCanon: _canon,
              readVersion: _version,
              readWorkflow: _workflow.get,
            );
        await access(body);
        final encoded = utf8.encode(key);
        if (encoded.isEmpty ||
            encoded.length > 16384 ||
            utf8.decode(encoded) != key) {
          throw invalid('invalid idempotency key');
        }
        if (expected < BigInt.zero || expected >= BigInt.one << 64) {
          throw invalid('invalid selection generation');
        }
        if (body != null) {
          if (body.assessor.principal.value !=
              principal.id.value.replaceFirst('prf_', 'prn_')) {
            throw denied;
          }
          await verify(body);
        }
        final digest = canonicalDigest(
          CanonicalArray([
            reference.toWire(),
            CanonicalNumber(expected.toString()),
            body?.toWire() ?? const CanonicalNull(),
            selected?.toWire() ?? const CanonicalNull(),
          ]),
        );
        final receiptKey =
            'assessment-receipt:${principal.id.value}:${canonicalDigest(CanonicalString(key))}';
        final receipt = _workflow.get(receiptKey);
        if (receipt != null) {
          final fields = WireFields(receipt, {
            'request_digest',
            'selection',
            'envelope',
          });
          final envelope = fields.optional(
            'envelope',
            AssessmentEnvelope.fromWire,
          );
          if (envelope != null) await access(envelope.body);
          if (fields.string('request_digest') != digest) {
            throw const IdempotencyKeyReusedError(message: 'request differs');
          }
          result = AssessmentSelection.fromWire(fields.require('selection'));
          return const {};
        }
        final frame = proposal.proposal.baseFrame;
        if (_workflow.latestKey('proposal:${reference.proposalId.value}:') !=
                proposal.key ||
            proposal.proposal.withdrawn ||
            proposal.proposal.submission != Submission.submitted ||
            _journal.head(frame.continuity) != frame.revision) {
          throw const ApprovalStaleError();
        }
        final previous = await readAssessmentSelection(
          reference: reference,
          readLatestKey: _workflow.latestKey,
          readWorkflow: _workflow.get,
        );
        if (previous.generation != expected) throw const ApprovalStaleError();
        AssessmentEnvelope? envelope;
        if (body != null) {
          envelope = AssessmentEnvelope(
            assessmentId: AssessmentId(
              RecordId.generate().value.replaceFirst('rec_', 'asm_'),
            ),
            digest: body.digest(),
            body: body,
          );
        } else if (selected != null) {
          final value = _workflow.get(assessmentEnvelopeKey(selected));
          if (value == null) throw denied;
          envelope = AssessmentEnvelope.fromWire(value);
          try {
            envelope.verify();
          } on FormatException catch (e) {
            throw invalid(e.message);
          }
          if (envelope.digest != selected.digest) throw denied;
          await access(envelope.body);
          await verify(envelope.body);
        }
        final next = envelope == null
            ? null
            : AssessmentRef(
                assessmentId: envelope.assessmentId,
                digest: envelope.digest,
              );
        CanonicalValue pin(AssessmentRef? ref) =>
            ref?.toWire() ?? const CanonicalNull();
        if (canonicalDigest(pin(next)) ==
            canonicalDigest(pin(previous.selected))) {
          throw invalid('selection is unchanged');
        }
        if (expected == (BigInt.one << 64) - BigInt.one) {
          throw invalid('selection generation exhausted');
        }
        result = AssessmentSelection(
          proposal: reference,
          generation: expected + BigInt.one,
          selected: next,
        );
        final prefix = assessmentSelectionPrefix(reference);
        entries.addAll([
          MapEntry(
            '$prefix${result.generation.toString().padLeft(20, '0')}',
            result.toWire(),
          ),
          MapEntry(
            receiptKey,
            CanonicalObject([
              MapEntry('request_digest', CanonicalString(digest)),
              MapEntry('selection', result.toWire()),
              MapEntry('envelope', envelope?.toWire() ?? const CanonicalNull()),
            ]),
          ),
          if (envelope != null)
            MapEntry(assessmentEnvelopeKey(next!), envelope.toWire()),
        ]);
        return {
          prefix: expected > BigInt.zero
              ? '$prefix${expected.toString().padLeft(20, '0')}'
              : null,
          'proposal:${reference.proposalId.value}:': proposal.key,
        };
      },
    );
    return result;
  });

  Future<void> persist(ProposalRef reference, CheckedValidation checked) =>
      authority.withUniverseAuthority(
        principal,
        universe,
        (current) => _workflow.compareAppendWithVerification(
          verify: () async {
            final proposal = _proposal(reference, current);
            if (checked.proposalDigest != proposal.proposal.digest) {
              throw const ApprovalStaleError();
            }
            final captured = checked.capture;
            if (captured == null) return const {};
            verifyValidationAuthority(captured, current.sequence);
            final fresh = await _capture(proposal, current);
            verifyValidationCapture(
              proposal: reference,
              captured: captured,
              current: fresh,
            );
            return captured.comparisons();
          },
          entries: [
            MapEntry(
              'validation:${checked.validation.runId.value}',
              checked.toWire(),
            ),
          ],
        ),
      );
}
