import 'package:ub_domain/ub_domain.dart';

import 'wire.dart';
import 'property_forms.dart';

final class RelationRoleInput {
  RelationRoleInput({
    this.name = '',
    Iterable<String> participantTypes = const [],
    this.multiplicity = '',
    this.ordered = false,
  }) : participantTypes = List.unmodifiable(participantTypes);
  final String name, multiplicity;
  final List<String> participantTypes;
  final bool ordered;
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('name', CanonicalString(name)),
    MapEntry(
      'participant_types',
      CanonicalArray(participantTypes.map(CanonicalString.new)),
    ),
    MapEntry('multiplicity', CanonicalString(multiplicity)),
    MapEntry('ordered', CanonicalBool(ordered)),
  ]);
  factory RelationRoleInput.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'name',
      'participant_types',
      'multiplicity',
      'ordered',
    });
    return RelationRoleInput(
      name: f.string('name'),
      participantTypes: f.array('participant_types').map(wireString),
      multiplicity: f.string('multiplicity'),
      ordered: f.boolean('ordered'),
    );
  }
  Iterable<String> get exactTexts => [name, multiplicity, ...participantTypes];
}

final class UnfinishedRelationForm {
  UnfinishedRelationForm({
    required this.baseRevision,
    required this.representedContext,
    required this.clientRef,
    this.namespace = '',
    this.key = '',
    Iterable<PropertyLabelInput> labels = const [],
    Iterable<RelationRoleInput> roles = const [],
    this.rationale = '',
    BigInt? draftVersion,
  }) : labels = List.unmodifiable(labels),
       roles = List.unmodifiable(roles),
       draftVersion = draftVersion == null ? null : checkedU64(draftVersion);
  final RevisionId baseRevision;
  final RecordId representedContext;
  final String clientRef, namespace, key, rationale;
  final List<PropertyLabelInput> labels;
  final List<RelationRoleInput> roles;
  final BigInt? draftVersion;
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('base_revision', CanonicalString(baseRevision.value)),
    MapEntry('represented_context', CanonicalString(representedContext.value)),
    MapEntry('client_ref', CanonicalString(clientRef)),
    MapEntry('namespace', CanonicalString(namespace)),
    MapEntry('key', CanonicalString(key)),
    MapEntry('labels', CanonicalArray(labels.map((l) => l.toWire()))),
    MapEntry('roles', CanonicalArray(roles.map((f) => f.toWire()))),
    MapEntry('rationale', CanonicalString(rationale)),
    if (draftVersion != null)
      MapEntry('draft_version', CanonicalString(draftVersion.toString())),
  ]);
  factory UnfinishedRelationForm.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'base_revision',
      'represented_context',
      'client_ref',
      'namespace',
      'key',
      'labels',
      'roles',
      'rationale',
      'draft_version',
    });
    return UnfinishedRelationForm(
      baseRevision: RevisionId.parse(f.string('base_revision')),
      representedContext: RecordId.parse(f.string('represented_context')),
      clientRef: f.string('client_ref'),
      namespace: f.string('namespace'),
      key: f.string('key'),
      labels: f.array('labels').map(PropertyLabelInput.fromWire),
      roles: f.array('roles').map(RelationRoleInput.fromWire),
      rationale: f.string('rationale'),
      draftVersion: f.optional(
        'draft_version',
        (v) => BigInt.parse(wireString(v)),
      ),
    );
  }
  Iterable<String> get exactTexts sync* {
    yield* [clientRef, namespace, key, rationale];
    for (final l in labels) {
      yield l.language;
      yield l.text;
    }
    for (final f in roles) {
      yield* f.exactTexts;
    }
  }
}

final class SavedRelationForm {
  SavedRelationForm({required BigInt generation, required this.form})
    : generation = checkedU64(generation);
  final BigInt generation;
  final UnfinishedRelationForm form;
}
