import 'package:ub_domain/ub_domain.dart';

import 'editor_forms.dart';
import 'expression_forms.dart';
import 'property_forms.dart';
import 'wire.dart';

final class ActionRequirementInput {
  const ActionRequirementInput({
    this.role = '',
    this.predicate = const ExpressionReferenceInput(),
    this.value = const QualifierInput(),
    this.original,
  });
  final String role;
  final ExpressionReferenceInput predicate;
  final QualifierInput value;
  final AttributeRequirement? original;
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('role', CanonicalString(role)),
    MapEntry('predicate', predicate.toWire()),
    MapEntry('value', value.toWire()),
    if (original != null) MapEntry('original', original!.toWire()),
  ]);
  factory ActionRequirementInput.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'role', 'predicate', 'value', 'original'});
    return ActionRequirementInput(
      role: f.string('role'),
      predicate: ExpressionReferenceInput.fromWire(f.require('predicate')),
      value: QualifierInput.fromWire(f.require('value')),
      original: f.optional('original', AttributeRequirement.fromWire),
    );
  }
}

/// Inputs remain strings until the existing consequence contract validates them.
final class ActionSlotInput {
  ActionSlotInput({
    Map<String, String> fields = const {},
    this.target = const ExpressionReferenceInput(),
    this.condition = const ActionRequirementInput(),
    this.value = const QualifierInput(),
    this.original,
  }) : fields = Map.unmodifiable(fields);
  final Map<String, String> fields;
  final ExpressionReferenceInput target;
  final ActionRequirementInput condition;
  final QualifierInput value;
  final EffectSlot? original;
  CanonicalObject toWire() => CanonicalObject([
    MapEntry(
      'fields',
      CanonicalObject(
        fields.entries.map((e) => MapEntry(e.key, CanonicalString(e.value))),
      ),
    ),
    MapEntry('target', target.toWire()),
    MapEntry('condition', condition.toWire()),
    MapEntry('value', value.toWire()),
    if (original != null) MapEntry('original', original!.toWire()),
  ]);
  factory ActionSlotInput.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'fields',
      'target',
      'condition',
      'value',
      'original',
    });
    final fields = f.require('fields');
    if (fields is! CanonicalObject) {
      throw const FormatException('Expected slot input fields.');
    }
    return ActionSlotInput(
      fields: {for (final e in fields.fields) e.key: wireString(e.value)},
      target: ExpressionReferenceInput.fromWire(f.require('target')),
      condition: ActionRequirementInput.fromWire(f.require('condition')),
      value: QualifierInput.fromWire(f.require('value')),
      original: f.optional('original', EffectSlot.fromWire),
    );
  }
}

final class UnfinishedActionForm {
  UnfinishedActionForm({
    required this.baseRevision,
    required this.representedContext,
    required this.clientRef,
    this.namespace = '',
    this.key = '',
    Iterable<PropertyLabelInput> labels = const [],
    Iterable<ActionRequirementInput> requirements = const [],
    Iterable<ActionSlotInput>? slots,
    this.scope = const ScopeInput(),
    this.validity = const TemporalValidityInput(kind: 'unspecified'),
    this.rationale = '',
    this.original,
    BigInt? draftVersion,
  }) : labels = List.unmodifiable(labels),
       requirements = List.unmodifiable(requirements),
       slots = slots == null ? null : List.unmodifiable(slots),
       draftVersion = draftVersion == null ? null : checkedU64(draftVersion);
  final RevisionId baseRevision;
  final RecordId representedContext;
  final String clientRef, namespace, key, rationale;
  final List<PropertyLabelInput> labels;
  final List<ActionRequirementInput> requirements;

  /// Null means no declared contract; an empty list is an explicit empty contract.
  final List<ActionSlotInput>? slots;
  final ScopeInput scope;
  final TemporalValidityInput validity;
  final ActionDefinitionRecord? original;
  final BigInt? draftVersion;
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('base_revision', CanonicalString(baseRevision.value)),
    MapEntry('represented_context', CanonicalString(representedContext.value)),
    MapEntry('client_ref', CanonicalString(clientRef)),
    MapEntry('namespace', CanonicalString(namespace)),
    MapEntry('key', CanonicalString(key)),
    MapEntry('rationale', CanonicalString(rationale)),
    MapEntry('labels', CanonicalArray(labels.map((v) => v.toWire()))),
    MapEntry(
      'requirements',
      CanonicalArray(requirements.map((v) => v.toWire())),
    ),
    if (slots != null)
      MapEntry('slots', CanonicalArray(slots!.map((v) => v.toWire()))),
    MapEntry('scope', scope.toWire()),
    MapEntry('validity', validity.toWire()),
    if (original != null) MapEntry('original', original!.toWire()),
    if (draftVersion != null)
      MapEntry('draft_version', CanonicalString(draftVersion.toString())),
  ]);
  factory UnfinishedActionForm.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'base_revision',
      'represented_context',
      'client_ref',
      'namespace',
      'key',
      'rationale',
      'labels',
      'requirements',
      'slots',
      'scope',
      'validity',
      'original',
      'draft_version',
    });
    return UnfinishedActionForm(
      baseRevision: RevisionId.parse(f.string('base_revision')),
      representedContext: RecordId.parse(f.string('represented_context')),
      clientRef: f.string('client_ref'),
      namespace: f.string('namespace'),
      key: f.string('key'),
      rationale: f.string('rationale'),
      labels: f.array('labels').map(PropertyLabelInput.fromWire),
      requirements: f
          .array('requirements')
          .map(ActionRequirementInput.fromWire),
      slots: f.values.containsKey('slots')
          ? f.array('slots').map(ActionSlotInput.fromWire)
          : null,
      scope: ScopeInput.fromWire(f.require('scope')),
      validity: TemporalValidityInput.fromWire(f.require('validity')),
      original: f.optional(
        'original',
        (v) => ActionDefinitionRecord.fromWire(v),
      ),
      draftVersion: f.optional(
        'draft_version',
        (v) => BigInt.parse(wireString(v)),
      ),
    );
  }
  Iterable<String> get exactTexts => _texts(toWire());
}

Iterable<String> _texts(CanonicalValue value) sync* {
  switch (value) {
    case CanonicalString(:final value):
      yield value;
    case CanonicalArray(:final items):
      for (final item in items) {
        yield* _texts(item);
      }
    case CanonicalObject(:final fields):
      for (final field in fields) {
        yield* _texts(field.value);
      }
    default:
      break;
  }
}

final class SavedActionForm {
  SavedActionForm({required BigInt generation, required this.form})
    : generation = checkedU64(generation);
  final BigInt generation;
  final UnfinishedActionForm form;
}
