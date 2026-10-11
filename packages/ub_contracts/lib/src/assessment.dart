import 'package:ub_domain/ub_domain.dart';

import 'wire.dart';
import 'workflow.dart';
import 'validation_scope.dart';

enum AssessmentKind {
  sourceAssessmentV1('source_assessment');

  const AssessmentKind(this.wireName);
  final String wireName;
  static AssessmentKind fromName(String name) => values.firstWhere(
    (v) => v.wireName == name,
    orElse: () => throw const FormatException('Unknown AssessmentKind'),
  );
}

enum Method {
  humanReview('human_review'),
  externalModelReview('external_model_review');

  const Method(this.wireName);
  final String wireName;
  static Method fromName(String name) => values.firstWhere(
    (v) => v.wireName == name,
    orElse: () => throw const FormatException('Unknown Method'),
  );
}

enum MaterialKind {
  fact('fact'),
  action('action'),
  prerequisite('prerequisite'),
  effect('effect'),
  knowledge('knowledge'),
  description('description'),
  disclosure('disclosure'),
  unchangedState('unchanged_state');

  const MaterialKind(this.wireName);
  final String wireName;
  static MaterialKind fromName(String name) => values.firstWhere(
    (v) => v.wireName == name,
    orElse: () => throw const FormatException('Unknown MaterialKind'),
  );
}

enum InventoryKind {
  materialInventoryDeclared('material_inventory_declared'),
  noMaterialClaims('no_material_claims');

  const InventoryKind(this.wireName);
  final String wireName;
  static InventoryKind fromName(String name) => values.firstWhere(
    (v) => v.wireName == name,
    orElse: () => throw const FormatException('Unknown InventoryKind'),
  );
}

enum Occurrence {
  occurred('occurred'),
  planned('planned'),
  hypothetical('hypothetical'),
  reported('reported'),
  unknown('unknown');

  const Occurrence(this.wireName);
  final String wireName;
  static Occurrence fromName(String name) => values.firstWhere(
    (v) => v.wireName == name,
    orElse: () => throw const FormatException('Unknown Occurrence'),
  );
}

enum Modality {
  asserted('asserted'),
  negated('negated'),
  possible('possible'),
  counterfactual('counterfactual'),
  attributed('attributed'),
  unknown('unknown');

  const Modality(this.wireName);
  final String wireName;
  static Modality fromName(String name) => values.firstWhere(
    (v) => v.wireName == name,
    orElse: () => throw const FormatException('Unknown Modality'),
  );
}

enum MappingJudgment {
  supported('supported'),
  contradicted('contradicted'),
  unresolved('unresolved');

  const MappingJudgment(this.wireName);
  final String wireName;
  static MappingJudgment fromName(String name) => values.firstWhere(
    (v) => v.wireName == name,
    orElse: () => throw const FormatException('Unknown MappingJudgment'),
  );
}

enum UnresolvedReason {
  ambiguousReferent('ambiguous_referent'),
  ambiguousModality('ambiguous_modality'),
  unsupportedSemantics('unsupported_semantics'),
  missingEvidence('missing_evidence'),
  unrepresentedMaterial('unrepresented_material'),
  interpretationDisagreement('interpretation_disagreement');

  const UnresolvedReason(this.wireName);
  final String wireName;
  static UnresolvedReason fromName(String name) => values.firstWhere(
    (v) => v.wireName == name,
    orElse: () => throw const FormatException('Unknown UnresolvedReason'),
  );
}

enum CandidateLinkKind {
  proposedRecord('proposed_record'),
  unchangedRecord('unchanged_record'),
  historicalEvidence('historical_evidence');

  const CandidateLinkKind(this.wireName);
  final String wireName;
  static CandidateLinkKind fromName(String name) => values.firstWhere(
    (v) => v.wireName == name,
    orElse: () => throw const FormatException('Unknown CandidateLinkKind'),
  );
}

enum Depiction {
  factual('factual'),
  subjective('subjective'),
  inspiration('inspiration');

  const Depiction(this.wireName);
  final String wireName;
  static Depiction fromName(String name) => values.firstWhere(
    (v) => v.wireName == name,
    orElse: () => throw const FormatException('Unknown Depiction'),
  );
}

enum ValidationBindingKind {
  sourceValidationBindingV1('source_validation_binding_v1');

