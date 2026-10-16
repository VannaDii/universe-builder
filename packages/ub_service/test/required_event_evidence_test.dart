import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart' as p;
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_rules/ub_rules.dart' as rules;
import 'package:ub_service/candidate_validation.dart';
import 'package:ub_service/proposal_authorization.dart';
import 'package:ub_service/operation_compilation.dart';
import 'package:ub_service/src/required_evidence_checks.dart';
import 'package:ub_service/src/required_evidence_reviews.dart';

import 'event_compilation_test.dart' as events;
import 'required_evidence_sources_test.dart' as sources;
import 'required_evidence_reviews_test.dart' as reviews;
import 'rule_checks_test.dart' as f;

EventRecord event({
  EvidenceBasis? basis,
  OccurrenceKind occurrence = OccurrenceKind.occurred,
  bool effect = false,
}) => EventRecord(
  occurrence: SimpleOccurrence(occurrence),
  action: f.ref(20),
  time: ExactTime(f.calendar, '12'),
  participants: [EventParticipant(f.ref(1), 'traveler')],
  labels: {},
  expansionVersion: rules.eventExpansionVersion,
  basis: basis,
  effects: effect
      ? [
          EntityEffect(
            slot: 'change',
            proposition: f.ref(3),
            polarity: Polarity.support,
            validity: CalendarIntervalValidity(
              f.calendar,
              const ExactBound('12'),
              const UnboundedBound(),
            ),
            scope: f.scope,
            order: BigInt.zero,
          ),
        ]
      : [],
);
List<RecordVersion> fixture({bool review = false, bool effect = false}) {
  final rows = sources.fixture()
    ..removeWhere((r) => r.identity.recordId == f.id(10));
  rows.addAll([
    f.record(
      10,
      CalendarRecord(
        namespace: 'test',
        key: 'clock',
        labels: {},
        unitStructure: {},
      ),
    ),
    f.record(
      40,
      sources.policy(
        predicates: [],
        reviewMethods: review ? [EvidenceReviewMethod.humanReview] : [],
      ),
    ),
    f.record(
      20,
      ActionDefinitionRecord(
        namespace: 'test',
        key: 'arrival',
        labels: {},
        requirements: [],
        scope: f.scope,
        validity: const UnspecifiedValidity(),
        consequenceContract: ConsequenceContract(
          effect
              ? [
                  EffectSlot(
                    slot: 'change',
                    order: 0,
                    presence: EffectPresence.required,
                    target: EffectTarget('traveler', f.ref(2)),
                    condition: const AlwaysEffect(),
                    change: const SetEffect(
                      Polarity.support,
                      BooleanValue(true),
                    ),
                    lifetime: const UntilChangedEffect(),
                  ),
                ]
              : [],
        ),
      ),
    ),
    f.record(
      30,
      event(basis: SourceAnchorBasis(f.ref(13), false), effect: effect),
    ),
  ]);
  for (final entry in rules.expandEvents(rows).entries) {
    rows.add(
      RecordVersion.build(
        recordVersionId: f.version(31),
        identity: RecordIdentity(
          universeId: f.universe,
          recordId: entry.key,
          recordKind: RecordKind.assertion,
        ),
        payload: entry.value,
      ),
    );
  }
  return rows;
}

