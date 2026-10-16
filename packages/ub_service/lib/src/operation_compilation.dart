import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_rules/ub_rules.dart';
import 'package:ub_store/ub_store.dart';

import 'event_compilation.dart';
import 'instance_initialization.dart';
import 'operation_lowering.dart';
import 'universe_policy_compilation.dart';

InvalidArgumentError _invalid(String message) =>
    InvalidArgumentError(field: 'operations', message: message);
UnsupportedSemanticsError _unsupported() => const UnsupportedSemanticsError(
  message: 'operation requires event/knowledge/pack semantics outside the basic authoring evaluator',
);
final _nonWhitespace = RegExp(
  r'[^\u0009-\u000d\u0020\u0085\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000]',
);
bool _blank(String s) => !_nonWhitespace.hasMatch(s);
bool _sameWire(CanonicalValue? a, CanonicalValue? b) =>
    a?.toText() == b?.toText();
bool _sameList<T>(List<T> a, List<T> b) =>
    a.length == b.length &&
    Iterable<int>.generate(a.length).every((i) => a[i] == b[i]);
StoredVersion _stored(RecordVersion r) => StoredVersion(
  versionId: r.recordVersionId,
  identity: r.identity,
  payload: r.payload.toWire(),
  digest: r.payloadDigest,
);
RecordVersion _version(
  UniverseId u,
  RecordId id,
  RecordPayload p, [
  RecordVersionId? allocated,
]) => RecordVersion.build(
  recordVersionId: allocated ?? RecordVersionId.generate(),
  identity: RecordIdentity(
    universeId: u,
    recordId: id,
    recordKind: p.recordKind,
  ),
  payload: p,
);
RecordVersion _current(
  Map<RecordId, RecordVersion> records,
  UniverseId u,
  RecordRef reference,
  RecordVersionId expected,
) {
  if (reference.universe != u) {
    throw _invalid('explicit local universe is required');
  }
  final v = records[reference.record];
  if (v == null) {
    throw _invalid('record unavailable');
  }
  if (v.recordVersionId != expected) {
    throw _invalid('expected record version differs');
  }
  return v;
}

CalendarId? _clock(TemporalExpression? t) => t is ExactTime ? t.calendar : null;
CalendarId? _validityClock(Validity v) => switch (v) {
  CalendarIntervalValidity(:final calendar) => calendar,
  InstantValidity(:final at) => _clock(at),
  _ => null,
};
EventRecord _event(EventRecord e) => EventRecord(
  occurrence: e.occurrence,
  action: e.action,
  worlds: e.worlds,
  region: e.region,
  time: e.time,
  sequence: e.sequence,
  occurrenceId: e.occurrenceId,
  participants: e.participants,
  preconditions: e.preconditions,
  effects: e.effects,
  labels: e.labels,
  expansionVersion: eventExpansionVersion,
  basis: e.basis,
);

/// Prepares exact versioned changes. This grants no admission or approval rights
/// and never writes canon; callers bind the returned changes into exact review.
List<Assignment> compileOperations({
  required UniverseId universe,
  required RevisionId revision,
  required List<RecordVersion> base,
  required List<DomainOperation> operations,
}) => compileAllocatedOperations(
  universe: universe,
  revision: revision,
  base: base,
  operations: operations,
  versions: const {},
);

