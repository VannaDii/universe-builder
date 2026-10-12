import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/ub_store.dart' show recordWorld;

import 'proposal_authorization.dart';

Description discoveryDescription({
  required List<RecordVersion> records,
  required Set<RecordId> visibility,
  bool definitions = false,
  WorldId? focus,
  Iterable<ContinuitySummary> continuities = const [],
}) => Description(
  fixture: false,
  worlds: [
    for (final row in records)
      if (visibility.contains(row.identity.recordId) &&
          row.payload is WorldRecord)
        WorldSummary(
          id: recordWorld(row.identity.recordId),
          name: Selector((row.payload as WorldRecord).selector),
        ),
  ],
  definitionIds: [
    if (definitions)
      for (final row in records)
        if (visibility.contains(row.identity.recordId) &&
            protectedRecord(row.payload) &&
            (focus == null ||
                recordWorlds(row).isEmpty ||
                recordWorlds(row).contains(focus)))
          row.identity.recordId,
  ],
  continuities: continuities,
  capabilities: serviceCapabilities(),
);

/// A continuity with no accessible represented context is not discoverable.
ContinuitySummary? discoveryContinuity({
  required ContinuityId id,
  required RevisionId revision,
  required String name,
  required List<RecordVersion> records,
  required Set<WorldId>? worldScope,
}) {
  final visibility = visibleRecordIds(records: records, worldScope: worldScope);
  final contexts = [
    for (final row in records)
      if (visibility.contains(row.identity.recordId) &&
          row.payload is RepresentedContextRecord)
        RepresentedContextSummary(
          id: row.identity.recordId,
          kind: (row.payload as RepresentedContextRecord).kind,
          labels: (row.payload as RepresentedContextRecord).labels,
        ),
  ];
  if (contexts.isEmpty) return null;
  return ContinuitySummary(
    id: id,
    revisionId: revision,
    name: name,
    representedContexts: contexts,
  );
}