p.AssessmentVersionRef pin(RecordVersion row) => p.AssessmentVersionRef(
  universe: row.identity.universeId,
  record: row.identity.recordId,
  version: row.recordVersionId,
);
p.AssessmentReview review(
  List<RecordVersion> rows, {
  bool includeEffect = false,
}) {
  final original = reviews.review();
  final old = original.envelope!.body;
  RecordVersion row(int n) =>
      rows.singleWhere((r) => r.identity.recordId == f.id(n));
  final mapping = p.ClaimMapping(
    mappingId: 'event',
    itemIds: ['event'],
    referents: [],
    context: reviews.ref(99),
    world: null,
    realm: null,
    storyTime: ExactTime(f.calendar, '12'),
    narrationPosition: const p.NotApplicablePosition(),
    readerPosition: const p.NotApplicablePosition(),
    occurrence: p.Occurrence.occurred,
    modality: p.Modality.asserted,
    semantic: p.ActionSemanticMapping(
      action: pin(row(20)),
      participants: [
        p.RoleParticipant(role: 'traveler', participant: reviews.ref(1)),
      ],
      prerequisites: [],
      effects: (row(30).payload as EventRecord).effects.map(
        (e) => pin(
          rows.singleWhere((r) => r.identity.recordId == e.proposition.record),
        ),
      ),
    ),
    candidateLinks: [
      p.CandidateLink(
        kind: p.CandidateLinkKind.unchangedRecord,
        version: pin(row(30)),
      ),
    ],
    judgment: p.MappingJudgment.supported,
    rationale: 'Reviewed occurrence',
  );
  final mappings = [...old.claimMappings, mapping];
  final generated = rows
      .where(
        (r) =>
            r.payload is AssertionRecord &&
            (r.payload as AssertionRecord).establishedBy != null,
      )
      .firstOrNull;
  if (includeEffect && generated != null) {
    mappings.add(
      p.ClaimMapping(
        mappingId: 'effect',
        itemIds: ['effect'],
        referents: [],
        context: reviews.ref(99),
        world: null,
        realm: null,
        storyTime: IntervalTime(
          f.calendar,
          const ExactBound('12'),
          const UnboundedBound(),
        ),
        narrationPosition: const p.NotApplicablePosition(),
        readerPosition: const p.NotApplicablePosition(),
        occurrence: p.Occurrence.occurred,
        modality: p.Modality.asserted,
        semantic: (old.claimMappings.single.semantic),
        candidateLinks: [
          p.CandidateLink(
            kind: p.CandidateLinkKind.unchangedRecord,
            version: pin(generated),
          ),
        ],
        judgment: p.MappingJudgment.supported,
        rationale: 'Reviewed exact effect',
      ),
    );
  }
  final dependencies = {
    for (final ref in [
      ...old.dependencies,
      pin(row(20)),
      pin(row(30)),
      pin(row(3)),
      if (generated != null) pin(generated),
    ])
      ref.toWire().toText(): ref,
  };
  final body = p.SourceAssessmentV1(
    kind: old.kind,
    proposal: old.proposal,
    baseFrame: old.baseFrame,
    assessor: old.assessor,
    sources: old.sources,
    dependencies: dependencies.values,
    declaredInventory: [
      for (final m in mappings)
        p.MaterialItem(
          itemId: m.mappingId,
          sourceKey: 'passage',
          range: old.sources.single.ranges.single,
          materialKind: m.mappingId == 'event'
              ? p.MaterialKind.action
              : p.MaterialKind.effect,
          statement: 'Reviewed exact claim',
          mappingIds: [m.mappingId],
          unresolvedIds: [],
        ),
    ],
    inventoryDeclaration: old.inventoryDeclaration,
    claimMappings: mappings,
    unresolved: [],
    conclusion: old.conclusion,
  );
  body.validate();
  final envelope = p.AssessmentEnvelope(
    assessmentId: original.envelope!.assessmentId,
    digest: body.digest(),
    body: body,
  );
  final selected = p.AssessmentRef(
    assessmentId: envelope.assessmentId,
    digest: envelope.digest,
  );
  return p.AssessmentReview(
    selection: p.AssessmentSelection(
      proposal: body.proposal,
      generation: BigInt.one,
      selected: selected,
    ),
    state: p.BoundAssessment(
      assessmentReference: selected,
      selectionGeneration: BigInt.one,
      byteVerification: p.ByteVerification.verified,
      declaredConclusion: body.conclusion,
      inventoryCount: BigInt.from(body.declaredInventory.length),
      mappingCount: BigInt.from(mappings.length),
      unresolvedCount: BigInt.zero,
      inventoryDigest: body.inventoryDigest(),
    ),
    envelope: envelope,
  );
}

