import 'package:ub_domain/ub_domain.dart';

import 'editor_forms.dart';
import 'expression_forms.dart';
import 'wire.dart';

final class UnfinishedItemPowerForm {
  UnfinishedItemPowerForm({
    required this.baseRevision,
    required this.representedContext,
    required this.clientRef,
    this.item = const ExpressionReferenceInput(),
    this.holderPredicate = const ExpressionReferenceInput(),
    this.powerPredicate = const ExpressionReferenceInput(),
    this.value = const QualifierInput(kind: 'text'),
    this.scope = const ScopeInput(),
    this.validity = const TemporalValidityInput(kind: 'unspecified'),
    this.rationale = '',
    this.original,
    this.correctionTarget,
    this.expectedRecordVersion,
    BigInt? draftVersion,
  }) : draftVersion = draftVersion == null ? null : checkedU64(draftVersion);
  final RevisionId baseRevision;
  final RecordId representedContext;
  final String clientRef, rationale;
  final ExpressionReferenceInput item, holderPredicate, powerPredicate;
  final QualifierInput value;
  final ScopeInput scope;
  final TemporalValidityInput validity;
  final ItemPowerRecord? original;
  final ExpressionReferenceInput? correctionTarget;
  final RecordVersionId? expectedRecordVersion;
  final BigInt? draftVersion;
  UnfinishedItemPowerForm copyWith({
    ExpressionReferenceInput? item,
    ExpressionReferenceInput? holderPredicate,
    ExpressionReferenceInput? powerPredicate,
    QualifierInput? value,
    ScopeInput? scope,
    TemporalValidityInput? validity,
    String? rationale,
  }) => UnfinishedItemPowerForm(
    baseRevision: baseRevision,
    representedContext: representedContext,
    clientRef: clientRef,
    item: item ?? this.item,
    holderPredicate: holderPredicate ?? this.holderPredicate,
    powerPredicate: powerPredicate ?? this.powerPredicate,
    value: value ?? this.value,
    scope: scope ?? this.scope,
    validity: validity ?? this.validity,
    rationale: rationale ?? this.rationale,
    original: original,
    correctionTarget: correctionTarget,
    expectedRecordVersion: expectedRecordVersion,
    draftVersion: draftVersion,
  );
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('base_revision', CanonicalString(baseRevision.value)),
    MapEntry('represented_context', CanonicalString(representedContext.value)),
    MapEntry('client_ref', CanonicalString(clientRef)),
    MapEntry('item', item.toWire()),
    MapEntry('holder_predicate', holderPredicate.toWire()),
    MapEntry('power_predicate', powerPredicate.toWire()),
    MapEntry('value', value.toWire()),
    MapEntry('scope', scope.toWire()),
    MapEntry('validity', validity.toWire()),
    MapEntry('rationale', CanonicalString(rationale)),
    if (correctionTarget != null)
      MapEntry('correction_target', correctionTarget!.toWire()),
    if (expectedRecordVersion != null)
      MapEntry(
        'expected_record_version',
        CanonicalString(expectedRecordVersion!.value),
      ),
    if (original != null) MapEntry('original', original!.toWire()),
    if (draftVersion != null)
      MapEntry('draft_version', CanonicalString(draftVersion.toString())),
  ]);
  factory UnfinishedItemPowerForm.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'base_revision',
      'represented_context',
      'client_ref',
      'item',
      'holder_predicate',
      'power_predicate',
      'value',
      'scope',
      'validity',
      'rationale',
      'original',
      'correction_target',
      'expected_record_version',
      'draft_version',
    });
    return UnfinishedItemPowerForm(
      baseRevision: RevisionId.parse(f.string('base_revision')),
      representedContext: RecordId.parse(f.string('represented_context')),
      clientRef: f.string('client_ref'),
      item: ExpressionReferenceInput.fromWire(f.require('item')),
      holderPredicate: ExpressionReferenceInput.fromWire(
        f.require('holder_predicate'),
      ),
      powerPredicate: ExpressionReferenceInput.fromWire(
        f.require('power_predicate'),
      ),
      value: QualifierInput.fromWire(f.require('value')),
      scope: ScopeInput.fromWire(f.require('scope')),
      validity: TemporalValidityInput.fromWire(f.require('validity')),
      rationale: f.string('rationale'),
      correctionTarget: f.optional(
        'correction_target',
        ExpressionReferenceInput.fromWire,
      ),
      expectedRecordVersion: f.optional(
        'expected_record_version',
        (v) => RecordVersionId.parse(wireString(v)),
      ),
      original: f.optional('original', ItemPowerRecord.fromWire),
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

final class SavedItemPowerForm {
  SavedItemPowerForm({required BigInt generation, required this.form})
    : generation = checkedU64(generation);
  final BigInt generation;
  final UnfinishedItemPowerForm form;
}
