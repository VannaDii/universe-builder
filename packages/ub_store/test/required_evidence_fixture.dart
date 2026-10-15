import 'package:ub_domain/ub_domain.dart';

CanonicalObject fictionalDeparturePayload(UniverseId universe, bool marked) =>
    ExceptionRecord(
      fictionalDeparture: marked,
      rule: RecordRef(
        universe: universe,
        record: RecordId.parse('rec_${'2'.padLeft(24, '0')}'),
      ),
      ruleVersion: RecordVersionId.parse('ver_${'3'.padLeft(24, '0')}'),
      scope: Scope(
        context: RecordRef(
          record: RecordId.parse('rec_${'4'.padLeft(24, '0')}'),
        ),
        applicability: const UniverseApplicability(),
      ),
      validity: const UnspecifiedValidity(),
      authorizingDecision: RecordRef(
        record: RecordId.parse('rec_${'5'.padLeft(24, '0')}'),
      ),
      rationale: 'Invented for the novel 記憶 😀',
    ).toWire();

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

CanonicalObject sourcedEventPayload(UniverseId universe) => EventRecord(
  occurrence: const SimpleOccurrence(OccurrenceKind.occurred),
  time: ExactTime(CalendarId.parse('cal_${'1'.padLeft(24, '0')}'), '12'),
  participants: [],
  labels: {},
  basis: SourceAnchorBasis(
    RecordRef(
      universe: universe,
      record: RecordId.parse('rec_${'6'.padLeft(24, '0')}'),
    ),
    false,
  ),
).toWire();
