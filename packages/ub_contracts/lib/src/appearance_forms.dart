import 'package:ub_domain/ub_domain.dart';

import 'expression_forms.dart';
import 'staged_image.dart';
import 'wire.dart';

final class AppearanceImageInput {
  const AppearanceImageInput({
    this.asset = const ExpressionReferenceInput(),
    this.caption = '',
    this.purpose = '',
    this.stagedOperation,
    this.preview = '',
  });
  final ExpressionReferenceInput asset;
  final String caption, purpose, preview;
  final AddImageAssetOperation? stagedOperation;
  factory AppearanceImageInput.staged(StagedImage image, UniverseId universe) =>
      AppearanceImageInput(
        asset: ExpressionReferenceInput(
          record: image.assetId.value,
          universe: universe.value,
        ),
        stagedOperation: image.operation,
        preview: image.preview,
      );
  AppearanceImageInput copyWith({
    ExpressionReferenceInput? asset,
    String? caption,
    String? purpose,
  }) {
    final changedAsset =
        asset != null &&
        asset.toWire().toText() != this.asset.toWire().toText();
    return AppearanceImageInput(
      asset: asset ?? this.asset,
      caption: caption ?? this.caption,
      purpose: purpose ?? this.purpose,
      stagedOperation: changedAsset ? null : stagedOperation,
      preview: changedAsset ? '' : preview,
    );
  }

  CanonicalObject toWire() => CanonicalObject([
    MapEntry('asset', asset.toWire()),
    MapEntry('caption', CanonicalString(caption)),
    MapEntry('purpose', CanonicalString(purpose)),
    MapEntry('preview', CanonicalString(preview)),
    if (stagedOperation != null)
      MapEntry('staged_operation', stagedOperation!.toWire()),
  ]);
  factory AppearanceImageInput.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'asset',
      'caption',
      'purpose',
      'preview',
      'staged_operation',
    });
    final operation = f.optional('staged_operation', DomainOperation.fromWire);
    if (operation != null && operation is! AddImageAssetOperation) {
      throw const FormatException('Expected an image asset operation.');
    }
    final preview = f.string('preview');
    if (preview.isNotEmpty) decodeImagePreviewBytes(preview);
    return AppearanceImageInput(
      asset: ExpressionReferenceInput.fromWire(f.require('asset')),
      caption: f.string('caption'),
      purpose: f.string('purpose'),
      preview: preview,
      stagedOperation: operation as AddImageAssetOperation?,
    );
  }
}

final class AppearanceLinkInput {
  const AppearanceLinkInput({
    this.entry = const ExpressionReferenceInput(),
    this.relationship = '',
    this.note = '',
  });
  final ExpressionReferenceInput entry;
  final String relationship, note;
  AppearanceLinkInput copyWith({
    ExpressionReferenceInput? entry,
    String? relationship,
    String? note,
  }) => AppearanceLinkInput(
    entry: entry ?? this.entry,
    relationship: relationship ?? this.relationship,
    note: note ?? this.note,
  );
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('entry', entry.toWire()),
    MapEntry('relationship', CanonicalString(relationship)),
    MapEntry('note', CanonicalString(note)),
  ]);
  factory AppearanceLinkInput.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'entry', 'relationship', 'note'});
    return AppearanceLinkInput(
      entry: ExpressionReferenceInput.fromWire(f.require('entry')),
      relationship: f.string('relationship'),
      note: f.string('note'),
    );
  }
}

