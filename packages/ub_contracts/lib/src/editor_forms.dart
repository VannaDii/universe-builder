import 'package:ub_domain/ub_domain.dart';

import 'wire.dart';
import 'property_forms.dart';

enum EditorRecoveryFailure {
  unavailable,
  incompatibleSchema,
  conflict,
  generationExhausted,
  invalidText,
}

final class EditorRecoveryException implements Exception {
  const EditorRecoveryException(this.failure);
  final EditorRecoveryFailure failure;
  @override
  String toString() => 'EditorRecoveryException(${failure.name})';
}

/// Client recovery belongs to this exact authenticated workspace. It grants no
/// authority to read canon, submit a proposal, approve or publish.
final class EditorFormScope {
  const EditorFormScope({
    required this.instance,
    required this.profile,
    required this.universe,
    required this.continuity,
    this.worldClientRef,
    this.representedContext,
    this.worldRecord,
    this.typeClientRef,
    this.entityClientRef,
    this.entityNameRecord,
    this.entityClassificationRecord,
    this.entityOperationIndex,
    this.attributeClientRef,
  });
  final OperationId instance;
  final ProfileId profile;
  final UniverseId universe;
  final ContinuityId continuity;

  /// Null is the new-world form. An edit has its own recovery slot, preserving
  /// other pending worlds and references supplied by external writers.
  final String? worldClientRef;
  final RecordId? representedContext;
  final RecordId? worldRecord;

  /// Null is creation; a draft definition reference identifies its edit slot.
  final String? typeClientRef;
  final String? entityClientRef;

  /// Published entity receiving a contextual name; separate from creation/edit slots.
  final RecordId? entityNameRecord;
  final RecordId? entityClassificationRecord;

  /// Null opens a published-record form; an index selects its edits in Changes.
  final int? entityOperationIndex;
  final String? attributeClientRef;
}

/// Entered fields can be incomplete or invalid. Completing an editor must build
/// and validate a domain operation separately; loading this never creates one.
final class UnfinishedWorldForm {
  UnfinishedWorldForm({
    required this.baseRevision,
    required this.representedContext,
    required this.record,
    required this.selector,
    required this.settingType,
    required this.rationale,
    Iterable<String> aliases = const [],
    Map<String, String> labels = const {},
    BigInt? draftVersion,
    this.expectedRecordVersion,
  }) : aliases = List.unmodifiable(aliases),
       labels = Map.unmodifiable(labels),
       draftVersion = draftVersion == null ? null : checkedU64(draftVersion);
  final RevisionId baseRevision;
  final RecordId representedContext, record;
  final String selector, settingType, rationale;
  final List<String> aliases;
  final Map<String, String> labels;
  final BigInt? draftVersion;
  final RecordVersionId? expectedRecordVersion;
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('base_revision', CanonicalString(baseRevision.value)),
    MapEntry('represented_context', CanonicalString(representedContext.value)),
    MapEntry('record', CanonicalString(record.value)),
    MapEntry('selector', CanonicalString(selector)),
    MapEntry('setting_type', CanonicalString(settingType)),
    MapEntry('rationale', CanonicalString(rationale)),
    if (draftVersion != null)
      MapEntry('draft_version', CanonicalString(draftVersion.toString())),
    if (expectedRecordVersion != null)
      MapEntry(
        'expected_record_version',
        CanonicalString(expectedRecordVersion!.value),
      ),
    MapEntry('aliases', CanonicalArray(aliases.map(CanonicalString.new))),
    MapEntry(
      'labels',
      CanonicalObject(
        labels.entries.map(
          (entry) => MapEntry(entry.key, CanonicalString(entry.value)),
        ),
      ),
    ),
  ]);
}

final class SavedWorldForm {
  SavedWorldForm({required BigInt generation, required this.form})
    : generation = checkedU64(generation);
  final BigInt generation;
  final UnfinishedWorldForm form;
}

