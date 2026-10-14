import 'package:ub_domain/ub_domain.dart';

import 'expression_forms.dart';
import 'editor_forms.dart';
import 'wire.dart';

final class UnfinishedAssertionEndForm {
  UnfinishedAssertionEndForm({
    required this.baseRevision,
    required this.representedContext,
    required this.clientRef,
    required this.target,
    required this.expectedRecordVersion,
    required this.calendar,
    required this.originalBasis,
    this.coordinate = '',
    this.basis = const EvidenceBasisInput(),
    this.rationale = '',
    BigInt? draftVersion,
  }) : draftVersion = draftVersion == null ? null : checkedU64(draftVersion);
  final RevisionId baseRevision;
  final RecordId representedContext;
  final String clientRef, rationale;
  final ExpressionReferenceInput target;
  final RecordVersionId expectedRecordVersion;
  final CalendarId calendar;
  final String coordinate;
  final EvidenceBasis originalBasis;
  final EvidenceBasisInput basis;
  final BigInt? draftVersion;
  UnfinishedAssertionEndForm copyWith({
    String? coordinate,
    EvidenceBasisInput? basis,
    String? rationale,
  }) => UnfinishedAssertionEndForm(
    baseRevision: baseRevision,
    representedContext: representedContext,
    clientRef: clientRef,
    target: target,
    expectedRecordVersion: expectedRecordVersion,
    calendar: calendar,
    originalBasis: originalBasis,
    coordinate: coordinate ?? this.coordinate,
    basis: basis ?? this.basis,
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
    MapEntry('calendar', CanonicalString(calendar.value)),
    MapEntry('coordinate', CanonicalString(coordinate)),
    MapEntry('original_basis', originalBasis.toWire()),
    MapEntry('basis', basis.toWire()),
    MapEntry('rationale', CanonicalString(rationale)),
    if (draftVersion != null)
      MapEntry('draft_version', CanonicalString(draftVersion.toString())),
  ]);
  factory UnfinishedAssertionEndForm.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'base_revision',
      'represented_context',
      'client_ref',
      'target',
      'expected_record_version',
      'rationale',
      'calendar',
      'coordinate',
      'original_basis',
      'basis',
      'draft_version',
    });
    return UnfinishedAssertionEndForm(
      baseRevision: RevisionId.parse(f.string('base_revision')),
      representedContext: RecordId.parse(f.string('represented_context')),
      clientRef: f.string('client_ref'),
      target: ExpressionReferenceInput.fromWire(f.require('target')),
      expectedRecordVersion: RecordVersionId.parse(
        f.string('expected_record_version'),
      ),
      calendar: CalendarId.parse(f.string('calendar')),
      coordinate: f.string('coordinate'),
      originalBasis: EvidenceBasis.fromWire(f.require('original_basis')),
      basis: EvidenceBasisInput.fromWire(f.require('basis')),
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
    coordinate,
    ...basis.exactTexts,
  ];
}

final class SavedAssertionEndForm {
  SavedAssertionEndForm({required BigInt generation, required this.form})
    : generation = checkedU64(generation);
  final BigInt generation;
  final UnfinishedAssertionEndForm form;
}
