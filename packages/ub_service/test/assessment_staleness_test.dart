import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/assessment_validation.dart';
import 'package:ub_service/proposal_state.dart';

import '../../ub_contracts/test/assessment_integrity_test.dart' as accounting;
import 'assessment_validation_test.dart' as a;
import 'operation_compilation_test.dart' as f;
import 'proposal_state_test.dart' as p;

final submitted = p.prepare(
  request: p.transition(a.proposal),
  previous: a.proposal,
);

Future<List<StaleReason>> reasons({
  StoredProposal? latest,
  SourceAssessmentV1? body,
  RevisionId? head,
  List<RecordVersion> rows = const [],
  void Function(ContinuityId, RevisionId)? onCanon,
}) => assessmentStaleReasons(
  proposal: a.proposal,
  body: body ?? a.body(),
  readLatestKey: (prefix) {
    expect(prefix, 'proposal:${a.proposal.reference.proposalId.value}:');
    return (latest ?? a.proposal).key;
  },
  readWorkflow: (key) {
    expect(key, (latest ?? a.proposal).key);
    return (latest ?? a.proposal).toWire();
  },
  readHead: (_) => head ?? a.proposal.proposal.baseFrame.revision,
  readCanon: (continuity, revision) {
    onCanon?.call(continuity, revision);
    return rows;
  },
);

void main() {
  test(
    'current unwithdrawn candidate does not read canon or retained sources',
    () async {
      expect(
        await reasons(onCanon: (_, _) => fail('Unexpected canon read')),
        isEmpty,
      );
    },
  );

  test(
    'new proposal version uses its full frozen overlay, not the old candidate',
    () async {
      final created = RecordVersion.fromWire(
        submitted.changes.single.next!.toCanonical(),
      );
      final body = a.body(
        dependencies: [
          AssessmentVersionRef(
            universe: f.u,
            record: created.identity.recordId,
            version: created.recordVersionId,
          ),
        ],
      );
      expect(await reasons(latest: submitted, body: body, rows: [a.source]), [
        StaleReason.candidateChanged,
      ]);
      final frozen = p.prepare(
        request: p.revise(a.proposal),
        previous: a.proposal,
      );
      expect(await reasons(latest: frozen, body: body, rows: [a.source]), [
        StaleReason.candidateChanged,
        StaleReason.dependencyChanged,
      ]);
    },
  );

  test(
    'advanced head uses current canon without overlaying frozen changes',
    () async {
      final head = RevisionId.parse('rev_${f.suffix(80)}');
      final changed = RecordVersion.fromWire(
        a.proposal.changes.single.next!.toCanonical(),
      );
      final body = a.body(
        dependencies: [
          AssessmentVersionRef(
            universe: f.u,
            record: changed.identity.recordId,
            version: changed.recordVersionId,
          ),
        ],
      );
      expect(
        await reasons(
          body: body,
          head: head,
          rows: [a.source],
          onCanon: (continuity, revision) {
            expect(continuity, a.proposal.proposal.baseFrame.continuity);
            expect(revision, head);
          },
        ),
        [StaleReason.candidateChanged, StaleReason.dependencyChanged],
      );
    },
  );

  test('source, edition and ordinary dependency drift have stable distinct ordering', () async {
    final body = SourceAssessmentV1.fromWire(
      accounting.replace(
        a.body(dependencies: [a.ref(10), a.ref(11)]).toWire(),
        ['sources', 0, 'work_edition'],
        a.ref(4).toWire(),
      ),
    );
    final result = await reasons(latest: submitted, body: body);
    expect(result, [
      StaleReason.candidateChanged,
      StaleReason.sourceChanged,
      StaleReason.editionChanged,
      StaleReason.dependencyChanged,
    ]);
    expect(() => result.clear(), throwsUnsupportedError);
  });

  test('only exact historical evidence exempts dependency drift', () async {
    final historical = a.mapped(kind: CandidateLinkKind.historicalEvidence);
    final ordinary = a.mapped(kind: CandidateLinkKind.unchangedRecord);
    final rows = [a.source, f.row(50, f.entity()), f.row(99, f.entity())];
    expect(await reasons(latest: submitted, body: historical, rows: rows), [
      StaleReason.candidateChanged,
    ]);
    expect(await reasons(latest: submitted, body: ordinary, rows: rows), [
      StaleReason.candidateChanged,
      StaleReason.dependencyChanged,
    ]);
  });

  test(
    'missing latest proposal is denied and store failures propagate',
    () async {
      Future<List<StaleReason>> missing({bool failure = false}) =>
          assessmentStaleReasons(
            proposal: a.proposal,
            body: a.body(),
            readLatestKey: (_) => failure ? a.proposal.key : null,
            readWorkflow: (_) => throw StateError('Store unavailable'),
            readHead: (_) => throw StateError('Unexpected head'),
            readCanon: (_, _) => throw StateError('Unexpected canon'),
          );
      await expectLater(
        missing(),
        throwsA(isA<NotFoundOrNotAccessibleError>()),
      );
      await expectLater(missing(failure: true), throwsStateError);
    },
  );
}
