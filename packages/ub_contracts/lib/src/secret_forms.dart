import 'package:ub_domain/ub_domain.dart';

import 'expression_forms.dart';
import 'wire.dart';

/// Incomplete author input. Fictional disclosure never grants application access.
final class UnfinishedSecretForm {
  UnfinishedSecretForm({
    required this.baseRevision,
    required this.representedContext,
    required this.clientRef,
    Iterable<ExpressionReferenceInput> scope = const [],
    Iterable<ExpressionReferenceInput> fictionalKnowers = const [],
    this.readerDisclosed,
    this.hasConcealment = false,
    this.concealment = '',
    this.validityKind = 'unspecified',
    this.calendar = '',
    this.start = '',
    this.end = '',
    this.startUnbounded = true,
    this.endUnbounded = true,
    this.rationale = '',
    this.revisionTarget,
    this.expectedRecordVersion,
    this.original,
    BigInt? draftVersion,
  }) : scope = List.unmodifiable(scope),
       fictionalKnowers = List.unmodifiable(fictionalKnowers),
       draftVersion = draftVersion == null ? null : checkedU64(draftVersion);
  final RevisionId baseRevision;
  final RecordId representedContext;
  final String clientRef,
      concealment,
      validityKind,
      calendar,
      start,
      end,
      rationale;
  final List<ExpressionReferenceInput> scope, fictionalKnowers;
  final bool? readerDisclosed;
  final bool hasConcealment, startUnbounded, endUnbounded;
  final ExpressionReferenceInput? revisionTarget;
  final RecordVersionId? expectedRecordVersion;
  final SecretRecord? original;
  final BigInt? draftVersion;
  String get recoveryKey =>
      revisionTarget == null ? clientRef : 'secret-revision:$clientRef';
  Iterable<String> get exactTexts => _texts(toWire());
  UnfinishedSecretForm copyWith({
    Iterable<ExpressionReferenceInput>? scope,
    Iterable<ExpressionReferenceInput>? fictionalKnowers,
    bool? readerDisclosed,
    bool? hasConcealment,
    String? concealment,
    String? validityKind,
    String? calendar,
    String? start,
    String? end,
    bool? startUnbounded,
    bool? endUnbounded,
    String? rationale,
  }) => UnfinishedSecretForm(
    baseRevision: baseRevision,
    representedContext: representedContext,
    clientRef: clientRef,
    scope: scope ?? this.scope,
    fictionalKnowers: fictionalKnowers ?? this.fictionalKnowers,
    readerDisclosed: readerDisclosed ?? this.readerDisclosed,
    hasConcealment: hasConcealment ?? this.hasConcealment,
    concealment: concealment ?? this.concealment,
    validityKind: validityKind ?? this.validityKind,
    calendar: calendar ?? this.calendar,
    start: start ?? this.start,
    end: end ?? this.end,
    startUnbounded: startUnbounded ?? this.startUnbounded,
    endUnbounded: endUnbounded ?? this.endUnbounded,
    rationale: rationale ?? this.rationale,
    revisionTarget: revisionTarget,
    expectedRecordVersion: expectedRecordVersion,
    original: original,
    draftVersion: draftVersion,
  );

  CanonicalObject toWire() => CanonicalObject([
    MapEntry('base_revision', CanonicalString(baseRevision.value)),
    MapEntry('represented_context', CanonicalString(representedContext.value)),
    MapEntry('client_ref', CanonicalString(clientRef)),
    MapEntry('scope', CanonicalArray(scope.map((ref) => ref.toWire()))),
    MapEntry(
      'fictional_knowers',
      CanonicalArray(fictionalKnowers.map((ref) => ref.toWire())),
    ),
    MapEntry(
      'reader_disclosed',
      readerDisclosed == null
          ? const CanonicalNull()
          : CanonicalBool(readerDisclosed!),
    ),
    MapEntry('has_concealment', CanonicalBool(hasConcealment)),
    MapEntry('concealment', CanonicalString(concealment)),
    MapEntry('validity_kind', CanonicalString(validityKind)),
    MapEntry('calendar', CanonicalString(calendar)),
    MapEntry('start', CanonicalString(start)),
    MapEntry('end', CanonicalString(end)),
    MapEntry('start_unbounded', CanonicalBool(startUnbounded)),
    MapEntry('end_unbounded', CanonicalBool(endUnbounded)),
    MapEntry('rationale', CanonicalString(rationale)),
    if (revisionTarget != null)
      MapEntry('revision_target', revisionTarget!.toWire()),
    if (expectedRecordVersion != null)
      MapEntry(
        'expected_record_version',
        CanonicalString(expectedRecordVersion!.value),
      ),
    if (original != null) MapEntry('original', original!.toWire()),
    if (draftVersion != null)
      MapEntry('draft_version', CanonicalString(draftVersion.toString())),
  ]);
  factory UnfinishedSecretForm.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'base_revision',
      'represented_context',
      'client_ref',
      'scope',
      'fictional_knowers',
      'reader_disclosed',
      'has_concealment',
      'concealment',
      'validity_kind',
      'calendar',
      'start',
      'end',
      'start_unbounded',
      'end_unbounded',
      'rationale',
      'revision_target',
      'expected_record_version',
      'original',
      'draft_version',
    });
    return UnfinishedSecretForm(
      baseRevision: RevisionId.parse(f.string('base_revision')),
      representedContext: RecordId.parse(f.string('represented_context')),
      clientRef: f.string('client_ref'),
      scope: f.array('scope').map(ExpressionReferenceInput.fromWire),
      fictionalKnowers: f
          .array('fictional_knowers')
          .map(ExpressionReferenceInput.fromWire),
      readerDisclosed: f.optional(
        'reader_disclosed',
        (v) => switch (v) {
          CanonicalBool(:final value) => value,
          _ => throw const FormatException('Expected reader disclosure choice'),
        },
      ),
      hasConcealment: f.boolean('has_concealment'),
      concealment: f.string('concealment'),
      validityKind: f.string('validity_kind'),
      calendar: f.string('calendar'),
      start: f.string('start'),
      end: f.string('end'),
      startUnbounded: f.boolean('start_unbounded'),
      endUnbounded: f.boolean('end_unbounded'),
      rationale: f.string('rationale'),
      revisionTarget: f.optional(
        'revision_target',
        ExpressionReferenceInput.fromWire,
      ),
      expectedRecordVersion: f.optional(
        'expected_record_version',
        (v) => RecordVersionId.parse(wireString(v)),
      ),
      original: f.optional('original', SecretRecord.fromWire),
      draftVersion: f.optional(
        'draft_version',
        (v) => checkedU64(BigInt.parse(wireString(v))),
      ),
    );
  }
}

Iterable<String> _texts(CanonicalValue value) sync* {
  switch (value) {
    case CanonicalString(:final value):
      yield value;
    case CanonicalArray(:final items):
      for (final child in items) {
        yield* _texts(child);
      }
    case CanonicalObject(:final fields):
      for (final field in fields) {
        yield field.key;
        yield* _texts(field.value);
      }
    default:
      break;
  }
}

final class SavedSecretForm {
  SavedSecretForm({required BigInt generation, required this.form})
    : generation = checkedU64(generation);
  final BigInt generation;
  final UnfinishedSecretForm form;
}
