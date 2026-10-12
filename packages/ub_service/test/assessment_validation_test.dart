import 'dart:convert';

import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/assessment_validation.dart';
import 'package:ub_service/proposal_state.dart';

import '../../ub_contracts/test/assessment_integrity_test.dart' as accounting;
import 'operation_compilation_test.dart' as f;
import 'proposal_state_test.dart' as p;
import 'source_verification_test.dart' as sources;
import 'structural_checks_test.dart' as structure;

AssessmentVersionRef ref(int record, {int? version}) => AssessmentVersionRef(
  universe: f.u,
  record: f.id(record),
  version: f.ver(version ?? record),
);
final proposal = p.prepare(
  request: p.create(
    operations: [
      CreateEntityOperation(clientRef: f.id(20).value, record: f.entity()),
    ],
  ),
);
final source = f.row(2, sources.source());
SourceAssessmentV1 body({List<AssessmentVersionRef> dependencies = const []}) {
  var value = accounting.base(bytes: accounting.retained(sources.sourceText));
  value = accounting.replace(value, ['proposal'], proposal.reference.toWire());
  value = accounting.replace(value, [
    'base_frame',
  ], proposal.proposal.baseFrame.toWire());
  value = accounting.replace(value, [
    'dependencies',
  ], CanonicalArray(dependencies.map((r) => r.toWire())));
  return SourceAssessmentV1.fromWire(value);
}

SourceAssessmentV1 mapped({required CandidateLinkKind kind, int subject = 50}) {
  final base = body(dependencies: [ref(10), ref(50), ref(99)]);
  final range = ByteRange(
    start: BigInt.zero,
    end: BigInt.from(utf8.encode(sources.sourceText).length),
  );
  return SourceAssessmentV1(
    kind: base.kind,
    proposal: base.proposal,
    baseFrame: base.baseFrame,
    assessor: base.assessor,
    sources: base.sources,
    dependencies: base.dependencies,
    declaredInventory: [
      MaterialItem(
        itemId: 'item',
        sourceKey: 'passage',
        range: range,
        materialKind: MaterialKind.description,
        statement: 'An attributed description',
        mappingIds: ['mapping'],
        unresolvedIds: ['pending'],
      ),
    ],
    inventoryDeclaration: InventoryDeclaration(
      kind: InventoryKind.materialInventoryDeclared,
      rationale: 'External review',
      exclusions: [],
    ),
    claimMappings: [
      ClaimMapping(
        mappingId: 'mapping',
        itemIds: ['item'],
        referents: [],
        context: ref(99),
        world: null,
        realm: null,
        storyTime: ExactTime(f.cal, '0'),
        narrationPosition: const UnknownPosition(reason: 'Unresolved position'),
        readerPosition: const UnknownPosition(reason: 'Unresolved position'),
        occurrence: Occurrence.reported,
        modality: Modality.attributed,
        semantic: SourceDescriptionSemanticMapping(
          subject: ref(subject),
          depiction: Depiction.subjective,
          impliedClaims: [],
        ),
        candidateLinks: [CandidateLink(kind: kind, version: ref(10))],
        judgment: MappingJudgment.unresolved,
        rationale: 'Externally attributed, unresolved positions',
      ),
    ],
    unresolved: [
      UnresolvedDisposition(
        unresolvedId: 'pending',
        itemIds: ['item'],
        reason: UnresolvedReason.interpretationDisagreement,
        detail: 'Positions are unresolved',
      ),
    ],
    conclusion: DeclaredConclusion.unresolved,
  );
}

Future<void> verify(
  SourceAssessmentV1 value, {
  List<RecordVersion>? candidate,
  RecordVersion? historical,
  Map<String, CanonicalValue>? entries,
  StoredProposal? stored,
}) => verifyAssessmentCandidate(
  proposal: stored ?? proposal,
  universe: f.u,
  body: value,
  readCanon: (_, _) => candidate ?? [source],
  readVersion: (_) => historical ?? (throw StateError('Missing history')),
  readWorkflow: (key) => (entries ?? sources.staging(sources.source()))[key],
);