/// Pending type input retains unresolved choices until the author completes
/// them. It is not a definition, proposal, or grant of authority.
final class UnfinishedTypeForm {
  UnfinishedTypeForm({
    required this.baseRevision,
    required this.representedContext,
    required this.clientRef,
    required this.namespace,
    required this.key,
    required this.name,
    required this.parentChoice,
    required this.applicabilityChoice,
    required this.rationale,
    this.classificationExecutable,
    Iterable<WorldId> worlds = const [],
    this.revisionTarget,
    this.expectedRecordVersion,
    this.original,
    this.parentResolution = '',
    Iterable<PropertyLabelInput> labels = const [],
    BigInt? draftVersion,
  }) : labels = List.unmodifiable(labels),
       worlds = List.unmodifiable(worlds),
       draftVersion = draftVersion == null ? null : checkedU64(draftVersion);
  final RevisionId baseRevision;
  final RecordId representedContext;
  final String clientRef,
      namespace,
      key,
      name,
      parentChoice,
      applicabilityChoice,
      rationale;
  final bool? classificationExecutable;
  final List<WorldId> worlds;
  final RecordRef? revisionTarget;
  final RecordVersionId? expectedRecordVersion;
  final EntityTypeRecord? original;
  final String parentResolution;
  final List<PropertyLabelInput> labels;
  final BigInt? draftVersion;
  CanonicalObject get revisionFields => CanonicalObject([
    MapEntry('target', revisionTarget?.toCanonical() ?? const CanonicalNull()),
    MapEntry(
      'expected_version',
      expectedRecordVersion == null
          ? const CanonicalNull()
          : CanonicalString(expectedRecordVersion!.value),
    ),
    MapEntry('original', original?.toWire() ?? const CanonicalNull()),
    MapEntry('parent_resolution', CanonicalString(parentResolution)),
    MapEntry('labels', CanonicalArray(labels.map((l) => l.toWire()))),
  ]);

  CanonicalObject toWire() => CanonicalObject([
    MapEntry('base_revision', CanonicalString(baseRevision.value)),
    MapEntry('represented_context', CanonicalString(representedContext.value)),
    MapEntry('client_ref', CanonicalString(clientRef)),
    if (revisionTarget != null) MapEntry('revision_fields', revisionFields),
    if (draftVersion != null)
      MapEntry('draft_version', CanonicalString(draftVersion.toString())),
    MapEntry('namespace', CanonicalString(namespace)),
    MapEntry('key', CanonicalString(key)),
    MapEntry('name', CanonicalString(name)),
    MapEntry('parent_choice', CanonicalString(parentChoice)),
    MapEntry('applicability_choice', CanonicalString(applicabilityChoice)),
    MapEntry('rationale', CanonicalString(rationale)),
    MapEntry(
      'classification_executable',
      classificationExecutable == null
          ? const CanonicalNull()
          : CanonicalBool(classificationExecutable!),
    ),
    MapEntry(
      'worlds',
      CanonicalArray(worlds.map((world) => CanonicalString(world.value))),
    ),
  ]);
}

final class SavedTypeForm {
  SavedTypeForm({required BigInt generation, required this.form})
    : generation = checkedU64(generation);
  final BigInt generation;
  final UnfinishedTypeForm form;
}

/// Incomplete instance input; associations do not establish physical location.
final class UnfinishedEntityForm {
  UnfinishedEntityForm({
    required this.baseRevision,
    required this.representedContext,
    required this.clientRef,
    required this.name,
    required this.classification,
    required this.worldRole,
    required this.rationale,
    Iterable<WorldId> worlds = const [],
    BigInt? draftVersion,
    Iterable<EntityAssociationForm>? associations,
    this.nameDetails,
    this.expectedRecordVersion,
  }) : associations = associations == null
           ? null
           : List.unmodifiable(associations),
       worlds = List.unmodifiable(worlds),
       draftVersion = draftVersion == null ? null : checkedU64(draftVersion);
  final RevisionId baseRevision;
  final RecordId representedContext;
  final String clientRef, name, classification, worldRole, rationale;
  final List<WorldId> worlds;
  final BigInt? draftVersion;

  /// Null retains the draft associations (older recovery forms). Empty explicitly removes them.
  final List<EntityAssociationForm>? associations;
  final EntityNameForm? nameDetails;
  final RecordVersionId? expectedRecordVersion;
  CanonicalObject toWire() => CanonicalObject([
    if (expectedRecordVersion != null)
      MapEntry(
        'expected_record_version',
        CanonicalString(expectedRecordVersion!.value),
      ),
    if (nameDetails != null) MapEntry('name_details', nameDetails!.toWire()),
    if (associations != null)
      MapEntry(
        'associations',
        CanonicalArray(associations!.map((a) => a.toWire())),
      ),
    MapEntry('base_revision', CanonicalString(baseRevision.value)),
    MapEntry('represented_context', CanonicalString(representedContext.value)),
    MapEntry('client_ref', CanonicalString(clientRef)),
    if (draftVersion != null)
      MapEntry('draft_version', CanonicalString(draftVersion.toString())),
    MapEntry('name', CanonicalString(name)),
    MapEntry('classification', CanonicalString(classification)),
    MapEntry('world_role', CanonicalString(worldRole)),
    MapEntry('rationale', CanonicalString(rationale)),
    MapEntry(
      'worlds',
      CanonicalArray(worlds.map((w) => CanonicalString(w.value))),
    ),
  ]);
}