  const ValidationBindingKind(this.wireName);
  final String wireName;
  static ValidationBindingKind fromName(String name) => values.firstWhere(
    (v) => v.wireName == name,
    orElse: () => throw const FormatException('Unknown ValidationBindingKind'),
  );
}

final class ToolIdentity {
  const ToolIdentity({
    required this.name,
    required this.version,
    required this.modelRevision,
    required this.procedureDigest,
  });
  final String name;
  final String version;
  final String modelRevision;
  final Sha256Hex procedureDigest;
  factory ToolIdentity.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'name',
      'version',
      'model_revision',
      'procedure_digest',
    });
    return ToolIdentity(
      name: wireString(f.require('name')),
      version: wireString(f.require('version')),
      modelRevision: wireString(f.require('model_revision')),
      procedureDigest: Sha256Hex(wireString(f.require('procedure_digest'))),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('name', CanonicalString(name)),
    MapEntry('version', CanonicalString(version)),
    MapEntry('model_revision', CanonicalString(modelRevision)),
    MapEntry('procedure_digest', CanonicalString(procedureDigest.value)),
  ]);
}

final class Assessor {
  const Assessor({
    required this.principal,
    required this.method,
    required this.tool,
    required this.assessedAt,
  });
  final PrincipalId principal;
  final Method method;
  final ToolIdentity? tool;
  final String assessedAt;
  factory Assessor.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'principal', 'method', 'tool', 'assessed_at'});
    f.require('tool');
    return Assessor(
      principal: PrincipalId.parse(wireString(f.require('principal'))),
      method: Method.fromName(wireString(f.require('method'))),
      tool: f.optional('tool', (v) => ToolIdentity.fromWire(v)),
      assessedAt: wireString(f.require('assessed_at')),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('principal', CanonicalString(principal.value)),
    MapEntry('method', CanonicalString(method.wireName)),
    MapEntry('tool', tool == null ? const CanonicalNull() : tool!.toWire()),
    MapEntry('assessed_at', CanonicalString(assessedAt)),
  ]);
}

final class MaterialItem {
  MaterialItem({
    required this.itemId,
    required this.sourceKey,
    required this.range,
    required this.materialKind,
    required this.statement,
    required Iterable<String> mappingIds,
    required Iterable<String> unresolvedIds,
  }) : mappingIds = List.unmodifiable(mappingIds),
       unresolvedIds = List.unmodifiable(unresolvedIds);
  final String itemId;
  final String sourceKey;
  final ByteRange range;
  final MaterialKind materialKind;
  final String statement;
  final List<String> mappingIds;
  final List<String> unresolvedIds;
  factory MaterialItem.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'item_id',
      'source_key',
      'range',
      'material_kind',
      'statement',
      'mapping_ids',
      'unresolved_ids',
    });
    return MaterialItem(
      itemId: wireString(f.require('item_id')),
      sourceKey: wireString(f.require('source_key')),
      range: ByteRange.fromWire(f.require('range')),
      materialKind: MaterialKind.fromName(
        wireString(f.require('material_kind')),
      ),
      statement: wireString(f.require('statement')),
      mappingIds: f.array('mapping_ids').map((v) => wireString(v)),
      unresolvedIds: f.array('unresolved_ids').map((v) => wireString(v)),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('item_id', CanonicalString(itemId)),
    MapEntry('source_key', CanonicalString(sourceKey)),
    MapEntry('range', range.toWire()),
    MapEntry('material_kind', CanonicalString(materialKind.wireName)),
    MapEntry('statement', CanonicalString(statement)),
    MapEntry(
      'mapping_ids',
      CanonicalArray(mappingIds.map((v) => CanonicalString(v))),
    ),
    MapEntry(
      'unresolved_ids',
      CanonicalArray(unresolvedIds.map((v) => CanonicalString(v))),
    ),
  ]);
}

final class Exclusion {
  const Exclusion({
    required this.sourceKey,
    required this.range,
    required this.reason,
  });
  final String sourceKey;
  final ByteRange range;
  final String reason;
  factory Exclusion.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'source_key', 'range', 'reason'});
    return Exclusion(
      sourceKey: wireString(f.require('source_key')),
      range: ByteRange.fromWire(f.require('range')),
      reason: wireString(f.require('reason')),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('source_key', CanonicalString(sourceKey)),
    MapEntry('range', range.toWire()),
    MapEntry('reason', CanonicalString(reason)),
  ]);
}