void main() {
  test('exact external accounting binds the frozen proposal and retained bytes without approving it', () async {
    final value = body();
    await verify(value);
    expect(
      value.conclusion,
      DeclaredConclusion.consistentWithDeclaredInventory,
    );
    await expectLater(
      verify(value, stored: p.prepare()),
      f.fails('Frozen proposal/frame mismatch', field: 'assessment'),
    );
    await expectLater(
      verify(value, entries: {}),
      throwsA(isA<NotFoundOrNotAccessibleError>()),
    );
  });

  test('source versions and ordinary dependencies must be active, not merely retained', () async {
    await expectLater(
      verify(body(), candidate: []),
      f.fails('source version is not active', field: 'assessment'),
    );
    final dependency = f.row(10, f.entity());
    await expectLater(
      verify(body(dependencies: [ref(10)]), historical: dependency),
      f.fails('dependency is not active', field: 'assessment'),
    );
    await verify(
      body(dependencies: [ref(10)]),
      candidate: [source, dependency],
    );
    await expectLater(
      verify(body(), candidate: [f.row(2, f.entity())]),
      f.fails('not a source version', field: 'assessment'),
    );
    final wrong = f.row(2, sources.source(size: 1));
    await expectLater(
      verify(body(), candidate: [wrong]),
      f.fails('source metadata mismatch', field: 'assessment'),
    );
  });

  test(
    'frozen changes replace base versions before dependency admission',
    () async {
      final old = f.row(20, f.entity());
      final next = RecordVersion.fromWire(
        proposal.changes.single.next!.toCanonical(),
      );
      await expectLater(
        verify(body(dependencies: [ref(20)]), candidate: [source, old]),
        f.fails('dependency is not active', field: 'assessment'),
      );
      await verify(
        body(
          dependencies: [
            AssessmentVersionRef(
              universe: f.u,
              record: next.identity.recordId,
              version: next.recordVersionId,
            ),
          ],
        ),
        candidate: [source, old],
      );
    },
  );

  test('historical evidence may be retained but semantic prerequisites must remain active', () async {
    final value = mapped(kind: CandidateLinkKind.historicalEvidence);
    final candidate = [source, f.row(50, f.entity()), structure.context(99)];
    await verify(
      value,
      candidate: candidate,
      historical: f.row(10, f.entity()),
    );
    await expectLater(
      verify(value, candidate: candidate),
      f.fails('missing historical version', field: 'assessment'),
    );
    await expectLater(
      verify(value, candidate: candidate, historical: f.row(11, f.entity())),
      f.fails('record/version mismatch', field: 'assessment'),
    );
    await expectLater(
      verify(
        mapped(kind: CandidateLinkKind.historicalEvidence, subject: 10),
        candidate: candidate,
        historical: f.row(10, f.entity()),
      ),
      f.fails('semantic reference is not active', field: 'assessment'),
    );
  });

  test('proposed and unchanged links retain their actual frozen change origin', () async {
    final proposed = RecordVersion.fromWire(
      proposal.changes.single.next!.toCanonical(),
    );
    final value = mapped(kind: CandidateLinkKind.unchangedRecord);
    CanonicalValue wire = value.toWire();
    // Use the actual compiler-allocated immutable version in both declarations.
    final pin = AssessmentVersionRef(
      universe: f.u,
      record: proposed.identity.recordId,
      version: proposed.recordVersionId,
    );
    wire = accounting.replace(wire, ['dependencies', 0], pin.toWire());
    wire = accounting.replace(wire, [
      'claim_mappings',
      0,
      'candidate_links',
      0,
      'version',
    ], pin.toWire());
    final candidate = [
      source,
      proposed,
      f.row(50, f.entity()),
      structure.context(99),
    ];
    await expectLater(
      verify(SourceAssessmentV1.fromWire(wire), candidate: candidate),
      f.fails('candidate link kind mismatch', field: 'assessment'),
    );
    wire = accounting.replace(wire, [
      'claim_mappings',
      0,
      'candidate_links',
      0,
      'kind',
    ], CanonicalString('proposed_record'));
    await verify(SourceAssessmentV1.fromWire(wire), candidate: candidate);
    await expectLater(
      verify(
        mapped(kind: CandidateLinkKind.proposedRecord),
        candidate: [
          source,
          f.row(10, f.entity()),
          f.row(50, f.entity()),
          structure.context(99),
        ],
      ),
      f.fails('candidate link kind mismatch', field: 'assessment'),
    );
  });

  test('dependency anchors must lie within an explicitly declared exact source range', () async {
    final anchor = f.row(
      3,
      sources.anchor(
        version: VersionRef(universe: f.u, record: f.id(2), version: f.ver(2)),
      ),
    );
    await verify(body(dependencies: [ref(3)]), candidate: [source, anchor]);
    CanonicalValue value = body(dependencies: [ref(3)]).toWire();
    value = accounting.replace(value, [
      'sources',
      0,
      'ranges',
      0,
      'end',
    ], const CanonicalNumber('1'));
    await expectLater(
      verify(SourceAssessmentV1.fromWire(value), candidate: [source, anchor]),
      f.fails('anchor is outside declared source binding', field: 'assessment'),
    );
  });
  test('edition and passage bindings require a current work version and a matching declared source anchor', () async {
    final anchor = f.row(
      3,
      sources.anchor(
        version: VersionRef(universe: f.u, record: f.id(2), version: f.ver(2)),
      ),
    );
    final edition = f.row(
      4,
      WorkVersionRecord(
        work: f.ref(5),
        versionLabel: 'first',
        binding: const UnboundWork(),
      ),
    );
    final passage = f.row(
      6,
      PassageRecord(
        workVersion: VersionRef(
          universe: f.u,
          record: f.id(4),
          version: f.ver(4),
        ),
        passageId: 'passage',
        anchor: f.ref(3),
      ),
    );
    CanonicalValue value = body(dependencies: [ref(3)]).toWire();
    value = accounting.replace(value, [
      'sources',
      0,
      'work_edition',
    ], ref(4).toWire());
    value = accounting.replace(value, [
      'sources',
      0,
      'passage_id',
    ], CanonicalString('passage'));
    final bound = SourceAssessmentV1.fromWire(value);
    await verify(bound, candidate: [source, anchor, edition, passage]);
    await expectLater(
      verify(bound, candidate: [source, anchor, passage]),
      f.fails('edition version is not active', field: 'assessment'),
    );
    await expectLater(
      verify(bound, candidate: [source, anchor, f.row(4, f.entity()), passage]),
      f.fails('edition version is not active', field: 'assessment'),
    );
    await expectLater(
      verify(bound, candidate: [source, anchor, edition]),
      f.fails('passage/edition/source anchor mismatch', field: 'assessment'),
    );
    final wrong = f.row(
      6,
      PassageRecord(
        workVersion: VersionRef(
          universe: f.u,
          record: f.id(4),
          version: f.ver(4),
        ),
        passageId: 'passage',
        anchor: f.ref(7),
      ),
    );
    await expectLater(
      verify(bound, candidate: [source, anchor, edition, wrong]),
      f.fails('passage/edition/source anchor mismatch', field: 'assessment'),
    );
  });
}