final class SavedEntityForm {
  SavedEntityForm({required BigInt generation, required this.form})
    : generation = checkedU64(generation);
  final BigInt generation;
  final UnfinishedEntityForm form;
}

/// Entered association fields reference their source row in the exact draft.
/// Null validity retains the exact source value; an explicit value replaces it.
/// Null qualifier input retains the source; an empty list explicitly clears it.
final class EntityAssociationForm {
  const EntityAssociationForm({
    required this.world,
    required this.role,
    this.originalOrdinal,
    this.validity,
    this.temporalValidity,
    this.qualifiers,
  });
  final Validity? validity;
  final TemporalValidityInput? temporalValidity;
  final List<QualifierInput>? qualifiers;
  final String world, role;
  final int? originalOrdinal;
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('world', CanonicalString(world)),
    MapEntry('role', CanonicalString(role)),
    if (qualifiers != null)
      MapEntry(
        'qualifiers',
        CanonicalArray(qualifiers!.map((q) => q.toWire())),
      ),
    if (validity != null) MapEntry('validity', validity!.toWire()),
    if (temporalValidity != null)
      MapEntry('temporal_validity', temporalValidity!.toWire()),
    if (originalOrdinal != null)
      MapEntry('original_ordinal', CanonicalString(originalOrdinal.toString())),
  ]);
}

/// Unfinished temporal fields retain entered text, including incomplete bounds.
final class TemporalValidityInput {
  const TemporalValidityInput({
    this.kind = 'interval',
    this.calendar = '',
    this.relation = '',
    this.targetUniverse = '',
    this.targetRecord = '',
    this.start = const TemporalBoundInput(),
    this.end = const TemporalBoundInput(),
  });
  final String kind, calendar, relation, targetUniverse, targetRecord;
  final TemporalBoundInput start, end;
  TemporalValidityInput copyWith({
    String? kind,
    String? calendar,
    String? relation,
    String? targetUniverse,
    String? targetRecord,
    TemporalBoundInput? start,
    TemporalBoundInput? end,
  }) => TemporalValidityInput(
    kind: kind ?? this.kind,
    calendar: calendar ?? this.calendar,
    relation: relation ?? this.relation,
    targetUniverse: targetUniverse ?? this.targetUniverse,
    targetRecord: targetRecord ?? this.targetRecord,
    start: start ?? this.start,
    end: end ?? this.end,
  );
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('kind', CanonicalString(kind)),
    MapEntry('calendar', CanonicalString(calendar)),
    MapEntry('relation', CanonicalString(relation)),
    MapEntry('target_universe', CanonicalString(targetUniverse)),
    MapEntry('target_record', CanonicalString(targetRecord)),
    MapEntry('start', start.toWire()),
    MapEntry('end', end.toWire()),
  ]);
  factory TemporalValidityInput.fromWire(
    CanonicalValue value, {
    int depth = 0,
  }) {
    if (depth > 128) throw const FormatException('Value nesting limit');
    final f = WireFields(value, {
      'kind',
      'calendar',
      'start',
      'end',
      'relation',
      'target_universe',
      'target_record',
    });
    return TemporalValidityInput(
      kind: f.string('kind'),
      calendar: f.string('calendar'),
      relation: f.string('relation'),
      targetUniverse: f.string('target_universe'),
      targetRecord: f.string('target_record'),
      start: TemporalBoundInput.fromWire(f.require('start'), depth: depth),
      end: TemporalBoundInput.fromWire(f.require('end'), depth: depth),
    );
  }
}