final class InventoryDeclaration {
  InventoryDeclaration({
    required this.kind,
    required this.rationale,
    required Iterable<Exclusion> exclusions,
  }) : exclusions = List.unmodifiable(exclusions);
  final InventoryKind kind;
  final String rationale;
  final List<Exclusion> exclusions;
  factory InventoryDeclaration.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'kind', 'rationale', 'exclusions'});
    return InventoryDeclaration(
      kind: InventoryKind.fromName(wireString(f.require('kind'))),
      rationale: wireString(f.require('rationale')),
      exclusions: f.array('exclusions').map((v) => Exclusion.fromWire(v)),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('kind', CanonicalString(kind.wireName)),
    MapEntry('rationale', CanonicalString(rationale)),
    MapEntry('exclusions', CanonicalArray(exclusions.map((v) => v.toWire()))),
  ]);
}

final class RoleParticipant {
  const RoleParticipant({required this.role, required this.participant});
  final String role;
  final AssessmentVersionRef participant;
  factory RoleParticipant.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'role', 'participant'});
    return RoleParticipant(
      role: wireString(f.require('role')),
      participant: AssessmentVersionRef.fromWire(f.require('participant')),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('role', CanonicalString(role)),
    MapEntry('participant', participant.toWire()),
  ]);
}

final class CandidateLink {
  const CandidateLink({required this.kind, required this.version});
  final CandidateLinkKind kind;
  final AssessmentVersionRef version;
  factory CandidateLink.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'kind', 'version'});
    return CandidateLink(
      kind: CandidateLinkKind.fromName(wireString(f.require('kind'))),
      version: AssessmentVersionRef.fromWire(f.require('version')),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('kind', CanonicalString(kind.wireName)),
    MapEntry('version', version.toWire()),
  ]);
}

final class ClaimMapping {
  ClaimMapping({
    required this.mappingId,
    required Iterable<String> itemIds,
    required Iterable<AssessmentVersionRef> referents,
    required this.context,
    required this.world,
    required this.realm,
    required this.storyTime,
    required this.narrationPosition,
    required this.readerPosition,
    required this.occurrence,
    required this.modality,
    required this.semantic,
    required Iterable<CandidateLink> candidateLinks,
    required this.judgment,
    required this.rationale,
  }) : itemIds = List.unmodifiable(itemIds),
       referents = List.unmodifiable(referents),
       candidateLinks = List.unmodifiable(candidateLinks);
  final String mappingId;
  final List<String> itemIds;
  final List<AssessmentVersionRef> referents;
  final AssessmentVersionRef context;
  final AssessmentVersionRef? world;
  final AssessmentVersionRef? realm;
  final TemporalExpression storyTime;
  final Position narrationPosition;
  final Position readerPosition;
  final Occurrence occurrence;
  final Modality modality;
  final SemanticMapping semantic;
  final List<CandidateLink> candidateLinks;
  final MappingJudgment judgment;
  final String rationale;
  factory ClaimMapping.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'mapping_id',
      'item_ids',
      'referents',
      'context',
      'world',
      'realm',
      'story_time',
      'narration_position',
      'reader_position',
      'occurrence',
      'modality',
      'semantic',
      'candidate_links',
      'judgment',
      'rationale',
    });
    f.require('world');
    f.require('realm');
    return ClaimMapping(
      mappingId: wireString(f.require('mapping_id')),
      itemIds: f.array('item_ids').map((v) => wireString(v)),
      referents: f
          .array('referents')
          .map((v) => AssessmentVersionRef.fromWire(v)),
      context: AssessmentVersionRef.fromWire(f.require('context')),
      world: f.optional('world', (v) => AssessmentVersionRef.fromWire(v)),
      realm: f.optional('realm', (v) => AssessmentVersionRef.fromWire(v)),
      storyTime: TemporalExpression.fromWire(f.require('story_time')),
      narrationPosition: Position.fromWire(f.require('narration_position')),
      readerPosition: Position.fromWire(f.require('reader_position')),
      occurrence: Occurrence.fromName(wireString(f.require('occurrence'))),
      modality: Modality.fromName(wireString(f.require('modality'))),
      semantic: SemanticMapping.fromWire(f.require('semantic')),
      candidateLinks: f
          .array('candidate_links')
          .map((v) => CandidateLink.fromWire(v)),
      judgment: MappingJudgment.fromName(wireString(f.require('judgment'))),
      rationale: wireString(f.require('rationale')),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('mapping_id', CanonicalString(mappingId)),
    MapEntry(
      'item_ids',
      CanonicalArray(itemIds.map((v) => CanonicalString(v))),
    ),
    MapEntry('referents', CanonicalArray(referents.map((v) => v.toWire()))),
    MapEntry('context', context.toWire()),
    MapEntry('world', world == null ? const CanonicalNull() : world!.toWire()),
    MapEntry('realm', realm == null ? const CanonicalNull() : realm!.toWire()),
    MapEntry('story_time', storyTime.encode(canonical: false)),
    MapEntry('narration_position', narrationPosition.toWire()),
    MapEntry('reader_position', readerPosition.toWire()),
    MapEntry('occurrence', CanonicalString(occurrence.wireName)),
    MapEntry('modality', CanonicalString(modality.wireName)),
    MapEntry('semantic', semantic.toWire()),
    MapEntry(
      'candidate_links',
      CanonicalArray(candidateLinks.map((v) => v.toWire())),
    ),
    MapEntry('judgment', CanonicalString(judgment.wireName)),
    MapEntry('rationale', CanonicalString(rationale)),
  ]);
}

