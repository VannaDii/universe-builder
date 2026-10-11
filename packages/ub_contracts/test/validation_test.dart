import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

final record = RecordId.parse('rec_000000000000000000000001');
final version = RecordVersionId.parse('ver_000000000000000000000001');
final ref = RecordRef(record: record);
final operationId = OperationId.parse('op_000000000000000000000001');
final run = ValidationRunId.parse('val_000000000000000000000001');

Validation execution({
  Coverage coverage = Coverage.partial,
  Iterable<Finding> findings = const [],
  Iterable<OpposingEvidence> opposing = const [],
}) => Validation(
  runId: run,
  coverage: coverage,
  findings: findings,
  opposingEvidence: opposing,
  unsupportedCapabilities: ['unresolved time'],
  inputDigest: 'exact candidate digest',
  evaluatorVersion: 'existing evaluator',
);
OpposingChain chain() => OpposingChain(
  assertionId: record,
  propositionId: record,
  assertion: version,
  proposition: version,
  dependencies: [VersionRef(record: record, version: version)],
  complete: false,
);

void main() {
  test(
    'finding coverage and outcome remain independent with opaque fingerprint',
    () {
      for (final outcome in EvidenceOutcome.values) {
        final f = Finding(
          fingerprint: const FindingFingerprint('opaque-fingerprint'),
          ruleId: record,
          outcome: outcome,
          evidence: [version],
          coverage: Coverage.restricted,
        );
        final back = Finding.fromWire(f.toWire());
        expect(back.outcome, outcome);
        expect(back.coverage, Coverage.restricted);
        expect(back.fingerprint.value, 'opaque-fingerprint');
        expect(back.toWire().toText(), isNot(contains('message')));
        expect(() => back.evidence.clear(), throwsUnsupportedError);
      }
    },
  );
  test('intersection keeps uncertainty and required branch fields without inventing validity', () {
    for (final intersection in [
      const UnqualifiedIntersection(),
      const UnresolvedIntersection(),
      const ExactIntersection(UnknownValidity()),
      const UncertainIntersection(
        left: UnknownValidity(),
        right: UnspecifiedValidity(),
      ),
      const UncertainIntersection(
        left: UnknownValidity(),
        right: UnspecifiedValidity(),
        guaranteed: UnspecifiedValidity(),
      ),
    ]) {
      expect(
        OpposingIntersection.fromWire(intersection.toWire()).toWire().toText(),
        intersection.toWire().toText(),
      );
    }
    expect(
      () => OpposingIntersection.fromWire(
        CanonicalValue.parseJson('{"kind":"exact"}'),
      ),
      throwsFormatException,
    );
    expect(
      () => OpposingIntersection.fromWire(
        CanonicalValue.parseJson(
          '{"kind":"unresolved","validity":{"kind":"unspecified"}}',
        ),
      ),
      throwsFormatException,
    );
  });
  test(
    'opposing diagnostics preserve both evidence chains and unresolved reasons',
    () {
      final proposition = PropositionRecord(
        predicate: ref,
        subject: ref,
        context: ref,
        value: const TextValue('claim'),
        quantification: Quantification.particular,
      );
      final e = OpposingEvidence(
        diagnosticVersion: 'v1',
        fingerprint: const FindingFingerprint('opposition'),
        kind: OpposingKind.unresolved,
        proposition: proposition,
        support: chain(),
        refutation: chain(),
        context: ref,
        intersection: const UnresolvedIntersection(),
        coverage: Coverage.partial,
        unresolvedReasons: OpposingReason.values,
        policyVersions: [version],
        exceptionVersions: [],
      );
      final back = OpposingEvidence.fromWire(e.toWire());
      expect(back.support.complete, isFalse);
      expect(back.support.dependencies.single.version, version);
      expect(back.refutation.assertion, version);
      expect(back.unresolvedReasons, OpposingReason.values);
      expect(back.applicability, isNull);
      expect(back.proposition.digest, proposition.digest);
      final fields = e.toWire().fields;
      expect(
        () => OpposingEvidence.fromWire(
          CanonicalObject([
            ...fields.where((f) => f.key != 'proposition'),
            MapEntry('proposition', proposition.toWire()),
          ]),
        ),
        throwsFormatException,
      );
    },
  );
  test('complete execution does not imply source assessment or approval', () {
    final report = Validation.fromWire(
      execution(coverage: Coverage.complete).toWire(),
    );
    expect(report.coverage, Coverage.complete);
    expect(report.inputDigest, 'exact candidate digest');
    expect(report.unsupportedCapabilities, ['unresolved time']);
    expect(report.toWire().toText(), isNot(contains('operation_id')));
    expect(report.toWire().toText(), isNot(contains('opposing_evidence')));
    expect(
      () => Validation.fromWire(
        CanonicalObject([
          ...report.toWire().fields,
          const MapEntry('approved', CanonicalBool(true)),
        ]),
      ),
      throwsFormatException,
    );
    expect(
      () => Validation.fromWire(
        CanonicalObject([
          ...report.toWire().fields,
          const MapEntry('opposing_evidence', CanonicalNull()),
        ]),
      ),
      throwsFormatException,
    );
  });
  test(
    'stored operation format keeps optional fields and uncertain outcome',
    () {
      final s = OperationStatus(
        operationId: operationId,
        kind: OperationKind.commit,
        state: OperationState.interrupted,
        cancellationRequested: true,
      );
      final back = OperationStatus.fromWire(s.toWire());
      expect(back.state, OperationState.interrupted);
      expect(back.receipt, isNull);
      expect(back.cancellationRequested, isTrue);
      expect(back.toWire().toText(), isNot(contains('validation')));
      expect(back.toWire().toText(), contains('"receipt":null'));
    },
  );
}