final class TemporalBoundInput {
  const TemporalBoundInput({
    this.kind = 'exact',
    this.value = '',
    this.upper = '',
    this.uncertaintyKind = 'decimal',
    this.uncertainty = '',
    this.denominator = '1',
    this.unit = '',
    this.amount,
  });
  final String kind,
      value,
      upper,
      uncertaintyKind,
      uncertainty,
      denominator,
      unit;
  final QualifierInput? amount;
  TemporalBoundInput copyWith({
    String? kind,
    String? value,
    String? upper,
    String? uncertaintyKind,
    String? uncertainty,
    String? denominator,
    String? unit,
    QualifierInput? amount,
  }) => TemporalBoundInput(
    amount: amount ?? this.amount,
    kind: kind ?? this.kind,
    value: value ?? this.value,
    upper: upper ?? this.upper,
    uncertaintyKind: uncertaintyKind ?? this.uncertaintyKind,
    uncertainty: uncertainty ?? this.uncertainty,
    denominator: denominator ?? this.denominator,
    unit: unit ?? this.unit,
  );
  CanonicalObject toWire() => CanonicalObject([
    if (amount != null) MapEntry('amount', amount!.toWire()),
    MapEntry('kind', CanonicalString(kind)),
    MapEntry('value', CanonicalString(value)),
    MapEntry('upper', CanonicalString(upper)),
    MapEntry('uncertainty_kind', CanonicalString(uncertaintyKind)),
    MapEntry('uncertainty', CanonicalString(uncertainty)),
    MapEntry('denominator', CanonicalString(denominator)),
    MapEntry('unit', CanonicalString(unit)),
  ]);
  factory TemporalBoundInput.fromWire(CanonicalValue value, {int depth = 0}) {
    if (depth > 128) throw const FormatException('Value nesting limit');
    final f = WireFields(value, {
      'amount',
      'kind',
      'value',
      'upper',
      'uncertainty_kind',
      'uncertainty',
      'denominator',
      'unit',
    });
    return TemporalBoundInput(
      amount: f.optional(
        'amount',
        (v) => QualifierInput.fromWire(v, depth: depth + 1),
      ),
      kind: f.string('kind'),
      value: f.string('value'),
      upper: f.string('upper'),
      uncertaintyKind: f.string('uncertainty_kind'),
      uncertainty: f.string('uncertainty'),
      denominator: f.string('denominator'),
      unit: f.string('unit'),
    );
  }
}

final class QualifierInput {
  const QualifierInput({
    this.key = '',
    this.kind = 'text',
    this.value = '',
    this.denominator = '1',
    this.unit = '',
    this.universe = '',
    this.definition = '',
    this.originalKey,
    this.children = const [],
    this.temporal,
    this.lower,
    this.upper,
    this.lowerInclusive = '',
    this.upperInclusive = '',
  });
  final String key, kind, value, denominator, unit, universe, definition;
  final String? originalKey;
  final List<QualifierInput> children;
  final QualifierInput? lower, upper;
  final TemporalValidityInput? temporal;
  final String lowerInclusive, upperInclusive;
  Iterable<String> get exactTexts sync* {
    yield* [
      key,
      kind,
      value,
      denominator,
      unit,
      universe,
      definition,
      ?originalKey,
      lowerInclusive,
      upperInclusive,
    ];
    if (temporal case final t?) {
      yield* [t.kind, t.calendar, t.relation, t.targetUniverse, t.targetRecord];
      for (final b in [t.start, t.end]) {
        if (b.amount != null) yield* b.amount!.exactTexts;
        yield* [
          b.kind,
          b.value,
          b.upper,
          b.uncertaintyKind,
          b.uncertainty,
          b.denominator,
          b.unit,
        ];
      }
    }
    for (final child in [...children, ?lower, ?upper]) {
      yield* child.exactTexts;
    }
  }