final class UnresolvedDisposition {
  UnresolvedDisposition({
    required this.unresolvedId,
    required Iterable<String> itemIds,
    required this.reason,
    required this.detail,
  }) : itemIds = List.unmodifiable(itemIds);
  final String unresolvedId;
  final List<String> itemIds;
  final UnresolvedReason reason;
  final String detail;
  factory UnresolvedDisposition.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'unresolved_id',
      'item_ids',
      'reason',
      'detail',
    });
    return UnresolvedDisposition(
      unresolvedId: wireString(f.require('unresolved_id')),
      itemIds: f.array('item_ids').map((v) => wireString(v)),
      reason: UnresolvedReason.fromName(wireString(f.require('reason'))),
      detail: wireString(f.require('detail')),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('unresolved_id', CanonicalString(unresolvedId)),
    MapEntry(
      'item_ids',
      CanonicalArray(itemIds.map((v) => CanonicalString(v))),
    ),
    MapEntry('reason', CanonicalString(reason.wireName)),
    MapEntry('detail', CanonicalString(detail)),
  ]);
}

/// Structural declaration DTO. Accounting and retained-byte admission remain
/// separate from decoding and must precede certifying an assessment body.
final class SourceAssessmentV1 {
  SourceAssessmentV1({
    required this.kind,
    required this.proposal,
    required this.baseFrame,
    required this.assessor,
    required Iterable<SourceBinding> sources,
    required Iterable<AssessmentVersionRef> dependencies,
    required Iterable<MaterialItem> declaredInventory,
    required this.inventoryDeclaration,
    required Iterable<ClaimMapping> claimMappings,
    required Iterable<UnresolvedDisposition> unresolved,
    required this.conclusion,
  }) : sources = List.unmodifiable(sources),
       dependencies = List.unmodifiable(dependencies),
       declaredInventory = List.unmodifiable(declaredInventory),
       claimMappings = List.unmodifiable(claimMappings),
       unresolved = List.unmodifiable(unresolved);
  final AssessmentKind kind;
  final ProposalRef proposal;
  final Frame baseFrame;
  final Assessor assessor;
  final List<SourceBinding> sources;
  final List<AssessmentVersionRef> dependencies;
  final List<MaterialItem> declaredInventory;
  final InventoryDeclaration inventoryDeclaration;
  final List<ClaimMapping> claimMappings;
  final List<UnresolvedDisposition> unresolved;
  final DeclaredConclusion conclusion;
  factory SourceAssessmentV1.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'kind',
      'proposal',
      'base_frame',
      'assessor',
      'sources',
      'dependencies',
      'declared_inventory',
      'inventory_declaration',
      'claim_mappings',
      'unresolved',
      'conclusion',
    });
    return SourceAssessmentV1(
      kind: AssessmentKind.fromName(wireString(f.require('kind'))),
      proposal: ProposalRef.fromWire(f.require('proposal')),
      baseFrame: Frame.fromWire(f.require('base_frame')),
      assessor: Assessor.fromWire(f.require('assessor')),
      sources: f.array('sources').map((v) => SourceBinding.fromWire(v)),
      dependencies: f
          .array('dependencies')
          .map((v) => AssessmentVersionRef.fromWire(v)),
      declaredInventory: f
          .array('declared_inventory')
          .map((v) => MaterialItem.fromWire(v)),
      inventoryDeclaration: InventoryDeclaration.fromWire(
        f.require('inventory_declaration'),
      ),
      claimMappings: f
          .array('claim_mappings')
          .map((v) => ClaimMapping.fromWire(v)),
      unresolved: f
          .array('unresolved')
          .map((v) => UnresolvedDisposition.fromWire(v)),
      conclusion: DeclaredConclusion.fromName(f.string('conclusion')),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('kind', CanonicalString(kind.wireName)),
    MapEntry('proposal', proposal.toWire()),
    MapEntry('base_frame', baseFrame.toWire()),
    MapEntry('assessor', assessor.toWire()),
    MapEntry('sources', CanonicalArray(sources.map((v) => v.toWire()))),
    MapEntry(
      'dependencies',
      CanonicalArray(dependencies.map((v) => v.toWire())),
    ),
    MapEntry(
      'declared_inventory',
      CanonicalArray(declaredInventory.map((v) => v.toWire())),
    ),
    MapEntry('inventory_declaration', inventoryDeclaration.toWire()),
    MapEntry(
      'claim_mappings',
      CanonicalArray(claimMappings.map((v) => v.toWire())),
    ),
    MapEntry('unresolved', CanonicalArray(unresolved.map((v) => v.toWire()))),
    MapEntry('conclusion', CanonicalString(conclusion.wireName)),
  ]);
}