/// Internal service preparation for privately allocated immutable source versions.
/// These allocations must never be accepted as an ordinary client operation.
List<Assignment> compileAllocatedOperations({
  required UniverseId universe,
  required RevisionId revision,
  required List<RecordVersion> base,
  required List<DomainOperation> operations,
  required Map<RecordId, RecordVersionId> versions,
}) {
  final lowered = lowerAuthoringOperations(
    universe: universe,
    base: base,
    operations: operations,
  );
  final records = {for (final r in base) r.identity.recordId: r};
  final changes = <Assignment>[], seen = <String>{};
  void create(String name, RecordPayload payload) {
    if (name.isEmpty || !seen.add(name)) {
      throw _invalid('duplicate or empty client_ref');
    }
    RecordId id;
    try {
      id = RecordId.parse(name);
    } on FormatException {
      id = RecordId.generate();
    }
    if (records.containsKey(id)) {
      throw _invalid('new record identity already exists');
    }
    changes.add(
      Assignment(
        recordId: id,
        next: _stored(_version(universe, id, payload, versions[id])),
      ),
    );
  }

  for (final op in lowered) {
    if (op is DefineUniversePolicyOperation) {
      if (!seen.add(op.clientRef)) {
        throw _invalid('duplicate client_ref');
      }
      changes.addAll(
        compileUniversePolicy(universe: universe, base: base, operation: op),
      );
      continue;
    }
    final (String, RecordPayload)? creation = switch (op) {
      CreateEntityOperation() => (op.clientRef, op.record),
      CreateWorldOperation() => (op.clientRef, op.record),
      CreateWorkOperation() => (op.clientRef, op.record),
      CreateSagaOperation() => (op.clientRef, op.record),
      DefineTypeOperation() => (op.clientRef, op.record),
      DefinePropertyOperation() => (op.clientRef, op.record),
      DefineRelationOperation() => (op.clientRef, op.record),
      DefineUnitOperation() => (op.clientRef, op.record),
      DefineCalendarOperation() => (op.clientRef, op.record),
      DefineValueOperation() => (op.clientRef, op.record),
      DefineRuleOperation() => (op.clientRef, op.record),
      SetCompletenessOperation() => (op.clientRef, op.record),
      SetCreativeBoundaryOperation() => (op.clientRef, op.record),
      AddExceptionOperation() => (op.clientRef, op.record),
      AddSourceAnchorOperation() => (op.clientRef, op.record),
      CreateSecretOperation() => (op.clientRef, op.record),
      CreateAppearanceOperation() => (op.clientRef, op.record),
      AddImageAssetOperation() => (op.clientRef, op.record),
      DefineItemPowerOperation() => (op.clientRef, op.record),
      DefineActionOperation() => (op.clientRef, op.record),
      DefinePropositionOperation() => (op.clientRef, op.record),
      RecordEventOperation() => (op.clientRef, _event(op.record)),
      AddBeliefOperation() => (op.clientRef, op.record),
      RecordObservationOperation() => (op.clientRef, op.record),
      RecordCommunicationOperation() => (op.clientRef, op.record),
      RecordMemoryOperation() => (op.clientRef, op.record),
      RecordPlanOperation() => (op.clientRef, op.record),
      RecordCommitmentOperation() => (op.clientRef, op.record),
      RecordIssueDecisionOperation() => (op.clientRef, op.record),
      InstallPackOperation() => (op.clientRef, op.record),
      _ => null,
    };
    if (creation != null) {
      create(creation.$1, creation.$2);
      continue;
    }
    switch (op) {
      case RecordNarrativeReferenceOperation():
        if (op.record != op.payload.recordKind ||
            !(op.payload is RepresentedContextRecord ||
                op.payload is SourceRecord ||
                op.payload is SourceVersionRecord ||
                op.payload is WorkVersionRecord ||
                op.payload is SceneRecord ||
                op.payload is PassageRecord)) {
          throw _invalid(
            'narrative reference kind is not a narrative/source/context payload',
          );
        }
        create(op.clientRef, op.payload);
      case AssertPropositionOperation(
            :final clientRef,
            :final proposition,
            :final assertion,
          ) ||
          RecordRelationOperation(
            :final clientRef,
            :final proposition,
            :final assertion,
          ):
        if (assertion.basis is InstanceInitializationBasis) {
          throw _invalid(
            'initialization evidence requires initialize_instance',
          );
        }
        RecordId reserved;
        try {
          reserved = RecordId.parse(clientRef);
        } on FormatException {
          throw _invalid('proposition client_ref must reserve a rec_ ID');
        }
        if (assertion.proposition !=
            RecordRef(universe: universe, record: reserved)) {
          throw _invalid("assertion must name this batch's proposition");
        }
        create(clientRef, proposition);
        create('$clientRef:assertion', assertion);
      case InitializeInstanceOperation() ||
          ReviseSecretOperation() ||
          ReviseAppearanceOperation() ||
          ReviseDefinitionOperation() ||
          ReviseItemPowerOperation() ||
          ReviseAttitudeOperation() ||
          ReviseCommunicationOperation() ||
          ReviseInterpretationOperation() ||
          ReviseSceneOperation() ||
          AdoptRecordVersionOperation() ||
          ReviseEventOperation() ||
          WithdrawEventOperation() ||
          UpgradePackOperation() ||
          SetStoryTimeOperation() ||
          AddNameOperation() ||
          AddTypeMembershipOperation() ||
          RenameWorldSelectorOperation() ||
          AddWorldAliasOperation() ||
          SetWorkBindingOperation() ||
          AssociateWorkWorldOperation() ||
          SetSagaMembershipOperation() ||
          EndAssertionAtOperation() ||
          SupersedeAssertionOperation() ||
          RetractAssertionOperation() ||
          TombstoneRecordOperation():
        break;
      default:
        throw _unsupported();
    }
  }
  final created = {
    for (final c in changes)
      c.recordId: RecordVersion.fromWire(c.next!.toCanonical()),
  };
  final ancestry = {...records, ...created};
  // Refinements inspect all candidate definition changes, regardless of order.
  for (final op in lowered) {
    switch (op) {
      case ReviseDefinitionOperation() when op.replacement is EntityTypeRecord:
        final old = _current(records, universe, op.record, op.expectedVersion);
        ancestry[op.record.record] = RecordVersion(
          recordVersionId: old.recordVersionId,
          identity: old.identity,
          payload: op.replacement,
          payloadDigest: old.payloadDigest,
        );
      case AdoptRecordVersionOperation()
          when op.source.payload is EntityTypeRecord:
        ancestry[op.source.identity.recordId] = op.source;
      case TombstoneRecordOperation():
        ancestry.remove(op.record.record);
      default:
        break;
    }
  }
  for (final op in lowered) {
    final edit = _edit(op, universe, records, created, ancestry);
    if (edit == null) {
      continue;
    }
    final (ref, expected, payload) = edit;
    changes.add(
      Assignment(
        recordId: ref.record,
        expected: expected,
        next: payload == null
            ? null
            : _stored(_version(universe, ref.record, payload)),
      ),
    );
  }
  for (final op in lowered) {
    if (op is! AdoptRecordVersionOperation) {
      continue;
    }
    final source = op.source;
    if (source.identity.universeId != universe || !source.verifiesDigest) {
      throw _invalid('adoption source has invalid identity or digest');
    }
    if (records[source.identity.recordId]?.recordVersionId !=
        op.expectedVersion) {
      throw _invalid('adoption target version changed');
    }
    changes.add(
      Assignment(
        recordId: source.identity.recordId,
        expected: op.expectedVersion,
        next: _stored(
          _version(universe, source.identity.recordId, source.payload),
        ),
      ),
    );
  }
  compileInitializations(
    universe: universe,
    revision: revision,
    base: base,
    operations: lowered,
    changes: changes,
  );
  synchronizeUniversePolicySelection(
    universe: universe,
    base: base,
    changes: changes,
  );
  freezeEventEffects(universe: universe, base: base, changes: changes);
  return List.unmodifiable(changes);
}

