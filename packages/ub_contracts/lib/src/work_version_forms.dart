import 'package:ub_domain/ub_domain.dart';

import 'expression_forms.dart';
import 'wire.dart';

final class WorkSegmentInput {
  const WorkSegmentInput({
    this.segment = '',
    this.continuity = '',
    this.revision = '',
  });
  final String segment, continuity, revision;
  WorkSegmentInput copyWith({
    String? segment,
    String? continuity,
    String? revision,
  }) => WorkSegmentInput(
    segment: segment ?? this.segment,
    continuity: continuity ?? this.continuity,
    revision: revision ?? this.revision,
  );
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('segment', CanonicalString(segment)),
    MapEntry('continuity', CanonicalString(continuity)),
    MapEntry('revision', CanonicalString(revision)),
  ]);
  factory WorkSegmentInput.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'segment', 'continuity', 'revision'});
    return WorkSegmentInput(
      segment: f.string('segment'),
      continuity: f.string('continuity'),
      revision: f.string('revision'),
    );
  }
}

final class UnfinishedWorkVersionForm {
  UnfinishedWorkVersionForm({
    required this.baseRevision,
    required this.representedContext,
    required this.clientRef,
    this.work = const ExpressionReferenceInput(),
    this.versionLabel = '',
    this.bindingKind = '',
    this.continuity = '',
    this.revision = '',
    Iterable<WorkSegmentInput> segments = const [],
    this.rationale = '',
    this.bindingTarget,
    this.expectedRecordVersion,
    BigInt? draftVersion,
  }) : segments = List.unmodifiable(segments),
       draftVersion = draftVersion == null ? null : checkedU64(draftVersion);
  final RevisionId baseRevision;
  final RecordId representedContext;
  final String clientRef,
      versionLabel,
      bindingKind,
      continuity,
      revision,
      rationale;
  final ExpressionReferenceInput work;
  final ExpressionReferenceInput? bindingTarget;
  final RecordVersionId? expectedRecordVersion;
  final List<WorkSegmentInput> segments;
  final BigInt? draftVersion;
  UnfinishedWorkVersionForm copyWith({
    ExpressionReferenceInput? work,
    String? versionLabel,
    String? bindingKind,
    String? continuity,
    String? revision,
    List<WorkSegmentInput>? segments,
    String? rationale,
  }) => UnfinishedWorkVersionForm(
    baseRevision: baseRevision,
    representedContext: representedContext,
    clientRef: clientRef,
    work: work ?? this.work,
    versionLabel: versionLabel ?? this.versionLabel,
    bindingKind: bindingKind ?? this.bindingKind,
    continuity: continuity ?? this.continuity,
    revision: revision ?? this.revision,
    segments: segments ?? this.segments,
    rationale: rationale ?? this.rationale,
    draftVersion: draftVersion,
    bindingTarget: bindingTarget,
    expectedRecordVersion: expectedRecordVersion,
  );
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('base_revision', CanonicalString(baseRevision.value)),
    MapEntry('represented_context', CanonicalString(representedContext.value)),
    MapEntry('client_ref', CanonicalString(clientRef)),
    MapEntry('work', work.toWire()),
    MapEntry('version_label', CanonicalString(versionLabel)),
    MapEntry('binding_kind', CanonicalString(bindingKind)),
    MapEntry('continuity', CanonicalString(continuity)),
    MapEntry('revision', CanonicalString(revision)),
    MapEntry('segments', CanonicalArray(segments.map((s) => s.toWire()))),
    MapEntry('rationale', CanonicalString(rationale)),
    if (bindingTarget != null)
      MapEntry('binding_target', bindingTarget!.toWire()),
    if (expectedRecordVersion != null)
      MapEntry(
        'expected_record_version',
        CanonicalString(expectedRecordVersion!.value),
      ),
    if (draftVersion != null)
      MapEntry('draft_version', CanonicalString(draftVersion.toString())),
  ]);
  factory UnfinishedWorkVersionForm.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'base_revision',
      'represented_context',
      'client_ref',
      'work',
      'version_label',
      'binding_kind',
      'continuity',
      'revision',
      'segments',
      'rationale',
      'binding_target',
      'expected_record_version',
      'draft_version',
    });
    return UnfinishedWorkVersionForm(
      baseRevision: RevisionId.parse(f.string('base_revision')),
      representedContext: RecordId.parse(f.string('represented_context')),
      clientRef: f.string('client_ref'),
      work: ExpressionReferenceInput.fromWire(f.require('work')),
      versionLabel: f.string('version_label'),
      bindingKind: f.string('binding_kind'),
      continuity: f.string('continuity'),
      revision: f.string('revision'),
      segments: f.array('segments').map(WorkSegmentInput.fromWire),
      rationale: f.string('rationale'),
      bindingTarget: f.optional(
        'binding_target',
        ExpressionReferenceInput.fromWire,
      ),
      expectedRecordVersion: f.optional(
        'expected_record_version',
        (v) => RecordVersionId.parse(wireString(v)),
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

final class SavedWorkVersionForm {
  SavedWorkVersionForm({required BigInt generation, required this.form})
    : generation = checkedU64(generation);
  final BigInt generation;
  final UnfinishedWorkVersionForm form;
}