  CanonicalObject toWire() => CanonicalObject([
    MapEntry('key', CanonicalString(key)),
    MapEntry('kind', CanonicalString(kind)),
    MapEntry('value', CanonicalString(value)),
    MapEntry('denominator', CanonicalString(denominator)),
    MapEntry('unit', CanonicalString(unit)),
    MapEntry('universe', CanonicalString(universe)),
    MapEntry('definition', CanonicalString(definition)),
    if (temporal != null) MapEntry('temporal', temporal!.toWire()),
    if (lower != null) MapEntry('lower', lower!.toWire()),
    if (upper != null) MapEntry('upper', upper!.toWire()),
    MapEntry('lower_inclusive', CanonicalString(lowerInclusive)),
    MapEntry('upper_inclusive', CanonicalString(upperInclusive)),
    MapEntry('children', CanonicalArray(children.map((c) => c.toWire()))),
    if (originalKey != null)
      MapEntry('original_key', CanonicalString(originalKey!)),
  ]);
  factory QualifierInput.fromWire(CanonicalValue value, {int depth = 0}) {
    if (depth > 128) throw const FormatException('Value nesting limit');
    final f = WireFields(value, {
      'key',
      'kind',
      'value',
      'denominator',
      'unit',
      'original_key',
      'universe',
      'definition',
      'children',
      'temporal',
      'lower',
      'upper',
      'lower_inclusive',
      'upper_inclusive',
    });
    return QualifierInput(
      temporal: f.optional(
        'temporal',
        (v) => TemporalValidityInput.fromWire(v, depth: depth + 1),
      ),
      lower: f.optional(
        'lower',
        (v) => QualifierInput.fromWire(v, depth: depth + 1),
      ),
      upper: f.optional(
        'upper',
        (v) => QualifierInput.fromWire(v, depth: depth + 1),
      ),
      lowerInclusive: f.string('lower_inclusive'),
      upperInclusive: f.string('upper_inclusive'),
      key: f.string('key'),
      kind: f.string('kind'),
      value: f.string('value'),
      denominator: f.string('denominator'),
      unit: f.string('unit'),
      universe: f.string('universe'),
      definition: f.string('definition'),
      originalKey: f.optional('original_key', wireString),
      children: f
          .array('children', defaultEmpty: true)
          .map((c) => QualifierInput.fromWire(c, depth: depth + 1))
          .toList(),
    );
  }
}

/// Null metadata is absent; an empty string remains an explicitly entered value.
final class EntityNameForm {
  const EntityNameForm({
    this.language,
    this.community,
    this.role,
    this.validity,
    this.temporalValidity,
  });
  final String? language, community, role;
  final Validity? validity;
  final TemporalValidityInput? temporalValidity;
  CanonicalObject toWire() => CanonicalObject([
    if (language != null) MapEntry('language', CanonicalString(language!)),
    if (community != null) MapEntry('community', CanonicalString(community!)),
    if (role != null) MapEntry('role', CanonicalString(role!)),
    if (validity != null) MapEntry('validity', validity!.toWire()),
    if (temporalValidity != null)
      MapEntry('temporal_validity', temporalValidity!.toWire()),
  ]);
  factory EntityNameForm.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'language',
      'community',
      'role',
      'validity',
      'temporal_validity',
    });
    return EntityNameForm(
      language: f.optional('language', wireString),
      community: f.optional('community', wireString),
      role: f.optional('role', wireString),
      validity: f.optional('validity', Validity.fromWire),
      temporalValidity: f.optional(
        'temporal_validity',
        TemporalValidityInput.fromWire,
      ),
    );
  }
  Iterable<String> get exactTexts sync* {
    yield* [?language, ?community, ?role];
    if (temporalValidity case final t?) {
      yield* [t.kind, t.calendar, t.relation, t.targetUniverse, t.targetRecord];
      for (final b in [t.start, t.end]) {
        yield* [
          b.kind,
          b.value,
          b.upper,
          b.uncertaintyKind,
          b.uncertainty,
          b.denominator,
          b.unit,
        ];
        if (b.amount != null) yield* b.amount!.exactTexts;
      }
    }
  }
}

/// Recoverable selection for a new fact about an existing entity.
final class AttributeCreationInput {
  const AttributeCreationInput({
    required this.subject,
    required this.operationRef,
    this.propertyRecord = '',
    this.propertyUniverse = '',
    this.relationship = false,
  });
  final VersionRef subject;
  final bool relationship;
  final String operationRef, propertyRecord, propertyUniverse;
  CanonicalObject toWire() => CanonicalObject([
    if (relationship) MapEntry('relationship', CanonicalBool(true)),
    MapEntry('subject', subject.toCanonical()),
    MapEntry('operation_ref', CanonicalString(operationRef)),
    MapEntry('property_record', CanonicalString(propertyRecord)),
    MapEntry('property_universe', CanonicalString(propertyUniverse)),
  ]);
  factory AttributeCreationInput.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'relationship',
      'subject',
      'operation_ref',
      'property_record',
      'property_universe',
    });
    return AttributeCreationInput(
      relationship: f.boolean('relationship'),
      subject: VersionRef.fromCanonical(f.require('subject')),
      operationRef: f.string('operation_ref'),
      propertyRecord: f.string('property_record'),
      propertyUniverse: f.string('property_universe'),
    );
  }
}

