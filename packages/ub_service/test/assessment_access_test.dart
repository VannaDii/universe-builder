import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/assessment_resolution.dart';

import 'assessment_validation_test.dart' as a;
import 'operation_compilation_test.dart' as f;
import 'proposal_authorization_test.dart' as auth;
import 'source_verification_test.dart' as sources;

Future<List<RecordVersion>> access({
  SourceAssessmentV1? body,
  GrantLimits? limits,
  Set<WorldId>? scope,
  List<RecordVersion> base = const [],
  RecordVersion? retained,
  void Function()? onHistory,
  void Function()? onCanon,
}) => checkAssessmentAccess(
  proposal: a.proposal,
  body: body,
  limits: limits ?? GrantLimits(),
  worldScope: scope,
  readCanon: (continuity, revision) {
    expect(continuity, a.proposal.proposal.baseFrame.continuity);
    expect(revision, a.proposal.proposal.baseFrame.revision);
    onCanon?.call();
    return base;
  },
  readVersion: (_) {
    onHistory?.call();
    return retained ?? (throw StateError('Missing history'));
  },
);
final denied = throwsA(isA<NotFoundOrNotAccessibleError>());

void main() {
  test('continuity denial precedes reads even with entity limits', () async {
    await expectLater(
      access(
        limits: GrantLimits(continuities: [], entities: [f.id(20)]),
        onCanon: () => fail('Unauthorized canon read'),
      ),
      denied,
    );
  });

  test('entity limits cover unchanged candidate records as well as proposal writes', () async {
    final base = [f.row(10, f.entity())];
    await expectLater(
      access(
        base: base,
        limits: GrantLimits(entities: [f.id(20)]),
      ),
      denied,
    );
    final records = await access(
      base: base,
      limits: GrantLimits(entities: [f.id(10), f.id(20)]),
    );
    expect(records.map((r) => r.identity.recordId), [f.id(10), f.id(20)]);
    expect(() => records.clear(), throwsUnsupportedError);
  });

  test(
    'historical dependencies join the same world and entity permission walk',
    () async {
      final body = a.body(dependencies: [a.ref(10)]);
      await expectLater(
        access(
          body: body,
          retained: f.row(10, auth.entity(worlds: [2])),
          scope: {auth.world(1)},
        ),
        denied,
      );
      await expectLater(
        access(
          body: body,
          retained: f.row(10, f.entity()),
          limits: GrantLimits(entities: [f.id(20)]),
        ),
        denied,
      );
      final records = await access(body: body, retained: f.row(10, f.entity()));
      expect(records.map((r) => r.identity.recordId), [f.id(20), f.id(10)]);
    },
  );

  test(
    'source and missing transitive dependencies close scoped visibility',
    () async {
      await expectLater(
        access(base: [a.source], scope: {auth.world(1)}),
        denied,
      );
      final dependent = f.row(
        10,
        auth.entity(
          metadata: {
            'dependency': ReferenceValue(
              ValueReferenceKind.entity,
              auth.ref(30),
            ),
          },
        ),
      );
      await expectLater(
        access(base: [dependent], scope: {auth.world(1)}),
        denied,
      );
      final rows = await access(base: [dependent]);
      expect(rows, hasLength(2));
    },
  );

  test('missing history stays absent and duplicate retained versions are read once', () async {
    final missing = await access(body: a.body(dependencies: [a.ref(10)]));
    expect(missing, hasLength(1));
    var reads = 0;
    final rows = await access(
      body: a.body(dependencies: [a.ref(10)]),
      base: [f.row(10, f.entity())],
      onHistory: () => reads++,
    );
    expect(reads, 0);
    expect(rows, hasLength(2));
  });

  test('historical source material cannot bypass scoped visibility', () async {
    await expectLater(
      access(
        body: a.body(dependencies: [a.ref(2)]),
        retained: f.row(2, sources.source()),
        scope: {auth.world(1)},
      ),
      denied,
    );
  });
}
