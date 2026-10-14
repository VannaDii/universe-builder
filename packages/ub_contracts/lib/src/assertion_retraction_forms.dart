import 'package:ub_domain/ub_domain.dart';

import 'expression_forms.dart';
import 'wire.dart';

final class UnfinishedAssertionRetractionForm {
  UnfinishedAssertionRetractionForm({
    required this.baseRevision,
    required this.representedContext,
    required this.clientRef,
    required this.target,
    required this.expectedRecordVersion,
    this.rationale = '',
    BigInt? draftVersion,
  }) : draftVersion = draftVersion == null ? null : checkedU64(draftVersion);
  final RevisionId baseRevision;
  final RecordId representedContext;
  final String clientRef, rationale;
  final ExpressionReferenceInput target;
  final RecordVersionId expectedRecordVersion;
  final BigInt? draftVersion;
  UnfinishedAssertionRetractionForm copyWith({String? rationale}) =>
      UnfinishedAssertionRetractionForm(
        baseRevision: baseRevision,
        representedContext: representedContext,
        clientRef: clientRef,
        target: target,
        expectedRecordVersion: expectedRecordVersion,
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
    MapEntry('rationale', CanonicalString(rationale)),
    if (draftVersion != null)
      MapEntry('draft_version', CanonicalString(draftVersion.toString())),
  ]);
  factory UnfinishedAssertionRetractionForm.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'base_revision',
      'represented_context',
      'client_ref',
      'target',
      'expected_record_version',
      'rationale',
      'draft_version',
    });
    return UnfinishedAssertionRetractionForm(
      baseRevision: RevisionId.parse(f.string('base_revision')),
      representedContext: RecordId.parse(f.string('represented_context')),
      clientRef: f.string('client_ref'),
      target: ExpressionReferenceInput.fromWire(f.require('target')),
      expectedRecordVersion: RecordVersionId.parse(
        f.string('expected_record_version'),
      ),
      rationale: f.string('rationale'),
      draftVersion: f.optional(
        'draft_version',
        (v) => BigInt.parse(wireString(v)),
      ),
    );
  }
  Iterable<String> get exactTexts => [
    clientRef,
    target.record,
    target.universe,
    rationale,
  ];
}

final class SavedAssertionRetractionForm {
  SavedAssertionRetractionForm({required BigInt generation, required this.form})
    : generation = checkedU64(generation);
  final BigInt generation;
  final UnfinishedAssertionRetractionForm form;
}