final class AssessmentEnvelope {
  const AssessmentEnvelope({
    required this.assessmentId,
    required this.digest,
    required this.body,
  });
  final AssessmentId assessmentId;
  final Sha256Hex digest;
  final SourceAssessmentV1 body;
  factory AssessmentEnvelope.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'assessment_id', 'digest', 'body'});
    return AssessmentEnvelope(
      assessmentId: AssessmentId(wireString(f.require('assessment_id'))),
      digest: Sha256Hex(wireString(f.require('digest'))),
      body: SourceAssessmentV1.fromWire(f.require('body')),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('assessment_id', CanonicalString(assessmentId.value)),
    MapEntry('digest', CanonicalString(digest.value)),
    MapEntry('body', body.toWire()),
  ]);
}

final class AssessmentSelection {
  AssessmentSelection({
    required this.proposal,
    required BigInt generation,
    required this.selected,
  }) : generation = checkedU64(generation);
  final ProposalRef proposal;
  final BigInt generation;
  final AssessmentRef? selected;
  factory AssessmentSelection.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'proposal', 'generation', 'selected'});
    f.require('selected');
    return AssessmentSelection(
      proposal: ProposalRef.fromWire(f.require('proposal')),
      generation: f.u64('generation'),
      selected: f.optional('selected', (v) => AssessmentRef.fromWire(v)),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('proposal', proposal.toWire()),
    MapEntry('generation', CanonicalNumber(generation.toString())),
    MapEntry(
      'selected',
      selected == null ? const CanonicalNull() : selected!.toWire(),
    ),
  ]);
}

final class AssessmentReview {
  const AssessmentReview({
    required this.selection,
    required this.state,
    required this.envelope,
  });
  final AssessmentSelection selection;
  final AssessmentState state;
  final AssessmentEnvelope? envelope;
  factory AssessmentReview.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'selection', 'state', 'envelope'});
    f.require('envelope');
    return AssessmentReview(
      selection: AssessmentSelection.fromWire(f.require('selection')),
      state: AssessmentState.fromWire(f.require('state')),
      envelope: f.optional('envelope', (v) => AssessmentEnvelope.fromWire(v)),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('selection', selection.toWire()),
    MapEntry('state', state.toWire()),
    MapEntry(
      'envelope',
      envelope == null ? const CanonicalNull() : envelope!.toWire(),
    ),
  ]);
}

