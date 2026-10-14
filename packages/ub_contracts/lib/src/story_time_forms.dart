import 'package:ub_domain/ub_domain.dart';

import 'expression_forms.dart';
import 'wire.dart';

/// Unfinished input for an explicit change to a pinned authored clock.
final class UnfinishedStoryTimeForm {
  UnfinishedStoryTimeForm({
    required this.baseRevision,
    required this.representedContext,
    required this.target,
    required this.expectedRecordVersion,
    required this.original,
    this.value = '',
    this.mode = '',
    this.reason = '',
    this.rationale = '',
    BigInt? draftVersion,
  }) : draftVersion = draftVersion == null ? null : checkedU64(draftVersion);
  final RevisionId baseRevision;
  final RecordId representedContext;
  final ExpressionReferenceInput target;
  final RecordVersionId expectedRecordVersion;
  final Chronology original;
  final String value, mode, reason, rationale;
  final BigInt? draftVersion;
  String get clientRef => target.record;
  String get recoveryKey => clientRef;
  Iterable<String> get exactTexts => [
    baseRevision.value,
    representedContext.value,
    target.record,
    target.universe,
    expectedRecordVersion.value,
    original.toWire().toText(),
    value,
    mode,
    reason,
    rationale,
  ];
  UnfinishedStoryTimeForm copyWith({
    String? value,
    String? mode,
    String? reason,
    String? rationale,
  }) => UnfinishedStoryTimeForm(
    baseRevision: baseRevision,
    representedContext: representedContext,
    target: target,
    expectedRecordVersion: expectedRecordVersion,
    original: original,
    value: value ?? this.value,
    mode: mode ?? this.mode,
    reason: reason ?? this.reason,
    rationale: rationale ?? this.rationale,
    draftVersion: draftVersion,
  );
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('base_revision', CanonicalString(baseRevision.value)),
    MapEntry('represented_context', CanonicalString(representedContext.value)),
    MapEntry('target', target.toWire()),
    MapEntry(
      'expected_record_version',
      CanonicalString(expectedRecordVersion.value),
    ),
    MapEntry('original', original.toWire()),
    MapEntry('value', CanonicalString(value)),
    MapEntry('mode', CanonicalString(mode)),
    MapEntry('reason', CanonicalString(reason)),
    MapEntry('rationale', CanonicalString(rationale)),
    if (draftVersion != null)
      MapEntry('draft_version', CanonicalString(draftVersion.toString())),
  ]);
  factory UnfinishedStoryTimeForm.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'base_revision',
      'represented_context',
      'target',
      'expected_record_version',
      'original',
      'value',
      'mode',
      'reason',
      'rationale',
      'draft_version',
    });
    return UnfinishedStoryTimeForm(
      baseRevision: RevisionId.parse(f.string('base_revision')),
      representedContext: RecordId.parse(f.string('represented_context')),
      target: ExpressionReferenceInput.fromWire(f.require('target')),
      expectedRecordVersion: RecordVersionId.parse(
        f.string('expected_record_version'),
      ),
      original: Chronology.fromWire(f.require('original')),
      value: f.string('value'),
      mode: f.string('mode'),
      reason: f.string('reason'),
      rationale: f.string('rationale'),
      draftVersion: f.optional(
        'draft_version',
        (v) => BigInt.parse(wireString(v)),
      ),
    );
  }
}

final class SavedStoryTimeForm {
  SavedStoryTimeForm({required BigInt generation, required this.form})
    : generation = checkedU64(generation);
  final BigInt generation;
  final UnfinishedStoryTimeForm form;
}