/// Factual capabilities of the Dart service, with unfinished native routes
/// explicitly distinguished from the already ported evaluator behavior.
List<Capability> serviceCapabilities() => List.unmodifiable([
  Capability(
    id: "relations.cardinality.v1",
    status: CapabilityStatus.implemented,
    limitation: "Opt-in authored maximum counts distinct participants across supported relation instances for a grouping key, overlapping world/context/realm and exact same-clock time. Repeated evidence is deduplicated. Unknown scope/time, opposing evidence and ambiguous grouping remain unresolved. No minima, completeness inference or clock conversion.",
  ),
  Capability(
    id: "communications.chronology.v1",
    status: CapabilityStatus.implemented,
    limitation: "Opt-in channel contracts enforce forward transmission and inclusive signed delay bounds on same-clock exact integer ticks. Missing rules, absent actual delivery and unmapped/nonexact clocks remain unresolved once activated. No inferred delivery, conversions or knowledge.",
  ),
  Capability(
    id: "source_assessment.v1",
    status: CapabilityStatus.partial,
    limitation: "Authenticated immutable attachment and generation-checked selection through universe_propose. Pinned permission-checked assessment retrieval and shared author review are available. Exact assessment or absence and selection generation bind validation, approval and atomic commit. Native interaction and prose qualification remain unavailable.",
  ),
  Capability(
    id: "canon.commit.v1",
    status: CapabilityStatus.implemented,
    limitation: "Exact author approval or explicit expiring entity/predicate/continuity delegation; fresh complete validation and current grants required. Restricted results reveal no hidden findings: retrieve visible policy/evidence with universe_get_context or universe_get evidence, then request author validation of the exact proposal reference.",
  ),
  Capability(
    id: "opposing_evidence.v1",
    status: CapabilityStatus.implemented,
    limitation: "Candidate-wide polarity diagnostics and explicitly scoped NoOpposingEvidence policies. Unresolved comparisons remain partial; no prose or integrated-story qualification.",
  ),
  Capability(
    id: "basic.v1",
    status: CapabilityStatus.implemented,
    limitation: "Exact scalar, explicitly supplied finite collection and integer-tick temporal expressions; unsupported blocking checks fail admission. Collection cardinality does not aggregate dynamic relation instances; Communication chronology is separately opt-in through communications.chronology.v1.",
  ),
  Capability(
    id: "events.owner_attributes.v1",
    status: CapabilityStatus.implemented,
    limitation: "New/revised events require declared actions. Mandatory values resolve on exactly one participant per owning role at pre-event time; direct and explicit item grants share evidence. Missing, muted, conflicting and unsupported prerequisites block use. Legacy actionless events remain readable but are not certified; prose/action classification still requires author review.",
  ),
  Capability(
    id: "events.v1",
    status: CapabilityStatus.implemented,
    limitation: "Exact occurred-event effects, explicit within-event order, pre/post state and possession powers. Noncommuting effects from separate simultaneous events and complex causality are rejected.",
  ),
  Capability(
    id: "knowledge.acquisition.v1",
    status: CapabilityStatus.implemented,
    limitation: "Explicit context policy distinguishes author-established knowledge from justified interpreted communication receipt. Justified knowledge checks actual recipient, acquisition/onset order, authored channel chronology and supported proposition truth at acquisition. Missing interpretation, truth, comparable clocks or policy stays unresolved; observation acquisition and automatic understanding are unavailable.",
  ),
  Capability(
    id: "knowledge.explicit.v1",
    status: CapabilityStatus.implemented,
    limitation: "Explicit, time-bound holder attitudes in their represented context. Presence, sending and receipt do not infer knowledge. Without an applicable acquisition policy, legacy Knows remains an authored attitude, not a justified-knowledge certificate.",
  ),
  Capability(
    id: "perspective.views.v1",
    status: CapabilityStatus.implemented,
    limitation: "Character and narrator views require matching represented contexts. Reader views require an exact scene and explicit disclosures in its bound work edition. No automatic knowledge inference.",
  ),
  Capability(
    id: "history.v1",
    status: CapabilityStatus.partial,
    limitation: "Typed summaries, evidence and pinned record history; history is limited to 100 changes per record and unrestricted author-perspective reads. Native reviewed restoration remains unported.",
  ),
  Capability(
    id: "knowledge.inference",
    status: CapabilityStatus.unsupported,
    limitation: "Automatic perception, understanding, nested attitude inference and memory decay require explicit author records.",
  ),
  Capability(
    id: "resources.accounting.v1",
    status: CapabilityStatus.partial,
    limitation: "Author-configured single integer/decimal/exact-unit stock continuity. Unexplained changes require exact author issue acceptance; accepted quantities remain canon with unexplained arrival. Exact named-calendar objective evidence only.",
  ),
  Capability(
    id: "scoped.exceptions.v1",
    status: CapabilityStatus.partial,
    limitation: "Exact rule or boundary version with author acceptance and scope containment. Named-clock periods are partitioned at evidence and exception boundaries; original findings remain visible. Independent clocks and realm-dependent constraint inference remain unresolved.",
  ),
  Capability(
    id: "completeness.v1",
    status: CapabilityStatus.partial,
    limitation: "Exact objective membership and matching scope only; observer-known sets never close reality.",
  ),
  Capability(
    id: "impact.jobs.v1",
    status: CapabilityStatus.implemented,
    limitation: "Conservative full-universe dependency closure, durable queued validation, bound cursors and explicit work limits; no incremental result cache.",
  ),
  Capability(
    id: "continuities.packs.v1",
    status: CapabilityStatus.partial,
    limitation: "Exact-version data-pack dependencies and internal pinned fork storage are available. Service commands for fork and reviewed historical adoption remain unported. No automatic parent propagation.",
  ),
  Capability(
    id: "cross_calendar.causality",
    status: CapabilityStatus.unsupported,
    limitation: "No inferred synchronization, route, speed, travel feasibility or causality across independent clocks.",
  ),
  Capability(
    id: "appearance.references.v1",
    status: CapabilityStatus.partial,
    limitation: "Optional typed appearance records and image content storage are available. Text and metadata accompany context briefs; native image staging and pixel retrieval remain unported. Pixels do not imply facts or executable rules.",
  ),
  Capability(
    id: "descriptive.domain_records",
    status: CapabilityStatus.descriptiveOnly,
    limitation: "Custom domain data round-trips without acquiring executable laws from prose or labels.",
  ),
]);