/// Incomplete role binding; an omitted universe remains unfinished input.
final class PropositionRoleInput {
  const PropositionRoleInput({
    this.role = '',
    this.record = '',
    this.universe = '',
  });
  final String role, record, universe;
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('role', CanonicalString(role)),
    MapEntry('record', CanonicalString(record)),
    MapEntry('universe', CanonicalString(universe)),
  ]);
  factory PropositionRoleInput.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'role', 'record', 'universe'});
    return PropositionRoleInput(
      role: f.string('role'),
      record: f.string('record'),
      universe: f.string('universe'),
    );
  }
  Iterable<String> get exactTexts => [role, record, universe];
}

/// Pending assertion edits do not replace definitions or unedited evidence.
final class UnfinishedAttributeForm {
  UnfinishedAttributeForm({
    required this.baseRevision,
    required this.representedContext,
    required this.clientRef,
    required BigInt draftVersion,
    required this.value,
    this.evidenceInput,
    this.creationInput,
    Iterable<PropositionRoleInput>? roles,
  }) : roles = roles == null ? null : List.unmodifiable(roles),
       draftVersion = checkedU64(draftVersion);
  final RevisionId baseRevision;
  final RecordId representedContext;
  final String clientRef;
  final BigInt draftVersion;
  final QualifierInput value;
  final AttributeEvidenceInput? evidenceInput;
  final AttributeCreationInput? creationInput;

  /// Null retains original roles; empty removes all role bindings.
  final List<PropositionRoleInput>? roles;
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('base_revision', CanonicalString(baseRevision.value)),
    MapEntry('represented_context', CanonicalString(representedContext.value)),
    MapEntry('client_ref', CanonicalString(clientRef)),
    MapEntry('draft_version', CanonicalString(draftVersion.toString())),
    MapEntry('value', value.toWire()),
    if (evidenceInput != null)
      MapEntry('evidence_input', evidenceInput!.toWire()),
    if (roles != null)
      MapEntry('roles', CanonicalArray(roles!.map((r) => r.toWire()))),
    if (creationInput != null)
      MapEntry('creation_input', creationInput!.toWire()),
  ]);
}

final class SavedAttributeForm {
  SavedAttributeForm({required BigInt generation, required this.form})
    : generation = checkedU64(generation);
  final BigInt generation;
  final UnfinishedAttributeForm form;
}

/// Null fields retain the authored assertion details; explicit input replaces them.
final class AttributeEvidenceInput {
  const AttributeEvidenceInput({
    this.basis,
    this.attributeMode,
    this.scope,
    this.polarity,
    this.precision,
    this.persistence,
    this.validity,
    this.temporalValidity,
    this.alternatives,
  });
  final AttributeMode? attributeMode;
  final EvidenceBasisInput? basis;
  final ScopeInput? scope;
  final Polarity? polarity;
  final Precision? precision;
  final PersistenceSemantics? persistence;
  final Validity? validity;
  final TemporalValidityInput? temporalValidity;

  /// Null retains alternatives; empty explicitly removes them.
  final List<QualifierInput>? alternatives;
  CanonicalObject toWire() => CanonicalObject([
    if (basis != null) MapEntry('basis', basis!.toWire()),
    if (attributeMode != null)
      MapEntry('attribute_mode', CanonicalString(attributeMode!.wireName)),
    if (scope != null) MapEntry('scope', scope!.toWire()),
    if (alternatives != null)
      MapEntry(
        'alternatives',
        CanonicalArray(alternatives!.map((v) => v.toWire())),
      ),
    if (polarity != null) MapEntry('polarity', polarity!.toWire()),
    if (precision != null) MapEntry('precision', precision!.toWire()),
    if (persistence != null) MapEntry('persistence', persistence!.toWire()),
    if (validity != null) MapEntry('validity', validity!.toWire()),
    if (temporalValidity != null)
      MapEntry('temporal_validity', temporalValidity!.toWire()),
  ]);
  factory AttributeEvidenceInput.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'basis',
      'attribute_mode',
      'scope',
      'polarity',
      'precision',
      'persistence',
      'validity',
      'temporal_validity',
      'alternatives',
    });
    return AttributeEvidenceInput(
      basis: f.optional('basis', EvidenceBasisInput.fromWire),
      attributeMode: f.optional('attribute_mode', AttributeMode.fromWire),
      scope: f.optional('scope', ScopeInput.fromWire),
      alternatives: f.optional('alternatives', (v) {
        if (v is! CanonicalArray) {
          throw const FormatException('Expected alternative inputs');
        }
        return v.items.map(QualifierInput.fromWire).toList();
      }),
      polarity: f.optional('polarity', Polarity.fromWire),
      precision: f.optional('precision', Precision.fromWire),
      persistence: f.optional('persistence', PersistenceSemantics.fromWire),
      validity: f.optional('validity', Validity.fromWire),
      temporalValidity: f.optional(
        'temporal_validity',
        TemporalValidityInput.fromWire,
      ),
    );
  }
  Iterable<String> get exactTexts sync* {
    if (basis != null) yield* basis!.exactTexts;
    if (scope != null) yield* scope!.exactTexts;
    for (final alternative in alternatives ?? <QualifierInput>[]) {
      yield* alternative.exactTexts;
    }
    if (temporalValidity != null) {
      yield* QualifierInput(
        kind: 'temporal',
        temporal: temporalValidity,
      ).exactTexts;
    }
  }
}

