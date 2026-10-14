import 'package:ub_domain/ub_domain.dart';

import 'editor_forms.dart';
import 'expression_forms.dart';
import 'wire.dart';

final class UnfinishedMemoryForm {
  UnfinishedMemoryForm({
    required this.baseRevision,
    required this.representedContext,
    required this.clientRef,
    this.holder = const ExpressionReferenceInput(),
    this.content = const ExpressionReferenceInput(),
    this.altered,
    this.validity = const TemporalValidityInput(kind: 'unspecified'),
    this.allegedEnabled = false,
    this.alleged = const ExpressionReferenceInput(),
    this.accessibility = '',
    this.rationale = '',
    this.original,
    BigInt? draftVersion,
  }) : draftVersion = draftVersion == null ? null : checkedU64(draftVersion);
  final RevisionId baseRevision;
  final RecordId representedContext;
  final String clientRef, rationale;
  final ExpressionReferenceInput holder, content, alleged;
  final bool? altered;
  final bool allegedEnabled;
  final TemporalValidityInput validity;
  final String accessibility;
  final MemoryRecord? original;
  final BigInt? draftVersion;
  UnfinishedMemoryForm copyWith({
    ExpressionReferenceInput? holder,
    ExpressionReferenceInput? content,
    bool? altered,
    TemporalValidityInput? validity,
    bool? allegedEnabled,
    ExpressionReferenceInput? alleged,
    String? accessibility,
    String? rationale,
  }) => UnfinishedMemoryForm(
    baseRevision: baseRevision,
    representedContext: representedContext,
    clientRef: clientRef,
    holder: holder ?? this.holder,
    content: content ?? this.content,
    altered: altered ?? this.altered,
    validity: validity ?? this.validity,
    allegedEnabled: allegedEnabled ?? this.allegedEnabled,
    alleged: alleged ?? this.alleged,
    accessibility: accessibility ?? this.accessibility,
    rationale: rationale ?? this.rationale,
    original: original,
    draftVersion: draftVersion,
  );
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('base_revision', CanonicalString(baseRevision.value)),
    MapEntry('represented_context', CanonicalString(representedContext.value)),
    MapEntry('client_ref', CanonicalString(clientRef)),
    MapEntry('holder', holder.toWire()),
    MapEntry('content', content.toWire()),
    MapEntry(
      'altered',
      altered == null ? const CanonicalNull() : CanonicalBool(altered!),
    ),
    MapEntry('validity', validity.toWire()),
    MapEntry('alleged_enabled', CanonicalBool(allegedEnabled)),
    MapEntry('alleged', alleged.toWire()),
    MapEntry('accessibility', CanonicalString(accessibility)),
    MapEntry('rationale', CanonicalString(rationale)),
    if (original != null) MapEntry('original', original!.toWire()),
    if (draftVersion != null)
      MapEntry('draft_version', CanonicalString(draftVersion.toString())),
  ]);
  factory UnfinishedMemoryForm.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'base_revision',
      'represented_context',
      'client_ref',
      'holder',
      'content',
      'altered',
      'validity',
      'alleged_enabled',
      'alleged',
      'accessibility',
      'rationale',
      'original',
      'draft_version',
    });
    return UnfinishedMemoryForm(
      baseRevision: RevisionId.parse(f.string('base_revision')),
      representedContext: RecordId.parse(f.string('represented_context')),
      clientRef: f.string('client_ref'),
      holder: ExpressionReferenceInput.fromWire(f.require('holder')),
      content: ExpressionReferenceInput.fromWire(f.require('content')),
      altered: f.optional(
        'altered',
        (v) => switch (v) {
          CanonicalBool(:final value) => value,
          _ => throw const FormatException('Expected memory-alteration choice'),
        },
      ),
      validity: TemporalValidityInput.fromWire(f.require('validity')),
      allegedEnabled: f.boolean('alleged_enabled'),
      alleged: ExpressionReferenceInput.fromWire(f.require('alleged')),
      accessibility: f.string('accessibility'),
      rationale: f.string('rationale'),
      original: f.optional('original', MemoryRecord.fromWire),
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

final class SavedMemoryForm {
  SavedMemoryForm({required BigInt generation, required this.form})
    : generation = checkedU64(generation);
  final BigInt generation;
  final UnfinishedMemoryForm form;
}
