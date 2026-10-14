import 'package:ub_domain/ub_domain.dart';

import 'expression_forms.dart';
import 'editor_forms.dart';
import 'wire.dart';

final class UnfinishedAssertionCorrectionForm {
  UnfinishedAssertionCorrectionForm({
    required this.baseRevision,
    required this.representedContext,
    required this.clientRef,
    required this.target,
    required this.expectedRecordVersion,
    required this.original,
    required this.proposition,
    this.evidence = const AttributeEvidenceInput(),
    this.rationale = '',
    BigInt? draftVersion,
  }) : draftVersion = draftVersion == null ? null : checkedU64(draftVersion);
  final RevisionId baseRevision;
  final RecordId representedContext;
  final String clientRef, rationale;
  final ExpressionReferenceInput target;
  final RecordVersionId expectedRecordVersion;
  final AssertionRecord original;
  final ExpressionReferenceInput proposition;
  final AttributeEvidenceInput evidence;
  final BigInt? draftVersion;
  UnfinishedAssertionCorrectionForm copyWith({
    ExpressionReferenceInput? proposition,
    AttributeEvidenceInput? evidence,
    String? rationale,
  }) => UnfinishedAssertionCorrectionForm(
    baseRevision: baseRevision,
    representedContext: representedContext,
    clientRef: clientRef,
    target: target,
    expectedRecordVersion: expectedRecordVersion,
    original: original,
    proposition: proposition ?? this.proposition,
    evidence: evidence ?? this.evidence,
    rationale: rationale ?? this.rationale,
    draftVersion: draftVersion,
  );
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('base_revision', CanonicalString(baseRevision.value)),
    MapEntry('represented_context', CanonicalString(representedContext.value)),
    MapEntry('client_ref', CanonicalString(clientRef)),
    MapEntry('target', target.toWire()),
    MapEntry(
      'expected_record_version',
      CanonicalString(expectedRecordVersion.value),
    ),
    MapEntry('original', original.toWire()),
    MapEntry('proposition', proposition.toWire()),
    MapEntry('evidence', evidence.toWire()),
    MapEntry('rationale', CanonicalString(rationale)),
    if (draftVersion != null)
      MapEntry('draft_version', CanonicalString(draftVersion.toString())),
  ]);
  factory UnfinishedAssertionCorrectionForm.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'base_revision',
      'represented_context',
      'client_ref',
      'target',
      'expected_record_version',
      'rationale',
      'original',
      'proposition',
      'evidence',
      'draft_version',
    });
    return UnfinishedAssertionCorrectionForm(
      baseRevision: RevisionId.parse(f.string('base_revision')),
      representedContext: RecordId.parse(f.string('represented_context')),
      clientRef: f.string('client_ref'),
      target: ExpressionReferenceInput.fromWire(f.require('target')),
      expectedRecordVersion: RecordVersionId.parse(
        f.string('expected_record_version'),
      ),
      original: AssertionRecord.fromWire(f.require('original')),
      proposition: ExpressionReferenceInput.fromWire(f.require('proposition')),
      evidence: AttributeEvidenceInput.fromWire(f.require('evidence')),
      rationale: f.string('rationale'),
      draftVersion: f.optional(
        'draft_version',
        (v) => BigInt.parse(wireString(v)),
      ),
    );
  }
  Iterable<String> get exactTexts => _texts(toWire());
}

final class SavedAssertionCorrectionForm {
  SavedAssertionCorrectionForm({required BigInt generation, required this.form})
    : generation = checkedU64(generation);
  final BigInt generation;
  final UnfinishedAssertionCorrectionForm form;
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