final class AssessmentFragment {
  AssessmentFragment({
    required this.assessmentReference,
    required BigInt offset,
    required BigInt totalBytes,
    required this.canonicalEnvelopeUtf8,
  }) : offset = checkedU64(offset),
       totalBytes = checkedU64(totalBytes);
  final AssessmentRef assessmentReference;
  final BigInt offset;
  final BigInt totalBytes;
  final String canonicalEnvelopeUtf8;
  factory AssessmentFragment.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'assessment_reference',
      'offset',
      'total_bytes',
      'canonical_envelope_utf8',
    });
    return AssessmentFragment(
      assessmentReference: AssessmentRef.fromWire(
        f.require('assessment_reference'),
      ),
      offset: f.u64('offset'),
      totalBytes: f.u64('total_bytes'),
      canonicalEnvelopeUtf8: wireString(f.require('canonical_envelope_utf8')),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('assessment_reference', assessmentReference.toWire()),
    MapEntry('offset', CanonicalNumber(offset.toString())),
    MapEntry('total_bytes', CanonicalNumber(totalBytes.toString())),
    MapEntry('canonical_envelope_utf8', CanonicalString(canonicalEnvelopeUtf8)),
  ]);
}

final class AssessmentReviewPage {
  const AssessmentReviewPage({
    required this.selection,
    required this.state,
    required this.envelope,
    required this.fragment,
  });
  final AssessmentSelection selection;
  final AssessmentState state;
  final AssessmentEnvelope? envelope;
  final AssessmentFragment? fragment;
  factory AssessmentReviewPage.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'selection', 'state', 'envelope', 'fragment'});
    f.require('envelope');
    f.require('fragment');
    return AssessmentReviewPage(
      selection: AssessmentSelection.fromWire(f.require('selection')),
      state: AssessmentState.fromWire(f.require('state')),
      envelope: f.optional('envelope', (v) => AssessmentEnvelope.fromWire(v)),
      fragment: f.optional('fragment', (v) => AssessmentFragment.fromWire(v)),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('selection', selection.toWire()),
    MapEntry('state', state.toWire()),
    MapEntry(
      'envelope',
      envelope == null ? const CanonicalNull() : envelope!.toWire(),
    ),
    MapEntry(
      'fragment',
      fragment == null ? const CanonicalNull() : fragment!.toWire(),
    ),
  ]);
}

final class SourceValidationBindingV1 {
  const SourceValidationBindingV1({
    required this.kind,
    required this.proposal,
    required this.baseFrame,
    required this.selection,
    required this.submittedInput,
    required this.assessmentState,
    required this.executionResultDigest,
    required this.evaluatorVersion,
  });
  final ValidationBindingKind kind;
  final ProposalRef proposal;
  final Frame baseFrame;
  final AssessmentSelection selection;
  final SubmittedInput submittedInput;
  final AssessmentState assessmentState;
  final Sha256Hex executionResultDigest;
  final String evaluatorVersion;
  factory SourceValidationBindingV1.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'kind',
      'proposal',
      'base_frame',
      'selection',
      'submitted_input',
      'assessment_state',
      'execution_result_digest',
      'evaluator_version',
    });
    return SourceValidationBindingV1(
      kind: ValidationBindingKind.fromName(wireString(f.require('kind'))),
      proposal: ProposalRef.fromWire(f.require('proposal')),
      baseFrame: Frame.fromWire(f.require('base_frame')),
      selection: AssessmentSelection.fromWire(f.require('selection')),
      submittedInput: SubmittedInput.fromWire(f.require('submitted_input')),
      assessmentState: AssessmentState.fromWire(f.require('assessment_state')),
      executionResultDigest: Sha256Hex(
        wireString(f.require('execution_result_digest')),
      ),
      evaluatorVersion: wireString(f.require('evaluator_version')),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('kind', CanonicalString(kind.wireName)),
    MapEntry('proposal', proposal.toWire()),
    MapEntry('base_frame', baseFrame.toWire()),
    MapEntry('selection', selection.toWire()),
    MapEntry('submitted_input', submittedInput.toWire()),
    MapEntry('assessment_state', assessmentState.toWire()),
    MapEntry(
      'execution_result_digest',
      CanonicalString(executionResultDigest.value),
    ),
    MapEntry('evaluator_version', CanonicalString(evaluatorVersion)),
  ]);
}

