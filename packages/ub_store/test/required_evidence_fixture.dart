import 'package:ub_domain/ub_domain.dart';

CanonicalObject requiredEvidencePayload(
  UniverseId universe, {
  bool review = false,
}) => RuleRecord(
  requiredEvidence: RequiredEvidence(
    sourceCategories: [
      VersionRef(
        universe: universe,
        record: RecordId.parse('rec_${'2'.padLeft(24, '0')}'),
        version: RecordVersionId.parse('ver_${'3'.padLeft(24, '0')}'),
      ),
    ],
    reviewMethods: review ? EvidenceReviewMethod.values : [],
  ),
  namespace: 'real_world',
  key: review ? 'reviewed_history' : 'attributed_recollection',
  labels: {'en': 'Authored evidence policy'},
  kind: RuleKind.authorialRestriction,
  commitPolicy: CommitPolicy.alwaysBlock,
  applicability: const UniverseApplicability(),
  targetPredicates: ['history:birth_date'],
  expression: const LiteralExpr(true),
  capabilities: [],
  executable: true,
  validity: const UnspecifiedValidity(),
).toWire();