/// Partial author input. Images are staged originals, not published facts.
final class UnfinishedAppearanceForm {
  UnfinishedAppearanceForm({
    required this.baseRevision,
    required this.representedContext,
    required this.clientRef,
    this.targetKind = '',
    this.target = const ExpressionReferenceInput(),
    this.label = '',
    this.physicalDescription = '',
    this.atmosphere = '',
    Iterable<AppearanceImageInput> images = const [],
    Iterable<AppearanceLinkInput> links = const [],
    this.validityKind = 'unspecified',
    this.calendar = '',
    this.start = '',
    this.end = '',
    this.startUnbounded = false,
    this.endUnbounded = false,
    this.rationale = '',
    this.original,
    this.revisionTarget,
    this.expectedRecordVersion,
    BigInt? draftVersion,
  }) : images = List.unmodifiable(images),
       links = List.unmodifiable(links),
       draftVersion = draftVersion == null ? null : checkedU64(draftVersion);
  final RevisionId baseRevision;
  final RecordId representedContext;
  final String clientRef,
      targetKind,
      label,
      physicalDescription,
      atmosphere,
      validityKind,
      rationale;
  final ExpressionReferenceInput target;
  final List<AppearanceImageInput> images;
  final List<AppearanceLinkInput> links;
  final String calendar, start, end;
  final bool startUnbounded, endUnbounded;
  final AppearanceRecord? original;
  final ExpressionReferenceInput? revisionTarget;
  final RecordVersionId? expectedRecordVersion;
  final BigInt? draftVersion;
  String get recoveryKey =>
      revisionTarget == null ? clientRef : 'appearance-revision:$clientRef';
  UnfinishedAppearanceForm copyWith({
    String? targetKind,
    ExpressionReferenceInput? target,
    String? label,
    String? physicalDescription,
    String? atmosphere,
    Iterable<AppearanceImageInput>? images,
    Iterable<AppearanceLinkInput>? links,
    String? validityKind,
    String? calendar,
    String? start,
    String? end,
    bool? startUnbounded,
    bool? endUnbounded,
    String? rationale,
  }) => UnfinishedAppearanceForm(
    baseRevision: baseRevision,
    representedContext: representedContext,
    clientRef: clientRef,
    targetKind: targetKind ?? this.targetKind,
    target: target ?? this.target,
    label: label ?? this.label,
    physicalDescription: physicalDescription ?? this.physicalDescription,
    atmosphere: atmosphere ?? this.atmosphere,
    images: images ?? this.images,
    links: links ?? this.links,
    validityKind: validityKind ?? this.validityKind,
    calendar: calendar ?? this.calendar,
    start: start ?? this.start,
    end: end ?? this.end,
    startUnbounded: startUnbounded ?? this.startUnbounded,
    endUnbounded: endUnbounded ?? this.endUnbounded,
    rationale: rationale ?? this.rationale,
    original: original,
    revisionTarget: revisionTarget,
    expectedRecordVersion: expectedRecordVersion,
    draftVersion: draftVersion,
  );
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('base_revision', CanonicalString(baseRevision.value)),
    MapEntry('represented_context', CanonicalString(representedContext.value)),
    MapEntry('client_ref', CanonicalString(clientRef)),
    MapEntry('target_kind', CanonicalString(targetKind)),
    MapEntry('target', target.toWire()),
    MapEntry('label', CanonicalString(label)),
    MapEntry('physical_description', CanonicalString(physicalDescription)),
    MapEntry('atmosphere', CanonicalString(atmosphere)),
    MapEntry('images', CanonicalArray(images.map((image) => image.toWire()))),
    MapEntry('links', CanonicalArray(links.map((link) => link.toWire()))),
    MapEntry('validity_kind', CanonicalString(validityKind)),
    MapEntry('calendar', CanonicalString(calendar)),
    MapEntry('start', CanonicalString(start)),
    MapEntry('end', CanonicalString(end)),
    MapEntry('start_unbounded', CanonicalBool(startUnbounded)),
    MapEntry('end_unbounded', CanonicalBool(endUnbounded)),
    MapEntry('rationale', CanonicalString(rationale)),
    if (original != null) MapEntry('original', original!.toWire()),
    if (revisionTarget != null)
      MapEntry('revision_target', revisionTarget!.toWire()),
    if (expectedRecordVersion != null)
      MapEntry(
        'expected_record_version',
        CanonicalString(expectedRecordVersion!.value),
      ),
    if (draftVersion != null)
      MapEntry('draft_version', CanonicalString(draftVersion.toString())),
  ]);
  factory UnfinishedAppearanceForm.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'base_revision',
      'represented_context',
      'client_ref',
      'target_kind',
      'target',
      'label',
      'physical_description',
      'atmosphere',
      'images',
      'links',
      'validity_kind',
      'calendar',
      'start',
      'end',
      'start_unbounded',
      'end_unbounded',
      'rationale',
      'original',
      'revision_target',
      'expected_record_version',
      'draft_version',
    });
    return UnfinishedAppearanceForm(
      baseRevision: RevisionId.parse(f.string('base_revision')),
      representedContext: RecordId.parse(f.string('represented_context')),
      clientRef: f.string('client_ref'),
      targetKind: f.string('target_kind'),
      target: ExpressionReferenceInput.fromWire(f.require('target')),
      label: f.string('label'),
      physicalDescription: f.string('physical_description'),
      atmosphere: f.string('atmosphere'),
      images: f.array('images').map(AppearanceImageInput.fromWire),
      links: f.array('links').map(AppearanceLinkInput.fromWire),
      validityKind: f.string('validity_kind'),
      calendar: f.string('calendar'),
      start: f.string('start'),
      end: f.string('end'),
      startUnbounded: f.boolean('start_unbounded'),
      endUnbounded: f.boolean('end_unbounded'),
      rationale: f.string('rationale'),
      original: f.optional('original', AppearanceRecord.fromWire),
      revisionTarget: f.optional(
        'revision_target',
        ExpressionReferenceInput.fromWire,
      ),
      expectedRecordVersion: f.optional(
        'expected_record_version',
        (v) => RecordVersionId.parse(wireString(v)),
      ),
      draftVersion: f.optional(
        'draft_version',
        (v) => checkedU64(BigInt.parse(wireString(v))),
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

final class SavedAppearanceForm {
  SavedAppearanceForm({required BigInt generation, required this.form})
    : generation = checkedU64(generation);
  final BigInt generation;
  final UnfinishedAppearanceForm form;
}