/// Authored provenance fields can recover before their reference is complete.
/// Evaluator-owned bases use retain rather than manufacturing their provenance.
final class EvidenceBasisInput {
  const EvidenceBasisInput({
    this.kind = 'retain',
    this.note = '',
    this.anchorRecord = '',
    this.anchorUniverse = '',
    this.verified = false,
  });
  final String kind, note, anchorRecord, anchorUniverse;
  final bool verified;
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('kind', CanonicalString(kind)),
    MapEntry('note', CanonicalString(note)),
    MapEntry('anchor_record', CanonicalString(anchorRecord)),
    MapEntry('anchor_universe', CanonicalString(anchorUniverse)),
    MapEntry('verified', CanonicalBool(verified)),
  ]);
  factory EvidenceBasisInput.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'kind',
      'note',
      'anchor_record',
      'anchor_universe',
      'verified',
    });
    return EvidenceBasisInput(
      kind: f.string('kind'),
      note: f.string('note'),
      anchorRecord: f.string('anchor_record'),
      anchorUniverse: f.string('anchor_universe'),
      verified: f.boolean('verified'),
    );
  }
  Iterable<String> get exactTexts => [kind, note, anchorRecord, anchorUniverse];
}

/// Unfinished factual scope fields, separate from the authenticated editor scope.
final class ScopeInput {
  const ScopeInput({
    this.applicability = 'unspecified',
    this.worlds = const [],
    this.contextRecord = '',
    this.contextUniverse = '',
    this.hasRealm = false,
    this.realmRecord = '',
    this.realmUniverse = '',
  });
  final String applicability,
      contextRecord,
      contextUniverse,
      realmRecord,
      realmUniverse;
  final List<String> worlds;
  final bool hasRealm;
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('applicability', CanonicalString(applicability)),
    MapEntry('worlds', CanonicalArray(worlds.map(CanonicalString.new))),
    MapEntry('context_record', CanonicalString(contextRecord)),
    MapEntry('context_universe', CanonicalString(contextUniverse)),
    MapEntry('has_realm', CanonicalBool(hasRealm)),
    MapEntry('realm_record', CanonicalString(realmRecord)),
    MapEntry('realm_universe', CanonicalString(realmUniverse)),
  ]);
  factory ScopeInput.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'applicability',
      'worlds',
      'context_record',
      'context_universe',
      'has_realm',
      'realm_record',
      'realm_universe',
    });
    final worlds = f.require('worlds');
    if (worlds is! CanonicalArray) {
      throw const FormatException('Expected world inputs');
    }
    return ScopeInput(
      applicability: f.string('applicability'),
      worlds: worlds.items.map((v) {
        if (v is! CanonicalString) {
          throw const FormatException('Expected world input');
        }
        return v.value;
      }).toList(),
      contextRecord: f.string('context_record'),
      contextUniverse: f.string('context_universe'),
      hasRealm: f.boolean('has_realm'),
      realmRecord: f.string('realm_record'),
      realmUniverse: f.string('realm_universe'),
    );
  }
  Iterable<String> get exactTexts => [
    applicability,
    ...worlds,
    contextRecord,
    contextUniverse,
    realmRecord,
    realmUniverse,
  ];
}