sealed class Position {
  const Position();
  CanonicalObject toWire();
  static Position fromWire(CanonicalValue value) {
    if (value is! CanonicalObject) {
      throw const FormatException('Expected variant object');
    }
    final kind = wireString(
      value.fields
          .firstWhere(
            (e) => e.key == 'kind',
            orElse: () => throw const FormatException('Missing kind'),
          )
          .value,
    );
    return switch (kind) {
      'not_applicable' => NotApplicablePosition.fromWire(value),
      'unknown' => UnknownPosition.fromWire(value),
      'work_position' => WorkPosition.fromWire(value),
      _ => throw const FormatException('Unknown variant'),
    };
  }
}

final class NotApplicablePosition extends Position {
  const NotApplicablePosition();
  factory NotApplicablePosition.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'kind'});
    if (f.string('kind') != 'not_applicable') {
      throw const FormatException('Wrong variant');
    }
    return NotApplicablePosition();
  }
  @override
  CanonicalObject toWire() =>
      CanonicalObject([MapEntry('kind', CanonicalString('not_applicable'))]);
}

final class UnknownPosition extends Position {
  const UnknownPosition({required this.reason});
  final String reason;
  factory UnknownPosition.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'reason', 'kind'});
    if (f.string('kind') != 'unknown') {
      throw const FormatException('Wrong variant');
    }
    return UnknownPosition(reason: wireString(f.require('reason')));
  }
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('kind', CanonicalString('unknown')),
    MapEntry('reason', CanonicalString(reason)),
  ]);
}

final class WorkPosition extends Position {
  WorkPosition({
    required this.workEdition,
    required this.sceneId,
    required BigInt ordinal,
  }) : ordinal = checkedU64(ordinal);
  final AssessmentVersionRef workEdition;
  final String sceneId;
  final BigInt ordinal;
  factory WorkPosition.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'work_edition',
      'scene_id',
      'ordinal',
      'kind',
    });
    if (f.string('kind') != 'work_position') {
      throw const FormatException('Wrong variant');
    }
    return WorkPosition(
      workEdition: AssessmentVersionRef.fromWire(f.require('work_edition')),
      sceneId: wireString(f.require('scene_id')),
      ordinal: f.u64('ordinal'),
    );
  }
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('kind', CanonicalString('work_position')),
    MapEntry('work_edition', workEdition.toWire()),
    MapEntry('scene_id', CanonicalString(sceneId)),
    MapEntry('ordinal', CanonicalNumber(ordinal.toString())),
  ]);
}

sealed class SemanticMapping {
  const SemanticMapping();
  CanonicalObject toWire();
  static SemanticMapping fromWire(CanonicalValue value) {
    if (value is! CanonicalObject) {
      throw const FormatException('Expected variant object');
    }
    final kind = wireString(
      value.fields
          .firstWhere(
            (e) => e.key == 'kind',
            orElse: () => throw const FormatException('Missing kind'),
          )
          .value,
    );
    return switch (kind) {
      'claim' => ClaimSemanticMapping.fromWire(value),
      'action' => ActionSemanticMapping.fromWire(value),
      'knowledge' => KnowledgeSemanticMapping.fromWire(value),
      'source_description' => SourceDescriptionSemanticMapping.fromWire(value),
      _ => throw const FormatException('Unknown variant'),
    };
  }
}

final class ClaimSemanticMapping extends SemanticMapping {
  ClaimSemanticMapping({
    required this.predicate,
    required this.subject,
    required this.value,
    required Iterable<RoleParticipant> roles,
    required this.polarity,
  }) : roles = List.unmodifiable(roles);
  final AssessmentVersionRef predicate;
  final AssessmentVersionRef subject;
  final DomainValue value;
  final List<RoleParticipant> roles;
  final Polarity polarity;
  factory ClaimSemanticMapping.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'predicate',
      'subject',
      'value',
      'roles',
      'polarity',
      'kind',
    });
    if (f.string('kind') != 'claim') {
      throw const FormatException('Wrong variant');
    }
    return ClaimSemanticMapping(
      predicate: AssessmentVersionRef.fromWire(f.require('predicate')),
      subject: AssessmentVersionRef.fromWire(f.require('subject')),
      value: DomainValue.fromWire(f.require('value')),
      roles: f.array('roles').map((v) => RoleParticipant.fromWire(v)),
      polarity: Polarity.fromWire(f.require('polarity')),
    );
  }
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('kind', CanonicalString('claim')),
    MapEntry('predicate', predicate.toWire()),
    MapEntry('subject', subject.toWire()),
    MapEntry('value', value.toWire()),
    MapEntry('roles', CanonicalArray(roles.map((v) => v.toWire()))),
    MapEntry('polarity', polarity.toWire()),
  ]);
}

