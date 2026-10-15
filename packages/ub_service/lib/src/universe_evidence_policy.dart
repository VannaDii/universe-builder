import 'package:ub_domain/ub_domain.dart';

/// The author's creation choice publishes real requirements, not a local label.
/// No imported source qualifies until the author selects its category membership.
List<RecordVersion> initialEvidencePolicyRecords(
  UniverseId universe,
  bool realWorld,
) {
  if (!realWorld) return const [];
  RecordVersion record(RecordPayload payload) => RecordVersion.build(
    recordVersionId: RecordVersionId.generate(),
    identity: RecordIdentity(
      universeId: universe,
      recordId: RecordId.generate(),
      recordKind: payload.recordKind,
    ),
    payload: payload,
  );
  final category = record(
    DomainPackRecord(
      key: 'real_world.sources',
      version: '1',
      dependencies: {},
      capabilities: [],
      records: [],
    ),
  );
  final policy = record(
    RuleRecord(
      namespace: 'real_world',
      key: 'default',
      labels: {'en': 'Real World evidence'},
      kind: RuleKind.authorialRestriction,
      commitPolicy: CommitPolicy.alwaysBlock,
      applicability: const UniverseApplicability(),
      targetPredicates: [],
      expression: const LiteralExpr(true),
      capabilities: [],
      executable: true,
      validity: const UnspecifiedValidity(),
      requiredEvidence: RequiredEvidence(
        sourceCategories: [
          VersionRef(
            universe: universe,
            record: category.identity.recordId,
            version: category.recordVersionId,
          ),
        ],
      ),
    ),
  );
  return List.unmodifiable([category, policy]);
}