(RecordRef, RecordVersionId, RecordPayload?)? _edit(
  DomainOperation op,
  UniverseId universe,
  Map<RecordId, RecordVersion> records,
  Map<RecordId, RecordVersion> created,
  Map<RecordId, RecordVersion> ancestry,
) {
  RecordPayload current(RecordRef ref, RecordVersionId expected) =>
      _current(records, universe, ref, expected).payload;
  PropositionRecord? proposition(RecordRef ref) {
    if (ref.universe != null && ref.universe != universe) {
      return null;
    }
    final p = (records[ref.record] ?? created[ref.record])?.payload;
    return p is PropositionRecord ? p : null;
  }

  switch (op) {
    case ReviseSecretOperation():
      if (current(op.record, op.expectedVersion) is! SecretRecord) {
        throw _invalid('expected story secret');
      }
      return (op.record, op.expectedVersion, op.replacement);
    case ReviseAppearanceOperation():
      if (current(op.record, op.expectedVersion) is! AppearanceRecord) {
        throw _invalid('expected appearance');
      }
      return (op.record, op.expectedVersion, op.replacement);
    case ReviseEventOperation():
      if (current(op.record, op.expectedVersion) is! EventRecord) {
        throw _invalid('expected event');
      }
      return (op.record, op.expectedVersion, _event(op.replacement));
    case ReviseCommunicationOperation():
      final old = current(op.record, op.expectedVersion), next = op.replacement;
      if (old is! CommunicationRecord) {
        throw _invalid('expected historical communication');
      }
      if (_blank(op.rationale)) {
        throw _invalid('Explain the historical message correction');
      }
      if (_clock(old.sentAt) != null &&
          _clock(old.sentAt) != _clock(next.sentAt)) {
        throw _invalid("Retain the message's authored sent calendar");
      }
      if (old.receivedAt != null &&
          next.receivedAt != null &&
          _clock(old.receivedAt) != null &&
          _clock(old.receivedAt) != _clock(next.receivedAt)) {
        throw _invalid("Retain the message's authored receipt calendar");
      }
      return (op.record, op.expectedVersion, next);
    case ReviseSceneOperation():
      final old = current(op.record, op.expectedVersion), next = op.replacement;
      if (old is! SceneRecord) {
        throw _invalid('expected scene');
      }
      if (_blank(op.rationale) ||
          old.sceneId != next.sceneId ||
          old.workVersion != next.workVersion ||
          !_sameList(old.worldAssociations, next.worldAssociations)) {
        throw _invalid(
          'Scene correction requires a reason and preserves identity, edition and worlds',
        );
      }
      return (op.record, op.expectedVersion, next);
    case ReviseInterpretationOperation():
      final old = current(op.record, op.expectedVersion);
      if (old is! EpistemicAttitudeRecord) {
        throw _invalid('expected recorded knowledge');
      }
      if (old.attitude != EpistemicAttitudeKind.knows || _blank(op.rationale)) {
        throw _invalid(
          'Interpretation correction requires existing knowledge and an author reason',
        );
      }
      final acquisition = old.acquisition;
      if (acquisition == null) {
        throw _invalid('No justified receipt acquisition to correct');
      }
      final basis = acquisition.basis;
      if (basis is! CommunicationKnowledge) {
        throw _invalid(
          'Only justified communication receipt interpretation is editable here',
        );
      }
      final interpretation = op.interpretation;
      if (interpretation != null &&
          proposition(interpretation)?.context != acquisition.truthContext) {
        throw _invalid(
          'Select an interpretation claim in the original acquisition context',
        );
      }
      final next = EpistemicAttitudeRecord(
        holder: old.holder,
        proposition: interpretation ?? old.proposition,
        attitude: old.attitude,
        certainty: old.certainty,
        validity: old.validity,
        basis: old.basis,
        acquisition: KnowledgeAcquisition(
          truthContext: acquisition.truthContext,
          time: acquisition.time,
          world: acquisition.world,
          basis: CommunicationKnowledge(
            communication: basis.communication,
            interpretation: interpretation,
          ),
        ),
      );
      return (op.record, op.expectedVersion, next);
    case ReviseAttitudeOperation():
      final old = current(op.record, op.expectedVersion), next = op.replacement;
      if (old is! EpistemicAttitudeRecord) {
        throw _invalid('expected recorded epistemic attitude');
      }
      if (_blank(op.rationale) ||
          old.holder != next.holder ||
          old.attitude != next.attitude ||
          !_sameWire(old.acquisition?.toWire(), next.acquisition?.toWire()) ||
          old.basis != next.basis) {
        throw _invalid(
          'Attitude correction must retain stance, holder, acquisition and basis and include a reason',
        );
      }
      if (old.attitude == EpistemicAttitudeKind.knows &&
          (old.proposition != next.proposition ||
              old.certainty != next.certainty)) {
        throw _invalid(
          'Knowledge corrections can change duration only; they cannot substitute a claim or manufacture acquisition evidence',
        );
      }
      if (old.proposition != next.proposition) {
        final before = proposition(old.proposition),
            after = proposition(next.proposition);
        if (before == null || after == null) {
          throw _invalid('Retrieve both attributed claims');
        }
        final corrected = PropositionRecord(
          subject: before.subject,
          predicate: before.predicate,
          roles: before.roles,
          value: after.value,
          quantification: before.quantification,
          context: before.context,
        );
        if (corrected != after) {
          throw _invalid(
            'An attributed claim correction changes its value only; subject, property, roles, polarity and truth context stay unchanged',
          );
        }
      }
      if (_validityClock(old.validity) != null &&
          _validityClock(old.validity) != _validityClock(next.validity)) {
        throw _invalid("Retain the attitude's authored calendar");
      }
      return (op.record, op.expectedVersion, next);
    case ReviseItemPowerOperation():
      final old = current(op.record, op.expectedVersion), next = op.replacement;
      if (old is! ItemPowerRecord) {
        throw _invalid('expected item-power declaration');
      }
      if (_blank(op.rationale) ||
          old.item != next.item ||
          old.holderPredicate != next.holderPredicate ||
          old.powerPredicate != next.powerPredicate ||
          old.scope.context != next.scope.context) {
        throw _invalid(
          'item-power correction requires a reason and must retain item, holder property, ability property and represented context',
        );
      }
      if (_validityClock(old.validity) != null &&
          _validityClock(old.validity) != _validityClock(next.validity)) {
        throw _invalid(
          'item-power correction must retain its authored calendar',
        );
      }
      return (op.record, op.expectedVersion, next);
    case ReviseDefinitionOperation():
      final old = current(op.record, op.expectedVersion), next = op.replacement;
      if (old.recordKind != next.recordKind ||
          !(old is EntityTypeRecord ||
              old is PropertyRecord ||
              old is RelationRecord ||
              old is UnitRecord ||
              old is CalendarRecord ||
              old is ValueDefinitionRecord ||
              old is RuleRecord ||
              old is ActionDefinitionRecord)) {
        throw _invalid('only a same-kind definition can be revised');
      }
      final a = {for (final f in old.toWire().fields) f.key: f.value},
          b = {for (final f in next.toWire().fields) f.key: f.value};
      if (!_sameWire(a['namespace'], b['namespace']) ||
          !_sameWire(a['key'], b['key'])) {
        throw _invalid('definition revision must retain namespace and key');
      }
      return (op.record, op.expectedVersion, next);
    case UpgradePackOperation():
      final old = current(op.record, op.expectedVersion), next = op.replacement;
      if (old is! DomainPackRecord) {
        throw _invalid('expected domain pack');
      }
      if (old.key != next.key || old.version == next.version) {
        throw _invalid('pack upgrade must retain key and change version');
      }
      return (op.record, op.expectedVersion, next);
    case AddNameOperation():
      final old = current(op.record, op.expectedVersion);
      if (old is! EntityRecord) {
        throw _invalid('expected entity');
      }
      return (
        op.record,
        op.expectedVersion,
        EntityRecord(
          names: [...old.names, op.name],
          classification: old.classification,
          classificationResolution: old.classificationResolution,
          worldAssociations: old.worldAssociations,
          labels: old.labels,
          metadata: old.metadata,
        ),
      );
    case AddTypeMembershipOperation():
      final old = current(op.record, op.expectedVersion);
      if (old is! EntityRecord) {
        throw _invalid('expected entity');
      }
      if (old.classificationResolution == ClassificationResolution.ambiguous) {
        throw _invalid(
          'ambiguous classification requires an explicit authored correction',
        );
      }
      final target = ancestry[op.entityType]?.payload;
      if (target is! EntityTypeRecord ||
          target.parentResolution == ParentResolution.ambiguous) {
        throw _invalid('refinement requires a resolved definition');
      }
      if (old.classification != null) {
        RecordId? id = op.entityType;
        final seen = <RecordId>{};
        var refinement = false;
        while (id != null) {
          if (id == old.classification) {
            refinement = true;
            break;
          }
          if (!seen.add(id)) {
            break;
          }
          final t = ancestry[id]?.payload;
          id =
              t is EntityTypeRecord &&
                  t.parentResolution != ParentResolution.ambiguous
              ? t.parent
              : null;
        }
        if (!refinement) {
          throw _invalid(
            'classification change is not a descendant refinement; use an explicit authored correction',
          );
        }
      }
      return (
        op.record,
        op.expectedVersion,
        EntityRecord(
          names: old.names,
          classification: op.entityType,
          classificationResolution: ClassificationResolution.resolved,
          worldAssociations: old.worldAssociations,
          labels: old.labels,
          metadata: old.metadata,
        ),
      );
    case RenameWorldSelectorOperation(
      :final record,
      :final expectedVersion,
      :final newSelector,
    ):
      final old = current(record, expectedVersion);
      if (old is! WorldRecord) {
        throw _invalid('expected world');
      }
      return (
        record,
        expectedVersion,
        WorldRecord(
          selector: newSelector,
          aliases: [...old.aliases, old.selector],
          settingType: old.settingType,
          labels: old.labels,
          metadata: old.metadata,
        ),
      );
    case AddWorldAliasOperation(
      :final record,
      :final expectedVersion,
      :final alias,
    ):
      final old = current(record, expectedVersion);
      if (old is! WorldRecord) {
        throw _invalid('expected world');
      }
      return (
        record,
        expectedVersion,
        WorldRecord(
          selector: old.selector,
          aliases: [...old.aliases, alias],
          settingType: old.settingType,
          labels: old.labels,
          metadata: old.metadata,
        ),
      );
    case SetWorkBindingOperation():
      final old = current(op.record, op.expectedVersion);
      if (old is! WorkVersionRecord) {
        throw _invalid('expected work version');
      }
      return (
        op.record,
        op.expectedVersion,
        WorkVersionRecord(
          work: old.work,
          versionLabel: old.versionLabel,
          binding: op.binding,
        ),
      );
    case AssociateWorkWorldOperation():
      final old = current(op.record, op.expectedVersion);
      if (old is! WorkRecord) {
        throw _invalid('expected work');
      }
      return (
        op.record,
        op.expectedVersion,
        WorkRecord(
          kind: old.kind,
          title: old.title,
          labels: old.labels,
          sourceRefs: old.sourceRefs,
          versions: old.versions,
          worldAssociations: [...old.worldAssociations, op.association],
        ),
      );
    case SetSagaMembershipOperation():
      final old = current(op.record, op.expectedVersion);
      if (old is! SagaRecord) {
        throw _invalid('expected saga');
      }
      if (op.membership.work.universe != universe) {
        throw _invalid('membership must name a work in this universe');
      }
      final memberships = [...old.memberships],
          i = old.memberships.indexWhere(
            (m) => m.work == op.membership.work && m.role == op.membership.role,
          );
      if (i < 0) {
        memberships.add(op.membership);
      } else {
        memberships[i] = op.membership;
      }
      return (
        op.record,
        op.expectedVersion,
        SagaRecord(
          title: old.title,
          labels: old.labels,
          memberships: memberships,
        ),
      );
    case SupersedeAssertionOperation():
      if (current(op.record, op.expectedVersion) is! AssertionRecord) {
        throw _invalid('expected assertion');
      }
      return (op.record, op.expectedVersion, op.replacement);
    case RetractAssertionOperation():
      if (current(op.record, op.expectedVersion) is! AssertionRecord) {
        throw _invalid('expected assertion');
      }
      if (_blank(op.rationale)) {
        throw _invalid('explain the assertion retraction');
      }
      return (op.record, op.expectedVersion, null);
    case WithdrawEventOperation():
      final old = current(op.record, op.expectedVersion);
      if (old is! EventRecord ||
          old.occurrence is! SimpleOccurrence ||
          (old.occurrence as SimpleOccurrence).kind !=
              OccurrenceKind.occurred) {
        throw _invalid('withdrawal requires an occurred event');
      }
      if (_blank(op.rationale)) {
        throw _invalid('explain the occurrence withdrawal');
      }
      return (op.record, op.expectedVersion, null);
    case TombstoneRecordOperation():
      current(op.record, op.expectedVersion);
      return (op.record, op.expectedVersion, null);
    case SetStoryTimeOperation():
      final old = current(op.record, op.expectedVersion);
      if (old is! RepresentedContextRecord) {
        throw _invalid('expected represented context');
      }
      final chronology = old.chronology;
      if (chronology == null) {
        throw _invalid('this context needs an authored starting chronology');
      }
      Chronology next;
      try {
        next = chronology.change(op.value, op.mode, op.reason);
      } on FormatException catch (e) {
        throw _invalid(e.message);
      }
      return (
        op.record,
        op.expectedVersion,
        RepresentedContextRecord(
          universe: old.universe,
          kind: old.kind,
          parent: old.parent,
          chronology: next,
          labels: old.labels,
        ),
      );
    case EndAssertionAtOperation():
      final old = current(op.record, op.expectedVersion);
      if (old is! AssertionRecord) {
        throw _invalid('expected assertion');
      }
      final at = op.at;
      if (at is! ExactTime) {
        throw _invalid(
          'ending an assertion requires an exact authored-clock instant',
        );
      }
      final validity = old.validity;
      if (validity is! CalendarIntervalValidity) {
        throw _unsupported();
      }
      if (at.calendar != validity.calendar ||
          temporalApplies(validity, AtFrameTime(at)) != true) {
        if (at.calendar != validity.calendar ||
            validity.end is! ExactBound ||
            (validity.end as ExactBound).value != at.value) {
          throw _invalid(
            "end must be within the assertion's declared interval and calendar",
          );
        }
      }
      return (
        op.record,
        op.expectedVersion,
        AssertionRecord(
          attributeMode: old.attributeMode,
          proposition: old.proposition,
          polarity: old.polarity,
          scope: old.scope,
          validity: CalendarIntervalValidity(
            validity.calendar,
            validity.start,
            ExactBound(at.value),
          ),
          persistence: old.persistence,
          precision: old.precision,
          alternatives: old.alternatives,
          basis: op.basis,
          establishedBy: old.establishedBy,
        ),
      );
    default:
      return null;
  }
}