final class ActionSemanticMapping extends SemanticMapping {
  ActionSemanticMapping({
    required this.action,
    required Iterable<RoleParticipant> participants,
    required Iterable<AssessmentVersionRef> prerequisites,
    required Iterable<AssessmentVersionRef> effects,
  }) : participants = List.unmodifiable(participants),
       prerequisites = List.unmodifiable(prerequisites),
       effects = List.unmodifiable(effects);
  final AssessmentVersionRef action;
  final List<RoleParticipant> participants;
  final List<AssessmentVersionRef> prerequisites;
  final List<AssessmentVersionRef> effects;
  factory ActionSemanticMapping.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'action',
      'participants',
      'prerequisites',
      'effects',
      'kind',
    });
    if (f.string('kind') != 'action') {
      throw const FormatException('Wrong variant');
    }
    return ActionSemanticMapping(
      action: AssessmentVersionRef.fromWire(f.require('action')),
      participants: f
          .array('participants')
          .map((v) => RoleParticipant.fromWire(v)),
      prerequisites: f
          .array('prerequisites')
          .map((v) => AssessmentVersionRef.fromWire(v)),
      effects: f.array('effects').map((v) => AssessmentVersionRef.fromWire(v)),
    );
  }
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('kind', CanonicalString('action')),
    MapEntry('action', action.toWire()),
    MapEntry(
      'participants',
      CanonicalArray(participants.map((v) => v.toWire())),
    ),
    MapEntry(
      'prerequisites',
      CanonicalArray(prerequisites.map((v) => v.toWire())),
    ),
    MapEntry('effects', CanonicalArray(effects.map((v) => v.toWire()))),
  ]);
}

final class KnowledgeSemanticMapping extends SemanticMapping {
  KnowledgeSemanticMapping({
    required this.holder,
    required this.content,
    required Iterable<AssessmentVersionRef> acquisition,
  }) : acquisition = List.unmodifiable(acquisition);
  final AssessmentVersionRef holder;
  final AssessmentVersionRef content;
  final List<AssessmentVersionRef> acquisition;
  factory KnowledgeSemanticMapping.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'holder', 'content', 'acquisition', 'kind'});
    if (f.string('kind') != 'knowledge') {
      throw const FormatException('Wrong variant');
    }
    return KnowledgeSemanticMapping(
      holder: AssessmentVersionRef.fromWire(f.require('holder')),
      content: AssessmentVersionRef.fromWire(f.require('content')),
      acquisition: f
          .array('acquisition')
          .map((v) => AssessmentVersionRef.fromWire(v)),
    );
  }
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('kind', CanonicalString('knowledge')),
    MapEntry('holder', holder.toWire()),
    MapEntry('content', content.toWire()),
    MapEntry('acquisition', CanonicalArray(acquisition.map((v) => v.toWire()))),
  ]);
}

final class SourceDescriptionSemanticMapping extends SemanticMapping {
  SourceDescriptionSemanticMapping({
    required this.subject,
    required this.depiction,
    required Iterable<AssessmentVersionRef> impliedClaims,
  }) : impliedClaims = List.unmodifiable(impliedClaims);
  final AssessmentVersionRef subject;
  final Depiction depiction;
  final List<AssessmentVersionRef> impliedClaims;
  factory SourceDescriptionSemanticMapping.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'subject',
      'depiction',
      'implied_claims',
      'kind',
    });
    if (f.string('kind') != 'source_description') {
      throw const FormatException('Wrong variant');
    }
    return SourceDescriptionSemanticMapping(
      subject: AssessmentVersionRef.fromWire(f.require('subject')),
      depiction: Depiction.fromName(wireString(f.require('depiction'))),
      impliedClaims: f
          .array('implied_claims')
          .map((v) => AssessmentVersionRef.fromWire(v)),
    );
  }
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('kind', CanonicalString('source_description')),
    MapEntry('subject', subject.toWire()),
    MapEntry('depiction', CanonicalString(depiction.wireName)),
    MapEntry(
      'implied_claims',
      CanonicalArray(impliedClaims.map((v) => v.toWire())),
    ),
  ]);
}