List<p.Finding> assess(
  List<RecordVersion> rows, {
  p.AssessmentReview? selected,
  Set<RecordId>? changed,
}) => assessRequiredEvidenceReviews(
  sourceFindings: assessRequiredEvidenceSources(
    records: rows,
    base: rows,
    changed: changed ?? {f.id(40)},
  ),
  records: rows,
  review: selected,
);
void main() {
  test('record-event compilation preserves the source and admits its exact generated effects', () {
    final rows = fixture(effect: true);
    final record =
        rows.singleWhere((r) => r.identity.recordId == f.id(30)).payload
            as EventRecord;
    final base = rows
        .where(
          (r) =>
              r.identity.recordId != f.id(30) &&
              !(r.payload is AssertionRecord &&
                  (r.payload as AssertionRecord).establishedBy != null),
        )
        .toList();
    final changes = compileOperations(
      universe: f.universe,
      revision: f.frame().revision,
      base: base,
      operations: [
        RecordEventOperation(clientRef: f.id(30).value, record: record),
      ],
    );
    final candidate = [
      ...base,
      for (final c in changes)
        if (c.next != null) RecordVersion.fromWire(c.next!.toCanonical()),
    ];
    expect(
      (candidate.singleWhere((r) => r.identity.recordId == f.id(30)).payload
              as EventRecord)
          .basis,
      record.basis,
    );
    final checked = evaluateCandidate(
      candidate: candidate,
      base: base,
      changes: changes,
      frame: f.frame(),
      digest: 'compiled-event',
      footprint: WriteFootprint(shared: true),
      authorOrigin: true,
      approvalAuthor: ProfileId.parse('prf_${f.suffix(1)}'),
    );
    expect(checked.admissible, isTrue);
  });
  test('occurred events require qualifying sources only where their policy applies', () {
    final rows = fixture();
    expect(
      assess(rows).every((f) => f.outcome == p.EvidenceOutcome.supported),
      isTrue,
    );
    sources.replace(rows, 30, event());
    expect(
      assess(rows)
          .singleWhere((finding) => finding.records.single.record == f.id(30))
          .outcome,
      p.EvidenceOutcome.notEstablished,
    );
  });
  test('plans reports and hypothetical events do not assert an occurrence', () {
    for (final kind in OccurrenceKind.values.where(
      (k) => k != OccurrenceKind.occurred,
    )) {
      final rows = fixture();
      sources.replace(rows, 30, event(occurrence: kind));
      expect(
        assess(rows)
            .any((finding) => finding.records.single.record == f.id(30)),
        isFalse,
      );
    }
  });
  test('an actionless historical occurrence has unresolved scope under a new broad policy', () {
    final rows = fixture();
    final old =
        rows.singleWhere((r) => r.identity.recordId == f.id(30)).payload
            as EventRecord;
    sources.replace(
      rows,
      30,
      EventRecord.fromWire(
        CanonicalObject(old.toWire().fields.where((e) => e.key != 'action')),
      ),
    );
    final finding = assess(rows)
        .singleWhere((f) => f.records.single.record == reviews.ref(30).record);
    expect(finding.outcome, p.EvidenceOutcome.notEstablished);
    expect(finding.coverage, p.Coverage.unsupported);
  });
  test(
    'disjoint world scope leaves unrelated event occurrences outside the duty',
    () {
      final rows = fixture();
      sources.replace(
        rows,
        40,
        sources.policy(
          predicates: [],
          applicability: WorldsApplicability([
            WorldId.parse('wld_${f.suffix(50)}'),
          ]),
        ),
      );
      final old =
          rows.singleWhere((r) => r.identity.recordId == f.id(30)).payload
              as EventRecord;
      sources.replace(
        rows,
        30,
        EventRecord.fromWire(
          CanonicalObject([
            ...old.toWire().fields.where((e) => e.key != 'worlds'),
            MapEntry(
              'worlds',
              CanonicalArray([CanonicalString('wld_${f.suffix(51)}')]),
            ),
          ]),
        ),
      );
      expect(
        assess(rows)
            .any((finding) => finding.records.single.record == f.id(30)),
        isFalse,
      );
    },
  );
  test(
    'an occurrence review does not discharge a required exact effect review',
    () {
      final rows = fixture(review: true, effect: true);
      final incomplete = assess(rows, selected: review(rows));
      expect(
        incomplete.where((f) => f.outcome != p.EvidenceOutcome.supported),
        hasLength(1),
      );
      expect(
        assess(
          rows,
          selected: review(rows, includeEffect: true),
        ).every((f) => f.outcome == p.EvidenceOutcome.supported),
        isTrue,
      );
    },
  );
  test('verified effects inherit the event source through the existing generated link', () {
    final rows = fixture(effect: true);
    expect(assess(rows), hasLength(3));
    expect(
      assess(rows).every((f) => f.outcome == p.EvidenceOutcome.supported),
      isTrue,
    );
  });
  test('broad policies reach the shared evaluator for occurred events and exact effects', () {
    final rows = fixture(effect: true);
    final result = evaluateCandidate(
      candidate: rows,
      base: rows,
      changes: [
        events.change(rows.singleWhere((r) => r.identity.recordId == f.id(30))),
      ],
      frame: f.frame(),
      digest: 'event-candidate',
      footprint: WriteFootprint(shared: true),
      authorOrigin: true,
      approvalAuthor: ProfileId.parse('prf_${f.suffix(1)}'),
    );
    expect(result.admissible, isTrue);
  });
}
