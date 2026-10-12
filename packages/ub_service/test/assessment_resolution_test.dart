import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/assessment_resolution.dart';

import 'assessment_validation_test.dart' as a;
import 'operation_compilation_test.dart' as f;
import 'source_verification_test.dart' as sources;
import 'structural_checks_test.dart' as structure;

AssessmentEnvelope envelope(int id, SourceAssessmentV1 body) =>
    AssessmentEnvelope(
      assessmentId: AssessmentId('asm_${f.suffix(id)}'),
      digest: body.digest(),
      body: body,
    );
AssessmentRef ref(AssessmentEnvelope e) =>
    AssessmentRef(assessmentId: e.assessmentId, digest: e.digest);
final selected = envelope(1, a.mapped(kind: CandidateLinkKind.unchangedRecord));
final historical = envelope(2, a.body());
final selection = AssessmentSelection(
  proposal: a.proposal.reference,
  generation: BigInt.from(3),
  selected: ref(selected),
);
Map<String, CanonicalValue> entries() => {
  a.proposal.key: a.proposal.toWire(),
  '${assessmentSelectionPrefix(a.proposal.reference)}00000000000000000003':
      selection.toWire(),
  assessmentEnvelopeKey(ref(selected)): selected.toWire(),
  assessmentEnvelopeKey(ref(historical)): historical.toWire(),
  ...sources.staging(sources.source()),
};
Future<AssessmentReview> resolve({
  Map<String, CanonicalValue>? stored,
  AssessmentRef? exact,
  bool mayObserveMissing = true,
  RevisionId? head,
  void Function(SourceAssessmentV1?)? access,
  CanonicalValue? Function(String)? read,
}) {
  final values = stored ?? entries();
  final records = [
    a.source,
    f.row(10, f.entity()),
    f.row(50, f.entity()),
    structure.context(99),
  ];
  return resolveAssessment(
    reference: a.proposal.reference,
    exact: exact,
    universe: f.u,
    canObserveMissingMaterial: mayObserveMissing,
    readProposal: (_) => a.proposal,
    checkAccess: (proposal, body) async {
      access?.call(body);
      await checkAssessmentAccess(
        proposal: proposal,
        body: body,
        limits: GrantLimits(),
        worldScope: null,
        readCanon: (_, _) => records,
        readVersion: (_) => throw StateError('Missing history'),
      );
    },
    readLatestKey: (prefix) {
      final keys = values.keys.where((k) => k.startsWith(prefix)).toList()
        ..sort();
      return keys.isEmpty ? null : keys.last;
    },
    readWorkflow: read ?? (key) => values[key],
    readHead: (_) => head ?? a.proposal.proposal.baseFrame.revision,
    readCanon: (_, _) => records,
    readVersion: (_) => throw StateError('Unexpected historical lookup'),
  );
}

void main() {
  test('bound state describes selected evidence even when viewing another exact envelope', () async {
    final accesses = <SourceAssessmentV1?>[];
    final result = await resolve(exact: ref(historical), access: accesses.add);
    expect(result.envelope!.assessmentId, historical.assessmentId);
    final state = result.state as BoundAssessment;
    expect(
      state.assessmentReference.toWire().toText(),
      ref(selected).toWire().toText(),
    );
    expect(state.selectionGeneration, BigInt.from(3));
    expect(state.byteVerification, ByteVerification.verified);
    expect(state.declaredConclusion, DeclaredConclusion.unresolved);
    expect(state.unresolvedCount, BigInt.one);
    expect(state.mappingCount, BigInt.one);
    expect(state.inventoryCount, BigInt.one);
    expect(state.inventoryDigest, selected.body.inventoryDigest());
    expect(accesses, hasLength(3));
    expect(accesses.first, isNull);
    expect(accesses[1]!.digest(), historical.digest);
    expect(accesses[2]!.digest(), selected.digest);
  });

  test(
    'no selection is absent even when an exact historical body is requested',
    () async {
      final values = entries()
        ..removeWhere((key, _) => key.startsWith('assessment-selection:'));
      final result = await resolve(stored: values, exact: ref(historical));
      expect(result.state, isA<AbsentAssessment>());
      expect(result.selection.generation, BigInt.zero);
      expect(result.envelope!.assessmentId, historical.assessmentId);
    },
  );

  test('lost selected body is hidden from partial viewers but retains historical access for author', () async {
    final values = entries()..remove(assessmentEnvelopeKey(ref(selected)));
    await expectLater(
      resolve(stored: values, mayObserveMissing: false, exact: ref(historical)),
      throwsA(isA<NotFoundOrNotAccessibleError>()),
    );
    final accesses = <SourceAssessmentV1?>[];
    final result = await resolve(
      stored: values,
      exact: ref(historical),
      access: accesses.add,
    );
    expect(
      (result.state as UnavailableAssessment).reason,
      UnavailableReason.missingRetainedMaterial,
    );
    expect(result.envelope!.assessmentId, historical.assessmentId);
    expect(accesses, hasLength(2));
    final lost = await resolve(stored: values, exact: ref(selected));
    expect(lost.envelope, isNull);
  });

  test('stale selected state precedes missing source bytes', () async {
    final values = entries()
      ..remove('source:${selected.body.sources.single.blobDigest.value}');
    final result = await resolve(
      stored: values,
      head: RevisionId.parse('rev_${f.suffix(80)}'),
    );
    expect((result.state as StaleAssessment).reasons, [
      StaleReason.candidateChanged,
    ]);
    final current = await resolve(stored: values);
    expect(current.state, isA<UnavailableAssessment>());
    expect(current.envelope, isNotNull);
  });

  test('candidate and selected dependency access denials propagate before byte checking', () async {
    for (final denyBody in [false, true]) {
      await expectLater(
        resolve(
          access: (body) {
            if ((body != null) == denyBody) {
              throw const NotFoundOrNotAccessibleError(message: 'resource');
            }
          },
        ),
        throwsA(isA<NotFoundOrNotAccessibleError>()),
      );
    }
  });

  test(
    'exact digest mismatch is denied; corruption is an assessment error',
    () async {
      final values = entries();
      values[assessmentEnvelopeKey(ref(selected))] = AssessmentEnvelope(
        assessmentId: selected.assessmentId,
        digest: historical.digest,
        body: historical.body,
      ).toWire();
      await expectLater(
        resolve(stored: values),
        throwsA(isA<NotFoundOrNotAccessibleError>()),
      );
      values[assessmentEnvelopeKey(ref(selected))] = AssessmentEnvelope(
        assessmentId: selected.assessmentId,
        digest: selected.digest,
        body: historical.body,
      ).toWire();
      await expectLater(
        resolve(stored: values),
        f.fails('', field: 'assessment'),
      );
    },
  );

  test(
    'source read failures are not misreported as missing retained material',
    () async {
      final values = entries();
      await expectLater(
        resolve(
          read: (key) {
            if (key.startsWith('source:')) {
              throw StateError('Store unavailable');
            }
            return values[key];
          },
        ),
        throwsStateError,
      );
    },
  );
}
