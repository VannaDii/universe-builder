import 'package:ub_domain/ub_domain.dart';

import 'editor_forms.dart';
import 'expression_forms.dart';
import 'wire.dart';

final class UnfinishedBoundaryForm {
  UnfinishedBoundaryForm({
    required this.baseRevision,
    required this.representedContext,
    required this.clientRef,
    this.key = '',
    this.areaKind = '',
    this.record = const ExpressionReferenceInput(),
    this.predicate = '',
    this.subjectEnabled = false,
    this.subject = const ExpressionReferenceInput(),
    this.category = '',
    this.mode = '',
    Iterable<ExpressionInput> constraints = const [],
    this.scope = const ScopeInput(),
    this.validity = const TemporalValidityInput(kind: 'unspecified'),
    this.rationale = '',
    this.original,
    BigInt? draftVersion,
  }) : constraints = List.unmodifiable(constraints),
       draftVersion = draftVersion == null ? null : checkedU64(draftVersion);
  final RevisionId baseRevision;
  final RecordId representedContext;
  final String clientRef, key, areaKind, predicate, category, mode, rationale;
  final ExpressionReferenceInput record, subject;
  final bool subjectEnabled;
  final List<ExpressionInput> constraints;
  final ScopeInput scope;
  final TemporalValidityInput validity;
  final BoundaryRecord? original;
  final BigInt? draftVersion;
  UnfinishedBoundaryForm copyWith({
    String? key,
    String? areaKind,
    ExpressionReferenceInput? record,
    String? predicate,
    bool? subjectEnabled,
    ExpressionReferenceInput? subject,
    String? category,
    String? mode,
    List<ExpressionInput>? constraints,
    ScopeInput? scope,
    TemporalValidityInput? validity,
    String? rationale,
  }) => UnfinishedBoundaryForm(
    baseRevision: baseRevision,
    representedContext: representedContext,
    clientRef: clientRef,
    key: key ?? this.key,
    areaKind: areaKind ?? this.areaKind,
    record: record ?? this.record,
    predicate: predicate ?? this.predicate,
    subjectEnabled: subjectEnabled ?? this.subjectEnabled,
    subject: subject ?? this.subject,
    category: category ?? this.category,
    mode: mode ?? this.mode,
    constraints: constraints ?? this.constraints,
    scope: scope ?? this.scope,
    validity: validity ?? this.validity,
    rationale: rationale ?? this.rationale,
    original: original,
    draftVersion: draftVersion,
  );
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('base_revision', CanonicalString(baseRevision.value)),
    MapEntry('represented_context', CanonicalString(representedContext.value)),
    MapEntry('client_ref', CanonicalString(clientRef)),
    MapEntry('key', CanonicalString(key)),
    MapEntry('area_kind', CanonicalString(areaKind)),
    MapEntry('record', record.toWire()),
    MapEntry('predicate', CanonicalString(predicate)),
    MapEntry('subject_enabled', CanonicalBool(subjectEnabled)),
    MapEntry('subject', subject.toWire()),
    MapEntry('category', CanonicalString(category)),
    MapEntry('mode', CanonicalString(mode)),
    MapEntry('constraints', CanonicalArray(constraints.map((e) => e.toWire()))),
    MapEntry('scope', scope.toWire()),
    MapEntry('validity', validity.toWire()),
    MapEntry('rationale', CanonicalString(rationale)),
    if (original != null) MapEntry('original', original!.toWire()),
    if (draftVersion != null)
      MapEntry('draft_version', CanonicalString(draftVersion.toString())),
  ]);
  factory UnfinishedBoundaryForm.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'base_revision',
      'represented_context',
      'client_ref',
      'key',
      'area_kind',
      'record',
      'predicate',
      'subject_enabled',
      'subject',
      'category',
      'mode',
      'constraints',
      'scope',
      'validity',
      'rationale',
      'original',
      'draft_version',
    });
    return UnfinishedBoundaryForm(
      baseRevision: RevisionId.parse(f.string('base_revision')),
      representedContext: RecordId.parse(f.string('represented_context')),
      clientRef: f.string('client_ref'),
      key: f.string('key'),
      areaKind: f.string('area_kind'),
      record: ExpressionReferenceInput.fromWire(f.require('record')),
      predicate: f.string('predicate'),
      subjectEnabled: f.boolean('subject_enabled'),
      subject: ExpressionReferenceInput.fromWire(f.require('subject')),
      category: f.string('category'),
      mode: f.string('mode'),
      constraints: f.array('constraints').map(ExpressionInput.fromWire),
      scope: ScopeInput.fromWire(f.require('scope')),
      validity: TemporalValidityInput.fromWire(f.require('validity')),
      rationale: f.string('rationale'),
      original: f.optional('original', BoundaryRecord.fromWire),
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

final class SavedBoundaryForm {
  SavedBoundaryForm({required BigInt generation, required this.form})
    : generation = checkedU64(generation);
  final BigInt generation;
  final UnfinishedBoundaryForm form;
}
